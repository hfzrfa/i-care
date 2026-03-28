import '../../domain/entities/health_metrics.dart';

class HealthMetricsModel {
  const HealthMetricsModel({
    required this.stressStatus,
    required this.gsrValue,
    required this.emgValue,
    required this.timestamp,
  });

  final String stressStatus;
  final double gsrValue;
  final double emgValue;
  final DateTime timestamp;

  factory HealthMetricsModel.fromMap(Map<dynamic, dynamic> map) {
    return HealthMetricsModel(
      stressStatus: _readStatus(map),
      gsrValue: _readDouble(map, const ['gsr', 'gsr_value', 'gsrValue']),
      emgValue: _readDouble(map, const ['emg', 'emg_value', 'emgValue']),
      timestamp: _readTimestamp(map),
    );
  }

  HealthMetrics toEntity() {
    return HealthMetrics(
      timestamp: timestamp,
      stressStatus: stressStatus,
      gsrValue: gsrValue,
      emgValue: emgValue,
    );
  }

  static String _readStatus(Map<dynamic, dynamic> map) {
    const keys = ['stress_status', 'stressStatus', 'stress', 'status'];
    for (final key in keys) {
      if (map.containsKey(key) && map[key] != null) {
        return map[key].toString().toUpperCase();
      }
    }
    return 'UNKNOWN';
  }

  static double _readDouble(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is num) {
        return value.toDouble();
      }
      if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return 0;
  }

  static DateTime _readTimestamp(Map<dynamic, dynamic> map) {
    final value = map['timestamp'];
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsedInt);
      }
      final parsedDate = DateTime.tryParse(value);
      if (parsedDate != null) {
        return parsedDate;
      }
    }
    return DateTime.now();
  }
}
