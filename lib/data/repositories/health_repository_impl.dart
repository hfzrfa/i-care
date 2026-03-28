import '../../domain/entities/health_metrics.dart';
import '../../domain/repositories/health_repository.dart';
import '../datasources/firebase_health_remote_data_source.dart';

class HealthRepositoryImpl implements HealthRepository {
  const HealthRepositoryImpl(this._remoteDataSource);

  final HealthRemoteDataSource _remoteDataSource;

  @override
  Stream<HealthMetrics> watchHealthMetrics() {
    return _remoteDataSource.watchHealthMetrics().map((model) => model.toEntity());
  }
}
