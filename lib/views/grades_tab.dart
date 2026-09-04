import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
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
          SectionLabel('All classes'),
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

    final subtitleParts = [
      if (terms.isNotEmpty) terms.last.term,
      if (snapshot.profile.name.isNotEmpty) snapshot.profile.name,
    ];

    return ScreenScaffold(
      title: 'Semester Overview',
      subtitle: subtitleParts.join(' · '),
      children: [
        _OverviewCard(
          currentGpa: snapshot.computedGpa,
          cumulativeGpa: snapshot.profile.overallGpa,
          credits: snapshot.earnedCredits,
          courseCount: courses.length,
          topPerformer: top,
          terms: terms,
        ),
        const SizedBox(height: 22),
        SectionLabel(
          'All classes',
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

/// The headline card: trend chart on the left, key figures on the right.
class _OverviewCard extends StatelessWidget {
  final double currentGpa;
  final double cumulativeGpa;
  final double credits;
  final int courseCount;
  final Course? topPerformer;
  final List<TermGpa> terms;

  const _OverviewCard({
    required this.currentGpa,
    required this.cumulativeGpa,
    required this.credits,
    required this.courseCount,
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
                _StatLine(
                  label: 'Cum. GPA',
                  value: cumulativeGpa > 0
                      ? cumulativeGpa.toStringAsFixed(2)
                      : '—',
                ),
                _StatLine(
                  label: 'Credits',
                  value: credits > 0 ? credits.toStringAsFixed(1) : '—',
                ),
                _StatLine(label: 'Courses', value: '$courseCount'),
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
