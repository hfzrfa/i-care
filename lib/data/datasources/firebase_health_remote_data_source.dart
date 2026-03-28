import 'package:firebase_database/firebase_database.dart';

import '../models/health_metrics_model.dart';

abstract class HealthRemoteDataSource {
  Stream<HealthMetricsModel> watchHealthMetrics();
}

class FirebaseHealthRemoteDataSource implements HealthRemoteDataSource {
  FirebaseHealthRemoteDataSource({
    FirebaseDatabase? database,
    String path = 'health_monitoring/latest',
  }) : _database = database ?? FirebaseDatabase.instance,
       _path = path;

  final FirebaseDatabase _database;
  final String _path;

  @override
  Stream<HealthMetricsModel> watchHealthMetrics() {
    return _database.ref(_path).onValue.map((event) {
      final dynamic raw = event.snapshot.value;
      if (raw is Map<dynamic, dynamic>) {
        return HealthMetricsModel.fromMap(raw);
      }
      return HealthMetricsModel.fromMap(const <String, dynamic>{});
    });
  }
}
