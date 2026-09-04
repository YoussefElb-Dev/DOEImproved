import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/schedule_models.dart';
import '../storage/state_providers.dart';
import 'widgets/app_shell.dart';

/// The school day in period order, with whichever class is running now
/// called out at the top.
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
    // Keeps "in class" and the period bar honest as the period runs down.
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
    final p = context.palette;
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return ScreenScaffold(
        title: 'Schedule',
        children: [PortalErrorState(error: portal.error!)],
      );
    }
    if (!portal.hasValue) {
      return const ScreenScaffold(
        title: 'Schedule',
        children: [
          SkeletonCard(lines: 3),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
        ],
      );
    }

    final day = ref.watch(scheduleProvider);
    if (day == null || !day.available || day.periods.isEmpty) {
      return const ScreenScaffold(
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

    // Period order is the order of the school day, whatever order the portal
    // happened to list them in.
    final periods = [...day.periods]
      ..sort((a, b) => a.period.compareTo(b.period));

    final now = DateTime.now();
    final currentIndex = periods.indexWhere((e) => e.isCurrent);
    final nextIndex = periods.indexWhere((e) => e.startTime.isAfter(now));

    return ScreenScaffold(
      title: day.label.isEmpty ? 'Schedule' : day.label,
      subtitle: '${periods.length} classes today',
      children: [
        _NowCard(
          current: currentIndex >= 0 ? periods[currentIndex] : null,
          next: nextIndex >= 0 ? periods[nextIndex] : null,
        ),
        const SizedBox(height: 20),
        SectionLabel(
          'Your day',
          trailing: Text(
            '${periods.first.period}–${periods.last.period}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: p.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        const SizedBox(height: 10),
        for (final (i, entry) in periods.indexed) ...[
          FadeSlideIn(
            index: i,
            child: _PeriodRow(
              entry: entry,
              isCurrent: i == currentIndex,
              isNext: currentIndex < 0 && i == nextIndex,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// What is happening right now, or what is coming next.
class _NowCard extends StatelessWidget {
  final ScheduleEntry? current;
  final ScheduleEntry? next;

  const _NowCard({this.current, this.next});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
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
    final colour = isNow ? p.accent : p.gradeB;
    final now = DateTime.now();

    final total = entry.endTime.difference(entry.startTime).inSeconds;
    final elapsed = now.difference(entry.startTime).inSeconds;
    final progress =
        total <= 0 ? 0.0 : (elapsed / total).clamp(0.0, 1.0).toDouble();
    final minutesLeft = entry.endTime.difference(now).inMinutes;
    final minutesUntil = entry.startTime.difference(now).inMinutes;

    return SurfaceCard(
      borderColor: colour.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusPill(
                label: isNow ? 'IN CLASS' : 'UP NEXT',
                color: colour,
                icon: isNow ? Icons.play_arrow_rounded : Icons.schedule_rounded,
              ),
              const Spacer(),
              Text(
                isNow
                    ? '$minutesLeft min left'
                    : minutesUntil < 60
                        ? 'in $minutesUntil min'
                        : clockTime(entry.startTime),
                style: tt.labelMedium?.copyWith(
                  color: colour,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.courseTitle.isEmpty
                ? 'Period ${entry.period}'
                : entry.courseTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            [
              'Period ${entry.period}',
              if (entry.teacherName.isNotEmpty) entry.teacherName,
              if (entry.room.isNotEmpty) 'Room ${entry.room}',
            ].join('  ·  '),
            style: tt.bodySmall?.copyWith(color: p.textSecondary),
          ),
          if (isNow && total > 0) ...[
            const SizedBox(height: 16),
            ThinProgressBar(value: progress, color: colour, animate: false),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(clockTime(entry.startTime),
                    style: tt.labelSmall?.copyWith(color: p.textTertiary)),
                Text(clockTime(entry.endTime),
                    style: tt.labelSmall?.copyWith(color: p.textTertiary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodRow extends StatelessWidget {
  final ScheduleEntry entry;
  final bool isCurrent;
  final bool isNext;

  const _PeriodRow({
    required this.entry,
    this.isCurrent = false,
    this.isNext = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final isLunch = entry.courseTitle.toLowerCase().contains('lunch');
    final accent = isLunch
        ? p.warning
        : isCurrent
            ? p.accent
            : p.gradeB;
    final isPast = DateTime.now().isAfter(entry.endTime);

    return Opacity(
      opacity: isPast && !isCurrent ? 0.55 : 1,
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        borderColor: isCurrent ? accent.withValues(alpha: 0.45) : null,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
                border: isCurrent
                    ? Border.all(color: accent.withValues(alpha: 0.5))
                    : null,
              ),
              child: Text(
                '${entry.period}',
                style: tt.titleSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.courseTitle.isEmpty
                              ? 'Period ${entry.period}'
                              : entry.courseTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: isCurrent ? accent : p.textPrimary,
                          ),
                        ),
                      ),
                      if (isNext) ...[
                        const SizedBox(width: 6),
                        StatusPill(label: 'NEXT', color: p.gradeB),
                      ],
                    ],
                  ),
                  if (entry.teacherName.isNotEmpty || entry.room.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [
                        if (entry.teacherName.isNotEmpty) entry.teacherName,
                        if (entry.room.isNotEmpty) 'Room ${entry.room}',
                      ].join('  ·  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: p.textTertiary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${clockTime(entry.startTime)}\n${clockTime(entry.endTime)}',
              textAlign: TextAlign.right,
              style: tt.labelSmall?.copyWith(
                color: p.textTertiary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
