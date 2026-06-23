import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

enum StressLevel { normal, sedang, stress, unknown }

class SensorClassification {
  const SensorClassification({
    required this.label,
    required this.description,
    required this.color,
  });

  final String label;
  final String description;
  final Color color;
}

class CombinedStressResult {
  const CombinedStressResult({
    required this.category,
    required this.interpretation,
    required this.level,
  });

  final String category;
  final String interpretation;
  final StressLevel level;
}

class StressLevelMapper {
  const StressLevelMapper._();

  static const double gsrNormalMax = 5.0;
  static const double gsrModerateMax = 12.0;
  static const double gsrHighMax = 20.0;

  static const double emgNormalMax = 200.0;

  static double gsrScore(double gsr) {
    return ((gsr.clamp(0.0, gsrHighMax) / gsrHighMax) * 100).toDouble();
  }

  static double emgScore(double emg) {
    final normalized = (emg / emgNormalMax) * 100;
    return normalized.clamp(0.0, 100.0).toDouble();
  }

  static SensorClassification gsrClassification(double gsr) {
    if (gsr <= gsrNormalMax) {
      return SensorClassification(
        label: 'Low',
        description: '1-5 uS',
        color: AppColors.normalStress,
      );
    }
    if (gsr <= gsrModerateMax) {
      return SensorClassification(
        label: 'Moderate',
        description: '>5-12 uS',
        color: AppColors.mediumStress,
      );
    }
    return SensorClassification(
      label: 'High',
      description: '>12-20 uS',
      color: AppColors.highStress,
    );
  }

  static SensorClassification emgClassification(double emg) {
    if (emg < emgNormalMax) {
      return SensorClassification(
        label: 'Normal',
        description: '<200 uV',
        color: AppColors.normalStress,
      );
    }
    return SensorClassification(
      label: 'Stress',
      description: '>200 uV',
      color: AppColors.highStress,
    );
  }

  static CombinedStressResult combinedResult({
    required double gsr,
    required double emg,
  }) {
    final emgStress = emg >= emgNormalMax;
    final gsrBand = gsr <= gsrNormalMax
        ? 0
        : gsr <= gsrModerateMax
        ? 1
        : 2;

    if (!emgStress && gsrBand == 0) {
      return const CombinedStressResult(
        category: 'Normal - Low',
        interpretation: 'Otot tenang, arousal kulit rendah, individu relaks.',
        level: StressLevel.normal,
      );
    }
    if (!emgStress && gsrBand == 1) {
      return const CombinedStressResult(
        category: 'Normal - Moderate',
        interpretation:
            'Otot normal, ada sedikit arousal fisiologis, mungkin stres ringan.',
        level: StressLevel.sedang,
      );
    }
    if (!emgStress) {
      return const CombinedStressResult(
        category: 'Normal - High',
        interpretation:
            'Otot normal, tapi arousal tinggi; kemungkinan stres psikologis tanpa ketegangan otot.',
        level: StressLevel.stress,
      );
    }
    if (gsrBand == 0) {
      return const CombinedStressResult(
        category: 'Stres - Low',
        interpretation:
            'Aktivitas otot tinggi tapi arousal kulit rendah; kemungkinan ketegangan fisik atau artefak.',
        level: StressLevel.sedang,
      );
    }
    if (gsrBand == 1) {
      return const CombinedStressResult(
        category: 'Stres - Moderate',
        interpretation:
            'Aktivitas otot tinggi dan arousal kulit sedang; stres fisik atau mental sedang.',
        level: StressLevel.stress,
      );
    }
    return const CombinedStressResult(
      category: 'Stres - High',
      interpretation:
          'Aktivitas otot tinggi dan arousal kulit tinggi; stres tinggi atau kecemasan akut.',
      level: StressLevel.stress,
    );
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
    return colorFromLevel(fromScore(score));
  }

  static Color colorFromLevel(StressLevel level) {
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
    if (normalized == 'NORMAL' || normalized == 'LOW') {
      return StressLevel.normal;
    }
    if (normalized == 'SEDANG' || normalized.contains('MODERATE')) {
      return StressLevel.sedang;
    }
    if (normalized == 'STRESS' ||
        normalized == 'STRES' ||
        normalized == 'TINGGI' ||
        normalized.contains('HIGH')) {
      return StressLevel.stress;
    }
    return StressLevel.unknown;
  }

  static Color toColor(String status) {
    return colorFromLevel(fromStatus(status));
  }
}
