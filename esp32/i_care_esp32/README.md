# I-Care ESP32 - PlatformIO

Project ini menggunakan board `DOIT ESP32 DEVKIT V1` dengan Arduino framework.

## Build

```powershell
cd esp32/i_care_esp32
pio run
```

## Upload

Hubungkan ESP32, lalu jalankan:

```powershell
pio run --target upload
```

Jika port tidak terdeteksi otomatis:

```powershell
pio run --target upload --upload-port COM6
```

## Serial Monitor

```powershell
pio device monitor
```

Kecepatan serial sudah dikonfigurasi ke `115200`.

## Wiring Wajib ADC

GPIO34 dan GPIO35 tidak memiliki pull-down internal. Agar pin kosong terbaca
sebagai sensor tidak terpasang, pasang:

```text
GSR SIG -> resistor 1 kOhm -> node ADC -> GPIO34
                                  |
                                  +-> resistor 100 kOhm -> GND
                                  +-> kapasitor 100 nF -> GND

EMG SIG -> resistor 1 kOhm -> node ADC -> GPIO35
                                  |
                                  +-> resistor 100 kOhm -> GND
                                  +-> kapasitor 100 nF -> GND
```

Tanpa resistor `100 kOhm` ke GND, pin kosong akan floating dan tetap dapat
menghasilkan angka acak. Kondisi tersebut tidak dapat dibedakan secara andal
dari sinyal sensor hanya melalui software.

## Konfigurasi

Ubah koneksi Wi-Fi, Firebase, akun perangkat, dan ID perangkat di
`Secrets.h`. Jangan membagikan file tersebut karena berisi kredensial.
