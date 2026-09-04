import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/schedule_models.dart';
import '../storage/state_providers.dart';
import 'widgets/app_shell.dart';
import 'widgets/charts.dart';

enum _Sort { dueDate, course, status }

extension on _Sort {
  String get label => switch (this) {
        _Sort.dueDate => 'Due date',
        _Sort.course => 'Course',
        _Sort.status => 'Status',
      };
}

/// Every piece of work the portal published, sortable and filterable.
class AssignmentsTab extends ConsumerStatefulWidget {
  const AssignmentsTab({super.key});

  @override
  ConsumerState<AssignmentsTab> createState() => _AssignmentsTabState();
}

class _AssignmentsTabState extends ConsumerState<AssignmentsTab> {
  _Sort _sort = _Sort.dueDate;

  /// null means "all courses".
  String? _courseFilter;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return ScreenScaffold(
        title: 'Assignments',
        children: [PortalErrorState(error: portal.error!)],
      );
    }
    if (!portal.hasValue) {
      return const ScreenScaffold(
        title: 'Assignments',
        children: [
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
          SizedBox(height: 10),
          SkeletonCard(lines: 2),
        ],
      );
    }

    final all = ref.watch(allWorkItemsProvider);
    final courseNames = {
      for (final w in all)
        if (w.courseTitle.trim().isNotEmpty) w.courseTitle.trim(),
    }.toList()
      ..sort();

    // A filter for a course that vanished from the portal would silently hide
    // everything, so fall back to "all" when it is no longer offered.
    final activeFilter =
        (_courseFilter != null && courseNames.contains(_courseFilter))
            ? _courseFilter
            : null;

    final items = _sorted(
      all.where((w) =>
          activeFilter == null || w.courseTitle.trim() == activeFilter),
    );

    return ScreenScaffold(
      title: 'Assignments',
      children: [
        _Controls(
          sort: _sort,
          courseFilter: activeFilter,
          courses: courseNames,
          onSort: (s) => setState(() => _sort = s),
          onFilter: (c) => setState(() => _courseFilter = c),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          EmptyState(
            icon: Icons.check_circle_outline_rounded,
            title: activeFilter == null ? 'Nothing due' : 'Nothing in $activeFilter',
            message: activeFilter == null
                ? "You're all caught up."
                : 'Try clearing the course filter.',
          )
        else
          for (final (i, item) in items.indexed) ...[
            FadeSlideIn(index: i, child: _AssignmentRow(item: item)),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionLabel('Workload, next 8 weeks'),
              const SizedBox(height: 4),
              Text(
                'Items due each week',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: 10),
              Sparkline(
                series: [_weeklyLoad(all)],
                colors: [p.accent],
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<WorkItem> _sorted(Iterable<WorkItem> input) {
    final list = input.toList();
    switch (_sort) {
      case _Sort.dueDate:
        list.sort((a, b) => a.dueDate.compareTo(b.dueDate));
      case _Sort.course:
        list.sort((a, b) {
          final byCourse = a.courseTitle.compareTo(b.courseTitle);
          return byCourse != 0 ? byCourse : a.dueDate.compareTo(b.dueDate);
        });
      case _Sort.status:
        // Overdue first, then outstanding, then anything already handed in.
        int rank(WorkItem w) =>
            w.submitted ? 2 : (w.isOverdue ? 0 : 1);
        list.sort((a, b) {
          final byRank = rank(a).compareTo(rank(b));
          return byRank != 0 ? byRank : a.dueDate.compareTo(b.dueDate);
        });
    }
    return list;
  }

  /// Count of items falling in each of the next eight weeks.
  List<double> _weeklyLoad(List<WorkItem> all) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final buckets = List<double>.filled(8, 0);
    for (final w in all) {
      final days = w.dueDate.difference(start).inDays;
      if (days < 0) continue;
      final week = days ~/ 7;
      if (week < buckets.length) buckets[week] += 1;
    }
    return buckets;
  }
}

/// Sort and course-filter controls, matching the row above the list.
class _Controls extends StatelessWidget {
  final _Sort sort;
  final String? courseFilter;
  final List<String> courses;
  final ValueChanged<_Sort> onSort;
  final ValueChanged<String?> onFilter;

  const _Controls({
    required this.sort,
    required this.courseFilter,
    required this.courses,
    required this.onSort,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            'SORT BY ${sort.label.toUpperCase()}  ·  '
            '${courseFilter == null ? 'ALL COURSES' : courseFilter!.toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.labelSmall?.copyWith(
              color: p.textTertiary,
              fontSize: 10,
              letterSpacing: 0.9,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<_Sort>(
          tooltip: 'Sort',
          color: p.surface,
          initialValue: sort,
          onSelected: onSort,
          itemBuilder: (_) => [
            for (final s in _Sort.values)
              PopupMenuItem(value: s, child: Text(s.label)),
          ],
          child: _ControlChip(icon: Icons.swap_vert_rounded, label: 'Sort'),
        ),
        const SizedBox(width: 6),
        PopupMenuButton<String?>(
          tooltip: 'Filter by course',
          color: p.surface,
          onSelected: onFilter,
          itemBuilder: (_) => [
            const PopupMenuItem<String?>(
              value: null,
              child: Text('All courses'),
            ),
            for (final c in courses)
              PopupMenuItem<String?>(value: c, child: Text(c)),
          ],
          child: _ControlChip(
            icon: Icons.filter_list_rounded,
            label: 'Filter',
            active: courseFilter != null,
          ),
        ),
      ],
    );
  }
}

class _ControlChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _ControlChip({
    required this.icon,
    required this.label,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final colour = active ? p.accent : p.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? p.accent.withValues(alpha: 0.12) : p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: active ? p.accent.withValues(alpha: 0.35) : p.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colour),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colour,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _AssignmentRow extends StatelessWidget {
  final WorkItem item;

  const _AssignmentRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(item.dueDate.year, item.dueDate.month, item.dueDate.day);
    final days = due.difference(today).inDays;

    final (statusColor, statusLabel, statusIcon) = item.submitted
        ? (p.gradeA, 'Complete', Icons.check_circle_rounded)
        : item.isOverdue
            ? (p.danger, 'Overdue', Icons.error_rounded)
            : days <= 1
                ? (p.warning, 'Due soon', Icons.schedule_rounded)
                : (p.textSecondary, 'Pending', Icons.radio_button_unchecked);

    final meta = [
      if (item.courseTitle.isNotEmpty) item.courseTitle,
      if (item.type.isNotEmpty) _titleCase(item.type),
      shortDate(item.dueDate),
    ].join('  ·  ');

    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(statusIcon, size: 20, color: statusColor),
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
                const SizedBox(height: 2),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                statusLabel,
                style: tt.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (item.grade != null && item.grade!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  item.grade!,
                  style: tt.labelSmall?.copyWith(color: p.textSecondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  static String _titleCase(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
