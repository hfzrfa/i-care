import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../viewmodels/dashboard_view_model.dart';
import '../widgets/glass_card.dart';
import '../widgets/realtime_line_chart.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardViewModel>(
      builder: (context, vm, _) {
        final gsrAvg = _average(vm.gsrHistory);
        final emgAvg = _average(vm.emgHistory);
        final length = vm.gsrHistory.length < vm.emgHistory.length
            ? vm.gsrHistory.length
            : vm.emgHistory.length;
        final points = List<double>.generate(
          length,
          (index) => (vm.gsrHistory[index] + vm.emgHistory[index]) / 2,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Health Reports',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Weekly insights and report-ready snapshots.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _ReportStatCard(
                      title: 'Avg GSR',
                      value: gsrAvg.toStringAsFixed(2),
                      subtitle: 'uS',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReportStatCard(
                      title: 'Avg EMG',
                      value: emgAvg.toStringAsFixed(2),
                      subtitle: 'mV',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (points.isEmpty)
                const GlassCard(
                  child: SizedBox(
                    height: 120,
                    child: Center(child: Text('Waiting for enough stream data...')),
                  ),
                )
              else
                RealtimeLineChart(
                  title: 'Combined Stress Trend',
                  points: points,
                  lineColor: Theme.of(context).colorScheme.secondary,
                ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Report Menu', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    const _MenuRow(icon: Icons.picture_as_pdf_outlined, text: 'Export PDF (Demo)'),
                    const SizedBox(height: 8),
                    const _MenuRow(icon: Icons.table_chart_outlined, text: 'Export CSV (Demo)'),
                    const SizedBox(height: 8),
                    const _MenuRow(icon: Icons.mail_outline, text: 'Share via Email (Demo)'),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double _average(List<double> values) {
    if (values.isEmpty) {
      return 0;
    }
    final total = values.fold<double>(0, (sum, value) => sum + value);
    return total / values.length;
  }
}

class _ReportStatCard extends StatelessWidget {
  const _ReportStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(subtitle),
        ],
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(text),
      ],
    );
  }
}

