import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/normalized_transcript.dart';
import '../services/analytics_service.dart';
import '../services/transcript/transcript_analytics.dart';
import '../storage/state_providers.dart';
import 'transcript_import_screen.dart';
import 'widgets/charts.dart';

class TranscriptLibraryScreen extends ConsumerWidget {
  const TranscriptLibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final records = ref.watch(transcriptRecordsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcripts'),
        actions: [
          IconButton(
            tooltip: 'Import PDF',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _openImport(context),
          ),
        ],
      ),
      body: SafeArea(
        child: records.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(18),
            child: SkeletonCard(lines: 5),
          ),
          error: (error, _) => Padding(
            padding: const EdgeInsets.all(18),
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Could not read transcripts',
              message: '$error',
            ),
          ),
          data: (items) => items.isEmpty
              ? _TranscriptEmpty(onImport: () => _openImport(context))
              : _TranscriptList(records: items),
        ),
      ),
      floatingActionButton: records.valueOrNull?.isNotEmpty == true
          ? FloatingActionButton.extended(
              onPressed: () => _openImport(context),
              icon: const Icon(Icons.upload_file_rounded),
              label: const Text('Import'),
            )
          : null,
    );
  }

  Future<void> _openImport(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const TranscriptImportScreen()),
    );
  }
}

class _TranscriptEmpty extends StatelessWidget {
  const _TranscriptEmpty({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 70),
        const EmptyState(
          icon: Icons.school_outlined,
          title: 'No transcripts saved',
          message: 'Import a text-layer PDF, review every field, then save it '
              'privately on this device.',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.upload_file_rounded),
          label: const Text('Choose transcript PDF'),
        ),
      ],
    );
  }
}

class _TranscriptList extends ConsumerWidget {
  const _TranscriptList({required this.records});

  final List<NormalizedTranscript> records;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final analytics = ref.watch(transcriptAnalyticsProvider);
    var credits = 0.0;
    var quality = 0.0;
    var gpaHours = 0.0;
    for (final record in records) {
      credits += record.cumulative.creditsEarned ??
          record.terms.fold<double>(
            0,
            (sum, term) =>
                sum +
                term.courses.fold<double>(
                  0,
                  (courseSum, course) =>
                      courseSum + (course.creditsEarned ?? 0),
                ),
          );
      final audit = analytics.audit(record);
      quality += audit.qualityPoints;
      gpaHours += audit.gpaCredits;
    }
    final combined = gpaHours == 0 ? null : quality / gpaHours;

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
      children: [
        if (records.length > 1) ...[
          const SectionLabel('Combined view'),
          const SizedBox(height: 8),
          SurfaceCard(
            fill: p.accent.withValues(alpha: .08),
            borderColor: p.accent.withValues(alpha: .3),
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Institutions',
                    value: '${records.length}',
                    valueColor: p.accent,
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: 'Total credits',
                    value: _number(credits),
                  ),
                ),
                Expanded(
                  child: MetricTile(
                    label: 'Combined GPA',
                    value: combined?.toStringAsFixed(3) ?? '—',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        const SectionLabel('On this device'),
        const SizedBox(height: 8),
        for (final record in records) ...[
          _TranscriptCard(record: record),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _TranscriptCard extends ConsumerWidget {
  const _TranscriptCard({required this.record});

  final NormalizedTranscript record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final audit = ref.watch(transcriptAnalyticsProvider).audit(record);
    return SurfaceCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TranscriptDetailScreen(transcript: record),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.school_rounded, color: p.accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.institution.name ?? 'Unknown institution',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  '${record.courseCount} courses · ${record.terms.length} terms '
                  '· ${shortDate(record.importedAt)}',
                  style: tt.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            record.cumulative.cumulativeAveragePercent == null
                ? audit.computed?.toStringAsFixed(2) ?? '—'
                : '${record.cumulative.cumulativeAveragePercent!.toStringAsFixed(2)}%',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textTertiary),
        ],
      ),
    );
  }
}

class TranscriptDetailScreen extends ConsumerStatefulWidget {
  const TranscriptDetailScreen({super.key, required this.transcript});

  final NormalizedTranscript transcript;

  @override
  ConsumerState<TranscriptDetailScreen> createState() =>
      _TranscriptDetailScreenState();
}

class _TranscriptDetailScreenState
    extends ConsumerState<TranscriptDetailScreen> {
  final _remaining = TextEditingController(text: '24');
  final _target = TextEditingController(text: '3.5');
  WhatIfResult? _whatIf;

  @override
  void dispose() {
    _remaining.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.transcript;
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final analytics = ref.watch(transcriptAnalyticsProvider);
    final audit = analytics.audit(record);
    final printedAverage = record.cumulative.cumulativeAveragePercent;
    final conversions = printedAverage == null
        ? analytics.convert(audit.computed ?? audit.stated)
        : analytics.convertPercentage(printedAverage);
    final terms = analytics.termMetrics(record);
    final subjects = analytics.creditsBySubject(record);
    final distribution = analytics.gradeDistribution(record);
    final progress = analytics.degreeProgress(record);
    final earned = record.cumulative.creditsEarned ??
        terms.fold<double>(0, (sum, term) => sum + term.creditsEarned);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcript'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Export',
            onSelected: _export,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'json', child: Text('Export JSON')),
              PopupMenuItem(value: 'csv', child: Text('Export CSV')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 36),
          children: [
            Text(
              record.institution.name ?? 'Unknown institution',
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              record.student.name ?? 'Student name not printed',
              style: tt.bodySmall?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 18),
            SurfaceCard(
              fill: p.accent.withValues(alpha: .08),
              borderColor:
                  audit.mismatched ? p.warning : p.accent.withValues(alpha: .3),
              child: Column(
                children: [
                  Text(
                    printedAverage == null
                        ? 'CUMULATIVE GPA'
                        : 'OFFICIAL CUMULATIVE AVERAGE',
                    style: tt.labelSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    printedAverage == null
                        ? (audit.computed ?? audit.stated)?.toStringAsFixed(3) ?? '—'
                        : '${printedAverage.toStringAsFixed(2)}%',
                    style: tt.displaySmall?.copyWith(
                      color: audit.mismatched ? p.warning : p.accent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          label: printedAverage == null
                              ? 'Transcript states'
                              : 'Estimated 4.0',
                          value: printedAverage == null
                              ? audit.stated?.toStringAsFixed(3) ?? '—'
                              : _fixed(conversions.fourPoint),
                          align: CrossAxisAlignment.center,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Recomputed',
                          value: audit.computed?.toStringAsFixed(3) ?? '—',
                          align: CrossAxisAlignment.center,
                        ),
                      ),
                      Expanded(
                        child: MetricTile(
                          label: 'Credits earned',
                          value: _number(earned),
                          align: CrossAxisAlignment.center,
                        ),
                      ),
                    ],
                  ),
                  if (audit.mismatched) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Mismatch ${audit.difference!.abs().toStringAsFixed(3)}. '
                      'Review the highlighted parsed fields and repeat policy.',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: p.warning),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Scale conversions'),
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: MetricTile(label: '4.0', value: _fixed(conversions.fourPoint))),
                      Expanded(child: MetricTile(label: '5.0', value: _fixed(conversions.fivePoint))),
                      Expanded(child: MetricTile(label: '4.3', value: _fixed(conversions.fourThreePoint))),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: MetricTile(label: 'Percent', value: conversions.percentage == null ? '—' : '${conversions.percentage!.toStringAsFixed(1)}%')),
                      Expanded(child: MetricTile(label: 'Letter', value: conversions.letter ?? '—')),
                      Expanded(child: MetricTile(label: 'GPA hours', value: _number(audit.gpaCredits))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Conversions are estimates; each institution sets its own scale.',
                    style: tt.bodySmall?.copyWith(color: p.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('GPA trend'),
            const SizedBox(height: 8),
            SurfaceCard(
              child: GpaTrendChart(
                height: 130,
                series: [
                  for (final term in terms)
                    if (term.gpa != null)
                      TermGpa(
                        term: term.label,
                        gpa: term.gpa!,
                        credits: term.creditsEarned,
                        courseCount: 0,
                      ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (progress != null) ...[
              const SectionLabel('Degree progress'),
              const SizedBox(height: 8),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${(progress * 100).toStringAsFixed(1)}% complete',
                        style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    ThinProgressBar(value: progress, color: p.gradeA, height: 8),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
            _BreakdownCard(title: 'Credits by subject', values: subjects.map((k, v) => MapEntry(k, v.toStringAsFixed(1)))),
            const SizedBox(height: 12),
            _BreakdownCard(title: 'Grade distribution', values: distribution.map((k, v) => MapEntry(k, '$v'))),
            const SizedBox(height: 24),
            const SectionLabel('What-if calculator'),
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _remaining, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Remaining credits'))),
                      const SizedBox(width: 12),
                      Expanded(child: TextField(controller: _target, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Target GPA'))),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: () => _calculate(audit, analytics), child: const Text('Calculate needed GPA')),
                  ),
                  if (_whatIf != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _whatIf!.message ?? 'You need a ${_whatIf!.requiredGpa!.toStringAsFixed(3)} GPA over those credits.',
                      style: tt.bodyMedium?.copyWith(color: _whatIf!.reachable ? p.gradeA : p.warning),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            const SectionLabel('Courses'),
            const SizedBox(height: 8),
            for (final term in record.terms) ...[
              _TermCard(term: term),
              const SizedBox(height: 10),
            ],
            if (record.warnings.isNotEmpty) ...[
              const SizedBox(height: 14),
              const SectionLabel('Parse notes'),
              const SizedBox(height: 8),
              SurfaceCard(
                borderColor: p.warning.withValues(alpha: .5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final warning in [...record.warnings, ...audit.warnings]) Text('• $warning', style: tt.bodySmall)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _calculate(GpaAudit audit, TranscriptAnalytics analytics) {
    final current = audit.computed ?? audit.stated;
    final remaining = double.tryParse(_remaining.text);
    final target = double.tryParse(_target.text);
    if (current == null || remaining == null || target == null) {
      setState(() => _whatIf = const WhatIfResult(
            reachable: false,
            message: 'Enter valid numbers and make sure a current GPA was parsed.',
          ));
      return;
    }
    setState(() {
      _whatIf = analytics.whatIf(
        currentGpa: current,
        currentGpaCredits: audit.gpaCredits,
        remainingCredits: remaining,
        targetGpa: target,
      );
    });
  }

  Future<void> _export(String format) async {
    final store = ref.read(transcriptStoreProvider);
    final content = format == 'json'
        ? store.exportJson(widget.transcript)
        : store.exportCsv(widget.transcript);
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export Gradly transcript',
        fileName: 'gradly-transcript.${format == 'json' ? 'json' : 'csv'}',
        type: FileType.custom,
        allowedExtensions: [format],
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (!mounted || path == null) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported ${format.toUpperCase()} successfully.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }
}

class _TermCard extends StatelessWidget {
  const _TermCard({required this.term});

  final NormalizedTerm term;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(term.label ?? 'Unassigned term', style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          '${term.statedAveragePercent == null ? 'GPA ${term.statedGpa?.toStringAsFixed(3) ?? '—'}' : 'Average ${term.statedAveragePercent!.toStringAsFixed(2)}%'} · ${_number(term.creditsEarned ?? 0)} credits',
          style: tt.bodySmall?.copyWith(color: p.textTertiary),
        ),
        children: [
          for (final course in term.courses)
            ListTile(
              dense: true,
              title: Text(course.title ?? '${course.subjectCode ?? ''} ${course.courseNumber ?? ''}'.trim()),
              subtitle: Text('${course.subjectCode ?? ''} ${course.courseNumber ?? ''} · ${_number(course.creditsEarned ?? course.creditsAttempted ?? 0)} credits'),
              trailing: Text(course.letterGrade ?? course.numericGrade?.toStringAsFixed(0) ?? '—', style: TextStyle(fontWeight: FontWeight.w800, color: p.forLetter(course.letterGrade ?? ''))),
            ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.title, required this.values});

  final String title;
  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (values.isEmpty)
            Text('No data parsed', style: TextStyle(color: p.textTertiary))
          else
            for (final entry in values.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [Expanded(child: Text(entry.key)), Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700))]),
              ),
        ],
      ),
    );
  }
}

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2);

String _fixed(double? value) => value?.toStringAsFixed(2) ?? '—';
