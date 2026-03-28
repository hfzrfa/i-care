#ifndef SECRETS_H
#define SECRETS_H

// WiFi credentials
#define WIFI_SSID "YOUR_WIFI_SSID"
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"

// Firebase Web API key from Project Settings > General > Web API Key
#define API_KEY "YOUR_FIREBASE_WEB_API_KEY"

// Firebase Realtime Database URL (must end with /)
// Example: https://your-project-id-default-rtdb.asia-southeast1.firebasedatabase.app/
#define DATABASE_URL "https://YOUR_PROJECT_ID-default-rtdb.YOUR_REGION.firebasedatabase.app/"

// Email/Password account created in Firebase Authentication
#define USER_EMAIL "esp32.device@demo.local"
#define USER_PASSWORD "YOUR_STRONG_PASSWORD"

// Optional device tag shown in the database
#define DEVICE_ID "esp32-icare-01"

#endif
