import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/schedule_models.dart';
import '../models/school_calendar_event.dart';
import '../services/nyc_school_calendar.dart';
import '../storage/state_providers.dart';
import 'widgets/app_shell.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Month view of everything due, with the selected day listed below.
class CalendarTab extends ConsumerStatefulWidget {
  const CalendarTab({super.key});

  @override
  ConsumerState<CalendarTab> createState() => _CalendarTabState();
}

class _CalendarTabState extends ConsumerState<CalendarTab> {
  late DateTime _month;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selected = DateTime(now.year, now.month, now.day);
    _month = DateTime(now.year, now.month);
  }

  void _shiftMonth(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return ScreenScaffold(
        title: 'Calendar',
        children: [PortalErrorState(error: portal.error!)],
      );
    }
    if (!portal.hasValue) {
      return const ScreenScaffold(
        title: 'Calendar',
        children: [SkeletonCard(lines: 6, height: 18)],
      );
    }

    final byDay = ref.watch(workByDayProvider);
    final selectedItems = byDay[_selected] ?? const <WorkItem>[];
    final schoolEvents = NycSchoolCalendar.on(_selected);
    final isToday = _isSameDay(_selected, DateTime.now());

    return ScreenScaffold(
      title: 'Calendar',
      titleTrailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ArrowButton(
            icon: Icons.chevron_left_rounded,
            onTap: () => _shiftMonth(-1),
          ),
          SizedBox(
            width: 108,
            child: Text(
              '${_monthNames[_month.month - 1]} ${_month.year}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          _ArrowButton(
            icon: Icons.chevron_right_rounded,
            onTap: () => _shiftMonth(1),
          ),
        ],
      ),
      children: [
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
          child: _MonthGrid(
            month: _month,
            selected: _selected,
            byDay: byDay,
            schoolEvents: NycSchoolCalendar.events,
            onSelect: (d) => setState(() => _selected = d),
          ),
        ),
        const SizedBox(height: 20),
        SectionLabel(
          isToday ? 'Today' : _longDate(_selected),
          trailing: selectedItems.isEmpty && schoolEvents.isEmpty
              ? null
              : Text(
                  '${schoolEvents.length + selectedItems.length} event${schoolEvents.length + selectedItems.length == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: p.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
        ),
        const SizedBox(height: 10),
        for (final (i, event) in schoolEvents.indexed) ...[
          FadeSlideIn(index: i, child: _SchoolEventRow(event: event)),
          const SizedBox(height: 8),
        ],
        if (selectedItems.isEmpty && schoolEvents.isEmpty)
          const EmptyState(
            icon: Icons.event_available_rounded,
            title: 'Nothing due',
            message: 'No work falls on this day.',
          )
        else
          for (final (i, item) in selectedItems.indexed) ...[
            FadeSlideIn(index: i + schoolEvents.length, child: _EventRow(item: item)),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 8),
        Text(
          'School dates: official NYCPS 2026–27 school year calendar',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: p.textTertiary,
              ),
        ),
      ],
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _longDate(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.day}';
}

class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ArrowButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      color: p.textSecondary,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  final DateTime month;
  final DateTime selected;
  final Map<DateTime, List<WorkItem>> byDay;
  final List<SchoolCalendarEvent> schoolEvents;
  final ValueChanged<DateTime> onSelect;

  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.byDay,
    required this.schoolEvents,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final today = DateTime.now();

    final first = DateTime(month.year, month.month);
    // DateTime.weekday runs Mon=1..Sun=7; the grid starts on Sunday.
    final leading = first.weekday % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final cells = leading + daysInMonth;
    final rows = (cells / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (final label in const ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'])
              Expanded(
                child: Center(
                  child: Text(
                    label,
                    style: tt.labelSmall?.copyWith(
                      color: p.textTertiary,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (var row = 0; row < rows; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++)
                Expanded(
                  child: _dayCell(
                    context,
                    row * 7 + col - leading + 1,
                    daysInMonth,
                    today,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _dayCell(
    BuildContext context,
    int dayNumber,
    int daysInMonth,
    DateTime today,
  ) {
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 42);
    }

    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final date = DateTime(month.year, month.month, dayNumber);
    final items = byDay[date] ?? const <WorkItem>[];
    final official = schoolEvents.where((event) => event.includes(date)).toList();
    final isSelected = _CalendarTabState._isSameDay(date, selected);
    final isToday = _CalendarTabState._isSameDay(date, today);

    // The most urgent item on the day decides the dot colour.
    Color dotColour() {
      if (items.any((w) => !w.submitted && w.isOverdue)) return p.danger;
      if (items.any((w) => !w.submitted)) return p.warning;
      return p.gradeA;
    }

    return GestureDetector(
      onTap: () => onSelect(date),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 42,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected
                    ? p.accent
                    : isToday
                        ? p.accent.withValues(alpha: 0.16)
                        : Colors.transparent,
              ),
              child: Text(
                '$dayNumber',
                style: tt.labelMedium?.copyWith(
                  color: isSelected
                      ? p.onAccent
                      : isToday
                          ? p.accent
                          : p.textPrimary,
                  fontWeight:
                      isSelected || isToday ? FontWeight.w800 : FontWeight.w500,
                  fontSize: 12.5,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 5,
              child: items.isEmpty && official.isEmpty
                  ? null
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (official.isNotEmpty)
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: official.any((event) =>
                                      event.kind == SchoolCalendarEventKind.schoolClosed ||
                                      event.kind == SchoolCalendarEventKind.noStudentAttendance)
                                  ? p.danger
                                  : p.accent,
                            ),
                          ),
                        for (var i = 0; i < items.length.clamp(0, 2); i++)
                          Container(
                            width: 4,
                            height: 4,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dotColour(),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SchoolEventRow extends StatelessWidget {
  const _SchoolEventRow({required this.event});

  final SchoolCalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final closed = event.kind == SchoolCalendarEventKind.schoolClosed ||
        event.kind == SchoolCalendarEventKind.noStudentAttendance;
    final color = closed
        ? p.danger
        : event.kind == SchoolCalendarEventKind.earlyDismissal
            ? p.warning
            : p.accent;
    final icon = closed
        ? Icons.event_busy_rounded
        : event.kind == SchoolCalendarEventKind.remoteInstruction
            ? Icons.laptop_mac_rounded
            : event.kind == SchoolCalendarEventKind.earlyDismissal
                ? Icons.schedule_rounded
                : Icons.account_balance_rounded;
    return SurfaceCard(
      fill: color.withValues(alpha: .07),
      borderColor: color.withValues(alpha: .28),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (event.details != null) ...[
                  const SizedBox(height: 3),
                  Text(event.details!,
                      style: tt.bodySmall?.copyWith(color: p.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  final WorkItem item;

  const _EventRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final colour = item.submitted
        ? p.gradeA
        : item.isOverdue
            ? p.danger
            : p.warning;

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colour),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (item.courseTitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.courseTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(color: p.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (item.submitted)
            Icon(Icons.check_circle_rounded, size: 18, color: p.gradeA),
        ],
      ),
    );
  }
}
