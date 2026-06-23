#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_ST7735.h>

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
static const uint32_t UPLOAD_RETRY_COUNT = 3;
static const uint32_t UPLOAD_RETRY_DELAY_MS = 250;
static const int ADC_FILTER_SAMPLES = 9;
static const float SENSOR_FILTER_ALPHA = 0.28f;
static const float SENSOR_RAIL_RATIO = 0.25f;
static const uint16_t ADC_RAIL_LOW = 8;
static const uint16_t ADC_RAIL_HIGH = 4087;
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

uint32_t packetSequence = 0;
uint32_t windowId = 0;

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

void tftHeader(const String& title, bool online) {
  if (!tftReady) return;

  tft.fillRect(0, 0, 160, 22, TFT_NAVY);
  tft.setTextWrap(false);
  tft.setTextSize(1);
  tft.setTextColor(ST77XX_WHITE);
  tft.setCursor(6, 7);
  tft.print(title);
  tft.setTextColor(online ? ST77XX_GREEN : ST77XX_RED);
  tft.setCursor(130, 7);
  tft.print(online ? "ON" : "OFF");
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

void initFirebase() {
  tftLoadingScreen("Connecting cloud", 60);

  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.token_status_callback = tokenStatusCallback;

  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  Firebase.reconnectWiFi(true);
  Firebase.begin(&config, &auth);

  Serial.println("[Firebase] Initializing client...");
  int fbAttempts = 0;
  while (!Firebase.ready() && fbAttempts < 30) {
    delay(500);
    fbAttempts++;
    if (fbAttempts % 2 == 0) {
      tftLoadingScreen(
        "Authenticating",
        (uint8_t)min(60 + fbAttempts, 90)
      );
    }
  }
  
  if (Firebase.ready()) {
    Serial.println("[Firebase] Ready.");
    tftLoadingScreen("Cloud connected", 75);
  } else {
    Serial.println("[Firebase] Timeout!");
    tftLoadingScreen("Local mode active", 75);
  }
  delay(300);
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

uint16_t readMedianAdc(int pin) {
  uint16_t samples[ADC_FILTER_SAMPLES];
  for (int i = 0; i < ADC_FILTER_SAMPLES; i++) {
    samples[i] = (uint16_t)analogRead(pin);
    delayMicroseconds(180);
  }

  for (int i = 1; i < ADC_FILTER_SAMPLES; i++) {
    const uint16_t key = samples[i];
    int j = i - 1;
    while (j >= 0 && samples[j] > key) {
      samples[j + 1] = samples[j];
      j--;
    }
    samples[j + 1] = key;
  }

  return samples[ADC_FILTER_SAMPLES / 2];
}

float smoothSensorValue(float previous, float current, bool initialized) {
  if (!initialized) {
    return current;
  }
  return (previous * (1.0f - SENSOR_FILTER_ALPHA)) + (current * SENSOR_FILTER_ALPHA);
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
    const uint16_t gsrRawValue = readMedianAdc(GSR_PIN);
    const uint16_t emgRawValue = readMedianAdc(EMG_PIN);
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
      gsrFilterInitialized
    );
    emgFiltered = smoothSensorValue(
      emgFiltered,
      emgMapped,
      emgFilterInitialized
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

bool uploadCompressedPacket(const float* yGsr, const float* yEmg) {
  packetSequence++;

  
  const float gsrAvg = arrayMean(cs_gsr_buffer, CS_N);
  const float emgAvg = arrayMean(cs_emg_buffer, CS_N);
  const float stressIndex = sensorsAttached ? combinedStressIndex(gsrAvg, emgAvg) : 0.0f;
  const String stressStatus = sensorsAttached
      ? classifyCombinedStress(gsrAvg, emgAvg)
      : "SENSOR_NOT_ATTACHED";
  const String gsrStatus = gsrSignalValid ? classifyGsr(gsrAvg) : "SENSOR_NOT_ATTACHED";
  const String emgStatus = emgSignalValid ? classifyEmg(emgAvg) : "SENSOR_NOT_ATTACHED";

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
  latest.set("window_id", (int)windowId);

  
  FirebaseJsonArray gsrArray;
  for (int i = 0; i < CS_M; i++) {
    gsrArray.add(yGsr[i]);
  }
  latest.set("y_gsr", gsrArray);

  FirebaseJsonArray emgArray;
  for (int i = 0; i < CS_M; i++) {
    emgArray.add(yEmg[i]);
  }
  latest.set("y_emg", emgArray);

  
  latest.set("gsr", gsrAvg);
  latest.set("emg", emgAvg);
  latest.set("gsr_unit", "uS");
  latest.set("emg_unit", "uV");
  latest.set("gsr_status", gsrStatus);
  latest.set("emg_status", emgStatus);
  latest.set("stress_status", stressStatus);
  latest.set("stress_index", stressIndex);
  latest.set("sensors_attached", sensorsAttached);
  latest.set("gsr_signal_valid", gsrSignalValid);
  latest.set("emg_signal_valid", emgSignalValid);
  latest.set("gsr_raw_min", (int)gsrRawMin);
  latest.set("gsr_raw_max", (int)gsrRawMax);
  latest.set("gsr_raw_avg", gsrRawAvg);
  latest.set("emg_raw_min", (int)emgRawMin);
  latest.set("emg_raw_max", (int)emgRawMax);
  latest.set("emg_raw_avg", emgRawAvg);
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
    historyGsrArray.add(yGsr[i]);
    historyEmgArray.add(yEmg[i]);
  }

  FirebaseJson history;
  history.set("schema_version", 2);
  history.set("cs_enabled", true);
  history.set("cs_n", CS_N);
  history.set("cs_m", CS_M);
  history.set("cs_seed", (int)CS_SEED);
  history.set("cs_transform", "dwt_haar");
  history.set("cs_measurement", "gaussian");
  history.set("window_id", (int)windowId);
  history.set("y_gsr", historyGsrArray);
  history.set("y_emg", historyEmgArray);
  history.set("gsr", gsrAvg);
  history.set("emg", emgAvg);
  history.set("gsr_unit", "uS");
  history.set("emg_unit", "uV");
  history.set("gsr_status", gsrStatus);
  history.set("emg_status", emgStatus);
  history.set("stress_status", stressStatus);
  history.set("stress_index", stressIndex);
  history.set("sensors_attached", sensorsAttached);
  history.set("gsr_signal_valid", gsrSignalValid);
  history.set("emg_signal_valid", emgSignalValid);
  history.set("gsr_raw_min", (int)gsrRawMin);
  history.set("gsr_raw_max", (int)gsrRawMax);
  history.set("gsr_raw_avg", gsrRawAvg);
  history.set("emg_raw_min", (int)emgRawMin);
  history.set("emg_raw_max", (int)emgRawMax);
  history.set("emg_raw_avg", emgRawAvg);
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

void setup() {
  Serial.begin(SERIAL_BAUD);
  delay(400);

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
    tftLoadingScreen("Connecting cloud", 60);
    initFirebase();
  } else {
    Serial.println("[Firebase] Skipped while WiFi is offline.");
    tftLoadingScreen("Local mode active", 60);
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

  tftLoadingScreen("Ready", 100);
  delay(500);

  Serial.println("[I-Care ESP32] Setup complete (Compressive Sensing mode).");
}

void loop() {
  static uint32_t lastReconnectAttempt = 0;
  if (
    WiFi.status() != WL_CONNECTED &&
    millis() - lastReconnectAttempt >= 10000
  ) {
    lastReconnectAttempt = millis();
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  }

  Serial.println("[CS] Sampling...");
  fillCsBuffer();
  windowId++;

  float yGsr[CS_M];
  float yEmg[CS_M];
  cs_compress_signal(cs_gsr_buffer, yGsr);
  cs_compress_signal(cs_emg_buffer, yEmg);

  const bool cloudReady =
      WiFi.status() == WL_CONNECTED && Firebase.ready();
  const bool ok = cloudReady
      ? uploadCompressedPacket(yGsr, yEmg)
      : false;

  const float gsrAvg = arrayMean(cs_gsr_buffer, CS_N);
  const float emgAvg = arrayMean(cs_emg_buffer, CS_N);
  const float stressIndex = sensorsAttached
      ? combinedStressIndex(gsrAvg, emgAvg)
      : 0.0f;

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
  Serial.print(" avg=");
  Serial.print(gsrRawAvg, 1);
  Serial.print(" rawEmg=");
  Serial.print(emgRawMin);
  Serial.print("-");
  Serial.print(emgRawMax);
  Serial.print(" avg=");
  Serial.print(emgRawAvg, 1);
  Serial.print(" stressIndex=");
  Serial.print(stressIndex, 2);
  Serial.print(" sent=");
  Serial.print(CS_M);
  Serial.print("/");
  Serial.print(CS_N);
  Serial.print(" upload=");
  Serial.println(ok ? "OK" : (cloudReady ? "FAIL" : "OFFLINE"));

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
    ok
  );

  
  delay(100);
}
