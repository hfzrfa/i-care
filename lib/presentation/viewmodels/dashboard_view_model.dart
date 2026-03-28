import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/health_metrics.dart';
import '../../domain/usecases/watch_health_metrics.dart';

enum DashboardState {
  initial,
  loading,
  ready,
  error,
}

enum MetricTrend {
  up,
  down,
  stable,
}

class DashboardViewModel extends ChangeNotifier {
  DashboardViewModel(this._watchHealthMetricsUseCase);

  static const int _maxPoints = 50;

  final WatchHealthMetricsUseCase _watchHealthMetricsUseCase;

  DashboardState _state = DashboardState.initial;
  HealthMetrics? _latestMetrics;
  final List<double> _gsrHistory = <double>[];
  final List<double> _emgHistory = <double>[];
  MetricTrend _gsrTrend = MetricTrend.stable;
  MetricTrend _emgTrend = MetricTrend.stable;
  String? _errorMessage;
  StreamSubscription<HealthMetrics>? _subscription;

  DashboardState get state => _state;
  HealthMetrics? get latestMetrics => _latestMetrics;
  List<double> get gsrHistory => List.unmodifiable(_gsrHistory);
  List<double> get emgHistory => List.unmodifiable(_emgHistory);
  MetricTrend get gsrTrend => _gsrTrend;
  MetricTrend get emgTrend => _emgTrend;
  String? get errorMessage => _errorMessage;

  void initialize() {
    if (_subscription != null) {
      return;
    }

    _state = DashboardState.loading;
    notifyListeners();

    _subscription = _watchHealthMetricsUseCase.execute().listen(
      _onMetricsReceived,
      onError: _onMetricsError,
      cancelOnError: false,
    );
  }

  void _onMetricsReceived(HealthMetrics metrics) {
    _state = DashboardState.ready;
    _errorMessage = null;
    _latestMetrics = metrics;

    if (_gsrHistory.isNotEmpty) {
      _gsrTrend = _resolveTrend(previous: _gsrHistory.last, current: metrics.gsrValue);
    }
    if (_emgHistory.isNotEmpty) {
      _emgTrend = _resolveTrend(previous: _emgHistory.last, current: metrics.emgValue);
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
    _state = DashboardState.error;
    _errorMessage = error.toString();
    notifyListeners();
  }

  MetricTrend _resolveTrend({required double previous, required double current}) {
    if (current > previous) {
      return MetricTrend.up;
    }
    if (current < previous) {
      return MetricTrend.down;
    }
    return MetricTrend.stable;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
