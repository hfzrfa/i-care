import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_colors.dart';
import '../viewmodels/app_flow_view_model.dart';
import 'auth_page.dart';
import 'home_shell_page.dart';
import 'onboarding_page.dart';

class AppEntryPage extends StatelessWidget {
  const AppEntryPage({
    super.key,
    required this.showFirebaseWarning,
    required this.showMockSensorInfo,
  });

  final bool showFirebaseWarning;
  final bool showMockSensorInfo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Consumer<AppFlowViewModel>(
      builder: (context, flowVm, _) {
        if (!flowVm.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? const [
                          AppColors.darkBackgroundTop,
                          AppColors.darkBackgroundBottom,
                        ]
                      : const [
                          AppColors.lightBackgroundTop,
                          AppColors.lightBackgroundBottom,
                        ],
                ),
              ),
            ),
            switch (flowVm.stage) {
              AppStage.onboarding => OnboardingPage(
                onContinue: flowVm.completeOnboarding,
              ),
              AppStage.authentication => AuthPage(
                onLogin: (email, password) =>
                    flowVm.login(email: email, password: password),
                onSignUp: (name, email, password) =>
                    flowVm.signUp(name: name, email: email, password: password),
              ),
              AppStage.home => const HomeShellPage(),
            },
            if (showFirebaseWarning)
              Positioned(
                left: 12,
                right: 12,
                bottom: 106,
                child: IgnorePointer(
                  child: Material(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Firebase not configured yet. Running in demo stream mode.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
            if (!showFirebaseWarning && showMockSensorInfo)
              Positioned(
                left: 12,
                right: 12,
                bottom: 106,
                child: IgnorePointer(
                  child: Material(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Mock sensor aktif. Data dashboard masih dummy, login/signup tetap Firebase.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
