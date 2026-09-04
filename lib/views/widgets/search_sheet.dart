import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui_kit.dart';
import '../../models/grade_models.dart';
import '../../models/schedule_models.dart';
import '../../storage/state_providers.dart';
import '../course_detail_screen.dart';

/// Opens the search sheet over the current tab.
Future<void> showSearchSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _SearchSheet(),
  );
}

class _SearchSheet extends ConsumerStatefulWidget {
  const _SearchSheet();

  @override
  ConsumerState<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends ConsumerState<_SearchSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final q = _query.trim().toLowerCase();

    final courses = ref.watch(courseListProvider);
    final work = ref.watch(workItemsProvider);
    final schedule = ref.watch(scheduleProvider);

    final matchedCourses = q.isEmpty
        ? const <Course>[]
        : courses
            .where((c) =>
                c.title.toLowerCase().contains(q) ||
                c.code.toLowerCase().contains(q) ||
                c.teacherName.toLowerCase().contains(q))
            .toList();

    final matchedWork = q.isEmpty
        ? const <WorkItem>[]
        : work
            .where((w) =>
                w.title.toLowerCase().contains(q) ||
                w.courseTitle.toLowerCase().contains(q))
            .toList();

    final matchedPeriods = q.isEmpty
        ? const <ScheduleEntry>[]
        : (schedule?.periods ?? const <ScheduleEntry>[])
            .where((e) =>
                e.courseTitle.toLowerCase().contains(q) ||
                e.teacherName.toLowerCase().contains(q) ||
                e.room.toLowerCase().contains(q))
            .toList();

    final noResults = q.isNotEmpty &&
        matchedCourses.isEmpty &&
        matchedWork.isEmpty &&
        matchedPeriods.isEmpty;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        decoration: BoxDecoration(
          color: p.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: TextField(
                controller: _controller,
                focusNode: _focus,
                onChanged: (v) => setState(() => _query = v),
                textInputAction: TextInputAction.search,
                style: tt.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search courses, work, teachers…',
                  hintStyle: tt.bodyMedium?.copyWith(color: p.textTertiary),
                  prefixIcon: Icon(Icons.search_rounded, color: p.textTertiary),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close_rounded, color: p.textTertiary),
                          onPressed: () {
                            _controller.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: p.surface,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: p.accent),
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                children: [
                  if (q.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(
                        child: Text(
                          'Start typing to search.',
                          style: tt.bodySmall?.copyWith(color: p.textTertiary),
                        ),
                      ),
                    ),
                  if (noResults)
                    Padding(
                      padding: const EdgeInsets.only(top: 30),
                      child: Center(
                        child: Text(
                          'Nothing matches "${_query.trim()}".',
                          style: tt.bodySmall?.copyWith(color: p.textTertiary),
                        ),
                      ),
                    ),
                  if (matchedCourses.isNotEmpty) ...[
                    const SectionLabel('Courses'),
                    const SizedBox(height: 8),
                    for (final c in matchedCourses)
                      _ResultTile(
                        leading: c.letterGrade.isEmpty ? '—' : c.letterGrade,
                        leadingColor: p.forLetter(c.letterGrade),
                        title: c.title,
                        subtitle: [
                          if (c.teacherName.isNotEmpty) c.teacherName,
                          if (c.code.isNotEmpty) c.code,
                        ].join('  ·  '),
                        onTap: () {
                          Navigator.of(context).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => CourseDetailScreen(course: c),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 14),
                  ],
                  if (matchedWork.isNotEmpty) ...[
                    const SectionLabel('Assignments'),
                    const SizedBox(height: 8),
                    for (final w in matchedWork)
                      _ResultTile(
                        icon: Icons.assignment_outlined,
                        leadingColor: p.accent,
                        title: w.title,
                        subtitle: [
                          if (w.courseTitle.isNotEmpty) w.courseTitle,
                          'Due ${shortDate(w.dueDate)}',
                        ].join('  ·  '),
                      ),
                    const SizedBox(height: 14),
                  ],
                  if (matchedPeriods.isNotEmpty) ...[
                    const SectionLabel('Schedule'),
                    const SizedBox(height: 8),
                    for (final e in matchedPeriods)
                      _ResultTile(
                        leading: '${e.period}',
                        leadingColor: p.gradeB,
                        title: e.courseTitle,
                        subtitle: [
                          if (e.teacherName.isNotEmpty) e.teacherName,
                          if (e.room.isNotEmpty) 'Room ${e.room}',
                        ].join('  ·  '),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultTile extends StatelessWidget {
  final String? leading;
  final IconData? icon;
  final Color leadingColor;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _ResultTile({
    this.leading,
    this.icon,
    required this.leadingColor,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SurfaceCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: leadingColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: icon != null
                  ? Icon(icon, size: 18, color: leadingColor)
                  : Text(
                      leading ?? '',
                      style: tt.labelLarge?.copyWith(
                        color: leadingColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: p.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: p.textTertiary, size: 20),
          ],
        ),
      ),
    );
  }
}
