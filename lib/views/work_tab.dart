import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/schedule_models.dart';
import '../storage/state_providers.dart';
import 'grades_tab.dart';

/// Work tab: upcoming assignments (due soon) + full transcript below.
class WorkTab extends ConsumerWidget {
  const WorkTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final work = ref.watch(workItemsProvider);
    final transcript = ref.watch(transcriptProvider);
    final tt = Theme.of(context).textTheme;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Work & Transcript',
              style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 20),
          _SectionLabel('DUE SOON'),
          const SizedBox(height: 10),
          work.when(
            loading: () => const _LoadingBlock(),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: AppColors.gradeDF)),
            data: (items) {
              if (items.isEmpty) {
                return const _EmptyNote('Nothing due soon 🎉');
              }
              return Column(children: [
                for (final w in items) ...[
                  _WorkTile(item: w),
                  const SizedBox(height: 10),
                ],
              ]);
            },
          ),
          const SizedBox(height: 26),
          _SectionLabel('TRANSCRIPT'),
          const SizedBox(height: 10),
          transcript.when(
            loading: () => const _LoadingBlock(),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: AppColors.gradeDF)),
            data: (records) {
              if (records.isEmpty) {
                return const _EmptyNote(
                    'Transcript unavailable — check back later');
              }
              return Column(children: [
                for (final r in records) ...[
                  _TranscriptTile(record: r),
                  const SizedBox(height: 8),
                ],
              ]);
            },
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
      );
}

class _WorkTile extends StatelessWidget {
  final WorkItem item;
  const _WorkTile({required this.item});

  IconData get _icon => switch (item.type) {
        'test' || 'quiz' => Icons.quiz_rounded,
        'project' => Icons.assignment_rounded,
        _ => Icons.edit_note_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final Color tagColor = item.isOverdue
        ? AppColors.gradeDF
        : item.daysUntilDue <= 1
            ? AppColors.gradeC
            : AppColors.gradeB;
    final when = item.submitted
        ? 'Submitted${item.grade != null ? ' · ${item.grade}' : ''}'
        : item.isOverdue
            ? 'Overdue'
            : item.daysUntilDue == 0
                ? 'Due today'
                : 'Due in ${item.daysUntilDue}d';

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tagColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_icon, color: tagColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title,
                    style:
                        tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(item.courseTitle,
                    style: tt.bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Text(when,
              style: tt.labelSmall?.copyWith(
                  color: tagColor, fontWeight: FontWeight.w700)),
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
                Text(record.courseTitle,
                    style:
                        tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(
                    '${record.courseCode} · ${record.term} · ${record.creditsEarned.toStringAsFixed(1)} cr',
                    style: tt.bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(record.letterGrade,
                style: tt.labelLarge
                    ?.copyWith(color: color, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: CircularProgressIndicator(),
      ));
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote(this.text);
  @override
  Widget build(BuildContext context) => GlassContainer(
        child: Center(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppColors.textSecondary)),
        ),
      );
}