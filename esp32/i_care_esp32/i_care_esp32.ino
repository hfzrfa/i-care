#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>
#include <esp_system.h>

#include "Secrets.h"
#include "cs_config.h"
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

static const int TFT_SCLK = 18;
static const int TFT_MOSI = 23;
static const int TFT_CS = 17;
static const int TFT_DC = 27;
static const int TFT_RST = 26;
Adafruit_ST7735 tft(TFT_CS, TFT_DC, TFT_RST);
bool tftReady = false;
static const uint16_t TFT_NAVY = 0x000F;

static const int GSR_PIN = 34;
static const int EMG_PIN = 35;

static const uint32_t SERIAL_BAUD = 115200;
static const uint32_t UPLOAD_RETRY_COUNT = 1;
static const uint32_t UPLOAD_RETRY_DELAY_MS = 150;
static const uint32_t FIREBASE_RETRY_INTERVAL_MS = 30000;
static const uint32_t FIREBASE_REBEGIN_INTERVAL_MS = 180000;
static const uint32_t CLOUD_TASK_STACK_BYTES = 24576;
static const int GSR_ADC_FILTER_SAMPLES = 9;
static const int EMG_ADC_FILTER_SAMPLES = 5;
static const int ADC_FILTER_SAMPLES_MAX = 9;
static const float GSR_FILTER_ALPHA = 0.18f;
static const float EMG_FILTER_ALPHA = 0.42f;
static const float SENSOR_RAIL_RATIO = 0.25f;
static const uint16_t ADC_RAIL_LOW = 8;
static const uint16_t ADC_RAIL_HIGH = 4087;
static const bool SERIAL_REPORT_FULL_INPUT_VECTOR = false;
static const bool SERIAL_REPORT_FULL_MEASUREMENT_VECTOR = false;
static const bool SERIAL_REPORT_FULL_RECONSTRUCTED_VECTOR = false;
static const bool SERIAL_REPORT_COMPARISON_TABLE = false;
static const int SERIAL_VECTOR_PREVIEW_COUNT = 8;
static const uint8_t SERIAL_VECTOR_DECIMALS = 2;
static const int CS_RECON_SPARSITY = CS_N / 4;
static const bool WIFI_DISTANCE_TEST_REPORT_ENABLED = true;
static const int WIFI_TEST_DISTANCE_M = 3;
static const int WIFI_TEST_TRIAL_NUMBER = 3;
// GPIO34/35 have no internal pull resistors. The external 100 kOhm pull-down
// from each ADC node to GND is required so an unplugged SIG line reads near 0.
static const float GSR_PRESENT_ADC_MIN = 200.0f;
static const float EMG_PRESENT_ADC_MIN = 250.0f;
static const float SENSOR_PRESENT_ADC_MAX = 4000.0f;
static const uint8_t SIGNAL_VALID_WINDOWS = 3;
static const uint8_t SIGNAL_INVALID_WINDOWS = 2;

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;
bool firebaseClientStarted = false;
uint32_t firebaseLastBeginMs = 0;

struct UploadPacket {
  uint32_t windowId;
  float yGsr[CS_M];
  float yEmg[CS_M];
  float gsrAvg;
  float emgAvg;
  float stressIndex;
  bool sensorsAttached;
  bool gsrSignalValid;
  bool emgSignalValid;
  uint16_t gsrRawMin;
  uint16_t gsrRawMax;
  uint16_t emgRawMin;
  uint16_t emgRawMax;
  float gsrRawAvg;
  float emgRawAvg;
};

QueueHandle_t uploadQueue = nullptr;
TaskHandle_t cloudTaskHandle = nullptr;
volatile bool latestCloudReady = false;
volatile bool latestUploadOk = false;
volatile int32_t latestUploadRssi = -127;
volatile uint32_t latestUploadDelayMs = 0;
volatile uint32_t latestUploadedWindowId = 0;
volatile uint32_t uploadAttemptWindows = 0;
volatile uint32_t uploadSuccessWindows = 0;

uint32_t packetSequence = 0;
uint32_t windowId = 0;
uint32_t wifiTestSentWindows = 0;
uint32_t wifiTestReceivedWindows = 0;
uint32_t wifiTestUploadDelaySumMs = 0;
uint32_t wifiTestUploadDelaySamples = 0;
int32_t wifiTestRssiSum = 0;
uint32_t wifiTestRssiSamples = 0;

uint64_t currentEpochMs() {
  const time_t now = time(nullptr);
  
  if (now < 1700000000) {
    return static_cast<uint64_t>(millis());
  }
  return static_cast<uint64_t>(now) * 1000ULL;
}

String shortGsrStatus(float gsrUs) {
  if (gsrUs <= 5.0f) return "LOW";
  if (gsrUs <= 12.0f) return "MODERATE";
  return "HIGH";
}

String shortEmgStatus(float emgUv) {
  if (emgUv < 200.0f) return "NORMAL";
  return "STRESS";
}

String shortCombinedStatus(float gsrUs, float emgUv) {
  const bool emgStress = emgUv >= 200.0f;
  if (gsrUs <= 5.0f && !emgStress) return "OK";
  if (gsrUs <= 12.0f && !emgStress) return "MILD";
  if (!emgStress) return "GSR HI";
  if (gsrUs <= 5.0f) return "EMG HI";
  if (gsrUs <= 12.0f) return "MID";
  return "HIGH";
}

uint16_t tftStatusColor(const String& status) {
  if (status == "LOW" || status == "NORMAL" || status == "OK") {
    return ST77XX_GREEN;
  }
  if (status == "MODERATE" || status == "MILD" || status == "MID") {
    return ST77XX_YELLOW;
  }
  return ST77XX_RED;
}

uint16_t tftWifiColor(int32_t rssi) {
  if (rssi >= -65) return ST77XX_GREEN;
  if (rssi >= -75) return ST77XX_YELLOW;
  return ST77XX_RED;
}

float uploadPacketLossPercent() {
  const uint32_t attempts = uploadAttemptWindows;
  const uint32_t successes = uploadSuccessWindows;
  if (attempts == 0) return 0.0f;
  return ((float)(attempts - successes) / (float)attempts) * 100.0f;
}

String resetReasonText(esp_reset_reason_t reason) {
  switch (reason) {
    case ESP_RST_POWERON: return "POWERON";
    case ESP_RST_EXT: return "EXTERNAL_RESET";
    case ESP_RST_SW: return "SOFTWARE_RESET";
    case ESP_RST_PANIC: return "PANIC";
    case ESP_RST_INT_WDT: return "INT_WATCHDOG";
    case ESP_RST_TASK_WDT: return "TASK_WATCHDOG";
    case ESP_RST_WDT: return "WATCHDOG";
    case ESP_RST_DEEPSLEEP: return "DEEPSLEEP";
    case ESP_RST_BROWNOUT: return "BROWNOUT";
    case ESP_RST_SDIO: return "SDIO";
    default: return "UNKNOWN";
  }
}

void tftHeader(const String& title, bool online) {
  if (!tftReady) return;

  tft.fillRect(0, 0, 160, 22, TFT_NAVY);
  tft.setTextWrap(false);
  tft.setTextSize(1);
  tft.setTextColor(ST77XX_WHITE);
  tft.setCursor(5, 2);
  tft.print(title);

  tft.setTextColor(online ? ST77XX_GREEN : ST77XX_RED);
  tft.setCursor(136, 2);
  tft.print(online ? "ON" : "OFF");

  const int32_t rssi = online
      ? (latestUploadRssi > -127 ? latestUploadRssi : WiFi.RSSI())
      : -127;
  const float packetLoss = uploadPacketLossPercent();

  tft.setCursor(5, 13);
  tft.setTextColor(online ? tftWifiColor(rssi) : ST77XX_RED);
  tft.print("WiFi:");
  if (online) {
    tft.print(rssi);
  } else {
    tft.print("--");
  }
  tft.print("dBm");

  tft.setCursor(93, 13);
  tft.setTextColor(packetLoss <= 5.0f ? ST77XX_GREEN : (packetLoss <= 20.0f ? ST77XX_YELLOW : ST77XX_RED));
  tft.print("PL:");
  tft.print(packetLoss, 0);
  tft.print("%");
}

void tftLoadingScreen(const String& message, uint8_t progress) {
  if (!tftReady) return;

  const uint8_t safeProgress = min(progress, (uint8_t)100);
  tft.fillScreen(ST77XX_BLACK);
  tft.setTextWrap(false);
  tft.setTextColor(ST77XX_WHITE);
  tft.setTextSize(2);
  tft.setCursor(25, 28);
  tft.print("I-CARE");
  tft.setTextSize(1);
  tft.setCursor(12, 62);
  tft.print(message);
  tft.drawRect(12, 88, 136, 12, ST77XX_WHITE);
  tft.fillRect(14, 90, (132 * safeProgress) / 100, 8, ST77XX_CYAN);
  tft.setCursor(66, 108);
  tft.print(safeProgress);
  tft.print("%");
}

void tftMetricPanel(
  int16_t y,
  const String& label,
  float value,
  const String& unit,
  const String& status,
  bool valid
) {
  const uint16_t panelColor = 0x18E3;
  const uint16_t statusColor = valid
      ? tftStatusColor(status)
      : ST77XX_YELLOW;

  tft.fillRoundRect(5, y, 150, 42, 4, panelColor);
  tft.drawRoundRect(5, y, 150, 42, 4, statusColor);
  tft.setTextSize(1);
  tft.setTextColor(ST77XX_WHITE);
  tft.setCursor(11, y + 7);
  tft.print(label);
  tft.setTextColor(statusColor);
  tft.setCursor(valid ? 93 : 82, y + 7);
  tft.print(valid ? status : "NO SIGNAL");

  tft.setTextSize(2);
  tft.setTextColor(ST77XX_WHITE);
  tft.setCursor(11, y + 20);
  if (valid) {
    tft.print(value, 2);
  } else {
    tft.print("--");
  }
  tft.setTextSize(1);
  tft.setTextColor(ST77XX_CYAN);
  tft.setCursor(104, y + 27);
  tft.print(unit);
}

void tftRealtimeScreen(
  float gsrAvg,
  float emgAvg,
  bool gsrValid,
  bool emgValid,
  bool uploadOk
) {
  if (!tftReady) return;

  static bool initialized = false;
  if (!initialized) {
    tft.fillScreen(ST77XX_BLACK);
    initialized = true;
  }

  tftHeader("I-CARE LIVE", WiFi.status() == WL_CONNECTED);
  tftMetricPanel(
    28,
    "GSR",
    gsrAvg,
    "uS",
    shortGsrStatus(gsrAvg),
    gsrValid
  );
  tftMetricPanel(
    75,
    "EMG",
    emgAvg,
    "uV",
    shortEmgStatus(emgAvg),
    emgValid
  );

  tft.fillRect(0, 118, 160, 10, ST77XX_BLACK);
  tft.setTextSize(1);
  tft.setCursor(8, 121);
  if (gsrValid && emgValid) {
    tft.setTextColor(tftStatusColor(shortCombinedStatus(gsrAvg, emgAvg)));
    tft.print("STATUS: ");
    tft.print(shortCombinedStatus(gsrAvg, emgAvg));
  } else {
    tft.setTextColor(ST77XX_YELLOW);
    tft.print("WAIT: ");
    if (!gsrValid) tft.print("GSR ");
    if (!emgValid) tft.print("EMG ");
  }
  tft.setTextColor(ST77XX_WHITE);
  tft.setCursor(119, 121);
  tft.print("W");
  tft.print(windowId % 100);
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  Serial.print("[WiFi] Connecting");
  tftLoadingScreen("Connecting WiFi", 35);

  WiFi.mode(WIFI_STA);
  WiFi.setSleep(false);
  WiFi.disconnect();
  delay(100);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500);
    Serial.print('.');
    attempts++;
  }
  Serial.println();
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("[WiFi] Connection timeout. Local monitoring continues.");
    return;
  }
  Serial.print("[WiFi] Connected. IP: ");
  Serial.println(WiFi.localIP());

  tftLoadingScreen("WiFi connected", 50);
  delay(300);
}

bool writeJsonWithRetry(const String& path, FirebaseJson& payload, bool usePush) {
  for (uint32_t attempt = 1; attempt <= UPLOAD_RETRY_COUNT; attempt++) {
    const bool ok = usePush
        ? Firebase.RTDB.pushJSON(&fbdo, path, &payload)
        : Firebase.RTDB.setJSON(&fbdo, path, &payload);

    if (ok) {
      return true;
    }

    Serial.print("[Firebase] write failed path=");
    Serial.print(path);
    Serial.print(" attempt=");
    Serial.print(attempt);
    Serial.print(" reason=");
    Serial.println(fbdo.errorReason());

    if (attempt < UPLOAD_RETRY_COUNT) {
      delay(UPLOAD_RETRY_DELAY_MS * attempt);
    }
  }

  return false;
}

void initFirebase(bool showTft = true, uint8_t waitAttempts = 0) {
  if (showTft) {
    tftLoadingScreen("Connecting cloud", 60);
  }

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.token_status_callback = tokenStatusCallback;

  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  Firebase.reconnectWiFi(true);
  if (!firebaseClientStarted) {
    Firebase.begin(&config, &auth);
    firebaseClientStarted = true;
    firebaseLastBeginMs = millis();
    Serial.println("[Firebase] Client begin requested.");
  } else {
    Serial.println("[Firebase] Client already started. Waiting token recovery.");
  }

  Serial.println("[Firebase] Checking client readiness...");
  int fbAttempts = 0;
  while (!Firebase.ready() && fbAttempts < waitAttempts) {
    delay(500);
    fbAttempts++;
    if (showTft && fbAttempts % 2 == 0) {
      tftLoadingScreen(
        "Authenticating",
        (uint8_t)min(60 + fbAttempts, 90)
      );
    }
  }
  
  if (Firebase.ready()) {
    Serial.println("[Firebase] Ready.");
    if (showTft) {
      tftLoadingScreen("Cloud connected", 75);
    }
  } else {
    Serial.println("[Firebase] Not ready yet. Local monitoring continues.");
    if (showTft) {
      tftLoadingScreen("Local mode active", 75);
    }
  }
  if (showTft) {
    delay(300);
  }
}

float clampRange(float value, float minValue, float maxValue) {
  if (value < minValue) return minValue;
  if (value > maxValue) return maxValue;
  return value;
}

float mapAdcToRange(float raw, float minAdc, float maxAdc, float minValue, float maxValue) {
  if (maxAdc <= minAdc) return minValue;
  const float normalized = (raw - minAdc) / (maxAdc - minAdc);
  const float mapped = minValue + (normalized * (maxValue - minValue));
  return clampRange(mapped, minValue, maxValue);
}

uint16_t readMedianAdc(int pin, int sampleCount) {
  const int safeSampleCount = constrain(sampleCount, 3, ADC_FILTER_SAMPLES_MAX);
  uint16_t samples[ADC_FILTER_SAMPLES_MAX];
  for (int i = 0; i < safeSampleCount; i++) {
    samples[i] = (uint16_t)analogRead(pin);
    delayMicroseconds(180);
  }

  for (int i = 1; i < safeSampleCount; i++) {
    const uint16_t key = samples[i];
    int j = i - 1;
    while (j >= 0 && samples[j] > key) {
      samples[j + 1] = samples[j];
      j--;
    }
    samples[j + 1] = key;
  }

  return samples[safeSampleCount / 2];
}

float smoothSensorValue(float previous, float current, bool initialized, float alpha) {
  if (!initialized) {
    return current;
  }
  const float safeAlpha = clampRange(alpha, 0.01f, 1.0f);
  return (previous * (1.0f - safeAlpha)) + (current * safeAlpha);
}

static const float GSR_ADC_MIN = 400.0f;
static const float GSR_ADC_MAX = 3200.0f;
static const float EMG_ADC_MIN = 500.0f;
static const float EMG_ADC_MAX = 3400.0f;
static const float GSR_US_MIN = 0.0f;
static const float GSR_US_MAX = 20.0f;
static const float EMG_UV_MIN = 0.0f;
static const float EMG_UV_MAX = 250.0f;

bool sensorsAttached = false;
bool gsrSignalValid = false;
bool emgSignalValid = false;
uint16_t gsrRawMin = 4095;
uint16_t gsrRawMax = 0;
uint16_t emgRawMin = 4095;
uint16_t emgRawMax = 0;
float gsrRawAvg = 0.0f;
float emgRawAvg = 0.0f;

bool updateSignalValidity(
  bool current,
  bool validCandidate,
  uint8_t& validWindows,
  uint8_t& invalidWindows
) {
  if (validCandidate) {
    invalidWindows = 0;
    if (validWindows < SIGNAL_VALID_WINDOWS) validWindows++;
    if (validWindows >= SIGNAL_VALID_WINDOWS) return true;
  } else {
    validWindows = 0;
    if (invalidWindows < SIGNAL_INVALID_WINDOWS) invalidWindows++;
    if (invalidWindows >= SIGNAL_INVALID_WINDOWS) return false;
  }
  return current;
}

void fillCsBuffer() {
  cs_buffer_index = 0;
  static bool gsrFilterInitialized = false;
  static bool emgFilterInitialized = false;
  static float gsrFiltered = 0.0f;
  static float emgFiltered = 0.0f;
  static uint8_t gsrValidWindows = 0;
  static uint8_t gsrInvalidWindows = 0;
  static uint8_t emgValidWindows = 0;
  static uint8_t emgInvalidWindows = 0;
  int gsrRailSamples = 0;
  int emgRailSamples = 0;
  uint32_t gsrRawSum = 0;
  uint32_t emgRawSum = 0;
  gsrRawMin = 4095;
  gsrRawMax = 0;
  emgRawMin = 4095;
  emgRawMax = 0;

  for (int i = 0; i < CS_N; i++) {
    const uint16_t gsrRawValue = readMedianAdc(GSR_PIN, GSR_ADC_FILTER_SAMPLES);
    const uint16_t emgRawValue = readMedianAdc(EMG_PIN, EMG_ADC_FILTER_SAMPLES);
    const float gsrRaw = (float)gsrRawValue;
    const float emgRaw = (float)emgRawValue;

    if (gsrRawValue < gsrRawMin) gsrRawMin = gsrRawValue;
    if (gsrRawValue > gsrRawMax) gsrRawMax = gsrRawValue;
    if (emgRawValue < emgRawMin) emgRawMin = emgRawValue;
    if (emgRawValue > emgRawMax) emgRawMax = emgRawValue;
    gsrRawSum += gsrRawValue;
    emgRawSum += emgRawValue;

    if (gsrRawValue <= ADC_RAIL_LOW || gsrRawValue >= ADC_RAIL_HIGH) {
      gsrRailSamples++;
    }
    if (emgRawValue <= ADC_RAIL_LOW || emgRawValue >= ADC_RAIL_HIGH) {
      emgRailSamples++;
    }

    const float gsrMapped = mapAdcToRange(gsrRaw, GSR_ADC_MIN, GSR_ADC_MAX, GSR_US_MIN, GSR_US_MAX);
    const float emgMapped = mapAdcToRange(emgRaw, EMG_ADC_MIN, EMG_ADC_MAX, EMG_UV_MIN, EMG_UV_MAX);

    gsrFiltered = smoothSensorValue(
      gsrFiltered,
      gsrMapped,
      gsrFilterInitialized,
      GSR_FILTER_ALPHA
    );
    emgFiltered = smoothSensorValue(
      emgFiltered,
      emgMapped,
      emgFilterInitialized,
      EMG_FILTER_ALPHA
    );
    gsrFilterInitialized = true;
    emgFilterInitialized = true;

    cs_gsr_buffer[i] = gsrFiltered;
    cs_emg_buffer[i] = emgFiltered;

    
    delayMicroseconds(CS_SAMPLE_DELAY_US);
  }

  gsrRawAvg = (float)gsrRawSum / (float)CS_N;
  emgRawAvg = (float)emgRawSum / (float)CS_N;
  const int railLimit = max(1, (int)((float)CS_N * SENSOR_RAIL_RATIO));
  const bool gsrCandidate =
      gsrRailSamples < railLimit &&
      gsrRawAvg >= GSR_PRESENT_ADC_MIN &&
      gsrRawAvg <= SENSOR_PRESENT_ADC_MAX;
  const bool emgCandidate =
      emgRailSamples < railLimit &&
      emgRawAvg >= EMG_PRESENT_ADC_MIN &&
      emgRawAvg <= SENSOR_PRESENT_ADC_MAX;
  gsrSignalValid = updateSignalValidity(
    gsrSignalValid,
    gsrCandidate,
    gsrValidWindows,
    gsrInvalidWindows
  );
  emgSignalValid = updateSignalValidity(
    emgSignalValid,
    emgCandidate,
    emgValidWindows,
    emgInvalidWindows
  );
  sensorsAttached = gsrSignalValid && emgSignalValid;
  if (!gsrSignalValid) {
    gsrFilterInitialized = false;
    gsrFiltered = 0.0f;
    for (int i = 0; i < CS_N; i++) {
      cs_gsr_buffer[i] = 0.0f;
    }
  }
  if (!emgSignalValid) {
    emgFilterInitialized = false;
    emgFiltered = 0.0f;
    for (int i = 0; i < CS_N; i++) {
      cs_emg_buffer[i] = 0.0f;
    }
  }
  cs_buffer_index = CS_N;
}

float arrayMean(const float* arr, int len) {
  float sum = 0.0f;
  for (int i = 0; i < len; i++) {
    sum += arr[i];
  }
  return sum / (float)len;
}

#if 0
// Disabled: laporan pengukuran measurement-rate dan WiFi-distance terlalu berat
// untuk mode monitoring harian. Aktifkan lagi hanya saat pengujian skripsi.
float arrayMinValue(const float* arr, int len) {
  if (len <= 0) return 0.0f;
  float minValue = arr[0];
  for (int i = 1; i < len; i++) {
    if (arr[i] < minValue) minValue = arr[i];
  }
  return minValue;
}

float arrayMaxValue(const float* arr, int len) {
  if (len <= 0) return 0.0f;
  float maxValue = arr[0];
  for (int i = 1; i < len; i++) {
    if (arr[i] > maxValue) maxValue = arr[i];
  }
  return maxValue;
}

bool supportContains(const int* support, int supportCount, int value) {
  for (int i = 0; i < supportCount; i++) {
    if (support[i] == value) return true;
  }
  return false;
}

void solveLeastSquaresForSupport(
  const float* y,
  const int* support,
  int supportCount,
  float* supportCoeffs
) {
  float aug[CS_RECON_SPARSITY][CS_RECON_SPARSITY + 1];

  for (int row = 0; row < supportCount; row++) {
    for (int col = 0; col < supportCount; col++) {
      float sum = 0.0f;
      for (int r = 0; r < CS_M; r++) {
        sum += cs_phi[r][support[row]] * cs_phi[r][support[col]];
      }
      aug[row][col] = sum;
    }

    float rhs = 0.0f;
    for (int r = 0; r < CS_M; r++) {
      rhs += cs_phi[r][support[row]] * y[r];
    }
    aug[row][supportCount] = rhs;
  }

  for (int col = 0; col < supportCount; col++) {
    int pivot = col;
    for (int row = col + 1; row < supportCount; row++) {
      if (fabsf(aug[row][col]) > fabsf(aug[pivot][col])) {
        pivot = row;
      }
    }

    if (pivot != col) {
      for (int c = col; c <= supportCount; c++) {
        const float tmp = aug[col][c];
        aug[col][c] = aug[pivot][c];
        aug[pivot][c] = tmp;
      }
    }

    if (fabsf(aug[col][col]) < 1e-8f) {
      continue;
    }

    for (int row = col + 1; row < supportCount; row++) {
      const float factor = aug[row][col] / aug[col][col];
      for (int c = col; c <= supportCount; c++) {
        aug[row][c] -= factor * aug[col][c];
      }
    }
  }

  for (int row = supportCount - 1; row >= 0; row--) {
    float sum = aug[row][supportCount];
    for (int col = row + 1; col < supportCount; col++) {
      sum -= aug[row][col] * supportCoeffs[col];
    }
    supportCoeffs[row] = fabsf(aug[row][row]) < 1e-8f
        ? 0.0f
        : sum / aug[row][row];
  }
}

void ompReconstructDwtCoeffs(const float* y, float* coeffs) {
  float residual[CS_M];
  int support[CS_RECON_SPARSITY];
  float supportCoeffs[CS_RECON_SPARSITY];
  int supportCount = 0;

  for (int i = 0; i < CS_M; i++) {
    residual[i] = y[i];
  }
  for (int i = 0; i < CS_N; i++) {
    coeffs[i] = 0.0f;
  }

  for (int iter = 0; iter < CS_RECON_SPARSITY; iter++) {
    int bestCol = 0;
    float bestCorr = -1.0f;

    for (int col = 0; col < CS_N; col++) {
      if (supportContains(support, supportCount, col)) {
        continue;
      }

      float corr = 0.0f;
      for (int row = 0; row < CS_M; row++) {
        corr += cs_phi[row][col] * residual[row];
      }

      if (fabsf(corr) > bestCorr) {
        bestCorr = fabsf(corr);
        bestCol = col;
      }
    }

    support[supportCount] = bestCol;
    supportCount++;

    for (int i = 0; i < CS_RECON_SPARSITY; i++) {
      supportCoeffs[i] = 0.0f;
    }
    solveLeastSquaresForSupport(y, support, supportCount, supportCoeffs);

    for (int i = 0; i < CS_N; i++) {
      coeffs[i] = 0.0f;
    }
    for (int i = 0; i < supportCount; i++) {
      coeffs[support[i]] = supportCoeffs[i];
    }

    for (int row = 0; row < CS_M; row++) {
      float estimate = 0.0f;
      for (int i = 0; i < supportCount; i++) {
        estimate += cs_phi[row][support[i]] * supportCoeffs[i];
      }
      residual[row] = y[row] - estimate;
    }
  }
}

void inverseDwtToSignal(const float* coeffs, float* signal) {
  for (int i = 0; i < CS_N; i++) {
    float sum = 0.0f;
    for (int j = 0; j < CS_N; j++) {
      sum += cs_psi[i][j] * coeffs[j];
    }
    signal[i] = sum < 0.0f ? 0.0f : sum;
  }
}

void reconstructSignalFromMeasurements(const float* y, float* reconstructed) {
  float sparseCoeffs[CS_N];
  ompReconstructDwtCoeffs(y, sparseCoeffs);
  inverseDwtToSignal(sparseCoeffs, reconstructed);
}

float averageAbsoluteDifference(const float* original, const float* reconstructed, int len) {
  float total = 0.0f;
  for (int i = 0; i < len; i++) {
    total += fabsf(original[i] - reconstructed[i]);
  }
  return total / (float)len;
}

float averagePercentError(const float* original, const float* reconstructed, int len) {
  float total = 0.0f;
  for (int i = 0; i < len; i++) {
    const float denominator = fabsf(original[i]);
    if (denominator < 1e-6f) {
      continue;
    }
    total += (fabsf(original[i] - reconstructed[i]) / denominator) * 100.0f;
  }
  return total / (float)len;
}

float prdPercent(const float* original, const float* reconstructed, int len) {
  float errorPower = 0.0f;
  float signalPower = 0.0f;
  for (int i = 0; i < len; i++) {
    const float error = original[i] - reconstructed[i];
    errorPower += error * error;
    signalPower += original[i] * original[i];
  }
  if (signalPower < 1e-8f) {
    return 0.0f;
  }
  return sqrtf(errorPower / signalPower) * 100.0f;
}

void printVectorReport(
  const char* label,
  const float* arr,
  int len,
  bool printFullVector,
  uint8_t decimals
) {
  Serial.print(label);
  Serial.print(" [");

  const int limit = printFullVector
      ? len
      : min(len, SERIAL_VECTOR_PREVIEW_COUNT);

  for (int i = 0; i < limit; i++) {
    if (i > 0) Serial.print(", ");
    Serial.print(arr[i], decimals);
  }

  if (!printFullVector && len > limit) {
    Serial.print(", ... total=");
    Serial.print(len);
  }

  Serial.println("]");
}

void printMeasurementRateReport(
  const float* yGsr,
  const float* yEmg,
  const float* xHatGsr,
  const float* xHatEmg,
  float gsrAvg,
  float emgAvg,
  float stressIndex,
  bool cloudReady,
  bool uploadOk
) {
  const float measurementRate = ((float)CS_M / (float)CS_N) * 100.0f;
  const float compressionRatio = (float)CS_N / (float)CS_M;
  const float inputGsrMin = arrayMinValue(cs_gsr_buffer, CS_N);
  const float inputGsrMax = arrayMaxValue(cs_gsr_buffer, CS_N);
  const float inputEmgMin = arrayMinValue(cs_emg_buffer, CS_N);
  const float inputEmgMax = arrayMaxValue(cs_emg_buffer, CS_N);
  const float yGsrMin = arrayMinValue(yGsr, CS_M);
  const float yGsrMax = arrayMaxValue(yGsr, CS_M);
  const float yGsrAvg = arrayMean(yGsr, CS_M);
  const float yEmgMin = arrayMinValue(yEmg, CS_M);
  const float yEmgMax = arrayMaxValue(yEmg, CS_M);
  const float yEmgAvg = arrayMean(yEmg, CS_M);
  const float xHatGsrMin = arrayMinValue(xHatGsr, CS_N);
  const float xHatGsrMax = arrayMaxValue(xHatGsr, CS_N);
  const float xHatGsrAvg = arrayMean(xHatGsr, CS_N);
  const float xHatEmgMin = arrayMinValue(xHatEmg, CS_N);
  const float xHatEmgMax = arrayMaxValue(xHatEmg, CS_N);
  const float xHatEmgAvg = arrayMean(xHatEmg, CS_N);
  const float gsrAverageDiff = averageAbsoluteDifference(cs_gsr_buffer, xHatGsr, CS_N);
  const float emgAverageDiff = averageAbsoluteDifference(cs_emg_buffer, xHatEmg, CS_N);
  const float gsrAverageError = averagePercentError(cs_gsr_buffer, xHatGsr, CS_N);
  const float emgAverageError = averagePercentError(cs_emg_buffer, xHatEmg, CS_N);
  const float gsrAverageAccuracy = 100.0f - gsrAverageError;
  const float emgAverageAccuracy = 100.0f - emgAverageError;
  const float gsrPrd = prdPercent(cs_gsr_buffer, xHatGsr, CS_N);
  const float emgPrd = prdPercent(cs_emg_buffer, xHatEmg, CS_N);

  Serial.println();
  Serial.println("============================================================");
  Serial.print("WINDOW ");
  Serial.print(windowId);
  Serial.println(" | LAPORAN MEASUREMENT RATE CS");
  Serial.println("============================================================");

  Serial.print("Measurement rate   : ");
  Serial.print(CS_M);
  Serial.print("/");
  Serial.print(CS_N);
  Serial.print(" = ");
  Serial.print(measurementRate, 2);
  Serial.println("%");

  Serial.print("Compression ratio  : ");
  Serial.print(compressionRatio, 2);
  Serial.println("x");

  Serial.print("Sensor status      : attached=");
  Serial.print(sensorsAttached ? "YES" : "NO");
  Serial.print(" | valid=");
  Serial.print(gsrSignalValid ? "GSR" : "-");
  Serial.print("/");
  Serial.println(emgSignalValid ? "EMG" : "-");

  Serial.print("Cloud upload       : ");
  Serial.println(wifiUploadStatusText(cloudReady, uploadOk));
  Serial.print("Cloud core 0       : lastWindow=");
  Serial.print(latestUploadedWindowId);
  Serial.print(" | rssi=");
  if (latestUploadRssi > -127) {
    Serial.print(latestUploadRssi);
    Serial.print(" dBm");
  } else {
    Serial.print("N/A");
  }
  Serial.print(" | delay=");
  Serial.print(latestUploadDelayMs);
  Serial.println(" ms");

  Serial.println("------------------------------------------------------------");
  Serial.println("SEBELUM CS (x[n] = sinyal input hasil filter, belum dikompresi)");

  Serial.print("GSR raw ADC        : min=");
  Serial.print(gsrRawMin);
  Serial.print(" max=");
  Serial.print(gsrRawMax);
  Serial.print(" avg=");
  Serial.println(gsrRawAvg, 1);

  Serial.print("EMG raw ADC        : min=");
  Serial.print(emgRawMin);
  Serial.print(" max=");
  Serial.print(emgRawMax);
  Serial.print(" avg=");
  Serial.println(emgRawAvg, 1);

  Serial.print("GSR x[n] stats     : avg=");
  Serial.print(gsrAvg, 2);
  Serial.print(" uS | min=");
  Serial.print(inputGsrMin, 2);
  Serial.print(" | max=");
  Serial.println(inputGsrMax, 2);

  Serial.print("EMG x[n] stats     : avg=");
  Serial.print(emgAvg, 2);
  Serial.print(" uV | min=");
  Serial.print(inputEmgMin, 2);
  Serial.print(" | max=");
  Serial.println(inputEmgMax, 2);

  printVectorReport(
    "GSR x[n] values    :",
    cs_gsr_buffer,
    CS_N,
    SERIAL_REPORT_FULL_INPUT_VECTOR,
    SERIAL_VECTOR_DECIMALS
  );
  printVectorReport(
    "EMG x[n] values    :",
    cs_emg_buffer,
    CS_N,
    SERIAL_REPORT_FULL_INPUT_VECTOR,
    SERIAL_VECTOR_DECIMALS
  );

  Serial.println("------------------------------------------------------------");
  Serial.println("HASIL KOMPRESI CS (y[m] = measurement vector, BUKAN rekonstruksi)");

  Serial.print("GSR y[m] stats     : avg=");
  Serial.print(yGsrAvg, 2);
  Serial.print(" | min=");
  Serial.print(yGsrMin, 2);
  Serial.print(" | max=");
  Serial.println(yGsrMax, 2);

  Serial.print("EMG y[m] stats     : avg=");
  Serial.print(yEmgAvg, 2);
  Serial.print(" | min=");
  Serial.print(yEmgMin, 2);
  Serial.print(" | max=");
  Serial.println(yEmgMax, 2);

  printVectorReport(
    "GSR y[m] values    :",
    yGsr,
    CS_M,
    SERIAL_REPORT_FULL_MEASUREMENT_VECTOR,
    SERIAL_VECTOR_DECIMALS
  );
  printVectorReport(
    "EMG y[m] values    :",
    yEmg,
    CS_M,
    SERIAL_REPORT_FULL_MEASUREMENT_VECTOR,
    SERIAL_VECTOR_DECIMALS
  );

  Serial.println("------------------------------------------------------------");
  Serial.println("HASIL REKONSTRUKSI (x_hat[n] = OMP + inverse DWT)");

  Serial.print("GSR x_hat stats    : avg=");
  Serial.print(xHatGsrAvg, 2);
  Serial.print(" uS | min=");
  Serial.print(xHatGsrMin, 2);
  Serial.print(" | max=");
  Serial.println(xHatGsrMax, 2);

  Serial.print("EMG x_hat stats    : avg=");
  Serial.print(xHatEmgAvg, 2);
  Serial.print(" uV | min=");
  Serial.print(xHatEmgMin, 2);
  Serial.print(" | max=");
  Serial.println(xHatEmgMax, 2);

  printVectorReport(
    "GSR x_hat values   :",
    xHatGsr,
    CS_N,
    SERIAL_REPORT_FULL_RECONSTRUCTED_VECTOR,
    SERIAL_VECTOR_DECIMALS
  );
  printVectorReport(
    "EMG x_hat values   :",
    xHatEmg,
    CS_N,
    SERIAL_REPORT_FULL_RECONSTRUCTED_VECTOR,
    SERIAL_VECTOR_DECIMALS
  );

  Serial.println("------------------------------------------------------------");
  Serial.println("RINGKASAN PERBANDINGAN VALID (x[n] vs x_hat[n])");

  Serial.print("GSR avg selisih    : ");
  Serial.print(gsrAverageDiff, 4);
  Serial.print(" uS | avg error=");
  Serial.print(gsrAverageError, 4);
  Serial.print("% | avg akurasi=");
  Serial.print(gsrAverageAccuracy, 4);
  Serial.print("% | PRD=");
  Serial.print(gsrPrd, 4);
  Serial.println("%");

  Serial.print("EMG avg selisih    : ");
  Serial.print(emgAverageDiff, 4);
  Serial.print(" uV | avg error=");
  Serial.print(emgAverageError, 4);
  Serial.print("% | avg akurasi=");
  Serial.print(emgAverageAccuracy, 4);
  Serial.print("% | PRD=");
  Serial.print(emgPrd, 4);
  Serial.println("%");

  if (SERIAL_REPORT_COMPARISON_TABLE) {
    Serial.println("------------------------------------------------------------");
    Serial.println("TABEL GSR: Sampel | x[n] asli | x_hat[n] rekonstruksi | Selisih | Error% | Akurasi%");
    for (int i = 0; i < CS_N; i++) {
      const float denominator = fabsf(cs_gsr_buffer[i]);
      const float diff = fabsf(cs_gsr_buffer[i] - xHatGsr[i]);
      const float error = denominator < 1e-6f ? 0.0f : (diff / denominator) * 100.0f;
      const float accuracy = 100.0f - error;
      Serial.print(i + 1);
      Serial.print(" | ");
      Serial.print(cs_gsr_buffer[i], 3);
      Serial.print(" | ");
      Serial.print(xHatGsr[i], 3);
      Serial.print(" | ");
      Serial.print(diff, 3);
      Serial.print(" | ");
      Serial.print(error, 3);
      Serial.print("% | ");
      Serial.print(accuracy, 3);
      Serial.println("%");
    }

    Serial.println("------------------------------------------------------------");
    Serial.println("TABEL EMG: Sampel | x[n] asli | x_hat[n] rekonstruksi | Selisih | Error% | Akurasi%");
    for (int i = 0; i < CS_N; i++) {
      const float denominator = fabsf(cs_emg_buffer[i]);
      const float diff = fabsf(cs_emg_buffer[i] - xHatEmg[i]);
      const float error = denominator < 1e-6f ? 0.0f : (diff / denominator) * 100.0f;
      const float accuracy = 100.0f - error;
      Serial.print(i + 1);
      Serial.print(" | ");
      Serial.print(cs_emg_buffer[i], 3);
      Serial.print(" | ");
      Serial.print(xHatEmg[i], 3);
      Serial.print(" | ");
      Serial.print(diff, 3);
      Serial.print(" | ");
      Serial.print(error, 3);
      Serial.print("% | ");
      Serial.print(accuracy, 3);
      Serial.println("%");
    }
  }

  Serial.println("------------------------------------------------------------");
  Serial.print("Stress index       : ");
  Serial.println(stressIndex, 2);
  Serial.println("============================================================");
}

String wifiUploadStatusText(bool cloudReady, bool uploadOk) {
  if (uploadOk) return "OK";
  if (WiFi.status() != WL_CONNECTED) return "TIDAK OK - WIFI OFFLINE";
  if (!cloudReady) return "TIDAK OK - FIREBASE NOT READY";
  return "TIDAK OK - FIREBASE FAIL";
}

String wifiStabilityLabel(float successRate, int32_t rssi) {
  if (successRate >= 95.0f && rssi >= -65) {
    return "Sangat stabil";
  }
  if (successRate >= 85.0f && rssi >= -75) {
    return "Stabil";
  }
  return "Kurang stabil";
}

void printWifiDistanceTestReport(
  bool cloudReady,
  bool uploadOk,
  int32_t rssi,
  uint32_t uploadDelayMs,
  uint32_t reportWindowId
) {
  if (!WIFI_DISTANCE_TEST_REPORT_ENABLED) {
    return;
  }

  wifiTestSentWindows++;
  if (uploadOk) {
    wifiTestReceivedWindows++;
    wifiTestUploadDelaySumMs += uploadDelayMs;
    wifiTestUploadDelaySamples++;
  }
  if (rssi > -127) {
    wifiTestRssiSum += rssi;
    wifiTestRssiSamples++;
  }

  const float packetLoss = wifiTestSentWindows == 0
      ? 0.0f
      : (((float)(wifiTestSentWindows - wifiTestReceivedWindows) /
          (float)wifiTestSentWindows) * 100.0f);
  const float successRate = wifiTestSentWindows == 0
      ? 0.0f
      : (((float)wifiTestReceivedWindows / (float)wifiTestSentWindows) * 100.0f);
  const float avgRssi = wifiTestRssiSamples == 0
      ? 0.0f
      : ((float)wifiTestRssiSum / (float)wifiTestRssiSamples);
  const float avgDelay = wifiTestUploadDelaySamples == 0
      ? 0.0f
      : ((float)wifiTestUploadDelaySumMs / (float)wifiTestUploadDelaySamples);

  Serial.println();
  Serial.println("============================================================");
  Serial.println("LAPORAN PENGUJIAN JARAK ACCESS POINT KE NODE IOT");
  Serial.println("============================================================");
  Serial.print("Jarak AP ke node   : ");
  Serial.print(WIFI_TEST_DISTANCE_M);
  Serial.println(" meter");
  Serial.print("Percobaan ke       : ");
  Serial.println(WIFI_TEST_TRIAL_NUMBER);
  Serial.print("Window             : ");
  Serial.println(reportWindowId);
  Serial.print("RSSI saat upload   : ");
  if (rssi > -127) {
    Serial.print(rssi);
    Serial.println(" dBm");
  } else {
    Serial.println("N/A");
  }
  Serial.print("Data dikirim       : ");
  Serial.print(wifiTestSentWindows);
  Serial.println(" window");
  Serial.print("Data diterima      : ");
  Serial.print(wifiTestReceivedWindows);
  Serial.println(" window");
  Serial.print("Measurement/window : ");
  Serial.print(CS_M * 2);
  Serial.println(" data kompresi (GSR + EMG)");
  Serial.print("Delay upload       : ");
  Serial.print(uploadDelayMs);
  Serial.println(" ms");
  Serial.print("Packet loss        : ");
  Serial.print(packetLoss, 2);
  Serial.println("%");
  Serial.print("Success rate       : ");
  Serial.print(successRate, 2);
  Serial.println("%");
  Serial.print("Status upload      : ");
  Serial.println(wifiUploadStatusText(cloudReady, uploadOk));

  Serial.println("------------------------------------------------------------");
  Serial.println("RINGKASAN SEMENTARA JARAK INI");
  Serial.print("Rata-rata RSSI     : ");
  Serial.print(avgRssi, 2);
  Serial.println(" dBm");
  Serial.print("Rata-rata delay OK : ");
  Serial.print(avgDelay, 2);
  Serial.println(" ms");
  Serial.print("Packet loss avg    : ");
  Serial.print(packetLoss, 2);
  Serial.println("%");
  Serial.print("Success rate avg   : ");
  Serial.print(successRate, 2);
  Serial.println("%");
  Serial.print("Keterangan         : ");
  Serial.println(wifiStabilityLabel(successRate, rssi));

  Serial.println("------------------------------------------------------------");
  Serial.println("FORMAT TABEL LAPORAN:");
  Serial.println("Jarak | Percobaan | RSSI | Data Dikirim | Data Diterima | Delay | Packet Loss | Success Rate | Status");
  Serial.print(WIFI_TEST_DISTANCE_M);
  Serial.print(" m | ");
  Serial.print(WIFI_TEST_TRIAL_NUMBER);
  Serial.print(" | ");
  Serial.print(rssi);
  Serial.print(" dBm | ");
  Serial.print(wifiTestSentWindows);
  Serial.print(" | ");
  Serial.print(wifiTestReceivedWindows);
  Serial.print(" | ");
  Serial.print(uploadDelayMs);
  Serial.print(" ms | ");
  Serial.print(packetLoss, 2);
  Serial.print("% | ");
  Serial.print(successRate, 2);
  Serial.print("% | ");
  Serial.println(wifiUploadStatusText(cloudReady, uploadOk));
  Serial.println("============================================================");
}
#endif

String wifiUploadStatusText(bool cloudReady, bool uploadOk) {
  if (uploadOk) return "OK";
  if (WiFi.status() != WL_CONNECTED) return "TIDAK OK - WIFI OFFLINE";
  if (!cloudReady) return "TIDAK OK - FIREBASE NOT READY";
  return "TIDAK OK - FIREBASE FAIL";
}

String wifiStabilityLabel(float successRate, int32_t rssi) {
  if (successRate >= 95.0f && rssi >= -65) {
    return "Sangat stabil";
  }
  if (successRate >= 85.0f && rssi >= -75) {
    return "Stabil";
  }
  return "Kurang stabil";
}

void printWifiDistanceTestReport(
  bool cloudReady,
  bool uploadOk,
  int32_t rssi,
  uint32_t uploadDelayMs,
  uint32_t reportWindowId
) {
  if (!WIFI_DISTANCE_TEST_REPORT_ENABLED) {
    return;
  }

  wifiTestSentWindows++;
  if (uploadOk) {
    wifiTestReceivedWindows++;
    wifiTestUploadDelaySumMs += uploadDelayMs;
    wifiTestUploadDelaySamples++;
  }
  if (rssi > -127) {
    wifiTestRssiSum += rssi;
    wifiTestRssiSamples++;
  }

  const float packetLoss = wifiTestSentWindows == 0
      ? 0.0f
      : (((float)(wifiTestSentWindows - wifiTestReceivedWindows) /
          (float)wifiTestSentWindows) * 100.0f);
  const float successRate = wifiTestSentWindows == 0
      ? 0.0f
      : (((float)wifiTestReceivedWindows / (float)wifiTestSentWindows) * 100.0f);
  const float avgRssi = wifiTestRssiSamples == 0
      ? 0.0f
      : ((float)wifiTestRssiSum / (float)wifiTestRssiSamples);
  const float avgDelay = wifiTestUploadDelaySamples == 0
      ? 0.0f
      : ((float)wifiTestUploadDelaySumMs / (float)wifiTestUploadDelaySamples);

  Serial.println();
  Serial.println("============================================================");
  Serial.println("LAPORAN PENGUJIAN JARAK ACCESS POINT KE NODE IOT");
  Serial.println("============================================================");
  Serial.print("Jarak AP ke node   : ");
  Serial.print(WIFI_TEST_DISTANCE_M);
  Serial.println(" meter");
  Serial.print("Percobaan ke       : ");
  Serial.println(WIFI_TEST_TRIAL_NUMBER);
  Serial.print("Window             : ");
  Serial.println(reportWindowId);
  Serial.print("RSSI saat upload   : ");
  if (rssi > -127) {
    Serial.print(rssi);
    Serial.println(" dBm");
  } else {
    Serial.println("N/A");
  }
  Serial.print("Data dikirim       : ");
  Serial.print(wifiTestSentWindows);
  Serial.println(" window");
  Serial.print("Data diterima      : ");
  Serial.print(wifiTestReceivedWindows);
  Serial.println(" window");
  Serial.print("Measurement/window : ");
  Serial.print(CS_M * 2);
  Serial.println(" data kompresi (GSR + EMG)");
  Serial.print("Delay upload       : ");
  Serial.print(uploadDelayMs);
  Serial.println(" ms");
  Serial.print("Packet loss        : ");
  Serial.print(packetLoss, 2);
  Serial.println("%");
  Serial.print("Success rate       : ");
  Serial.print(successRate, 2);
  Serial.println("%");
  Serial.print("Status upload      : ");
  Serial.println(wifiUploadStatusText(cloudReady, uploadOk));

  Serial.println("------------------------------------------------------------");
  Serial.println("RINGKASAN SEMENTARA JARAK INI");
  Serial.print("Rata-rata RSSI     : ");
  Serial.print(avgRssi, 2);
  Serial.println(" dBm");
  Serial.print("Rata-rata delay OK : ");
  Serial.print(avgDelay, 2);
  Serial.println(" ms");
  Serial.print("Packet loss avg    : ");
  Serial.print(packetLoss, 2);
  Serial.println("%");
  Serial.print("Success rate avg   : ");
  Serial.print(successRate, 2);
  Serial.println("%");
  Serial.print("Keterangan         : ");
  Serial.println(wifiStabilityLabel(successRate, rssi));
  Serial.println("============================================================");
}

String classifyGsr(float gsrUs) {
  if (gsrUs <= 5.0f) {
    return "Low";
  }
  if (gsrUs <= 12.0f) {
    return "Moderate";
  }
  return "High";
}

String classifyEmg(float emgUv) {
  if (emgUv < 200.0f) {
    return "Normal";
  }
  return "Stress";
}

String classifyCombinedStress(float gsrUs, float emgUv) {
  const bool emgStress = emgUv >= 200.0f;
  const bool gsrNormal = gsrUs <= 5.0f;
  const bool gsrModerate = gsrUs > 5.0f && gsrUs <= 12.0f;

  if (!emgStress && gsrNormal) return "Normal - Low";
  if (!emgStress && gsrModerate) return "Normal - Moderate";
  if (!emgStress) return "Normal - High";
  if (gsrNormal) return "Stres - Low";
  if (gsrModerate) return "Stres - Moderate";
  return "Stres - High";
}

float combinedStressIndex(float gsrUs, float emgUv) {
  const float gsrScore = (gsrUs / 20.0f) * 100.0f;
  const float emgScore = (emgUv / 200.0f) * 100.0f;
  return (clampRange(gsrScore, 0.0f, 100.0f) * 0.4f) +
         (clampRange(emgScore, 0.0f, 100.0f) * 0.6f);
}

bool uploadCompressedPacket(const UploadPacket& packet) {
  packetSequence++;

  const String stressStatus = packet.sensorsAttached
      ? classifyCombinedStress(packet.gsrAvg, packet.emgAvg)
      : "SENSOR_NOT_ATTACHED";
  const String gsrStatus = packet.gsrSignalValid
      ? classifyGsr(packet.gsrAvg)
      : "SENSOR_NOT_ATTACHED";
  const String emgStatus = packet.emgSignalValid
      ? classifyEmg(packet.emgAvg)
      : "SENSOR_NOT_ATTACHED";

  const String deviceBasePath = String("/health_monitoring/devices/") + DEVICE_ID;
  const String deviceLatestPath = deviceBasePath + "/latest";
  const String deviceHistoryPath = deviceBasePath + "/history";
  const String globalLatestPath = "/health_monitoring/latest";

  

  FirebaseJson latest;
  latest.set("schema_version", 2);
  latest.set("cs_enabled", true);
  latest.set("cs_n", CS_N);
  latest.set("cs_m", CS_M);
  latest.set("cs_seed", (int)CS_SEED);
  latest.set("cs_transform", "dwt_haar");
  latest.set("cs_measurement", "gaussian");
  latest.set("window_id", (int)packet.windowId);

  
  FirebaseJsonArray gsrArray;
  for (int i = 0; i < CS_M; i++) {
    gsrArray.add(packet.yGsr[i]);
  }
  latest.set("y_gsr", gsrArray);

  FirebaseJsonArray emgArray;
  for (int i = 0; i < CS_M; i++) {
    emgArray.add(packet.yEmg[i]);
  }
  latest.set("y_emg", emgArray);

  
  latest.set("gsr", packet.gsrAvg);
  latest.set("emg", packet.emgAvg);
  latest.set("gsr_unit", "uS");
  latest.set("emg_unit", "uV");
  latest.set("gsr_status", gsrStatus);
  latest.set("emg_status", emgStatus);
  latest.set("stress_status", stressStatus);
  latest.set("stress_index", packet.stressIndex);
  latest.set("sensors_attached", packet.sensorsAttached);
  latest.set("gsr_signal_valid", packet.gsrSignalValid);
  latest.set("emg_signal_valid", packet.emgSignalValid);
  latest.set("gsr_raw_min", (int)packet.gsrRawMin);
  latest.set("gsr_raw_max", (int)packet.gsrRawMax);
  latest.set("gsr_raw_avg", packet.gsrRawAvg);
  latest.set("emg_raw_min", (int)packet.emgRawMin);
  latest.set("emg_raw_max", (int)packet.emgRawMax);
  latest.set("emg_raw_avg", packet.emgRawAvg);
  latest.set("value_source", "esp32_filtered_average");
  latest.set("timestamp", static_cast<int64_t>(currentEpochMs()));
  latest.set("device_id", DEVICE_ID);
  latest.set("sequence", static_cast<int>(packetSequence));
  latest.set("rssi", WiFi.RSSI());
  latest.set("uptime_ms", static_cast<int64_t>(millis()));

  

  const bool deviceLatestOk = writeJsonWithRetry(deviceLatestPath, latest, false);
  if (!deviceLatestOk) {
    return false;
  }

  const bool globalLatestOk = writeJsonWithRetry(globalLatestPath, latest, false);
  if (!globalLatestOk) {
    Serial.println("[Firebase] global latest mirror write failed.");
  }

  
  FirebaseJsonArray historyGsrArray;
  FirebaseJsonArray historyEmgArray;
  for (int i = 0; i < CS_M; i++) {
    historyGsrArray.add(packet.yGsr[i]);
    historyEmgArray.add(packet.yEmg[i]);
  }

  FirebaseJson history;
  history.set("schema_version", 2);
  history.set("cs_enabled", true);
  history.set("cs_n", CS_N);
  history.set("cs_m", CS_M);
  history.set("cs_seed", (int)CS_SEED);
  history.set("cs_transform", "dwt_haar");
  history.set("cs_measurement", "gaussian");
  history.set("window_id", (int)packet.windowId);
  history.set("y_gsr", historyGsrArray);
  history.set("y_emg", historyEmgArray);
  history.set("gsr", packet.gsrAvg);
  history.set("emg", packet.emgAvg);
  history.set("gsr_unit", "uS");
  history.set("emg_unit", "uV");
  history.set("gsr_status", gsrStatus);
  history.set("emg_status", emgStatus);
  history.set("stress_status", stressStatus);
  history.set("stress_index", packet.stressIndex);
  history.set("sensors_attached", packet.sensorsAttached);
  history.set("gsr_signal_valid", packet.gsrSignalValid);
  history.set("emg_signal_valid", packet.emgSignalValid);
  history.set("gsr_raw_min", (int)packet.gsrRawMin);
  history.set("gsr_raw_max", (int)packet.gsrRawMax);
  history.set("gsr_raw_avg", packet.gsrRawAvg);
  history.set("emg_raw_min", (int)packet.emgRawMin);
  history.set("emg_raw_max", (int)packet.emgRawMax);
  history.set("emg_raw_avg", packet.emgRawAvg);
  history.set("value_source", "esp32_filtered_average");
  history.set("timestamp", static_cast<int64_t>(currentEpochMs()));
  history.set("device_id", DEVICE_ID);
  history.set("sequence", static_cast<int>(packetSequence));
  history.set("rssi", WiFi.RSSI());
  history.set("uptime_ms", static_cast<int64_t>(millis()));

  if (!writeJsonWithRetry(deviceHistoryPath, history, true)) {
    Serial.println("[Firebase] history push failed after retries.");
  }

  return true;
}

void updateLatestUploadStatus(
  bool cloudReady,
  bool uploadOk,
  int32_t rssi,
  uint32_t uploadDelayMs,
  uint32_t uploadedWindowId
) {
  latestCloudReady = cloudReady;
  latestUploadOk = uploadOk;
  latestUploadRssi = rssi;
  latestUploadDelayMs = uploadDelayMs;
  latestUploadedWindowId = uploadedWindowId;
}

void cloudTask(void* parameter) {
  uint32_t lastReconnectAttempt = 0;
  uint32_t lastFirebaseRetryAttempt = 0;

  Serial.print("[Core] Cloud task running on core ");
  Serial.println(xPortGetCoreID());

  for (;;) {
    if (
      WiFi.status() != WL_CONNECTED &&
      millis() - lastReconnectAttempt >= 10000
    ) {
      lastReconnectAttempt = millis();
      Serial.println("[WiFi] Core 0 reconnect attempt...");
      WiFi.disconnect();
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    }

    if (
      WiFi.status() == WL_CONNECTED &&
      !Firebase.ready() &&
      millis() - lastFirebaseRetryAttempt >= FIREBASE_RETRY_INTERVAL_MS
    ) {
      lastFirebaseRetryAttempt = millis();
      Serial.println("[Firebase] Token/cloud not ready. Upload skipped until client recovers.");
      Firebase.reconnectWiFi(true);

      if (millis() - firebaseLastBeginMs >= FIREBASE_REBEGIN_INTERVAL_MS) {
        Serial.println("[Firebase] Long recovery timeout. Rebegin client once.");
        firebaseClientStarted = false;
        initFirebase(false);
      }
    }

    UploadPacket packet;
    if (uploadQueue != nullptr &&
        xQueueReceive(uploadQueue, &packet, pdMS_TO_TICKS(100)) == pdTRUE) {
      const int32_t uploadRssi = WiFi.status() == WL_CONNECTED
          ? WiFi.RSSI()
          : -127;
      const bool cloudReady =
          WiFi.status() == WL_CONNECTED && Firebase.ready();
      const uint32_t uploadStartMs = millis();
      const bool uploadOk = cloudReady
          ? uploadCompressedPacket(packet)
          : false;
      const uint32_t uploadDelayMs = cloudReady
          ? (millis() - uploadStartMs)
          : 0;

      uploadAttemptWindows++;
      if (uploadOk) {
        uploadSuccessWindows++;
      }

      updateLatestUploadStatus(
        cloudReady,
        uploadOk,
        uploadRssi,
        uploadDelayMs,
        packet.windowId
      );
      printWifiDistanceTestReport(
        cloudReady,
        uploadOk,
        uploadRssi,
        uploadDelayMs,
        packet.windowId
      );
    }

    vTaskDelay(pdMS_TO_TICKS(20));
  }
}

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(400);

  const esp_reset_reason_t resetReason = esp_reset_reason();
  Serial.print("[Reset] reason=");
  Serial.print(resetReasonText(resetReason));
  Serial.print(" code=");
  Serial.println((int)resetReason);
  Serial.print("[Core] setup() running on core ");
  Serial.println(xPortGetCoreID());
  Serial.println("[TFT] Initializing ST7735...");
  SPI.begin(TFT_SCLK, -1, TFT_MOSI, TFT_CS);
  tft.initR(INITR_BLACKTAB);
  tft.setRotation(1);
  tft.setTextWrap(false);
  tftReady = true;
  Serial.println("[TFT] ST7735 initialized.");
  tftLoadingScreen("Starting device", 15);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);
  analogSetPinAttenuation(GSR_PIN, ADC_11db);
  analogSetPinAttenuation(EMG_PIN, ADC_11db);
  pinMode(GSR_PIN, INPUT);
  pinMode(EMG_PIN, INPUT);

  tftLoadingScreen("Connecting WiFi", 35);
  connectWiFi();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");

  if (WiFi.status() == WL_CONNECTED) {
    initFirebase(false, 0);
  } else {
    Serial.println("[Firebase] Skipped while WiFi is offline.");
  }

  tftLoadingScreen("Preparing sensor", 80);
  cs_generate_wavelet_basis();
  cs_generate_measurement_matrix();
  Serial.print("[CS] Measurement matrix generated: ");
  Serial.print(CS_M);
  Serial.print("x");
  Serial.print(CS_N);
  Serial.print(" (CR=");
  Serial.print((float)CS_N / (float)CS_M, 2);
  Serial.println(")");
  Serial.print("[Filter] GSR median=");
  Serial.print(GSR_ADC_FILTER_SAMPLES);
  Serial.print(" alpha=");
  Serial.print(GSR_FILTER_ALPHA, 2);
  Serial.print(" | EMG median=");
  Serial.print(EMG_ADC_FILTER_SAMPLES);
  Serial.print(" alpha=");
  Serial.println(EMG_FILTER_ALPHA, 2);

  tftLoadingScreen("Ready", 100);
  delay(500);

  uploadQueue = xQueueCreate(1, sizeof(UploadPacket));
  if (uploadQueue == nullptr) {
    Serial.println("[Core] ERROR: Upload queue allocation failed.");
  } else {
    xTaskCreatePinnedToCore(
      cloudTask,
      "cloudTask",
      CLOUD_TASK_STACK_BYTES,
      nullptr,
      1,
      &cloudTaskHandle,
      0
    );
  }

  Serial.println("[Core] core 1 = sensor/filter/CS/reconstruction/TFT/Serial");
  Serial.println("[Core] core 0 = WiFi/Firebase token/upload/retry");
  Serial.println("[I-Care ESP32] Setup complete (Compressive Sensing mode).");
}

void loop() {
  fillCsBuffer();
  windowId++;

  float yGsr[CS_M];
  float yEmg[CS_M];
  cs_compress_signal(cs_gsr_buffer, yGsr);
  cs_compress_signal(cs_emg_buffer, yEmg);

  const float gsrAvg = arrayMean(cs_gsr_buffer, CS_N);
  const float emgAvg = arrayMean(cs_emg_buffer, CS_N);
  const float stressIndex = sensorsAttached
      ? combinedStressIndex(gsrAvg, emgAvg)
      : 0.0f;

  UploadPacket packet;
  packet.windowId = windowId;
  for (int i = 0; i < CS_M; i++) {
    packet.yGsr[i] = yGsr[i];
    packet.yEmg[i] = yEmg[i];
  }
  packet.gsrAvg = gsrAvg;
  packet.emgAvg = emgAvg;
  packet.stressIndex = stressIndex;
  packet.sensorsAttached = sensorsAttached;
  packet.gsrSignalValid = gsrSignalValid;
  packet.emgSignalValid = emgSignalValid;
  packet.gsrRawMin = gsrRawMin;
  packet.gsrRawMax = gsrRawMax;
  packet.emgRawMin = emgRawMin;
  packet.emgRawMax = emgRawMax;
  packet.gsrRawAvg = gsrRawAvg;
  packet.emgRawAvg = emgRawAvg;

  if (uploadQueue != nullptr) {
    xQueueOverwrite(uploadQueue, &packet);
  }

  const bool wifiOnline = WiFi.status() == WL_CONNECTED;
  const int32_t serialRssi = wifiOnline
      ? (latestUploadRssi > -127 ? latestUploadRssi : WiFi.RSSI())
      : -127;
  const float serialPacketLoss = uploadPacketLossPercent();

  if (!WIFI_DISTANCE_TEST_REPORT_ENABLED) {
    Serial.print("[I-Care CS] window=");
    Serial.print(windowId);
    Serial.print(" gsrAvg(uS)=");
    Serial.print(gsrAvg, 2);
    Serial.print(" emgAvg(uV)=");
    Serial.print(emgAvg, 2);
    Serial.print(" attached=");
    Serial.print(sensorsAttached ? "YES" : "NO");
    Serial.print(" valid=");
    Serial.print(gsrSignalValid ? "GSR" : "-");
    Serial.print("/");
    Serial.print(emgSignalValid ? "EMG" : "-");
    Serial.print(" rawGsr=");
    Serial.print(gsrRawMin);
    Serial.print("-");
    Serial.print(gsrRawMax);
    Serial.print(" rawEmg=");
    Serial.print(emgRawMin);
    Serial.print("-");
    Serial.print(emgRawMax);
    Serial.print(" stressIndex=");
    Serial.print(stressIndex, 2);
    Serial.print(" sent=");
    Serial.print(CS_M);
    Serial.print("/");
    Serial.print(CS_N);
    Serial.print(" wifiRssi=");
    if (wifiOnline) {
      Serial.print(serialRssi);
      Serial.print("dBm");
    } else {
      Serial.print("OFF");
    }
    Serial.print(" packetLoss=");
    Serial.print(serialPacketLoss, 1);
    Serial.print("%");
    Serial.print(" uploadWin=");
    Serial.print(uploadSuccessWindows);
    Serial.print("/");
    Serial.print(uploadAttemptWindows);
    Serial.print(" cloud=");
    Serial.println(wifiUploadStatusText(latestCloudReady, latestUploadOk));
  }

  if (!gsrSignalValid && windowId % 5 == 0) {
    Serial.print("[GSR DIAG] GPIO34=");
    Serial.print(analogRead(34));
    Serial.print(" GPIO32=");
    Serial.print(analogRead(32));
    Serial.print(" GPIO33=");
    Serial.print(analogRead(33));
    Serial.print(" GPIO36=");
    Serial.print(analogRead(36));
    Serial.print(" GPIO39=");
    Serial.println(analogRead(39));
  }

  tftRealtimeScreen(
    gsrAvg,
    emgAvg,
    gsrSignalValid,
    emgSignalValid,
    latestUploadOk
  );

  
  delay(100);
}
