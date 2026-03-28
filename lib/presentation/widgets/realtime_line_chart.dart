import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'glass_card.dart';

class RealtimeLineChart extends StatelessWidget {
  const RealtimeLineChart({
    super.key,
    required this.title,
    required this.points,
    required this.lineColor,
  });

  final String title;
  final List<double> points;
  final Color lineColor;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i]));
    }

    final yInterval = _yInterval(points);
    final maxY = _maxY(points, yInterval);

    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          SizedBox(
            height: 210,
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: yInterval,
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 34,
                      interval: yInterval,
                      getTitlesWidget: (value, meta) {
                        // Hide the upper bound label so it doesn't overlap title.
                        if (value >= maxY - (yInterval / 4)) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          value.toStringAsFixed(0),
                          style: Theme.of(context).textTheme.bodySmall,
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(enabled: true),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    barWidth: 3,
                    color: lineColor,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: lineColor.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  double _yInterval(List<double> values) {
    if (values.isEmpty) {
      return 10;
    }
    final max = values.reduce((a, b) => a > b ? a : b);
    final interval = max / 4;
    return interval <= 1 ? 1 : interval;
  }

  double _maxY(List<double> values, double interval) {
    if (values.isEmpty) {
      return 40;
    }
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    return maxValue + (interval * 0.75);
  }
}
