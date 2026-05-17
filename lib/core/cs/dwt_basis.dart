import 'dart:math' as math;

class DwtBasis {
  DwtBasis._();

  static List<List<double>> generate(int n) {
    assert(n > 0 && (n & (n - 1)) == 0, 'N must be a power of 2');

    final h = List<List<double>>.generate(
      n,
      (_) => List<double>.filled(n, 0.0),
    );

    final double invSqrtN = 1.0 / math.sqrt(n);
    for (int i = 0; i < n; i++) {
      h[0][i] = invSqrtN;
    }

    for (int k = 1; k < n; k++) {
      int p = (math.log(k) / math.ln2).floor();
      int q = k - (1 << p);

      double factor = math.pow(2.0, p / 2.0) / math.sqrt(n);
      int start = q * (n >> p);
      int mid = start + (n >> (p + 1));
      int end = start + (n >> p);

      for (int i = start; i < mid; i++) {
        h[k][i] = factor;
      }
      for (int i = mid; i < end; i++) {
        h[k][i] = -factor;
      }
    }

    final psi = List<List<double>>.generate(
      n,
      (_) => List<double>.filled(n, 0.0),
    );

    for (int i = 0; i < n; i++) {
      for (int j = 0; j < n; j++) {
        psi[i][j] = h[j][i];
      }
    }

    return psi;
  }

  static List<double> forward(List<double> x) {
    final n = x.length;
    final h = generate(n);

    final psi = h;

    final coeffs = List<double>.filled(n, 0.0);
    for (int k = 0; k < n; k++) {
      double sum = 0.0;
      for (int i = 0; i < n; i++) {
        sum += psi[i][k] * x[i];
      }
      coeffs[k] = sum;
    }
    return coeffs;
  }

  static List<double> inverse(List<double> coeffs) {
    final n = coeffs.length;
    final psi = generate(n);
    final x = List<double>.filled(n, 0.0);

    for (int i = 0; i < n; i++) {
      double sum = 0.0;
      for (int j = 0; j < n; j++) {
        sum += psi[i][j] * coeffs[j];
      }
      x[i] = sum;
    }

    return x;
  }
}
