import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accentBlue,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: AppColors.glassLight.withValues(alpha: 0.25),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF7FFFA).withValues(alpha: 0.9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFFF2FAF4).withValues(alpha: 0.94),
        selectedItemColor: AppColors.accentTeal,
        unselectedItemColor: const Color(0xFF6B8A7B),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: const Color(0xFF183A33),
        displayColor: const Color(0xFF0F2E2A),
      ),
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.accentTeal,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      cardColor: AppColors.glassDark.withValues(alpha: 0.4),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF0E504B).withValues(alpha: 0.78),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: const Color(0xFF083835).withValues(alpha: 0.93),
        selectedItemColor: const Color(0xFF6CE3C0),
        unselectedItemColor: const Color(0xFF8FC1B6),
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: const Color(0xFFD8F0E7),
        displayColor: const Color(0xFFEFFFF6),
      ),
    );
  }
}
