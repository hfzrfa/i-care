import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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
                    _MenuActionButton(
                      icon: Icons.picture_as_pdf_outlined,
                      text: 'Export PDF',
                      onTap: () => _exportPdf(context, vm),
                    ),
                    const SizedBox(height: 8),
                    _MenuActionButton(
                      icon: Icons.table_chart_outlined,
                      text: 'Export CSV',
                      onTap: () => _exportCsv(context, vm),
                    ),
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

  Future<void> _exportPdf(BuildContext context, DashboardViewModel vm) async {
    final pointCount = vm.gsrHistory.length < vm.emgHistory.length
        ? vm.gsrHistory.length
        : vm.emgHistory.length;

    if (pointCount == 0) {
      _showSnackBar(context, 'Belum ada data untuk diekspor.');
      return;
    }

    try {
      final now = DateTime.now();
      final gsrAvg = _average(vm.gsrHistory);
      final emgAvg = _average(vm.emgHistory);
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (context) => [
            pw.Header(level: 0, child: pw.Text('GSR Health Report')),
            pw.Text('Generated at: ${now.toIso8601String()}'),
            pw.SizedBox(height: 12),
            pw.Text('Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Bullet(text: 'Average GSR: ${gsrAvg.toStringAsFixed(2)} uS'),
            pw.Bullet(text: 'Average EMG: ${emgAvg.toStringAsFixed(2)} mV'),
            pw.Bullet(text: 'Data points: $pointCount'),
            pw.SizedBox(height: 16),
            pw.Text('Data Table', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table.fromTextArray(
              headers: const ['No', 'GSR (uS)', 'EMG (mV)', 'Combined'],
              data: List<List<String>>.generate(pointCount, (index) {
                final gsr = vm.gsrHistory[index];
                final emg = vm.emgHistory[index];
                final combined = (gsr + emg) / 2;

                return [
                  '${index + 1}',
                  gsr.toStringAsFixed(3),
                  emg.toStringAsFixed(3),
                  combined.toStringAsFixed(3),
                ];
              }),
            ),
          ],
        ),
      );

      final reportFile = await _writeReportFile(
        extension: 'pdf',
        bytes: await pdf.save(),
      );

      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, 'PDF berhasil dibuat di: ${reportFile.path}');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, 'Gagal membuat PDF. Coba lagi.');
    }
  }

  Future<void> _exportCsv(BuildContext context, DashboardViewModel vm) async {
    final pointCount = vm.gsrHistory.length < vm.emgHistory.length
        ? vm.gsrHistory.length
        : vm.emgHistory.length;

    if (pointCount == 0) {
      _showSnackBar(context, 'Belum ada data untuk diekspor.');
      return;
    }

    try {
      final buffer = StringBuffer();
      buffer.writeln('No,GSR_uS,EMG_mV,Combined');

      for (var index = 0; index < pointCount; index++) {
        final gsr = vm.gsrHistory[index];
        final emg = vm.emgHistory[index];
        final combined = (gsr + emg) / 2;
        buffer.writeln(
          '${index + 1},${gsr.toStringAsFixed(3)},${emg.toStringAsFixed(3)},${combined.toStringAsFixed(3)}',
        );
      }

      final reportFile = await _writeReportFile(
        extension: 'csv',
        bytes: utf8.encode(buffer.toString()),
      );

      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, 'CSV berhasil dibuat di: ${reportFile.path}');
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, 'Gagal membuat CSV. Coba lagi.');
    }
  }

  Future<File> _writeReportFile({
    required String extension,
    required List<int> bytes,
  }) async {
    final baseDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final reportFile = File('${baseDir.path}/gsr_report_$timestamp.$extension');
    return reportFile.writeAsBytes(bytes, flush: true);
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
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

class _MenuActionButton extends StatelessWidget {
  const _MenuActionButton({
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

