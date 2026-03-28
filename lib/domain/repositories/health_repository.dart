import '../entities/health_metrics.dart';

abstract class HealthRepository {
  Stream<HealthMetrics> watchHealthMetrics();
}
