import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/grade_models.dart';
import '../storage/state_providers.dart';
import 'course_detail_screen.dart';
import 'widgets/course_card.dart';
import 'widgets/gpa_hero_card.dart';
import 'widgets/portal_shell.dart';

/// Grades tab: GPA hero card over the course feed, pull-to-refresh.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portal = ref.watch(portalProvider);

    // A failed first sync has nothing to render — show the error full-width.
    if (portal.hasError && !portal.hasValue) {
      return PortalScaffold(
        children: [PortalErrorState(error: portal.error!)],
      );
    }

    final snapshot = portal.valueOrNull;
    if (snapshot == null) {
      return const PortalScaffold(
        children: [
          SkeletonCard(lines: 4, height: 18),
          SizedBox(height: 24),
          SectionLabel('YOUR COURSES'),
          SizedBox(height: 12),
          SkeletonCard(),
          SizedBox(height: 14),
          SkeletonCard(),
          SizedBox(height: 14),
          SkeletonCard(),
        ],
      );
    }

    final courses = snapshot.courses;

    return PortalScaffold(
      children: [
        GpaHeroCard(snapshot: snapshot),
        const SizedBox(height: 24),
        SectionLabel(
          'YOUR COURSES',
          trailing: courses.isEmpty
              ? null
              : Text(
                  '${courses.length}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
        ),
        const SizedBox(height: 12),
        if (courses.isEmpty)
          const EmptyState(
            icon: Icons.menu_book_rounded,
            title: 'No courses yet',
            message:
                "Your school hasn't posted grades for this term. Check back later.",
          )
        else
          for (final (i, course) in courses.indexed) ...[
            FadeSlideIn(
              index: i,
              child: CourseCard(
                course: course,
                onTap: () => _openCourse(context, course),
              ),
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  void _openCourse(BuildContext context, Course course) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CourseDetailScreen(course: course)),
    );
  }
}
