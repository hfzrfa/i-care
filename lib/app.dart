import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
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
          create: (context) => HealthRepositoryImpl(
            context.read<HealthRemoteDataSource>(),
          ),
        ),
        Provider<WatchHealthMetricsUseCase>(
          create: (context) => WatchHealthMetricsUseCase(
            context.read<HealthRepositoryImpl>(),
          ),
        ),
        ChangeNotifierProvider<DashboardViewModel>(
          create: (context) => DashboardViewModel(
            context.read<WatchHealthMetricsUseCase>(),
          ),
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
    final flowVm = context.read<AppFlowViewModel>();
    final settingsVm = context.read<SettingsViewModel>();

    if (!widget.initializeFirebase) {
      await flowVm.initialize();
      await settingsVm.initialize();
      return;
    }

    try {
      await Firebase.initializeApp();
    } catch (error) {
      _bootstrapError = error;
    }

    await flowVm.initialize();
    await settingsVm.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
  Stream<HealthMetricsModel> watchHealthMetrics() {
    return Stream<HealthMetricsModel>.periodic(
      const Duration(milliseconds: 800),
      (tick) {
        final t = tick.toDouble();

        final gsrWave = 4.6 + (math.sin(t / 3.4) * 1.1) + (math.cos(t / 8.0) * 0.5);
        final gsrJitter = ((tick % 5) - 2) * 0.08;
        final gsrSpike = tick % 21 == 0
            ? 1.3
            : tick % 17 == 0
                ? -0.9
                : 0.0;
        final gsr = (gsrWave + gsrJitter + gsrSpike).clamp(1.3, 9.8);

        final emgWave = 32 + (math.sin((t + 4) / 2.9) * 7.5) + (math.cos(t / 6.7) * 4.2);
        final emgJitter = ((tick % 7) - 3) * 0.9;
        final emgSpike = tick % 19 == 0
            ? 10.0
            : tick % 13 == 0
                ? -6.0
                : 0.0;
        final emg = (emgWave + emgJitter + emgSpike).clamp(10.0, 49.0);

        final stressScore = ((gsr / 10) * 0.4 + (emg / 50) * 0.6) * 100;
        final status = stressScore <= 39
            ? 'NORMAL'
            : stressScore <= 69
                ? 'SEDANG'
                : 'STRESS';

        return HealthMetricsModel(
          stressStatus: status,
          gsrValue: gsr,
          emgValue: emg,
          timestamp: DateTime.now(),
        );
      },
    );
  }
}
