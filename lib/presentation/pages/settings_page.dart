import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/datasources/firebase_health_remote_data_source.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import '../viewmodels/theme_view_model.dart';
import '../widgets/glass_card.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _sensorPathController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_sensorPathController.text.isEmpty) {
      _sensorPathController.text = context
          .read<SettingsViewModel>()
          .sensorApiPath;
    }
  }

  @override
  void dispose() {
    _sensorPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<SettingsViewModel, ThemeViewModel, DashboardViewModel>(
      builder: (context, settingsVm, themeVm, dashboardVm, _) {
        final sensorStatus = _sensorStatusMeta(
          settingsVm.sensorConnectionStatus,
        );

        final isConnected = dashboardVm.isDeviceOnline;
        final connectionLabel = isConnected ? 'Connected' : 'Disconnected';
        final connectionColor = isConnected ? Colors.green : Colors.red;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Device Connection',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.sensors, color: connectionColor),
                        const SizedBox(width: 8),
                        Text(
                          connectionLabel,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: connectionColor,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _sensorPathController,
                      decoration: const InputDecoration(
                        labelText: 'ESP32 API Path (Realtime DB)',
                        hintText: 'health_monitoring/latest',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed:
                                settingsVm.sensorConnectionStatus ==
                                    SensorConnectionStatus.checking
                                ? null
                                : () async {
                                    await settingsVm.setSensorApiPath(
                                      _sensorPathController.text,
                                    );
                                    if (!context.mounted) {
                                      return;
                                    }
                                    await settingsVm.testSensorConnection();
                                  },
                            icon: const Icon(Icons.wifi_tethering),
                            label: const Text('Test Koneksi'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () async {
                              await settingsVm.setSensorApiPath(
                                _sensorPathController.text,
                              );
                              if (!context.mounted) {
                                return;
                              }
                              context.read<HealthRemoteDataSource>().updatePath(
                                settingsVm.sensorApiPath,
                              );
                              await dashboardVm.restartStream();
                              if (!context.mounted) {
                                return;
                              }
                              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Path diterapkan: ${settingsVm.sensorApiPath}',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.check_circle_outline),
                            label: const Text('Apply'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(sensorStatus.icon, color: sensorStatus.color),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            settingsVm.sensorConnectionMessage,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: sensorStatus.color,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Dark Theme'),
                      value: themeVm.themeMode == ThemeMode.dark,
                      onChanged: (enabled) {
                        themeVm.setThemeMode(
                          enabled ? ThemeMode.dark : ThemeMode.light,
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    Text('App Version: ${settingsVm.appVersion}'),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  _SensorStatusMeta _sensorStatusMeta(SensorConnectionStatus status) {
    switch (status) {
      case SensorConnectionStatus.connected:
        return const _SensorStatusMeta(Icons.check_circle, Colors.green);
      case SensorConnectionStatus.noData:
        return const _SensorStatusMeta(Icons.info_outline, Colors.orange);
      case SensorConnectionStatus.error:
        return const _SensorStatusMeta(Icons.error_outline, Colors.red);
      case SensorConnectionStatus.checking:
        return const _SensorStatusMeta(Icons.sync, Colors.blue);
      case SensorConnectionStatus.idle:
        return const _SensorStatusMeta(
          Icons.radio_button_unchecked,
          Colors.grey,
        );
    }
  }
}

class _SensorStatusMeta {
  const _SensorStatusMeta(this.icon, this.color);

  final IconData icon;
  final Color color;
}
