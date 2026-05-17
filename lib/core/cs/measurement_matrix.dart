import 'dart:math' as math;

class MeasurementMatrix {
  MeasurementMatrix._();

  static const int _lcgA = 1103515245;
  static const int _lcgC = 12345;
  static const int _lcgM = 1 << 31;

  static List<List<double>> generate({
    required int m,
    required int n,
    required int seed,
  }) {
    assert(m > 0 && n > 0, 'M and N must be positive');
    assert(m < n, 'M must be less than N for compression');

    final scale = 1.0 / math.sqrt(m.toDouble());
    int state = seed;

    final phi = List<List<double>>.generate(
      m,
      (_) => List<double>.filled(n, 0.0),
    );

    for (int i = 0; i < m; i++) {
      for (int j = 0; j < n; j++) {
        final u1 = _nextUniform(state);
        state = u1.nextState;
        final u2 = _nextUniform(state);
        state = u2.nextState;

        final gaussian =
            math.sqrt(-2.0 * math.log(u1.value)) *
            math.cos(2.0 * math.pi * u2.value);

        phi[i][j] = gaussian * scale;
      }
    }

    return phi;
  }

  static List<double> multiply(List<List<double>> phi, List<double> x) {
    final m = phi.length;
    final n = phi[0].length;
    assert(x.length == n, 'Signal length must match matrix columns');

    final y = List<double>.filled(m, 0.0);
    for (int i = 0; i < m; i++) {
      double sum = 0.0;
      for (int j = 0; j < n; j++) {
        sum += phi[i][j] * x[j];
      }
      y[i] = sum;
    }
    return y;
  }

  static List<List<double>> transpose(List<List<double>> matrix) {
    final rows = matrix.length;
    final cols = matrix[0].length;
    return List<List<double>>.generate(
      cols,
      (j) => List<double>.generate(rows, (i) => matrix[i][j]),
    );
  }

  static _UniformResult _nextUniform(int state) {
    state = ((state * _lcgA + _lcgC) & 0x7FFFFFFF);

    final value = (state.toDouble() + 1.0) / (_lcgM.toDouble() + 2.0);
    return _UniformResult(state, value);
  }
}

class _UniformResult {
  const _UniformResult(this.nextState, this.value);
  final int nextState;
  final double value;
}
