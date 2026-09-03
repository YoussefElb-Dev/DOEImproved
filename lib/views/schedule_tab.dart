import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/schedule_models.dart';
import '../storage/state_providers.dart';
import 'widgets/portal_shell.dart';

/// Schedule tab: today's bell schedule with the current period highlighted,
/// or an empty state when the school hasn't posted one.
class ScheduleTab extends ConsumerStatefulWidget {
  const ScheduleTab({super.key});

  @override
  ConsumerState<ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleTabState extends ConsumerState<ScheduleTab> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Keep "in progress" and the period bar honest as the class period runs.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return PortalScaffold(
        title: 'Schedule',
        children: [PortalErrorState(error: portal.error!)],
      );
    }

    final day = ref.watch(scheduleProvider);
    if (day == null) {
      return const PortalScaffold(
        title: 'Schedule',
        children: [
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
        ],
      );
    }

    if (!day.available || day.periods.isEmpty) {
      return const PortalScaffold(
        title: 'Schedule',
        children: [
          EmptyState(
            icon: Icons.event_busy_rounded,
            title: 'Schedule unavailable',
            message: "Your school hasn't posted this yet. Check back later.",
          ),
        ],
      );
    }

    final now = DateTime.now();
    final currentIndex = day.periods.indexWhere((p) => p.isCurrent);
    final nextIndex = day.periods.indexWhere((p) => p.startTime.isAfter(now));

    return PortalScaffold(
      title: day.label.isEmpty ? 'Today' : day.label,
      children: [
        _NowCard(
          current: currentIndex >= 0 ? day.periods[currentIndex] : null,
          next: nextIndex >= 0 ? day.periods[nextIndex] : null,
        ),
        const SizedBox(height: 20),
        SectionLabel(
          'PERIODS',
          trailing: Text(
            '${day.periods.length}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 12),
        for (final (i, p) in day.periods.indexed) ...[
          FadeSlideIn(
            index: i,
            child: _PeriodTile(entry: p, isCurrent: i == currentIndex),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// The "right now" card: what class you're in and how much of it is left,
/// or what's coming up next.
class _NowCard extends StatelessWidget {
  final ScheduleEntry? current;
  final ScheduleEntry? next;

  const _NowCard({this.current, this.next});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final entry = current ?? next;

    if (entry == null) {
      return const EmptyState(
        icon: Icons.nightlight_round,
        title: 'No more classes today',
        message: 'Enjoy the rest of your day.',
      );
    }

    final isNow = current != null;
    final color = isNow ? AppColors.gradeA : AppColors.gradeB;
    final now = DateTime.now();

    final total = entry.endTime.difference(entry.startTime).inSeconds;
    final elapsed = now.difference(entry.startTime).inSeconds;
    final progress =
        total <= 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0).toDouble();
    final minutesLeft = entry.endTime.difference(now).inMinutes;
    final minutesUntil = entry.startTime.difference(now).inMinutes;

    return GlassContainer(
      glow: color,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(
                label: isNow ? 'IN CLASS' : 'UP NEXT',
                color: color,
                icon: isNow
                    ? Icons.play_arrow_rounded
                    : Icons.schedule_rounded,
              ),
              const Spacer(),
              Text(
                isNow
                    ? '$minutesLeft min left'
                    : minutesUntil < 60
                        ? 'in $minutesUntil min'
                        : _clock(entry.startTime),
                style: tt.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.courseTitle.isEmpty ? 'Period ${entry.period}' : entry.courseTitle,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 5),
          Text(
            [
              'Period ${entry.period}',
              if (entry.teacherName.isNotEmpty) entry.teacherName,
              if (entry.room.isNotEmpty) 'Room ${entry.room}',
            ].join('  ·  '),
            style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          if (isNow && total > 0) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: AppColors.surfaceBorder,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_clock(entry.startTime),
                    style: tt.labelSmall
                        ?.copyWith(color: AppColors.textSecondary)),
                Text(_clock(entry.endTime),
                    style: tt.labelSmall
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodTile extends StatelessWidget {
  final ScheduleEntry entry;
  final bool isCurrent;

  const _PeriodTile({required this.entry, this.isCurrent = false});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isLunch = entry.courseTitle.toLowerCase().contains('lunch');
    final accent = isLunch
        ? AppColors.gradeC
        : isCurrent
            ? AppColors.gradeA
            : AppColors.gradeB;
    final isPast = DateTime.now().isAfter(entry.endTime);

    return Opacity(
      opacity: isPast && !isCurrent ? 0.5 : 1,
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        glow: isCurrent ? accent : null,
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: isCurrent
                    ? Border.all(
                        color: accent.withValues(alpha: 0.5), width: 1.5)
                    : null,
              ),
              child: Text(
                '${entry.period}',
                style: tt.titleMedium?.copyWith(
                  color: accent,
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
                    entry.courseTitle.isEmpty
                        ? 'Period ${entry.period}'
                        : entry.courseTitle,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCurrent ? accent : AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (entry.teacherName.isNotEmpty) entry.teacherName,
                      if (entry.room.isNotEmpty) 'Room ${entry.room}',
                    ].join('  ·  '),
                    style:
                        tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${_clock(entry.startTime)}\n${_clock(entry.endTime)}',
              textAlign: TextAlign.right,
              style: tt.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour >= 12 ? 'PM' : 'AM'}';
}
