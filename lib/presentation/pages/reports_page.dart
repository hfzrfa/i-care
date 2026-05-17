import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';

import '../../core/utils/stress_level.dart';
import '../viewmodels/dashboard_view_model.dart';
import '../widgets/glass_card.dart';

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
        final gsrClassification = StressLevelMapper.gsrClassification(gsrAvg);
        final emgClassification = StressLevelMapper.emgClassification(emgAvg);
        final combined = StressLevelMapper.combinedResult(
          gsr: gsrAvg,
          emg: emgAvg,
        );
        final combinedColor = StressLevelMapper.colorFromLevel(combined.level);

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
                      status: gsrClassification.label,
                      statusColor: gsrClassification.color,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ReportStatCard(
                      title: 'Avg EMG',
                      value: emgAvg.toStringAsFixed(2),
                      subtitle: 'uV',
                      status: emgClassification.label,
                      statusColor: emgClassification.color,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (length == 0)
                const GlassCard(
                  child: SizedBox(
                    height: 120,
                    child: Center(
                      child: Text('Waiting for enough stream data...'),
                    ),
                  ),
                )
              else
                _CombinedExplanationCard(
                  category: combined.category,
                  interpretation: combined.interpretation,
                  color: combinedColor,
                ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Report Menu',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 10),
                    _MenuActionButton(
                      icon: Icons.picture_as_pdf_outlined,
                      text: 'Export PDF',
                      onTap: () => _exportPdf(context, vm),
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
      final gsrClassification = StressLevelMapper.gsrClassification(gsrAvg);
      final emgClassification = StressLevelMapper.emgClassification(emgAvg);
      final combined = StressLevelMapper.combinedResult(
        gsr: gsrAvg,
        emg: emgAvg,
      );
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          build: (context) => [
            _pdfHeader(now),
            pw.Container(
              color: const PdfColor.fromInt(0xFFF4F7FA),
              padding: const pw.EdgeInsets.fromLTRB(42, 18, 42, 32),
              child: pw.Column(
                children: [
                  _pdfCard(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _pdfSectionTitle('Ringkasan Biometrik'),
                        pw.SizedBox(height: 16),
                        pw.Row(
                          children: [
                            pw.Expanded(
                              child: _pdfMetricCard(
                                title: 'AVG GSR',
                                value: gsrAvg.toStringAsFixed(2),
                                unit: 'uS',
                                status: gsrClassification.label,
                                statusColor: _pdfSensorColor(
                                  gsrClassification.label,
                                ),
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Expanded(
                              child: _pdfMetricCard(
                                title: 'AVG EMG',
                                value: emgAvg.toStringAsFixed(2),
                                unit: 'uV',
                                status: emgClassification.label,
                                statusColor: _pdfSensorColor(
                                  emgClassification.label,
                                ),
                              ),
                            ),
                            pw.SizedBox(width: 8),
                            pw.Expanded(
                              child: _pdfMetricCard(
                                title: 'STRESS LEVEL',
                                value: combined.category,
                                status: _pdfStressNote(combined.category),
                                statusColor: _pdfCombinedColor(combined.level),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  _pdfCard(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        _pdfSectionTitle('Combined Stress Trend'),
                        pw.SizedBox(height: 8),
                        pw.Text(
                          'Analisis korelasi antara aktivitas kelenjar keringat (GSR) dan ketegangan otot (EMG).',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                        pw.SizedBox(height: 12),
                        _pdfCombinedPanel(
                          gsrValue: gsrAvg,
                          gsrStatus: gsrClassification.label,
                          emgValue: emgAvg,
                          emgStatus: emgClassification.label,
                          combined: combined,
                        ),
                        pw.SizedBox(height: 10),
                        pw.Text(
                          'Jumlah data yang dianalisis: $pointCount titik.',
                          style: const pw.TextStyle(
                            fontSize: 8.5,
                            color: PdfColors.grey700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

      final reportFile = await _writeReportFile(
        extension: 'pdf',
        bytes: await pdf.save(),
      );

      final openResult = await OpenFilex.open(
        reportFile.path,
        type: 'application/pdf',
      );

      if (!context.mounted) {
        return;
      }
      if (openResult.type == ResultType.done) {
        _showSnackBar(context, 'PDF berhasil dibuat dan dibuka.');
      } else {
        _showSnackBar(
          context,
          'PDF berhasil dibuat, tetapi gagal dibuka: ${openResult.message}',
        );
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showSnackBar(context, 'Gagal membuat PDF. Coba lagi.');
    }
  }

  Future<File> _writeReportFile({
    required String extension,
    required List<int> bytes,
  }) async {
    final baseDir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final reportFile = File(
      '${baseDir.path}/laporan_kesehatan_stress_$timestamp.$extension',
    );
    return reportFile.writeAsBytes(bytes, flush: true);
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  pw.Widget _pdfHeader(DateTime generatedAt) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFF111827)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'Laporan Kesehatan Stress',
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 22,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Periode: ${_formatPdfDate(generatedAt)} | User ID: #1000305969',
            style: const pw.TextStyle(color: PdfColors.grey300, fontSize: 9),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Row(
      children: [
        pw.Container(width: 4, height: 22, color: PdfColors.teal),
        pw.SizedBox(width: 8),
        pw.Text(
          title,
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15),
        ),
      ],
    );
  }

  pw.Widget _pdfCard({required pw.Widget child}) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(18),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB)),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: child,
    );
  }

  pw.Widget _pdfMetricCard({
    required String title,
    required String value,
    String unit = '',
    required String status,
    required PdfColor statusColor,
  }) {
    return pw.Container(
      height: 78,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE5E7EB)),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            title,
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            unit.isEmpty ? value : '$value $unit',
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF111827),
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            status,
            style: pw.TextStyle(
              fontSize: 8,
              color: statusColor,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfCombinedPanel({
    required double gsrValue,
    required String gsrStatus,
    required double emgValue,
    required String emgStatus,
    required CombinedStressResult combined,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(14),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFF1F5F9),
        border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            children: [
              _pdfInputBadge(
                label: 'EMG',
                value: '${emgValue.toStringAsFixed(2)} uV',
                status: emgStatus,
              ),
              pw.SizedBox(width: 8),
              _pdfInputBadge(
                label: 'GSR',
                value: '${gsrValue.toStringAsFixed(2)} uS',
                status: gsrStatus,
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                width: 150,
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(
                    color: const PdfColor.fromInt(0xFFE2E8F0),
                  ),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Kombinasi Kategori',
                      style: const pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      combined.category,
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: _pdfCombinedColor(combined.level),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.white,
                    border: pw.Border.all(
                      color: const PdfColor.fromInt(0xFFE2E8F0),
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Interpretasi / Keterangan',
                        style: const pw.TextStyle(
                          fontSize: 8,
                          color: PdfColors.grey700,
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        combined.interpretation,
                        style: const pw.TextStyle(
                          fontSize: 10.5,
                          color: PdfColor.fromInt(0xFF374151),
                          lineSpacing: 3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfInputBadge({
    required String label,
    required String value,
    required String status,
  }) {
    return pw.Expanded(
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: const PdfColor.fromInt(0xFFE2E8F0)),
        ),
        child: pw.Row(
          children: [
            pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF111827),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
                color: const PdfColor.fromInt(0xFF111827),
              ),
            ),
            pw.SizedBox(width: 8),
            pw.Expanded(
              child: pw.Text(
                status,
                style: pw.TextStyle(
                  fontSize: 8.5,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfSensorColor(status),
                ),
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  PdfColor _pdfSensorColor(String status) {
    final normalized = status.toLowerCase();
    if (normalized.contains('high') || normalized.contains('stress')) {
      return const PdfColor.fromInt(0xFFE84A5F);
    }
    if (normalized.contains('moderate') || normalized.contains('sedang')) {
      return const PdfColor.fromInt(0xFFF59E0B);
    }
    return const PdfColor.fromInt(0xFF10B981);
  }

  PdfColor _pdfCombinedColor(StressLevel level) {
    switch (level) {
      case StressLevel.normal:
        return const PdfColor.fromInt(0xFF10B981);
      case StressLevel.sedang:
        return const PdfColor.fromInt(0xFFF59E0B);
      case StressLevel.stress:
        return const PdfColor.fromInt(0xFFE84A5F);
      case StressLevel.unknown:
        return PdfColors.grey600;
    }
  }

  String _pdfStressNote(String category) {
    final normalized = category.toLowerCase();
    if (normalized.contains('high')) {
      return 'Perlu Perhatian';
    }
    if (normalized.contains('moderate')) {
      return 'Perlu Dipantau';
    }
    return 'Normal';
  }

  String _formatPdfDate(DateTime date) {
    final months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _ReportStatCard extends StatelessWidget {
  const _ReportStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.status,
    required this.statusColor,
  });

  final String title;
  final String value;
  final String subtitle;
  final String status;
  final Color statusColor;

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
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(subtitle),
          const SizedBox(height: 6),
          Text(
            status,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: statusColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _CombinedExplanationCard extends StatelessWidget {
  const _CombinedExplanationCard({
    required this.category,
    required this.interpretation,
    required this.color,
  });

  final String category;
  final String interpretation;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Keterangan Hasil Kombinasi',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          Text(
            category,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(interpretation, style: Theme.of(context).textTheme.bodyLarge),
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
