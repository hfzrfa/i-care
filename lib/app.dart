import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'core/utils/stress_level.dart';
import 'data/datasources/firebase_health_remote_data_source.dart';
import 'data/models/health_metrics_model.dart';
import 'data/repositories/health_repository_impl.dart';
import 'domain/usecases/watch_health_metrics.dart';
import 'presentation/pages/app_entry_page.dart';
import 'presentation/viewmodels/app_flow_view_model.dart';
import 'presentation/viewmodels/dashboard_view_model.dart';
import 'presentation/viewmodels/settings_view_model.dart';
import 'presentation/viewmodels/theme_view_model.dart';

class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.initializeFirebase = true,
    this.useMockSensor = true,
  });

  final bool initializeFirebase;
  final bool useMockSensor;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
        ChangeNotifierProvider(create: (_) => AppFlowViewModel()),
        ChangeNotifierProvider(create: (_) => SettingsViewModel()),
        Provider<HealthRemoteDataSource>(
          create: (_) {
            if (!initializeFirebase || useMockSensor) {
              return const MockHealthRemoteDataSource();
            }
            return FirebaseHealthRemoteDataSource();
          },
        ),
        Provider<HealthRepositoryImpl>(
          create: (context) =>
              HealthRepositoryImpl(context.read<HealthRemoteDataSource>()),
        ),
        Provider<WatchHealthMetricsUseCase>(
          create: (context) =>
              WatchHealthMetricsUseCase(context.read<HealthRepositoryImpl>()),
        ),
        ChangeNotifierProvider<DashboardViewModel>(
          create: (context) =>
              DashboardViewModel(context.read<WatchHealthMetricsUseCase>()),
        ),
      ],
      child: Consumer<ThemeViewModel>(
        builder: (context, themeVm, _) {
          return MaterialApp(
            title: 'I-Care',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeVm.themeMode,
            home: _AppBootstrap(
              initializeFirebase: initializeFirebase,
              useMockSensor: useMockSensor,
            ),
          );
        },
      ),
    );
  }
}

class _AppBootstrap extends StatefulWidget {
  const _AppBootstrap({
    required this.initializeFirebase,
    required this.useMockSensor,
  });

  final bool initializeFirebase;
  final bool useMockSensor;

  @override
  State<_AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<_AppBootstrap> {
  late final Future<void> _bootstrapFuture;
  Object? _bootstrapError;

  @override
  void initState() {
    super.initState();
    _bootstrapFuture = _bootstrap();
  }

  Future<void> _bootstrap() async {
    debugPrint('--- BOOTSTRAP: START ---');
    final flowVm = context.read<AppFlowViewModel>();
    final settingsVm = context.read<SettingsViewModel>();

    if (!widget.initializeFirebase) {
      debugPrint('--- BOOTSTRAP: Skipping Firebase ---');
      await flowVm.initialize();
      await settingsVm.initialize();
      return;
    }

    try {
      debugPrint('--- BOOTSTRAP: Initializing Firebase ---');
      await Firebase.initializeApp();
      debugPrint('--- BOOTSTRAP: Firebase Initialized ---');
    } catch (error) {
      debugPrint('--- BOOTSTRAP: Firebase Error: $error ---');
      _bootstrapError = error;
    }

    debugPrint('--- BOOTSTRAP: Initializing AppFlowViewModel ---');
    await flowVm.initialize();
    debugPrint('--- BOOTSTRAP: Initializing SettingsViewModel ---');
    await settingsVm.initialize();

    if (!mounted) {
      return;
    }

    final healthRemoteDataSource = context.read<HealthRemoteDataSource>();
    healthRemoteDataSource.updatePath(settingsVm.sensorApiPath);
    debugPrint('--- BOOTSTRAP: DONE ---');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return AppEntryPage(
          showFirebaseWarning: _bootstrapError != null,
          showMockSensorInfo: widget.useMockSensor,
        );
      },
    );
  }
}

class MockHealthRemoteDataSource implements HealthRemoteDataSource {
  const MockHealthRemoteDataSource();

  @override
  String get currentPath => 'mock://health_monitoring/latest';

  @override
  void updatePath(String path) {}

  @override
  Stream<HealthMetricsModel> watchHealthMetrics() {
    return Stream<HealthMetricsModel>.periodic(const Duration(seconds: 2), (
      tick,
    ) {
      final t = tick.toDouble();

      final gsrWave =
          4.6 + (math.sin(t / 3.4) * 1.1) + (math.cos(t / 8.0) * 0.5);
      final gsrJitter = ((tick % 5) - 2) * 0.08;
      final gsrSpike = tick % 21 == 0
          ? 1.3
          : tick % 17 == 0
          ? -0.9
          : 0.0;
      final gsr = (gsrWave + gsrJitter + gsrSpike).clamp(1.3, 9.8).toDouble();

      final emgWave =
          125 + (math.sin((t + 4) / 2.9) * 26) + (math.cos(t / 6.7) * 14);
      final emgJitter = ((tick % 7) - 3) * 2.5;
      final emgSpike = tick % 19 == 0
          ? 38.0
          : tick % 13 == 0
          ? -22.0
          : 0.0;
      final emg = (emgWave + emgJitter + emgSpike)
          .clamp(80.0, 190.0)
          .toDouble();
      final status = StressLevelMapper.combinedResult(
        gsr: gsr,
        emg: emg,
      ).category;

      return HealthMetricsModel(
        stressStatus: status,
        gsrValue: gsr,
        emgValue: emg,
        timestamp: DateTime.now(),

        csEnabled: false,
      );
    });
  }
}
