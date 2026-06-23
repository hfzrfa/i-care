import 'dart:math' as math;

import 'dwt_basis.dart';
import 'measurement_matrix.dart';
import 'omp_solver.dart';

class CsReconstructionResult {
  const CsReconstructionResult({
    required this.reconstructedSignal,
    required this.averageValue,
    required this.compressionRatio,
    required this.sparsityUsed,
  });

  final List<double> reconstructedSignal;

  final double averageValue;

  final double compressionRatio;

  final int sparsityUsed;
}

class CsReconstructor {
  CsReconstructor({
    required this.n,
    required this.m,
    required this.seed,
    int? sparsity,
  }) : sparsity = sparsity ?? (n ~/ 4);

  final int n;

  final int m;

  final int seed;

  final int sparsity;

  List<List<double>>? _phi;
  List<List<double>>? _psi;
  List<List<double>>? _sensingMatrix;

  List<List<double>> get phi =>
      _phi ??= MeasurementMatrix.generate(m: m, n: n, seed: seed);

  List<List<double>> get psi => _psi ??= DwtBasis.generate(n);

  List<List<double>> get sensingMatrix {
    if (_sensingMatrix != null) return _sensingMatrix!;

    _sensingMatrix = List<List<double>>.generate(m, (i) {
      return List<double>.generate(n, (j) {
        double sum = 0.0;
        for (int k = 0; k < n; k++) {
          sum += phi[i][k] * psi[k][j];
        }
        return sum;
      });
    });

    return _sensingMatrix!;
  }

  CsReconstructionResult reconstruct(List<double> compressedY) {
    assert(
      compressedY.length == m,
      'Expected $m compressed values, got ${compressedY.length}',
    );

    final sparseCoeffs = OmpSolver.solve(
      y: compressedY,
      sensingMatrix: phi,
      sparsity: sparsity,
    );

    final rawReconstructed = DwtBasis.inverse(sparseCoeffs);

    final reconstructed = rawReconstructed.map((v) => v < 0 ? 0.0 : v).toList();

    double sum = 0.0;
    for (final v in reconstructed) {
      sum += v;
    }
    final average = sum / reconstructed.length;

    return CsReconstructionResult(
      reconstructedSignal: reconstructed,
      averageValue: average,
      compressionRatio: n.toDouble() / m.toDouble(),
      sparsityUsed: sparsity,
    );
  }

  static double rmse(List<double> original, List<double> reconstructed) {
    assert(
      original.length == reconstructed.length,
      'Signal lengths must match',
    );
    final n = original.length;
    double sumSqErr = 0.0;
    for (int i = 0; i < n; i++) {
      final err = original[i] - reconstructed[i];
      sumSqErr += err * err;
    }
    return math.sqrt(sumSqErr / n);
  }

  static double snrDb(List<double> original, List<double> reconstructed) {
    assert(
      original.length == reconstructed.length,
      'Signal lengths must match',
    );
    double signalPower = 0.0;
    double noisePower = 0.0;
    for (int i = 0; i < original.length; i++) {
      signalPower += original[i] * original[i];
      final err = original[i] - reconstructed[i];
      noisePower += err * err;
    }
    if (noisePower < 1e-14) return double.infinity;
    return 10.0 * math.log(signalPower / noisePower) / math.ln10;
  }
}
