import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/dashboard_view_model.dart';
import '../viewmodels/settings_view_model.dart';
import '../viewmodels/theme_view_model.dart';
import '../widgets/glass_card.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer3<SettingsViewModel, ThemeViewModel, DashboardViewModel>(
      builder: (context, settingsVm, themeVm, dashboardVm, _) {
        final isConnected = dashboardVm.state == DashboardState.ready;
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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: connectionColor,
                            fontWeight: FontWeight.w700,
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
                        themeVm.setThemeMode(enabled ? ThemeMode.dark : ThemeMode.light);
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Allow Notifications'),
                      value: settingsVm.notificationsEnabled,
                      onChanged: settingsVm.setNotificationsEnabled,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Push Alerts'),
                      value: settingsVm.pushAlerts,
                      onChanged: settingsVm.setPushAlerts,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Critical Alerts Only'),
                      value: settingsVm.criticalOnly,
                      onChanged: settingsVm.setCriticalOnly,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Haptic Feedback'),
                      value: settingsVm.hapticFeedback,
                      onChanged: settingsVm.setHapticFeedback,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('About', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    Text('App Version: ${settingsVm.appVersion}'),
                    const SizedBox(height: 10),
                    const _AboutRow(title: 'Privacy Policy'),
                    const SizedBox(height: 8),
                    const _AboutRow(title: 'Terms of Service'),
                    const SizedBox(height: 8),
                    const _AboutRow(title: 'Help & Support'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$title (demo)')),
        );
      },
      child: Row(
        children: [
          Expanded(child: Text(title)),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
