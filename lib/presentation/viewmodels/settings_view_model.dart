import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsViewModel extends ChangeNotifier {
  bool _notificationsEnabled = true;
  bool _pushAlerts = true;
  bool _criticalOnly = false;
  bool _hapticFeedback = true;
  String _appVersion = '-';

  bool get notificationsEnabled => _notificationsEnabled;

  bool get pushAlerts => _pushAlerts;
  bool get criticalOnly => _criticalOnly;
  bool get hapticFeedback => _hapticFeedback;
  String get appVersion => _appVersion;

  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {
      _appVersion = '1.0.0+unknown';
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
