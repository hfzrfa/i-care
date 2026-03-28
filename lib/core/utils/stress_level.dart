import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum StressLevel {
  normal,
  sedang,
  stress,
  unknown,
}

class StressLevelMapper {
  const StressLevelMapper._();

  static double gsrScore(double gsr) {
    return ((gsr / 10).clamp(0.0, 1.0)) * 100;
  }

  static double emgScore(double emg) {
    return ((emg / 50).clamp(0.0, 1.0)) * 100;
  }

  static double combinedScore({
    required double gsr,
    required double emg,
  }) {
    final gsrNormalized = (gsr / 10).clamp(0.0, 1.0);
    final emgNormalized = (emg / 50).clamp(0.0, 1.0);

    return ((gsrNormalized * 0.4) + (emgNormalized * 0.6)) * 100;
  }

  static StressLevel fromScore(double score) {
    if (score <= 39) {
      return StressLevel.normal;
    }
    if (score <= 69) {
      return StressLevel.sedang;
    }
    return StressLevel.stress;
  }

  static String labelFromScore(double score) {
    final level = fromScore(score);
    switch (level) {
      case StressLevel.normal:
        return 'NORMAL';
      case StressLevel.sedang:
        return 'SEDANG';
      case StressLevel.stress:
        return 'TINGGI';
      case StressLevel.unknown:
        return 'UNKNOWN';
    }
  }

  static Color colorFromScore(double score) {
    final level = fromScore(score);
    switch (level) {
      case StressLevel.normal:
        return AppColors.normalStress;
      case StressLevel.sedang:
        return AppColors.mediumStress;
      case StressLevel.stress:
        return AppColors.highStress;
      case StressLevel.unknown:
        return Colors.grey;
    }
  }

  static StressLevel fromStatus(String status) {
    final normalized = status.trim().toUpperCase();
    if (normalized == 'NORMAL') {
      return StressLevel.normal;
    }
    if (normalized == 'SEDANG') {
      return StressLevel.sedang;
    }
    if (normalized == 'STRESS' || normalized == 'TINGGI') {
      return StressLevel.stress;
    }
    return StressLevel.unknown;
  }

  static Color toColor(String status) {
    switch (fromStatus(status)) {
      case StressLevel.normal:
        return AppColors.normalStress;
      case StressLevel.sedang:
        return AppColors.mediumStress;
      case StressLevel.stress:
        return AppColors.highStress;
      case StressLevel.unknown:
        return Colors.grey;
    }
  }
}
