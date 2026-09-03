import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/schedule_models.dart';
import '../storage/state_providers.dart';
import 'widgets/portal_shell.dart';

/// Work tab: upcoming assignments bucketed by urgency, with the transcript
/// grouped by term underneath.
class WorkTab extends ConsumerWidget {
  const WorkTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return PortalScaffold(
        title: 'Work & Transcript',
        children: [PortalErrorState(error: portal.error!)],
      );
    }

    if (!portal.hasValue) {
      return const PortalScaffold(
        title: 'Work & Transcript',
        children: [
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
        ],
      );
    }

    final work = ref.watch(workItemsProvider);
    final transcript = ref.watch(transcriptProvider);

    return PortalScaffold(
      title: 'Work & Transcript',
      children: [
        ..._workSection(context, work),
        const SizedBox(height: 28),
        ..._transcriptSection(context, transcript),
      ],
    );
  }

  List<Widget> _workSection(BuildContext context, List<WorkItem> work) {
    if (work.isEmpty) {
      return const [
        SectionLabel('DUE SOON'),
        SizedBox(height: 10),
        EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'Nothing due',
          message: "You're all caught up.",
        ),
      ];
    }

    final buckets = <String, List<WorkItem>>{};
    for (final item in work) {
      buckets.putIfAbsent(_bucketFor(item), () => []).add(item);
    }

    const order = ['OVERDUE', 'DUE TODAY', 'THIS WEEK', 'LATER'];
    final widgets = <Widget>[];
    var animIndex = 0;

    for (final name in order) {
      final items = buckets[name];
      if (items == null || items.isEmpty) continue;
      widgets
        ..add(SectionLabel(
          name,
          trailing: Text(
            '${items.length}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: name == 'OVERDUE'
                      ? AppColors.gradeDF
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ))
        ..add(const SizedBox(height: 10));
      for (final item in items) {
        widgets
          ..add(FadeSlideIn(index: animIndex++, child: _WorkTile(item: item)))
          ..add(const SizedBox(height: 10));
      }
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  static String _bucketFor(WorkItem item) {
    if (item.isOverdue) return 'OVERDUE';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day);
    final days = due.difference(today).inDays;
    if (days <= 0) return 'DUE TODAY';
    if (days <= 7) return 'THIS WEEK';
    return 'LATER';
  }

  List<Widget> _transcriptSection(
    BuildContext context,
    List<TranscriptRecord> records,
  ) {
    if (records.isEmpty) {
      return const [
        SectionLabel('TRANSCRIPT'),
        SizedBox(height: 10),
        EmptyState(
          icon: Icons.history_edu_rounded,
          title: 'Transcript unavailable',
          message: "Your school hasn't posted this yet. Check back later.",
        ),
      ];
    }

    // Group by term, newest term first (the portal lists them chronologically).
    final byTerm = <String, List<TranscriptRecord>>{};
    for (final r in records) {
      byTerm.putIfAbsent(r.term.isEmpty ? 'Other' : r.term, () => []).add(r);
    }
    final terms = byTerm.keys.toList().reversed.toList();

    final totalCredits =
        records.fold<double>(0, (s, r) => s + r.creditsEarned);

    final widgets = <Widget>[
      SectionLabel(
        'TRANSCRIPT',
        trailing: Text(
          '${totalCredits.toStringAsFixed(1)} credits',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      const SizedBox(height: 12),
    ];

    var animIndex = 0;
    for (final term in terms) {
      final rows = byTerm[term]!;
      widgets
        ..add(_TermHeader(term: term, records: rows))
        ..add(const SizedBox(height: 8));
      for (final r in rows) {
        widgets
          ..add(FadeSlideIn(index: animIndex++, child: _TranscriptTile(record: r)))
          ..add(const SizedBox(height: 8));
      }
      widgets.add(const SizedBox(height: 14));
    }
    return widgets;
  }
}

/// Per-term summary line: GPA and credits for that term alone.
class _TermHeader extends StatelessWidget {
  final String term;
  final List<TranscriptRecord> records;

  const _TermHeader({required this.term, required this.records});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    var points = 0.0;
    var credits = 0.0;
    for (final r in records) {
      if (r.creditsEarned <= 0) continue;
      points += r.gpaPoints * r.creditsEarned;
      credits += r.creditsEarned;
    }
    final gpa = credits > 0 ? points / credits : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2, left: 4, right: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            term,
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            credits > 0
                ? 'GPA ${gpa.toStringAsFixed(2)} · ${credits.toStringAsFixed(1)} cr'
                : '${records.length} courses',
            style: tt.labelSmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _WorkTile extends StatelessWidget {
  final WorkItem item;

  const _WorkTile({required this.item});

  IconData get _icon => switch (item.type) {
        'test' || 'quiz' || 'exam' => Icons.quiz_rounded,
        'project' => Icons.folder_special_rounded,
        'essay' || 'paper' => Icons.article_rounded,
        _ => Icons.edit_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due =
        DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day);
    final days = due.difference(today).inDays;

    final color = item.isOverdue
        ? AppColors.gradeDF
        : days <= 1
            ? AppColors.gradeC
            : AppColors.gradeB;

    final when = item.submitted
        ? 'Submitted${item.grade != null && item.grade!.isNotEmpty ? ' · ${item.grade}' : ''}'
        : item.isOverdue
            ? 'Overdue'
            : days == 0
                ? 'Due today'
                : days == 1
                    ? 'Due tomorrow'
                    : 'Due in ${days}d';

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: color, size: 20),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  item.courseTitle,
                  style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            when,
            textAlign: TextAlign.right,
            style: tt.labelSmall?.copyWith(
              color: item.submitted ? AppColors.textSecondary : color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TranscriptTile extends StatelessWidget {
  final TranscriptRecord record;

  const _TranscriptTile({required this.record});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = AppColors.forLetterGrade(record.letterGrade);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.courseTitle,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (record.courseCode.isNotEmpty) record.courseCode,
                    '${record.creditsEarned.toStringAsFixed(1)} cr',
                    if (record.finalScore > 0)
                      '${record.finalScore.toStringAsFixed(0)}%',
                  ].join('  ·  '),
                  style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            constraints: const BoxConstraints(minWidth: 38),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Text(
              record.letterGrade.isEmpty ? '—' : record.letterGrade,
              textAlign: TextAlign.center,
              style: tt.labelLarge?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
