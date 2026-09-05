import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/academic_history.dart';
import '../models/grade_models.dart';
import '../models/schedule_models.dart';
import '../services/analytics_service.dart';
import '../storage/state_providers.dart';
import 'course_detail_screen.dart';
import 'widgets/app_shell.dart';
import 'widgets/charts.dart';
import 'widgets/course_card.dart';

/// Semester overview: the GPA trend, headline figures, and the course feed.
class GradesTab extends ConsumerWidget {
  const GradesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(portalProvider);

    if (portal.hasError && !portal.hasValue) {
      return ScreenScaffold(
        title: 'Semester Overview',
        children: [PortalErrorState(error: portal.error!)],
      );
    }

    final snapshot = portal.valueOrNull;
    if (snapshot == null) {
      return const ScreenScaffold(
        title: 'Semester Overview',
        children: [
          SkeletonCard(lines: 5, height: 16),
          SizedBox(height: 22),
          SectionLabel('Current classes'),
          SizedBox(height: 10),
          SkeletonCard(),
          SizedBox(height: 12),
          SkeletonCard(),
        ],
      );
    }

    final courses = snapshot.courses;
    final work = ref.watch(workItemsProvider);
    final analytics = ref.watch(analyticsProvider);
    final terms = ref.watch(termGpaSeriesProvider);
    final top = ref.watch(topPerformerProvider);
    final historyState = ref.watch(academicHistoryProvider);
    final history = historyState.valueOrNull;

    final subtitleParts = [
      if (terms.isNotEmpty) terms.last.term,
      if (snapshot.profile.name.isNotEmpty) snapshot.profile.name,
    ];

    return ScreenScaffold(
      title: 'Semester Overview',
      subtitle: subtitleParts.join(' · '),
      children: [
        _OverviewCard(
          currentGpa:
              terms.isNotEmpty ? terms.last.gpa : snapshot.computedGpa,
          cumulativeGpa:
              history?.cumulativeGpa ?? snapshot.profile.overallGpa,
          cumulativeAverage: history?.cumulativeAveragePercent,
          credits: (history?.creditsEarned ?? 0) > 0
              ? history!.creditsEarned
              : snapshot.earnedCredits,
          courseCount: courses.length,
          takenCourseCount: history?.classes.length ?? 0,
          topPerformer: top,
          terms: terms,
        ),
        const SizedBox(height: 22),
        SectionLabel(
          'Current classes',
          trailing: courses.isEmpty
              ? null
              : Text(
                  '${courses.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.palette.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
        ),
        const SizedBox(height: 10),
        if (courses.isEmpty)
          const EmptyState(
            icon: Icons.menu_book_rounded,
            title: 'No courses yet',
            message:
                "Your school hasn't posted grades for this term. Check back later.",
          )
        else
          ..._courseFeed(context, courses, work, analytics),
        const SizedBox(height: 22),
        _TakenClassesSection(state: historyState),
      ],
    );
  }

  /// The first two courses sit side by side, the rest run full width — the
  /// pair reads as a summary and keeps the fold busy without shrinking every
  /// card's type.
  List<Widget> _courseFeed(
    BuildContext context,
    List<Course> courses,
    List<WorkItem> work,
    AnalyticsService analytics,
  ) {
    final out = <Widget>[];

    if (courses.length >= 2) {
      out
        ..add(FadeSlideIn(
          index: 0,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CourseCard(
                    course: courses[0],
                    next: analytics.nextFor(courses[0], work),
                    compact: true,
                    onTap: () => _open(context, courses[0]),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CourseCard(
                    course: courses[1],
                    next: analytics.nextFor(courses[1], work),
                    compact: true,
                    onTap: () => _open(context, courses[1]),
                  ),
                ),
              ],
            ),
          ),
        ))
        ..add(const SizedBox(height: 12));
    }

    final rest = courses.length >= 2 ? courses.skip(2) : courses;
    var i = 1;
    for (final course in rest) {
      out
        ..add(FadeSlideIn(
          index: i++,
          child: CourseCard(
            course: course,
            next: analytics.nextFor(course, work),
            onTap: () => _open(context, course),
          ),
        ))
        ..add(const SizedBox(height: 12));
    }
    return out;
  }

  void _open(BuildContext context, Course course) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CourseDetailScreen(course: course),
      ),
    );
  }
}

class _TakenClassesSection extends StatelessWidget {
  const _TakenClassesSection({required this.state});

  final AsyncValue<AcademicHistory> state;

  @override
  Widget build(BuildContext context) {
    final history = state.valueOrNull;
    final count = history?.classes.length ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionLabel(
          'Taken classes',
          trailing: count == 0
              ? null
              : Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: context.palette.textTertiary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          'Completed courses saved from your transcript, newest term first.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.palette.textSecondary,
              ),
        ),
        const SizedBox(height: 10),
        if (state.isLoading && history == null)
          const SkeletonCard(lines: 4)
        else if (state.hasError && history == null)
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load taken classes',
            message: '${state.error}',
          )
        else if (history == null || history.classes.isEmpty)
          const EmptyState(
            icon: Icons.history_edu_rounded,
            title: 'No taken classes yet',
            message:
                'Import or download a transcript to add your completed courses.',
          )
        else
          ..._termCards(history),
      ],
    );
  }

  List<Widget> _termCards(AcademicHistory history) {
    final groups = <String, List<TakenClassRecord>>{};
    for (final course in history.classes) {
      final key = '${course.institution ?? ''}|${course.term}';
      groups.putIfAbsent(key, () => []).add(course);
    }

    final widgets = <Widget>[];
    for (final (index, entry) in groups.entries.indexed) {
      final courses = entry.value;
      final credits = courses.fold<double>(
        0,
        (sum, course) => sum + course.creditsEarned,
      );
      widgets
        ..add(FadeSlideIn(
          index: index,
          child: _TakenTermCard(
            term: courses.first.term,
            institution: courses.first.institution,
            courses: courses,
            credits: credits,
          ),
        ))
        ..add(const SizedBox(height: 10));
    }
    return widgets;
  }
}

class _TakenTermCard extends StatelessWidget {
  const _TakenTermCard({
    required this.term,
    required this.institution,
    required this.courses,
    required this.credits,
  });

  final String term;
  final String? institution;
  final List<TakenClassRecord> courses;
  final double credits;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: p.accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.school_rounded, size: 18, color: p.accent),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        term,
                        style: tt.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (institution != null && institution!.isNotEmpty)
                        Text(
                          institution!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: p.textTertiary,
                            fontSize: 10.5,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${courses.length} courses · ${credits.toStringAsFixed(2)} cr',
                  style: tt.labelSmall?.copyWith(
                    color: p.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: p.border),
          for (final (index, course) in courses.indexed) ...[
            _TakenCourseRow(course: course),
            if (index != courses.length - 1)
              Divider(height: 1, indent: 14, endIndent: 14, color: p.border),
          ],
        ],
      ),
    );
  }
}

class _TakenCourseRow extends StatelessWidget {
  const _TakenCourseRow({required this.course});

  final TakenClassRecord course;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final score = course.numericGrade;
    final gradeColor = score == null
        ? p.textSecondary
        : score >= 90
            ? p.gradeA
            : score >= 80
                ? p.gradeB
                : score >= 70
                    ? p.gradeC
                    : score >= 65
                        ? p.gradeD
                        : p.gradeF;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (course.courseCode.isNotEmpty) course.courseCode,
                    '${course.creditsEarned.toStringAsFixed(2)} credits',
                    if (!course.countsTowardGpa) 'not averaged',
                    if (course.weighted) 'weighted',
                  ].join(' · '),
                  style: tt.bodySmall?.copyWith(
                    color: p.textTertiary,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            constraints: const BoxConstraints(minWidth: 46),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: gradeColor.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: gradeColor.withValues(alpha: .3)),
            ),
            child: Text(
              course.displayGrade,
              textAlign: TextAlign.center,
              style: tt.labelMedium?.copyWith(
                color: gradeColor,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The headline card: trend chart on the left, key figures on the right.
class _OverviewCard extends StatelessWidget {
  final double currentGpa;
  final double cumulativeGpa;
  final double? cumulativeAverage;
  final double credits;
  final int courseCount;
  final int takenCourseCount;
  final Course? topPerformer;
  final List<TermGpa> terms;

  const _OverviewCard({
    required this.currentGpa,
    required this.cumulativeGpa,
    required this.cumulativeAverage,
    required this.credits,
    required this.courseCount,
    required this.takenCourseCount,
    required this.topPerformer,
    required this.terms,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 5, child: GpaTrendChart(series: terms)),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatLine(
                  label: 'Current GPA',
                  value: currentGpa > 0 ? currentGpa.toStringAsFixed(2) : '—',
                  valueColor: p.accent,
                ),
                if (cumulativeAverage != null)
                  _StatLine(
                    label: 'Cum. average',
                    value: '${cumulativeAverage!.toStringAsFixed(2)}%',
                  )
                else
                  _StatLine(
                    label: 'Cum. GPA',
                    value: cumulativeGpa > 0
                        ? cumulativeGpa.toStringAsFixed(2)
                        : '—',
                  ),
                _StatLine(
                  label: 'Credits',
                  value: credits > 0 ? credits.toStringAsFixed(2) : '—',
                ),
                _StatLine(label: 'Current', value: '$courseCount'),
                _StatLine(label: 'Taken', value: '$takenCourseCount'),
                if (topPerformer != null) ...[
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'TOP PERFORMER',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: p.textTertiary,
                            fontSize: 8.5,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      topPerformer!.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: p.gradeA,
                            fontWeight: FontWeight.w700,
                            height: 1.25,
                          ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _StatLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(
                color: p.textSecondary,
                fontSize: 10.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: tt.labelMedium?.copyWith(
              color: valueColor ?? p.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
