import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/health_metrics.dart';
import '../../domain/usecases/watch_health_metrics.dart';

enum DashboardState { initial, loading, ready, error }

enum MetricTrend { up, down, stable }

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel(this._watchHealthMetricsUseCase);

  static const int _maxPoints = 50;
  static const Duration _initialDataTimeout = Duration(seconds: 10);
  static const Duration _staleThreshold = Duration(seconds: 30);

  final WatchHealthMetricsUseCase _watchHealthMetricsUseCase;

  DashboardState _state = DashboardState.initial;
  HealthMetrics? _latestMetrics;
  final List<double> _gsrHistory = <double>[];
  final List<double> _emgHistory = <double>[];
  MetricTrend _gsrTrend = MetricTrend.stable;
  MetricTrend _emgTrend = MetricTrend.stable;
  String? _errorMessage;
  StreamSubscription<HealthMetrics>? _subscription;
  Timer? _initialDataTimer;
  Timer? _staleCheckTimer;
  bool _deviceOnline = false;

  bool _csEnabled = false;
  double? _compressionRatio;
  double? _reconstructionRmse;
  int? _csN;
  int? _csM;
  List<double>? _reconstructedGsrWaveform;
  List<double>? _reconstructedEmgWaveform;

  DashboardState get state => _state;
  HealthMetrics? get latestMetrics => _latestMetrics;
  List<double> get gsrHistory => List.unmodifiable(_gsrHistory);
  List<double> get emgHistory => List.unmodifiable(_emgHistory);
  MetricTrend get gsrTrend => _gsrTrend;
  MetricTrend get emgTrend => _emgTrend;
  String? get errorMessage => _errorMessage;
  bool get isDeviceOnline => _deviceOnline;

  bool get csEnabled => _csEnabled;
  double? get compressionRatio => _compressionRatio;
  double? get reconstructionRmse => _reconstructionRmse;
  int? get csN => _csN;
  int? get csM => _csM;
  List<double>? get reconstructedGsrWaveform => _reconstructedGsrWaveform;
  List<double>? get reconstructedEmgWaveform => _reconstructedEmgWaveform;

  void initialize() {
    if (_subscription != null) {
      debugPrint('[DashboardVM] Already subscribed, skipping.');
      return;
    }

    _initialDataTimer?.cancel();
    _initialDataTimer = Timer(_initialDataTimeout, _onInitialDataTimeout);

    _state = DashboardState.loading;
    notifyListeners();

    debugPrint('[DashboardVM] Starting health metrics stream...');
    _subscription = _watchHealthMetricsUseCase.execute().listen(
      _onMetricsReceived,
      onError: _onMetricsError,
      cancelOnError: false,
    );
    debugPrint('[DashboardVM] Stream subscription created.');

    _staleCheckTimer?.cancel();
    _staleCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkStaleness(),
    );
  }

  Future<void> restartStream() async {
    await _subscription?.cancel();
    _subscription = null;
    _initialDataTimer?.cancel();
    _initialDataTimer = null;
    _latestMetrics = null;
    _errorMessage = null;
    _gsrHistory.clear();
    _emgHistory.clear();
    _gsrTrend = MetricTrend.stable;
    _emgTrend = MetricTrend.stable;
    _deviceOnline = false;
    _staleCheckTimer?.cancel();
    initialize();
  }

  void _onMetricsReceived(HealthMetrics metrics) {
    _initialDataTimer?.cancel();
    _initialDataTimer = null;

    debugPrint(
      '[DashboardVM] Data received! GSR=${metrics.gsrValue}, EMG=${metrics.emgValue}, Status=${metrics.stressStatus}, CS=${metrics.csEnabled}',
    );

    _state = DashboardState.ready;
    _errorMessage = null;
    _latestMetrics = metrics;
    _deviceOnline = true;

    _csEnabled = metrics.csEnabled;
    _compressionRatio = metrics.compressionRatio;
    _reconstructionRmse = metrics.reconstructionRmse;
    _reconstructedGsrWaveform = metrics.reconstructedGsrSignal;
    _reconstructedEmgWaveform = metrics.reconstructedEmgSignal;

    if (metrics.csEnabled && metrics.reconstructedGsrSignal != null) {
      _csN = metrics.reconstructedGsrSignal!.length;
      if (metrics.compressionRatio != null && metrics.compressionRatio! > 0) {
        _csM = (_csN! / metrics.compressionRatio!).round();
      }
    }

    if (_gsrHistory.isNotEmpty) {
      _gsrTrend = _resolveTrend(
        previous: _gsrHistory.last,
        current: metrics.gsrValue,
      );
    }
    if (_emgHistory.isNotEmpty) {
      _emgTrend = _resolveTrend(
        previous: _emgHistory.last,
        current: metrics.emgValue,
      );
    }

    _gsrHistory.add(metrics.gsrValue);
    _emgHistory.add(metrics.emgValue);

    if (_gsrHistory.length > _maxPoints) {
      _gsrHistory.removeAt(0);
    }
    if (_emgHistory.length > _maxPoints) {
      _emgHistory.removeAt(0);
    }

    notifyListeners();
  }

  void _onMetricsError(Object error, StackTrace stackTrace) {
    _initialDataTimer?.cancel();
    _initialDataTimer = null;

    debugPrint('[DashboardVM] STREAM ERROR: $error');
    debugPrint('[DashboardVM] Stack: $stackTrace');

    _state = DashboardState.error;
    _errorMessage = error.toString();
    notifyListeners();
  }

  void _onInitialDataTimeout() {
    if (_state != DashboardState.loading) {
      return;
    }

    debugPrint(
      '[DashboardVM] TIMEOUT: No data received within ${_initialDataTimeout.inSeconds}s',
    );

    _state = DashboardState.error;
    _errorMessage = 'Belum ada data sensor dari Firebase.';
    notifyListeners();
  }

  MetricTrend _resolveTrend({
    required double previous,
    required double current,
  }) {
    if (current > previous) {
      return MetricTrend.up;
    }
    if (current < previous) {
      return MetricTrend.down;
    }
    return MetricTrend.stable;
  }

  void _checkStaleness() {
    final latest = _latestMetrics;
    if (latest == null) return;

    final age = DateTime.now().difference(latest.timestamp);
    final wasOnline = _deviceOnline;
    _deviceOnline = age < _staleThreshold;

    if (wasOnline && !_deviceOnline) {
      debugPrint(
        '[DashboardVM] Device went OFFLINE (data age: ${age.inSeconds}s)',
      );
      notifyListeners();
    } else if (!wasOnline && _deviceOnline) {
      debugPrint('[DashboardVM] Device came back ONLINE');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _initialDataTimer?.cancel();
    _staleCheckTimer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
