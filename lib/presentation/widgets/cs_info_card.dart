import 'package:flutter/material.dart';

class CsInfoCard extends StatelessWidget {
  const CsInfoCard({super.key, required this.csEnabled, this.compressionRatio});

  final bool csEnabled;
  final double? compressionRatio;

  @override
  Widget build(BuildContext context) {
    if (!csEnabled) return const SizedBox.shrink();

    final theme = Theme.of(context);
    const accentColor = Color(0xFF0AA5BA);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accentColor.withValues(alpha: 0.08),
        border: Border.all(color: accentColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.compress_rounded, size: 18, color: accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Kompresi Data Aktif',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (compressionRatio != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: accentColor.withValues(alpha: 0.12),
              ),
              child: Text(
                '${compressionRatio!.toStringAsFixed(1)}× hemat',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accentColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
