#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <time.h>

// Install the Firebase ESP Client library by Mobizt from Library Manager.
// Copy Secrets.example.h to Secrets.h and fill your credentials.
#include "Secrets.h"

// Helper headers are provided by Firebase_ESP_Client examples.
#include <addons/TokenHelper.h>
#include <addons/RTDBHelper.h>

// ADC pins (ESP32 input-only analog pins are safe defaults).
static const int GSR_PIN = 34;
static const int EMG_PIN = 35;

static const uint32_t SERIAL_BAUD = 115200;
static const uint32_t READ_SAMPLES = 12;
static const uint32_t UPLOAD_INTERVAL_MS = 1000;
static const uint32_t UPLOAD_RETRY_COUNT = 3;
static const uint32_t UPLOAD_RETRY_DELAY_MS = 250;

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

uint32_t lastUploadMs = 0;
uint32_t packetSequence = 0;

uint64_t currentEpochMs() {
  const time_t now = time(nullptr);
  // If NTP is not ready yet, return an increasing fallback timestamp.
  if (now < 1700000000) {
    return static_cast<uint64_t>(millis());
  }
  return static_cast<uint64_t>(now) * 1000ULL;
}

struct SensorPacket {
  float gsr;
  float emg;
  float stressIndex;
  String stressStatus;
  uint64_t timestampMs;
};

void connectWiFi() {
  if (WiFi.status() == WL_CONNECTED) {
    return;
  }

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  Serial.print("[WiFi] Connecting");
  while (WiFi.status() != WL_CONNECTED) {
    delay(400);
    Serial.print('.');
  }
  Serial.println();
  Serial.print("[WiFi] Connected. IP: ");
  Serial.println(WiFi.localIP());
}

float readAveragedADC(int pin) {
  uint32_t total = 0;
  for (uint32_t i = 0; i < READ_SAMPLES; i++) {
    total += analogRead(pin);
    delay(2);
  }
  return static_cast<float>(total) / static_cast<float>(READ_SAMPLES);
}

float clamp01(float value) {
  if (value < 0.0f) {
    return 0.0f;
  }
  if (value > 1.0f) {
    return 1.0f;
  }
  return value;
}

float normalizeTo100(float raw, float minAdc, float maxAdc) {
  if (maxAdc <= minAdc) {
    return 0.0f;
  }
  const float normalized = (raw - minAdc) / (maxAdc - minAdc);
  return clamp01(normalized) * 100.0f;
}

String classifyStress(float stressIndex) {
  // Keep this in sync with app legend: NORMAL 0-39, SEDANG 40-69, STRESS 70-100.
  if (stressIndex < 40.0f) {
    return "NORMAL";
  }
  if (stressIndex < 70.0f) {
    return "SEDANG";
  }
  return "STRESS";
}

SensorPacket readSensors() {
  // Calibrate these ranges against your real hardware.
  // Default ranges below are a practical starting point for many analog front-ends.
  static const float GSR_ADC_MIN = 400.0f;
  static const float GSR_ADC_MAX = 3200.0f;
  static const float EMG_ADC_MIN = 500.0f;
  static const float EMG_ADC_MAX = 3400.0f;

  const float gsrRaw = readAveragedADC(GSR_PIN);
  const float emgRaw = readAveragedADC(EMG_PIN);

  const float gsrValue = normalizeTo100(gsrRaw, GSR_ADC_MIN, GSR_ADC_MAX);
  const float emgValue = normalizeTo100(emgRaw, EMG_ADC_MIN, EMG_ADC_MAX);

  // Weighted stress index; adjust weights if needed.
  const float stressIndex = (gsrValue * 0.55f) + (emgValue * 0.45f);

  SensorPacket packet;
  packet.gsr = gsrValue;
  packet.emg = emgValue;
  packet.stressIndex = stressIndex;
  packet.stressStatus = classifyStress(stressIndex);
  packet.timestampMs = currentEpochMs();
  return packet;
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
  config.api_key = API_KEY;
  config.database_url = DATABASE_URL;
  config.token_status_callback = tokenStatusCallback;

  auth.user.email = USER_EMAIL;
  auth.user.password = USER_PASSWORD;

  Firebase.reconnectWiFi(true);
  Firebase.begin(&config, &auth);

  Serial.println("[Firebase] Initializing client...");
  while (!Firebase.ready()) {
    delay(200);
  }
  Serial.println("[Firebase] Ready.");
}

bool uploadPacket(const SensorPacket& packet) {
  packetSequence++;

  const String deviceBasePath = String("/health_monitoring/devices/") + DEVICE_ID;
  const String deviceLatestPath = deviceBasePath + "/latest";
  const String deviceHistoryPath = deviceBasePath + "/history";
  const String globalLatestPath = "/health_monitoring/latest";

  FirebaseJson latest;
  latest.set("schema_version", 1);
  latest.set("sequence", static_cast<int>(packetSequence));
  latest.set("device_id", DEVICE_ID);
  latest.set("gsr", packet.gsr);
  latest.set("emg", packet.emg);
  latest.set("stress_status", packet.stressStatus);
  latest.set("stress_index", packet.stressIndex);
  latest.set("timestamp", static_cast<int64_t>(packet.timestampMs));
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

  // Optional history stream for future analytics/reporting.
  FirebaseJson history;
  history.set("schema_version", 1);
  history.set("sequence", static_cast<int>(packetSequence));
  history.set("device_id", DEVICE_ID);
  history.set("gsr", packet.gsr);
  history.set("emg", packet.emg);
  history.set("stress_status", packet.stressStatus);
  history.set("stress_index", packet.stressIndex);
  history.set("timestamp", static_cast<int64_t>(packet.timestampMs));
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

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  connectWiFi();
  configTime(0, 0, "pool.ntp.org", "time.nist.gov");
  initFirebase();

  Serial.println("[I-Care ESP32] Setup complete.");
}

void loop() {
  connectWiFi();

  const uint32_t now = millis();
  if (now - lastUploadMs < UPLOAD_INTERVAL_MS) {
    return;
  }
  lastUploadMs = now;

  if (!Firebase.ready()) {
    return;
  }

  const SensorPacket packet = readSensors();

  const bool ok = uploadPacket(packet);
  Serial.print("[I-Care] status=");
  Serial.print(packet.stressStatus);
  Serial.print(" gsr=");
  Serial.print(packet.gsr, 2);
  Serial.print(" emg=");
  Serial.print(packet.emg, 2);
  Serial.print(" stressIndex=");
  Serial.print(packet.stressIndex, 2);
  Serial.print(" upload=");
  Serial.println(ok ? "OK" : "FAIL");
}
