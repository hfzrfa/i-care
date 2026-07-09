# GSR + EMG Health Monitoring App

Project ini berisi aplikasi Flutter dan firmware ESP32 untuk monitoring GSR, EMG, Firebase Realtime Database, TFT ST7735, dan Compressive Sensing.

## Struktur Project

```text
lib/                         Source Flutter app
android/                     Konfigurasi Android dan Firebase
assets/                      Asset aplikasi
esp32/i_care_esp32/          Firmware ESP32 PlatformIO
esp32/i_care_esp32/Secrets.h Konfigurasi WiFi/Firebase ESP32, tidak masuk Git
esp32/i_care_esp32/cs_config.h Konfigurasi CS_N, CS_M, seed, sampling rate
esp32/i_care_esp32/wiring_guide.html Panduan wiring sensor ke ESP32
```

## Kebutuhan Software

Install ini di Windows atau macOS:

- Git
- Flutter SDK sesuai versi Dart di project ini, minimal mendukung `sdk: ^3.10.8`
- Android Studio, Android SDK, dan Android emulator atau HP Android
- Python 3
- PlatformIO CLI untuk firmware ESP32
- Driver USB serial ESP32, biasanya CP210x atau CH340 sesuai board

## Setup Awal Windows

1. Clone project:

```powershell
git clone <URL_REPOSITORY> gsrapp
cd gsrapp
```

2. Cek Flutter:

```powershell
flutter doctor
flutter pub get
```

3. Install PlatformIO CLI jika belum ada:

```powershell
python -m pip install --user platformio
pio --version
```

Jika `pio` belum dikenali, tutup dan buka ulang terminal. Pastikan folder Scripts Python masuk `PATH`.

4. Cek device Android:

```powershell
flutter devices
```

5. Cek port ESP32:

```powershell
pio device list
```

Port di Windows biasanya `COM3`, `COM4`, dan seterusnya.

## Setup Awal macOS

1. Clone project:

```bash
git clone <URL_REPOSITORY> gsrapp
cd gsrapp
```

2. Cek Flutter:

```bash
flutter doctor
flutter pub get
```

3. Install PlatformIO CLI:

```bash
python3 -m pip install --user platformio
pio --version
```

Jika `pio` belum dikenali, tambahkan path Python user bin ke shell. Contoh:

```bash
USER_BASE=$(python3 -m site --user-base)
echo "export PATH=\"$USER_BASE/bin:\$PATH\"" >> ~/.zshrc
source ~/.zshrc
```

4. Cek device Android:

```bash
flutter devices
```

5. Cek port ESP32:

```bash
pio device list
```

Port ESP32 di macOS biasanya `/dev/cu.usbserial-*`, `/dev/cu.SLAB_USBtoUART`, atau `/dev/cu.wchusbserial*`.

## Setup Firebase App

Project Flutter sudah membaca Firebase dari konfigurasi Android:

```text
android/app/google-services.json
```

Jika memakai Firebase project baru:

1. Buat Firebase project.
2. Aktifkan Authentication Email/Password.
3. Aktifkan Realtime Database.
4. Download `google-services.json` dari Firebase Console.
5. Letakkan file ke `android/app/google-services.json`.
6. Sesuaikan URL database di:

```text
lib/data/datasources/firebase_health_remote_data_source.dart
```

Ubah nilai:

```dart
const String kFirebaseDatabaseUrl = 'https://...firebasedatabase.app/';
```

## Setup Secrets ESP32

File ini wajib ada untuk firmware ESP32:

```text
esp32/i_care_esp32/Secrets.h
```

File ini sengaja di-ignore oleh Git karena berisi WiFi dan Firebase credential. Jika belum ada, buat file tersebut dengan format:

```cpp
#ifndef SECRETS_H
#define SECRETS_H

#define WIFI_SSID "NAMA_WIFI"
#define WIFI_PASSWORD "PASSWORD_WIFI"

#define API_KEY "FIREBASE_WEB_API_KEY"
#define DATABASE_URL "https://PROJECT_ID-default-rtdb.REGION.firebasedatabase.app/"

#define USER_EMAIL "email-device@example.com"
#define USER_PASSWORD "password-device"

#define DEVICE_ID "icare_esp32_001"

#endif
```

Pastikan `USER_EMAIL` dan `USER_PASSWORD` sudah terdaftar di Firebase Authentication.

## Jalankan Flutter App

Mode normal dengan Firebase:

```powershell
flutter pub get
flutter run
```

Di macOS perintahnya sama:

```bash
flutter pub get
flutter run
```

Mode dummy tanpa data sensor Firebase:

```powershell
flutter run --dart-define=USE_MOCK_SENSOR=true
```

Mode tanpa inisialisasi Firebase:

```powershell
flutter run --dart-define=USE_FIREBASE=false --dart-define=USE_MOCK_SENSOR=true
```

## Build dan Upload Firmware ESP32

Masuk ke folder firmware:

```powershell
cd esp32/i_care_esp32
```

Build:

```powershell
pio run
```

Upload otomatis:

```powershell
pio run --target upload
```

Jika perlu menentukan port Windows:

```powershell
pio run --target upload --upload-port COM3
```

Jika perlu menentukan port macOS:

```bash
pio run --target upload --upload-port /dev/cu.usbserial-0001
```

Buka Serial Monitor:

```powershell
pio device monitor
```

Atau dengan port tertentu:

```powershell
pio device monitor --port COM3 --baud 115200
```

macOS:

```bash
pio device monitor --port /dev/cu.usbserial-0001 --baud 115200
```

Keluar dari Serial Monitor PlatformIO: tekan `Ctrl+]`.

## Konfigurasi Measurement Rate

Konfigurasi Compressive Sensing ada di:

```text
esp32/i_care_esp32/cs_config.h
```

Nilai utama:

```cpp
static const int CS_N = 64;
static const int CS_M = 24;
```

Contoh measurement rate:

- `CS_M = 24` berarti `24/64 = 37.5%`
- `CS_M = 32` berarti `32/64 = 50%`

Setelah mengubah `CS_M`, firmware wajib di-build dan upload ulang.

## Capture Serial Measurement Rate

Firmware saat ini bisa mencetak laporan measurement rate lengkap di Serial Monitor, berisi:

- Data sebelum CS: `x[n]`
- Data kompresi: `y[m]`
- Data rekonstruksi: `x_hat[n]`
- Ringkasan selisih, error, akurasi, dan PRD
- Tabel GSR dan EMG per 64 sampel

Flag-nya ada di:

```text
esp32/i_care_esp32/i_care_esp32.ino
```

Bagian konfigurasi:

```cpp
static const bool SERIAL_REPORT_FULL_INPUT_VECTOR = true;
static const bool SERIAL_REPORT_FULL_MEASUREMENT_VECTOR = true;
static const bool SERIAL_REPORT_FULL_RECONSTRUCTED_VECTOR = true;
static const bool SERIAL_REPORT_COMPARISON_TABLE = true;
static const bool WIFI_DISTANCE_TEST_REPORT_ENABLED = false;
```

Untuk capture laporan, biarkan seperti di atas.

Untuk monitoring harian agar ESP32 lebih ringan, ubah menjadi:

```cpp
static const bool SERIAL_REPORT_FULL_INPUT_VECTOR = false;
static const bool SERIAL_REPORT_FULL_MEASUREMENT_VECTOR = false;
static const bool SERIAL_REPORT_FULL_RECONSTRUCTED_VECTOR = false;
static const bool SERIAL_REPORT_COMPARISON_TABLE = false;
```

## Wiring Hardware

Panduan wiring ada di:

```text
esp32/i_care_esp32/wiring_guide.html
```

Pin utama firmware:

| Fungsi | ESP32 |
| --- | --- |
| GSR signal | GPIO34 |
| EMG signal | GPIO35 |
| TFT SCLK | GPIO18 |
| TFT MOSI | GPIO23 |
| TFT CS | GPIO17 |
| TFT DC | GPIO27 |
| TFT RST | GPIO26 |

Catatan penting:

- GPIO34 dan GPIO35 tidak punya pull-up/pull-down internal.
- Gunakan pull-down eksternal 100 kOhm dari node ADC ke GND agar pembacaan tidak floating saat sensor belum terpasang.
- Semua GND sensor, TFT, dan ESP32 harus tersambung bersama.
- Pastikan output sensor tidak melebihi 3.3 V.

## Path Firebase yang Dipakai

Firmware mengirim data ke:

```text
/health_monitoring/latest
/health_monitoring/devices/<DEVICE_ID>/latest
/health_monitoring/devices/<DEVICE_ID>/history
```

App default membaca:

```text
health_monitoring/latest
```

Path bisa diuji atau diubah dari halaman Settings aplikasi.

## Troubleshooting

Jika Flutter gagal jalan:

```powershell
flutter clean
flutter pub get
flutter doctor
flutter run
```

Jika ESP32 tidak terdeteksi:

- Cek kabel USB, gunakan kabel data bukan kabel charge-only.
- Install driver CP210x atau CH340.
- Cek port dengan `pio device list`.
- Di macOS, beri izin driver jika diminta di System Settings.

Jika upload ESP32 gagal:

- Tekan dan tahan tombol `BOOT` saat proses `Connecting...`.
- Lepas tombol `BOOT` setelah upload mulai.
- Coba turunkan upload speed di `platformio.ini` jika masih gagal.

Jika Firebase timeout atau ESP32 tampak restart:

- Cek Serial Monitor bagian awal: `[Reset] reason=...`.
- Jika `BROWNOUT`, gunakan power supply atau kabel USB yang lebih stabil.
- Jika `TASK_WATCHDOG` atau `PANIC`, matikan sementara laporan serial lengkap karena OMP dan tabel measurement rate cukup berat.
- Dekatkan ESP32 ke access point dan pastikan RSSI tidak terlalu rendah.

## Klasifikasi Sensor

| Sensor | Rentang | Status |
| --- | --- | --- |
| GSR | 1-5 uS | Low |
| GSR | >5-12 uS | Moderate |
| GSR | >12-20 uS | High |
| EMG | <200 uV | Normal |
| EMG | >=200 uV | Stress |
