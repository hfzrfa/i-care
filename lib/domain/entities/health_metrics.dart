class HealthMetrics {
  const HealthMetrics({
    required this.timestamp,
    required this.stressStatus,
    required this.gsrValue,
    required this.emgValue,
    this.sensorsAttached = true,
    this.gsrSignalValid = true,
    this.emgSignalValid = true,
    this.csEnabled = false,
    this.compressionRatio,
    this.reconstructionRmse,
    this.reconstructedGsrSignal,
    this.reconstructedEmgSignal,
  });

  final DateTime timestamp;
  final String stressStatus;
  final double gsrValue;
  final double emgValue;
  final bool sensorsAttached;
  final bool gsrSignalValid;
  final bool emgSignalValid;

  final bool csEnabled;

  final double? compressionRatio;

  final double? reconstructionRmse;

  final List<double>? reconstructedGsrSignal;

  final List<double>? reconstructedEmgSignal;

  HealthMetrics copyWith({
    DateTime? timestamp,
    String? stressStatus,
    double? gsrValue,
    double? emgValue,
    bool? sensorsAttached,
    bool? gsrSignalValid,
    bool? emgSignalValid,
    bool? csEnabled,
    double? compressionRatio,
    double? reconstructionRmse,
    List<double>? reconstructedGsrSignal,
    List<double>? reconstructedEmgSignal,
  }) {
    return HealthMetrics(
      timestamp: timestamp ?? this.timestamp,
      stressStatus: stressStatus ?? this.stressStatus,
      gsrValue: gsrValue ?? this.gsrValue,
      emgValue: emgValue ?? this.emgValue,
      sensorsAttached: sensorsAttached ?? this.sensorsAttached,
      gsrSignalValid: gsrSignalValid ?? this.gsrSignalValid,
      emgSignalValid: emgSignalValid ?? this.emgSignalValid,
      csEnabled: csEnabled ?? this.csEnabled,
      compressionRatio: compressionRatio ?? this.compressionRatio,
      reconstructionRmse: reconstructionRmse ?? this.reconstructionRmse,
      reconstructedGsrSignal:
          reconstructedGsrSignal ?? this.reconstructedGsrSignal,
      reconstructedEmgSignal:
          reconstructedEmgSignal ?? this.reconstructedEmgSignal,
    );
  }
}
