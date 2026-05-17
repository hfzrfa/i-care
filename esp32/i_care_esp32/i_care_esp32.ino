#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

#include "Secrets.h"
#include "cs_config.h"
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
#define SCREEN_ADDRESS 0x3C
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
bool oledReady = false;

static const int GSR_PIN = 34;
static const int EMG_PIN = 35;

static const uint32_t SERIAL_BAUD = 115200;
static const uint32_t UPLOAD_RETRY_COUNT = 3;
static const uint32_t UPLOAD_RETRY_DELAY_MS = 250;

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
  if (gsrUs <= 5.0f) return "NORMAL";
  if (gsrUs <= 12.0f) return "MODERATE";
  return "HIGH";
}

String shortEmgStatus(float emgUv) {
  if (emgUv <= 150.0f) return "RELAKS";
  return "STRESS";
}

String shortCombinedStatus(float gsrUs, float emgUv) {
  const bool emgStress = emgUv > 150.0f;
  if (gsrUs <= 5.0f && !emgStress) return "OK";
  if (gsrUs <= 12.0f && !emgStress) return "MILD";
  if (!emgStress) return "GSR HI";
  if (gsrUs <= 5.0f) return "EMG HI";
  if (gsrUs <= 12.0f) return "MID";
  return "HIGH";
}

void oledHeader(const String& title, bool online) {
  if (!oledReady) return;

  display.fillRect(0, 0, SCREEN_WIDTH, 11, SSD1306_WHITE);
  display.setTextSize(1);
  display.setTextColor(SSD1306_BLACK);
  display.setCursor(2, 2);
  display.print(title);
  display.setCursor(102, 2);
  display.print(online ? "WiFi" : "OFF");
  display.setTextColor(SSD1306_WHITE);
}

void oledStatusScreen(const String& title, const String& line1, const String& line2) {
  if (!oledReady) return;

  display.clearDisplay();
  oledHeader(title, WiFi.status() == WL_CONNECTED);
  display.setTextSize(1);
  display.setCursor(0, 18);
  display.println(line1);
  display.setCursor(0, 32);
  display.println(line2);
  display.drawFastHLine(0, 50, SCREEN_WIDTH, SSD1306_WHITE);
  display.setCursor(0, 54);
  display.print("I-Care Stress Monitor");
  display.display();
}

void oledProgressScreen(const String& title, const String& line1, uint8_t progressPercent) {
  if (!oledReady) return;

  const int barWidth = 104;
  const int fillWidth = (barWidth * progressPercent) / 100;

  display.clearDisplay();
  oledHeader(title, WiFi.status() == WL_CONNECTED);
  display.setTextSize(1);
  display.setCursor(0, 18);
  display.println(line1);
  display.drawRect(12, 36, barWidth, 10, SSD1306_WHITE);
  display.fillRect(14, 38, fillWidth > 4 ? fillWidth - 4 : 0, 6, SSD1306_WHITE);
  display.setCursor(46, 52);
  display.print(progressPercent);
  display.print("%");
  display.display();
}

void oledRealtimeScreen(float gsrAvg, float emgAvg, bool uploadOk) {
  if (!oledReady) return;

  display.clearDisplay();
  oledHeader(uploadOk ? "I-CARE LIVE" : "UPLOAD FAIL", WiFi.status() == WL_CONNECTED);

  display.setTextSize(1);
  display.setCursor(0, 14);
  display.print("GSR ");
  display.print(shortGsrStatus(gsrAvg));
  display.setCursor(92, 14);
  display.print("W");
  display.print(windowId % 1000);

  display.setTextSize(2);
  display.setCursor(0, 23);
  display.print(gsrAvg, 1);
  display.setTextSize(1);
  display.setCursor(58, 30);
  display.print("uS");

  display.drawFastHLine(0, 40, SCREEN_WIDTH, SSD1306_WHITE);

  display.setTextSize(1);
  display.setCursor(0, 43);
  display.print("EMG ");
  display.print(shortEmgStatus(emgAvg));
  display.setCursor(82, 43);
  display.print(shortCombinedStatus(gsrAvg, emgAvg));

  display.setTextSize(2);
  display.setCursor(0, 52);
  display.print(emgAvg, 0);
  display.setTextSize(1);
  display.setCursor(44, 58);
  display.print("uV");

  display.display();
}

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  Serial.print("[WiFi] Connecting");
  oledStatusScreen("NETWORK", "Connecting WiFi", WIFI_SSID);

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print('.');
    attempts++;
    if (attempts > 30) {
      
      WiFi.disconnect();
      delay(500);
      WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
      attempts = 0;
    }
  }
  Serial.println();
  Serial.print("[WiFi] Connected. IP: ");
  Serial.println(WiFi.localIP());

  oledStatusScreen("NETWORK", "WiFi connected", WiFi.localIP().toString());
  delay(1000);
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
  oledStatusScreen("FIREBASE", "Initializing client", "Please wait...");

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
      oledProgressScreen("FIREBASE", "Authenticating", min(fbAttempts * 3, 90));
    }
  }
  
  if (Firebase.ready()) {
    Serial.println("[Firebase] Ready.");
    oledStatusScreen("FIREBASE", "Firebase ready", "Streaming enabled");
  } else {
    Serial.println("[Firebase] Timeout!");
    oledStatusScreen("FIREBASE", "Firebase timeout", "Check credentials");
  }
  delay(1000);
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

static const float GSR_ADC_MIN = 400.0f;
static const float GSR_ADC_MAX = 3200.0f;
static const float EMG_ADC_MIN = 500.0f;
static const float EMG_ADC_MAX = 3400.0f;
static const float GSR_US_MIN = 0.0f;
static const float GSR_US_MAX = 20.0f;
static const float EMG_UV_MIN = 0.0f;
static const float EMG_UV_MAX = 250.0f;

void fillCsBuffer() {
  cs_buffer_index = 0;

  for (int i = 0; i < CS_N; i++) {
    const float gsrRaw = (float)analogRead(GSR_PIN);
    const float emgRaw = (float)analogRead(EMG_PIN);

    cs_gsr_buffer[i] = mapAdcToRange(gsrRaw, GSR_ADC_MIN, GSR_ADC_MAX, GSR_US_MIN, GSR_US_MAX);
    cs_emg_buffer[i] = mapAdcToRange(emgRaw, EMG_ADC_MIN, EMG_ADC_MAX, EMG_UV_MIN, EMG_UV_MAX);

    
    delayMicroseconds(CS_SAMPLE_DELAY_US);
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
    return "Normal";
  }
  if (gsrUs <= 12.0f) {
    return "Moderate Stress";
  }
  return "High Stress";
}

String classifyEmg(float emgUv) {
  if (emgUv <= 150.0f) {
    return "Relaks";
  }
  return "Stress";
}

String classifyCombinedStress(float gsrUs, float emgUv) {
  const bool emgStress = emgUv > 150.0f;
  const bool gsrNormal = gsrUs <= 5.0f;
  const bool gsrModerate = gsrUs > 5.0f && gsrUs <= 12.0f;

  if (!emgStress && gsrNormal) return "Relaks - Normal";
  if (!emgStress && gsrModerate) return "Relaks - Moderate";
  if (!emgStress) return "Relaks - High";
  if (gsrNormal) return "Stress - Normal";
  if (gsrModerate) return "Stress - Moderate";
  return "Stress - High";
}

float combinedStressIndex(float gsrUs, float emgUv) {
  const float gsrScore = (gsrUs / 20.0f) * 100.0f;
  const float emgScore = ((emgUv - 20.0f) / 130.0f) * 100.0f;
  return (clampRange(gsrScore, 0.0f, 100.0f) * 0.4f) +
         (clampRange(emgScore, 0.0f, 100.0f) * 0.6f);
}

bool uploadCompressedPacket(const float* yGsr, const float* yEmg) {
  packetSequence++;
  windowId++;

  
  const float gsrAvg = arrayMean(cs_gsr_buffer, CS_N);
  const float emgAvg = arrayMean(cs_emg_buffer, CS_N);
  const float stressIndex = combinedStressIndex(gsrAvg, emgAvg);
  const String stressStatus = classifyCombinedStress(gsrAvg, emgAvg);
  const String gsrStatus = classifyGsr(gsrAvg);
  const String emgStatus = classifyEmg(emgAvg);

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

  
  if (!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println(F("SSD1306 allocation failed"));
    
  } else {
    oledReady = true;
    display.setTextWrap(false);
    oledStatusScreen("I-CARE", "Booting ESP32", "Preparing sensors");
  }

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  connectWiFi();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  
  initFirebase();

  
  cs_generate_measurement_matrix();
  Serial.print("[CS] Measurement matrix generated: ");
  Serial.print(CS_M);
  Serial.print("x");
  Serial.print(CS_N);
  Serial.print(" (CR=");
  Serial.print((float)CS_N / (float)CS_M, 2);
  Serial.println(")");

  oledStatusScreen("I-CARE", "Setup complete", "Monitoring started");
  delay(1000); 

  Serial.println("[I-Care ESP32] Setup complete (Compressive Sensing mode).");
}

void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    connectWiFi();
  }

  if (!Firebase.ready()) {
    delay(100);
    return;
  }

  
  Serial.println("[CS] Sampling...");
  fillCsBuffer();

  
  float yGsr[CS_M];
  float yEmg[CS_M];
  cs_compress_signal(cs_gsr_buffer, yGsr);
  cs_compress_signal(cs_emg_buffer, yEmg);

  
  const bool ok = uploadCompressedPacket(yGsr, yEmg);

  const float gsrAvg = arrayMean(cs_gsr_buffer, CS_N);
  const float emgAvg = arrayMean(cs_emg_buffer, CS_N);
  const float stressIndex = combinedStressIndex(gsrAvg, emgAvg);

  Serial.print("[I-Care CS] window=");
  Serial.print(windowId);
  Serial.print(" gsrAvg(uS)=");
  Serial.print(gsrAvg, 2);
  Serial.print(" emgAvg(uV)=");
  Serial.print(emgAvg, 2);
  Serial.print(" stressIndex=");
  Serial.print(stressIndex, 2);
  Serial.print(" sent=");
  Serial.print(CS_M);
  Serial.print("/");
  Serial.print(CS_N);
  Serial.print(" upload=");
  Serial.println(ok ? "OK" : "FAIL");

  oledRealtimeScreen(gsrAvg, emgAvg, ok);

  
  delay(100);
}

