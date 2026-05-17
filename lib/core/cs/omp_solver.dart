import 'dart:math' as math;

class OmpSolver {
  const OmpSolver._();

  static List<double> solve({
    required List<double> y,
    required List<List<double>> sensingMatrix,
    required int sparsity,
  }) {
    final m = sensingMatrix.length;
    final n = sensingMatrix[0].length;

    assert(y.length == m, 'y length must equal sensing matrix rows (M)');
    assert(sparsity > 0 && sparsity <= m, 'Sparsity K must be in (0, M]');

    final residual = List<double>.from(y);

    final support = <int>[];

    for (int iter = 0; iter < sparsity; iter++) {
      int bestIndex = -1;
      double bestCorrelation = -1.0;

      for (int j = 0; j < n; j++) {
        if (support.contains(j)) continue;

        double correlation = 0.0;
        for (int i = 0; i < m; i++) {
          correlation += sensingMatrix[i][j] * residual[i];
        }
        final absCorr = correlation.abs();
        if (absCorr > bestCorrelation) {
          bestCorrelation = absCorr;
          bestIndex = j;
        }
      }

      if (bestIndex < 0) break;
      support.add(bestIndex);

      final sSize = support.length;
      final aS = List<List<double>>.generate(
        m,
        (i) =>
            List<double>.generate(sSize, (k) => sensingMatrix[i][support[k]]),
      );

      final coefficients = _leastSquares(aS, y);

      for (int i = 0; i < m; i++) {
        double projection = 0.0;
        for (int k = 0; k < sSize; k++) {
          projection += aS[i][k] * coefficients[k];
        }
        residual[i] = y[i] - projection;
      }

      final residualNorm = _norm(residual);
      if (residualNorm < 1e-10) break;
    }

    final s = List<double>.filled(n, 0.0);
    if (support.isNotEmpty) {
      final aS = List<List<double>>.generate(
        m,
        (i) => List<double>.generate(
          support.length,
          (k) => sensingMatrix[i][support[k]],
        ),
      );
      final coefficients = _leastSquares(aS, y);
      for (int k = 0; k < support.length; k++) {
        s[support[k]] = coefficients[k];
      }
    }

    return s;
  }

  static List<double> _leastSquares(List<List<double>> a, List<double> b) {
    final m = a.length;
    final k = a[0].length;

    final ata = List<List<double>>.generate(
      k,
      (i) => List<double>.filled(k, 0.0),
    );
    for (int i = 0; i < k; i++) {
      for (int j = i; j < k; j++) {
        double sum = 0.0;
        for (int r = 0; r < m; r++) {
          sum += a[r][i] * a[r][j];
        }
        ata[i][j] = sum;
        ata[j][i] = sum;
      }
    }

    final atb = List<double>.filled(k, 0.0);
    for (int i = 0; i < k; i++) {
      double sum = 0.0;
      for (int r = 0; r < m; r++) {
        sum += a[r][i] * b[r];
      }
      atb[i] = sum;
    }

    return _solveLinearSystem(ata, atb);
  }

  static List<double> _solveLinearSystem(List<List<double>> a, List<double> b) {
    final k = b.length;

    final mat = List<List<double>>.generate(k, (i) => List<double>.from(a[i]));
    final rhs = List<double>.from(b);

    for (int col = 0; col < k; col++) {
      int maxRow = col;
      double maxVal = mat[col][col].abs();
      for (int row = col + 1; row < k; row++) {
        final v = mat[row][col].abs();
        if (v > maxVal) {
          maxVal = v;
          maxRow = row;
        }
      }
      if (maxRow != col) {
        final tmpRow = mat[col];
        mat[col] = mat[maxRow];
        mat[maxRow] = tmpRow;
        final tmpB = rhs[col];
        rhs[col] = rhs[maxRow];
        rhs[maxRow] = tmpB;
      }

      final pivot = mat[col][col];
      if (pivot.abs() < 1e-14) continue;

      for (int row = col + 1; row < k; row++) {
        final factor = mat[row][col] / pivot;
        for (int j = col; j < k; j++) {
          mat[row][j] -= factor * mat[col][j];
        }
        rhs[row] -= factor * rhs[col];
      }
    }

    final x = List<double>.filled(k, 0.0);
    for (int col = k - 1; col >= 0; col--) {
      if (mat[col][col].abs() < 1e-14) continue;
      double sum = rhs[col];
      for (int j = col + 1; j < k; j++) {
        sum -= mat[col][j] * x[j];
      }
      x[col] = sum / mat[col][col];
    }

    return x;
  }

  static double _norm(List<double> v) {
    double sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    return math.sqrt(sum);
  }
}
