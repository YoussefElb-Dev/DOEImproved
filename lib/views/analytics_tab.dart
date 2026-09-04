import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/schedule_models.dart';
import '../services/analytics_service.dart';
import '../storage/state_providers.dart';
import 'widgets/app_shell.dart';
import 'widgets/charts.dart';

/// Where the numbers get looked at: grade spread, subject strengths, and the
/// full transcript grouped by term.
class AnalyticsTab extends ConsumerWidget {
  const AnalyticsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return ScreenScaffold(
        title: 'Analytics',
        children: [PortalErrorState(error: portal.error!)],
      );
    }
    if (!portal.hasValue) {
      return const ScreenScaffold(
        title: 'Analytics',
        children: [
          SkeletonCard(lines: 5, height: 16),
          SizedBox(height: 14),
          SkeletonCard(lines: 5, height: 16),
        ],
      );
    }

    final snapshot = portal.valueOrNull!;
    final distribution = ref.watch(gradeDistributionProvider);
    final subjects = ref.watch(subjectPerformanceProvider);
    final transcript = ref.watch(transcriptProvider);
    final terms = ref.watch(termGpaSeriesProvider);

    return ScreenScaffold(
      title: 'Analytics',
      children: [
        SurfaceCard(
          child: Row(
            children: [
              RingGauge(
                progress: (snapshot.computedGpa / 4.0).clamp(0.0, 1.0),
                color: _gpaColour(context, snapshot.computedGpa),
                value: snapshot.computedGpa.toStringAsFixed(2),
                caption: 'GPA',
                diameter: 84,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetricTile(
                      label: 'Credits earned',
                      value: snapshot.earnedCredits > 0
                          ? snapshot.earnedCredits.toStringAsFixed(1)
                          : '—',
                    ),
                    const SizedBox(height: 12),
                    MetricTile(
                      label: 'Courses on record',
                      value: '${transcript.length + snapshot.courses.length}',
                    ),
                    const SizedBox(height: 12),
                    MetricTile(
                      label: 'Terms completed',
                      value: '${terms.length}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Grade distribution'),
              const SizedBox(height: 4),
              Text(
                transcript.isEmpty
                    ? 'Across this term'
                    : 'Across every course on record',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 8),
              GradeDistributionChart(counts: distribution),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Performance by subject'),
              const SizedBox(height: 4),
              Text(
                'Average of your current courses',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 6),
              if (subjects.length >= 3)
                SubjectRadarChart(subjects: subjects)
              else if (subjects.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 22),
                  child: Center(
                    child: Text(
                      'No scored courses yet',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: p.textTertiary),
                    ),
                  ),
                )
              else
                // A radar needs three spokes to be a shape; below that a plain
                // list says the same thing without pretending to be a chart.
                for (final s in subjects) _SubjectRow(subject: s),
            ],
          ),
        ),
        const SizedBox(height: 22),
        ..._transcriptSection(context, transcript, terms),
      ],
    );
  }

  Color _gpaColour(BuildContext context, double gpa) {
    final p = context.palette;
    if (gpa >= 3.5) return p.gradeA;
    if (gpa >= 3.0) return p.gradeB;
    if (gpa >= 2.0) return p.gradeC;
    return p.gradeF;
  }

  List<Widget> _transcriptSection(
    BuildContext context,
    List<TranscriptRecord> transcript,
    List<TermGpa> terms,
  ) {
    final p = context.palette;
    if (transcript.isEmpty) {
      return const [
        SectionLabel('Transcript'),
        SizedBox(height: 10),
        EmptyState(
          icon: Icons.history_edu_rounded,
          title: 'Transcript unavailable',
          message: "Your school hasn't posted this yet. Check back later.",
        ),
      ];
    }

    final byTerm = <String, List<TranscriptRecord>>{};
    for (final r in transcript) {
      byTerm.putIfAbsent(r.term.isEmpty ? 'Other' : r.term, () => []).add(r);
    }

    // Newest term first, ordered by the same academic-calendar rule the trend
    // chart uses rather than alphabetically.
    final ordered = terms.map((t) => t.term).toList().reversed.toList();
    for (final key in byTerm.keys) {
      if (!ordered.contains(key)) ordered.add(key);
    }

    final totalCredits =
        transcript.fold<double>(0, (sum, r) => sum + r.creditsEarned);

    final widgets = <Widget>[
      SectionLabel(
        'Transcript',
        trailing: Text(
          '${totalCredits.toStringAsFixed(1)} credits',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.textTertiary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      const SizedBox(height: 12),
    ];

    var index = 0;
    for (final term in ordered) {
      final rows = byTerm[term];
      if (rows == null || rows.isEmpty) continue;
      TermGpa? gpa;
      for (final t in terms) {
        if (t.term == term) {
          gpa = t;
          break;
        }
      }

      widgets
        ..add(Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2, right: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                term,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                gpa == null
                    ? '${rows.length} courses'
                    : 'GPA ${gpa.gpa.toStringAsFixed(2)} · '
                        '${gpa.credits.toStringAsFixed(1)} cr',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: p.textSecondary),
              ),
            ],
          ),
        ))
        ..addAll([
          for (final r in rows) ...[
            FadeSlideIn(index: index++, child: _TranscriptRow(record: r)),
            const SizedBox(height: 8),
          ],
        ])
        ..add(const SizedBox(height: 12));
    }
    return widgets;
  }
}

class _SubjectRow extends StatelessWidget {
  final SubjectScore subject;

  const _SubjectRow({required this.subject});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colour = p.forScore(subject.score);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  subject.subject,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '${subject.score.toStringAsFixed(1)}%',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colour,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ThinProgressBar(value: subject.score / 100, color: colour),
        ],
      ),
    );
  }
}

class _TranscriptRow extends StatelessWidget {
  final TranscriptRecord record;

  const _TranscriptRow({required this.record});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final colour = p.forLetter(record.letterGrade);

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.courseTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (record.courseCode.isNotEmpty) record.courseCode,
                    '${record.creditsEarned.toStringAsFixed(1)} cr',
                    if (record.finalScore > 0)
                      '${record.finalScore.toStringAsFixed(0)}%',
                  ].join('  ·  '),
                  style: tt.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: colour.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colour.withValues(alpha: 0.3)),
            ),
            child: Text(
              record.letterGrade.isEmpty ? '—' : record.letterGrade,
              textAlign: TextAlign.center,
              style: tt.labelLarge?.copyWith(
                color: colour,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
