# GSR + EMG Health Monitoring App

Project ini adalah implementasi aplikasi pemantauan kesehatan berbasis IoT dengan sensor GSR
dan EMG menggunakan ESP32, Firebase Realtime Database, Flutter Android app, dan Compressive
Sensing. Dokumen proposal dan catatan non-runtime disimpan di folder backup lokal
`backup_non_runtime/` dan tidak ikut ke Git.

## Struktur Utama

```text
lib/                         Flutter app
esp32/i_care_esp32/          Firmware ESP32 PlatformIO
assets/                      Asset aplikasi
android/                     Konfigurasi Android/Firebase
```

## Jalankan Aplikasi Debug

```powershell
flutter pub get
flutter run
```

Untuk mode dummy tanpa Firebase:

```powershell
flutter run --dart-define=USE_MOCK_SENSOR=true
```

## Build dan Upload ESP32

```powershell
cd esp32/i_care_esp32
pio run
pio run --target upload
pio device monitor
```

Konfigurasi Wi-Fi, Firebase, akun device, dan `DEVICE_ID` ada di:

```text
esp32/i_care_esp32/Secrets.h
```

## Klasifikasi

| Sensor | Rentang | Status |
| --- | --- | --- |
| GSR | 1-5 uS | Low |
| GSR | >5-12 uS | Moderate |
| GSR | >12-20 uS | High |
| EMG | <200 uV | Normal |
| EMG | >200 uV | Stress |

## Catatan Hardware

GPIO34 dan GPIO35 pada ESP32 tidak memiliki pull-down internal. Untuk pembacaan sensor yang
stabil, gunakan rangkaian filter pada `esp32/i_care_esp32/wiring_guide.html` dan pastikan node
ADC memiliki pull-down 100 kOhm ke GND.
