import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

import '../../core/utils/stress_level.dart';
import '../viewmodels/dashboard_view_model.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<DashboardViewModel>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardViewModel>(
      builder: (context, vm, _) {
        if (vm.state == DashboardState.loading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (vm.state == DashboardState.error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                vm.errorMessage ?? 'Failed to stream sensor data.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final metrics = vm.latestMetrics;
        if (metrics == null) {
          return const Center(child: Text('Waiting for first sensor data...'));
        }
        final gsrClassification = StressLevelMapper.gsrClassification(
          metrics.gsrValue,
        );
        final emgClassification = StressLevelMapper.emgClassification(
          metrics.emgValue,
        );
        final gsrStatusColor = gsrClassification.color;
        final emgStatusColor = emgClassification.color;
        final gsrScoreHistory = vm.gsrHistory
            .map(StressLevelMapper.gsrScore)
            .toList();
        final emgScoreHistory = vm.emgHistory
            .map(StressLevelMapper.emgScore)
            .toList();

        return ListView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            Row(
              children: [
                Expanded(
                  child: _StressSummaryCard(
                    title: 'Stres Kulit',
                    status: gsrClassification.label,
                    valueText: '${metrics.gsrValue.toStringAsFixed(2)} uS',
                    statusColor: gsrStatusColor,
                    icon: Icons.sentiment_neutral_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StressSummaryCard(
                    title: 'Stres Otot',
                    status: emgClassification.label,
                    valueText: '${metrics.emgValue.toStringAsFixed(2)} uV',
                    statusColor: emgStatusColor,
                    icon: Icons.fitness_center_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            _SensorValueCard(
              title: 'GSR Value',
              value: '${metrics.gsrValue.toStringAsFixed(2)} uS',
              color: gsrStatusColor,
              icon: Icons.waves_outlined,
            ),
            const SizedBox(height: 12),
            _StressGraphCard(
              title: 'Grafik Stres Kulit',
              status: gsrClassification.label,
              valueText: '${metrics.gsrValue.toStringAsFixed(2)} uS',
              points: gsrScoreHistory,
              color: gsrStatusColor,
            ),

            const SizedBox(height: 20),

            _SensorValueCard(
              title: 'EMG Value',
              value: '${metrics.emgValue.toStringAsFixed(2)} uV',
              color: emgStatusColor,
              icon: Icons.graphic_eq,
            ),
            const SizedBox(height: 12),
            _StressGraphCard(
              title: 'Grafik Stress Otot',
              status: emgClassification.label,
              valueText: '${metrics.emgValue.toStringAsFixed(2)} uV',
              points: emgScoreHistory,
              color: emgStatusColor,
            ),
          ],
        );
      },
    );
  }
}

class _StressSummaryCard extends StatelessWidget {
  const _StressSummaryCard({
    required this.title,
    required this.status,
    required this.valueText,
    required this.statusColor,
    required this.icon,
  });

  final String title;
  final String status;
  final String valueText;
  final Color statusColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: statusColor),
          const SizedBox(height: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.75),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            status,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Nilai: $valueText',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SensorValueCard extends StatelessWidget {
  const _SensorValueCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: color.withValues(alpha: 0.16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _StressGraphCard extends StatelessWidget {
  const _StressGraphCard({
    required this.title,
    required this.status,
    required this.valueText,
    required this.points,
    required this.color,
  });

  final String title;
  final String status;
  final String valueText;
  final List<double> points;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final spots = <FlSpot>[];
    for (var i = 0; i < points.length; i++) {
      spots.add(FlSpot(i.toDouble(), points[i]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        RepaintBoundary(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: Theme.of(context).colorScheme.surfaceContainer,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Klasifikasi: $status',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: color.withValues(alpha: 0.14),
                      ),
                      child: Text(
                        valueText,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 200,
                  child: LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                        getDrawingHorizontalLine: (_) => FlLine(
                          color: Theme.of(
                            context,
                          ).dividerColor.withValues(alpha: 0.26),
                          strokeWidth: 1,
                        ),
                      ),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: 25,
                            getTitlesWidget: (value, meta) => Text(
                              value.toStringAsFixed(0),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                        bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      lineTouchData: const LineTouchData(enabled: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          curveSmoothness: 0.3,
                          color: color,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: color.withValues(alpha: 0.10),
                          ),
                        ),
                      ],
                    ),
                    duration: const Duration(milliseconds: 150),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
