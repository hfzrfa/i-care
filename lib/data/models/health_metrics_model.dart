import '../../domain/entities/health_metrics.dart';

class HealthMetricsModel {
  const HealthMetricsModel({
    required this.stressStatus,
    required this.gsrValue,
    required this.emgValue,
    required this.timestamp,
    this.csEnabled = false,
    this.csN,
    this.csM,
    this.csSeed,
    this.windowId,
    this.compressedGsr,
    this.compressedEmg,
    this.reconstructedGsrSignal,
    this.reconstructedEmgSignal,
    this.compressionRatio,
    this.reconstructionRmse,
  });

  final String stressStatus;
  final double gsrValue;
  final double emgValue;
  final DateTime timestamp;

  final bool csEnabled;

  final int? csN;

  final int? csM;

  final int? csSeed;

  final int? windowId;

  final List<double>? compressedGsr;

  final List<double>? compressedEmg;

  final List<double>? reconstructedGsrSignal;

  final List<double>? reconstructedEmgSignal;

  final double? compressionRatio;

  final double? reconstructionRmse;

  factory HealthMetricsModel.fromMap(Map<dynamic, dynamic> map) {
    final schemaVersion = _readInt(map, ['schema_version']) ?? 1;
    final csEnabled = map['cs_enabled'] == true && schemaVersion >= 2;

    if (csEnabled) {
      return HealthMetricsModel(
        stressStatus: _readStatus(map),

        gsrValue: _readDouble(map, const ['gsr', 'gsr_value', 'gsrValue']),
        emgValue: _readDouble(map, const ['emg', 'emg_value', 'emgValue']),
        timestamp: _readTimestamp(map),
        csEnabled: true,
        csN: _readInt(map, ['cs_n']),
        csM: _readInt(map, ['cs_m']),
        csSeed: _readInt(map, ['cs_seed']),
        windowId: _readInt(map, ['window_id']),
        compressedGsr: _readDoubleList(map, 'y_gsr'),
        compressedEmg: _readDoubleList(map, 'y_emg'),
      );
    }

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
      csEnabled: csEnabled,
      compressionRatio: compressionRatio,
      reconstructionRmse: reconstructionRmse,
      reconstructedGsrSignal: reconstructedGsrSignal,
      reconstructedEmgSignal: reconstructedEmgSignal,
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

  static int? _readInt(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value);
    }
    return null;
  }

  static List<double>? _readDoubleList(Map<dynamic, dynamic> map, String key) {
    final raw = map[key];
    if (raw == null) return null;

    if (raw is List) {
      return raw.map((e) {
        if (e is num) return e.toDouble();
        if (e is String) return double.tryParse(e) ?? 0.0;
        return 0.0;
      }).toList();
    }

    if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) {
          final ai = int.tryParse(a.key.toString()) ?? 0;
          final bi = int.tryParse(b.key.toString()) ?? 0;
          return ai.compareTo(bi);
        });
      return entries.map((e) {
        final v = e.value;
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      }).toList();
    }

    return null;
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
