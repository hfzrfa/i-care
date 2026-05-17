import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/datasources/firebase_health_remote_data_source.dart';

enum SensorConnectionStatus { idle, checking, connected, noData, error }

class SettingsViewModel extends ChangeNotifier {
  static const String _keySensorApiPath = 'sensor_api_path';

  bool _notificationsEnabled = true;
  bool _pushAlerts = true;
  bool _criticalOnly = false;
  bool _hapticFeedback = true;
  String _appVersion = '-';
  String _sensorApiPath = 'health_monitoring/latest';
  SensorConnectionStatus _sensorConnectionStatus = SensorConnectionStatus.idle;
  String _sensorConnectionMessage = 'Belum dicek.';

  bool get notificationsEnabled => _notificationsEnabled;

  bool get pushAlerts => _pushAlerts;
  bool get criticalOnly => _criticalOnly;
  bool get hapticFeedback => _hapticFeedback;
  String get appVersion => _appVersion;
  String get sensorApiPath => _sensorApiPath;
  SensorConnectionStatus get sensorConnectionStatus => _sensorConnectionStatus;
  String get sensorConnectionMessage => _sensorConnectionMessage;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _sensorApiPath = prefs.getString(_keySensorApiPath) ?? _sensorApiPath;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {
      _appVersion = '1.0.0+unknown';
    }
    notifyListeners();
  }

  Future<void> setSensorApiPath(String value) async {
    final sanitized = value.trim();
    if (sanitized.isEmpty || sanitized == _sensorApiPath) {
      return;
    }
    _sensorApiPath = sanitized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keySensorApiPath, _sensorApiPath);
    notifyListeners();
  }

  Future<void> testSensorConnection({FirebaseDatabase? database}) async {
    _sensorConnectionStatus = SensorConnectionStatus.checking;
    _sensorConnectionMessage = 'Mengecek koneksi...';
    notifyListeners();

    try {
      final db =
          database ??
          FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: kFirebaseDatabaseUrl,
          );
      final snapshot = await db.ref(_sensorApiPath).get();
      final raw = snapshot.value;

      if (raw is Map<dynamic, dynamic>) {
        final hasSignal = raw.containsKey('gsr') && raw.containsKey('emg');
        if (hasSignal) {
          _sensorConnectionStatus = SensorConnectionStatus.connected;
          _sensorConnectionMessage = 'Connected. Data sensor terbaca.';
        } else {
          _sensorConnectionStatus = SensorConnectionStatus.noData;
          _sensorConnectionMessage = 'Path ada, tapi format data belum cocok.';
        }
      } else {
        _sensorConnectionStatus = SensorConnectionStatus.noData;
        _sensorConnectionMessage = 'Path ditemukan, tapi belum ada data.';
      }
    } catch (error) {
      _sensorConnectionStatus = SensorConnectionStatus.error;
      _sensorConnectionMessage = 'Gagal konek: ${error.toString()}';
    }

    notifyListeners();
  }

  void setNotificationsEnabled(bool value) {
    _notificationsEnabled = value;
    notifyListeners();
  }

  void setPushAlerts(bool value) {
    _pushAlerts = value;
    notifyListeners();
  }

  void setCriticalOnly(bool value) {
    _criticalOnly = value;
    notifyListeners();
  }

  void setHapticFeedback(bool value) {
    _hapticFeedback = value;
    notifyListeners();
  }
}
