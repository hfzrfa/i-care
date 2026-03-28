class HealthMetrics {
  const HealthMetrics({
    required this.timestamp,
    required this.stressStatus,
    required this.gsrValue,
    required this.emgValue,
  });

  final DateTime timestamp;
  final String stressStatus;
  final double gsrValue;
  final double emgValue;

  HealthMetrics copyWith({
    DateTime? timestamp,
    String? stressStatus,
    double? gsrValue,
    double? emgValue,
  }) {
    return HealthMetrics(
      timestamp: timestamp ?? this.timestamp,
      stressStatus: stressStatus ?? this.stressStatus,
      gsrValue: gsrValue ?? this.gsrValue,
      emgValue: emgValue ?? this.emgValue,
    );
  }
}
