import '../entities/health_metrics.dart';
import '../repositories/health_repository.dart';

class WatchHealthMetricsUseCase {
  const WatchHealthMetricsUseCase(this._healthRepository);

  final HealthRepository _healthRepository;

  Stream<HealthMetrics> execute() {
    return _healthRepository.watchHealthMetrics();
  }
}
