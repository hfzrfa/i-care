import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../core/cs/cs_reconstructor.dart';
import '../../core/utils/stress_level.dart';
import '../models/health_metrics_model.dart';

const String kFirebaseDatabaseUrl =
    'https://i-care-esp32-default-rtdb.asia-southeast1.firebasedatabase.app/';

abstract class HealthRemoteDataSource {
  Stream<HealthMetricsModel> watchHealthMetrics();

  void updatePath(String path);

  String get currentPath;
}

class FirebaseHealthRemoteDataSource implements HealthRemoteDataSource {
  FirebaseHealthRemoteDataSource({
    FirebaseDatabase? database,
    String path = 'health_monitoring/latest',
  }) : _database =
           database ??
           FirebaseDatabase.instanceFor(
             app: Firebase.app(),
             databaseURL: kFirebaseDatabaseUrl,
           ),
       _path = path;

  final FirebaseDatabase _database;
  String _path;

  final Map<String, CsReconstructor> _csCache = {};

  @override
  String get currentPath => _path;

  @override
  void updatePath(String path) {
    final sanitized = path.trim();
    if (sanitized.isEmpty) {
      return;
    }
    _path = sanitized;
  }

  CsReconstructor _getReconstructor(int n, int m, int seed) {
    final key = '$n-$m-$seed';
    return _csCache.putIfAbsent(
      key,
      () => CsReconstructor(n: n, m: m, seed: seed),
    );
  }

  @override
  Stream<HealthMetricsModel> watchHealthMetrics() {
    debugPrint('[FirebaseDS] Listening on path: $_path');
    debugPrint('[FirebaseDS] Database URL: ${_database.databaseURL}');
    return _database
        .ref(_path)
        .onValue
        .asyncMap((event) async {
          final dynamic raw = event.snapshot.value;
          debugPrint('[FirebaseDS] Data received: ${raw.runtimeType} => $raw');
          if (raw is Map<dynamic, dynamic>) {
            final model = HealthMetricsModel.fromMap(raw);

            if (model.csEnabled &&
                model.csN != null &&
                model.csM != null &&
                model.csSeed != null &&
                model.compressedGsr != null &&
                model.compressedEmg != null) {
              return await _reconstructFromCS(model);
            }

            return model;
          }
          debugPrint(
            '[FirebaseDS] WARNING: data is not a Map, returning empty.',
          );
          return HealthMetricsModel.fromMap(const <String, dynamic>{});
        })
        .handleError((error, stackTrace) {
          debugPrint('[FirebaseDS] STREAM ERROR: $error');
          debugPrint('[FirebaseDS] Stack: $stackTrace');
        });
  }

  Future<HealthMetricsModel> _reconstructFromCS(
    HealthMetricsModel model,
  ) async {
    final cs = _getReconstructor(model.csN!, model.csM!, model.csSeed!);

    debugPrint(
      '[FirebaseDS] CS reconstruction: N=${model.csN}, '
      'M=${model.csM}, seed=${model.csSeed}, window=${model.windowId}',
    );

    final results = await compute(
      _csReconstructIsolate,
      _CsInput(
        compressedGsr: model.compressedGsr!,
        compressedEmg: model.compressedEmg!,
        phi: cs.phi,
        psi: cs.psi,
        n: model.csN!,
        m: model.csM!,
        sparsity: cs.sparsity,
      ),
    );

    debugPrint(
      '[FirebaseDS] CS done: gsrAvg=${results.gsrAvg.toStringAsFixed(2)}, '
      'emgAvg=${results.emgAvg.toStringAsFixed(2)}, '
      'CR=${results.compressionRatio.toStringAsFixed(2)}',
    );

    final gsrAvg = model.gsrSignalValid ? results.gsrAvg : 0.0;
    final emgAvg = model.emgSignalValid ? results.emgAvg : 0.0;
    final stressStatus = model.sensorsAttached
        ? StressLevelMapper.combinedResult(gsr: gsrAvg, emg: emgAvg).category
        : 'SENSOR_NOT_ATTACHED';

    return HealthMetricsModel(
      stressStatus: stressStatus,
      gsrValue: gsrAvg,
      emgValue: emgAvg,
      sensorsAttached: model.sensorsAttached,
      gsrSignalValid: model.gsrSignalValid,
      emgSignalValid: model.emgSignalValid,
      timestamp: model.timestamp,
      csEnabled: true,
      csN: model.csN,
      csM: model.csM,
      csSeed: model.csSeed,
      windowId: model.windowId,
      compressedGsr: model.compressedGsr,
      compressedEmg: model.compressedEmg,
      reconstructedGsrSignal: results.gsrSignal,
      reconstructedEmgSignal: results.emgSignal,
      compressionRatio: results.compressionRatio,
    );
  }
}

class _CsInput {
  const _CsInput({
    required this.compressedGsr,
    required this.compressedEmg,
    required this.phi,
    required this.psi,
    required this.n,
    required this.m,
    required this.sparsity,
  });

  final List<double> compressedGsr;
  final List<double> compressedEmg;
  final List<List<double>> phi;
  final List<List<double>> psi;
  final int n;
  final int m;
  final int sparsity;
}

class _CsOutput {
  const _CsOutput({
    required this.gsrSignal,
    required this.emgSignal,
    required this.gsrAvg,
    required this.emgAvg,
    required this.compressionRatio,
  });

  final List<double> gsrSignal;
  final List<double> emgSignal;
  final double gsrAvg;
  final double emgAvg;
  final double compressionRatio;
}

_CsOutput _csReconstructIsolate(_CsInput input) {
  final gsrSparse = _ompSolve(input.compressedGsr, input.phi, input.sparsity);
  final gsrRaw = _inverseTransform(gsrSparse, input.psi);
  final gsrSignal = gsrRaw.map((v) => v < 0 ? 0.0 : v).toList();

  final emgSparse = _ompSolve(input.compressedEmg, input.phi, input.sparsity);
  final emgRaw = _inverseTransform(emgSparse, input.psi);
  final emgSignal = emgRaw.map((v) => v < 0 ? 0.0 : v).toList();

  double gsrSum = 0, emgSum = 0;
  for (final v in gsrSignal) {
    gsrSum += v;
  }
  for (final v in emgSignal) {
    emgSum += v;
  }
  final gsrAvg = (gsrSum / gsrSignal.length)
      .clamp(0.0, double.infinity)
      .toDouble();
  final emgAvg = (emgSum / emgSignal.length)
      .clamp(0.0, double.infinity)
      .toDouble();

  return _CsOutput(
    gsrSignal: gsrSignal,
    emgSignal: emgSignal,
    gsrAvg: gsrAvg,
    emgAvg: emgAvg,
    compressionRatio: input.n.toDouble() / input.m.toDouble(),
  );
}

List<double> _ompSolve(List<double> y, List<List<double>> a, int k) {
  final m = y.length;
  final n = a[0].length;
  final residual = List<double>.from(y);
  final support = <int>[];
  final coeffs = List<double>.filled(n, 0.0);

  for (int iter = 0; iter < k; iter++) {
    int bestCol = 0;
    double bestCorr = -1.0;
    for (int j = 0; j < n; j++) {
      if (support.contains(j)) continue;
      double corr = 0.0;
      for (int i = 0; i < m; i++) {
        corr += a[i][j] * residual[i];
      }
      if (corr.abs() > bestCorr) {
        bestCorr = corr.abs();
        bestCol = j;
      }
    }
    support.add(bestCol);

    final sLen = support.length;
    final ata = List<List<double>>.generate(
      sLen,
      (i) => List<double>.generate(sLen, (j) {
        double s = 0;
        for (int r = 0; r < m; r++) {
          s += a[r][support[i]] * a[r][support[j]];
        }
        return s;
      }),
    );
    final aty = List<double>.generate(sLen, (i) {
      double s = 0;
      for (int r = 0; r < m; r++) {
        s += a[r][support[i]] * y[r];
      }
      return s;
    });

    final aug = List<List<double>>.generate(sLen, (i) => [...ata[i], aty[i]]);
    for (int col = 0; col < sLen; col++) {
      int pivot = col;
      for (int row = col + 1; row < sLen; row++) {
        if (aug[row][col].abs() > aug[pivot][col].abs()) pivot = row;
      }
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;
      if (aug[col][col].abs() < 1e-14) continue;
      for (int row = col + 1; row < sLen; row++) {
        final factor = aug[row][col] / aug[col][col];
        for (int c = col; c <= sLen; c++) {
          aug[row][c] -= factor * aug[col][c];
        }
      }
    }
    final xS = List<double>.filled(sLen, 0.0);
    for (int row = sLen - 1; row >= 0; row--) {
      double s = aug[row][sLen];
      for (int c = row + 1; c < sLen; c++) {
        s -= aug[row][c] * xS[c];
      }
      xS[row] = aug[row][row].abs() < 1e-14 ? 0.0 : s / aug[row][row];
    }

    for (int i = 0; i < m; i++) {
      double approx = 0;
      for (int si = 0; si < sLen; si++) {
        approx += a[i][support[si]] * xS[si];
      }
      residual[i] = y[i] - approx;
    }

    for (int i = 0; i < n; i++) {
      coeffs[i] = 0.0;
    }
    for (int si = 0; si < sLen; si++) {
      coeffs[support[si]] = xS[si];
    }
  }
  return coeffs;
}

List<double> _inverseTransform(
  List<double> sparseCoeffs,
  List<List<double>> psi,
) {
  final n = sparseCoeffs.length;
  return List<double>.generate(n, (i) {
    double sum = 0;
    for (int j = 0; j < n; j++) {
      sum += psi[i][j] * sparseCoeffs[j];
    }
    return sum;
  });
}
