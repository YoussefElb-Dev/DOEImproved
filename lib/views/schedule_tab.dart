import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/schedule_models.dart';
import '../storage/state_providers.dart';
import 'grades_tab.dart';

/// Schedule tab: today's bell schedule from the portal, or an
/// "unavailable" card when the school hasn't posted it.
class ScheduleTab extends ConsumerWidget {
  const ScheduleTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedule = ref.watch(scheduleProvider);

    return schedule.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => TabBody(
        title: 'Schedule',
        children: [_UnavailableCard(label: 'Schedule', reason: '$e')],
      ),
      data: (day) {
        if (!day.available) {
          return TabBody(
            title: 'Schedule',
            children: const [
              _UnavailableCard(label: 'Schedule'),
            ],
          );
        }
        return TabBody(
          title: day.label.isEmpty ? 'Today' : day.label,
          children: [
            for (final p in day.periods) ...[
              _PeriodTile(entry: p),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _PeriodTile extends StatelessWidget {
  final ScheduleEntry entry;
  const _PeriodTile({required this.entry});

  String _fmt(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isCurrent = entry.isCurrent;
    final isLunch = entry.courseTitle == 'Lunch';
    final color = isLunch
        ? AppColors.gradeC
        : isCurrent
            ? AppColors.gradeA
            : AppColors.textPrimary;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (isLunch ? AppColors.gradeC : AppColors.gradeB)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${entry.period}',
              style: tt.titleMedium?.copyWith(
                color: isLunch ? AppColors.gradeC : AppColors.gradeB,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.courseTitle,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (entry.teacherName.isNotEmpty) entry.teacherName,
                    if (entry.room.isNotEmpty) 'Room ${entry.room}',
                  ].join('  •  '),
                  style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${_fmt(entry.startTime)}\n${_fmt(entry.endTime)}',
            textAlign: TextAlign.right,
            style: tt.labelSmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnavailableCard extends StatelessWidget {
  final String label;
  final String? reason;
  const _UnavailableCard({required this.label, this.reason});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.event_busy_rounded,
              color: AppColors.textSecondary, size: 44),
          const SizedBox(height: 14),
          Text(
            '$label unavailable',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            reason ?? "Your school hasn't posted this yet. Check back later.",
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}