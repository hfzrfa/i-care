# I-Care ESP32 Firebase Uploader

This ESP32 sketch is already aligned with the Flutter app in this repo.

## API paths and schema
The Flutter app currently reads:
- `health_monitoring/latest`

This sketch now writes to **device-scoped paths** and mirrors latest to app path:
- `health_monitoring/devices/{DEVICE_ID}/latest`
- `health_monitoring/devices/{DEVICE_ID}/history`
- `health_monitoring/latest` (compatibility mirror for current app)

### Payload fields
- `schema_version` (int)
- `sequence` (incrementing packet number)
- `device_id`
- `gsr` (0-100)
- `emg` (0-100)
- `stress_status` (`NORMAL`, `SEDANG`, `STRESS`)
- `stress_index` (0-100)
- `timestamp` (milliseconds epoch)
- `rssi` (WiFi signal dBm)
- `uptime_ms` (device uptime)

Example JSON:

```json
{
  "schema_version": 1,
  "sequence": 145,
  "device_id": "esp32-icare-01",
  "gsr": 46.6,
  "emg": 73.8,
  "stress_status": "SEDANG",
  "stress_index": 58.3,
  "timestamp": 1743146425000,
  "rssi": -62,
  "uptime_ms": 934402
}
```

## 1) Firebase setup
1. Create Firebase project.
2. Enable **Realtime Database**.
3. Enable **Authentication > Sign-in method > Email/Password**.
4. Create a user account for ESP32 (email/password).
5. Get values from Firebase:
- `API_KEY` (Project Settings > General)
- `DATABASE_URL` (Realtime Database URL)
- `USER_EMAIL` / `USER_PASSWORD`

## 2) Security Rules
Use this for fast development testing:

```json
{
  "rules": {
    ".read": "auth != null",
    ".write": "auth != null"
  }
}
```

Recommended next step for production:
- restrict write path by device identity, for example only allow device account to write under `health_monitoring/devices/{DEVICE_ID}`.

## 3) Fill credentials
1. Copy `Secrets.example.h` to `Secrets.h`.
2. Fill all placeholders.

## 4) Arduino IDE dependencies
Install these libraries:
- `Firebase Arduino Client Library for ESP8266 and ESP32` by Mobizt

Also ensure board package `esp32 by Espressif Systems` is installed.

## 5) Flash and run
1. Open `i_care_esp32.ino` in Arduino IDE.
2. Select board + COM port.
3. Upload.
4. Open Serial Monitor at `115200`.

## 6) Flutter app side
This repo app already reads `health_monitoring/latest`.

If Firebase is configured in Flutter, run:

```bash
flutter run --dart-define=USE_FIREBASE=true
```

If not configured yet, app still works in demo mode by default.

## 7) Internet/API reliability built in
Sketch includes retry behavior for internet/API hiccups:
- up to 3 retries per write
- incremental retry delays
- logs reason to Serial Monitor

## Calibration notes
In `i_care_esp32.ino`, tune:
- `GSR_ADC_MIN`, `GSR_ADC_MAX`
- `EMG_ADC_MIN`, `EMG_ADC_MAX`

These values depend on your sensor board and wiring.
