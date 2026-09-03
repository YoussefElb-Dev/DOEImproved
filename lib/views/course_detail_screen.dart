import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/grade_models.dart';
import '../storage/state_providers.dart';
import 'widgets/portal_shell.dart';
import 'widgets/what_if_slider.dart';

/// Full breakdown for one course: weighted categories, What-If projection,
/// and the graded assignment history.
class CourseDetailScreen extends ConsumerWidget {
  final Course course;

  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final calculator = ref.read(calculatorProvider);
    final gradeColor = AppColors.forLetterGrade(course.letterGrade);

    // Prefer the recomputed average — it reflects the same category weights
    // the What-If slider uses, so the two never disagree on screen.
    final computed = calculator.calculateCourseAverage(course);
    final score = computed > 0 ? computed : course.currentScore;
    final letter = course.letterGrade.isNotEmpty
        ? course.letterGrade
        : calculator.letterGradeFor(score);

    return Scaffold(
      appBar: AppBar(
        title: Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 36),
          children: [
            GlassContainer(
              glow: gradeColor,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          course.teacherName.isEmpty
                              ? 'Teacher not listed'
                              : course.teacherName,
                          style: tt.bodyMedium
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                        if (course.code.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            course.code,
                            style: tt.bodySmall
                                ?.copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    '${score.toStringAsFixed(1)}%',
                    style: tt.headlineSmall?.copyWith(
                      color: gradeColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: gradeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(
                        color: gradeColor.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      letter,
                      style: tt.titleLarge?.copyWith(
                        color: gradeColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            if (course.categories.isEmpty && course.assignments.isEmpty)
              const EmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: 'No breakdown posted',
                message:
                    "This teacher hasn't published categories or assignments yet.",
              ),

            if (course.categories.isNotEmpty) ...[
              const SectionLabel('CATEGORY BREAKDOWN'),
              const SizedBox(height: 12),
              for (final (i, cat) in course.categories.indexed)
                FadeSlideIn(
                  index: i,
                  child: _CategoryTile(category: cat),
                ),
              const SizedBox(height: 20),
              const SectionLabel('WHAT-IF'),
              const SizedBox(height: 6),
              Text(
                'Drag a score to see how one more assignment would move your average.',
                style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              for (final cat in course.categories) ...[
                WhatIfSlider(
                  course: course,
                  categoryName: cat.name,
                  calculator: calculator,
                ),
                const SizedBox(height: 12),
              ],
            ],

            if (course.assignments.isNotEmpty) ...[
              const SizedBox(height: 12),
              SectionLabel(
                'ASSIGNMENTS',
                trailing: Text(
                  '${course.assignments.length}',
                  style: tt.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              for (final (i, a) in course.assignments.indexed)
                FadeSlideIn(index: i, child: _AssignmentTile(assignment: a)),
            ],
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final GradeCategory category;

  const _CategoryTile({required this.category});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final pct = category.categoryScore;
    final color = AppColors.forScore(pct);
    final hasPoints = category.totalPoints > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  hasPoints ? '${pct.toStringAsFixed(1)}%' : 'No grades yet',
                  style: tt.bodyMedium?.copyWith(
                    color: hasPoints ? color : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: hasPoints ? pct / 100 : 0),
                duration: const Duration(milliseconds: 700),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => LinearProgressIndicator(
                  value: v,
                  minHeight: 6,
                  backgroundColor: AppColors.surfaceBorder,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  hasPoints
                      ? '${category.earnedPoints.toStringAsFixed(0)} / '
                          '${category.totalPoints.toStringAsFixed(0)} pts'
                      : '',
                  style:
                      tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                ),
                Text(
                  'weight ${category.weightPercentage.toStringAsFixed(0)}%',
                  style:
                      tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AssignmentTile extends StatelessWidget {
  final Assignment assignment;

  const _AssignmentTile({required this.assignment});

  (Color, String) get _status => switch (assignment.status) {
        AssignmentStatus.missing => (AppColors.gradeDF, 'Missing'),
        AssignmentStatus.pending => (AppColors.gradeC, 'Pending'),
        AssignmentStatus.upcoming => (AppColors.gradeB, 'Upcoming'),
        AssignmentStatus.graded => (
            AppColors.forScore(assignment.percentage),
            'Graded',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final (color, statusLabel) = _status;
    final isGraded = assignment.status == AssignmentStatus.graded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    assignment.title,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${assignment.category} · $statusLabel',
                    style:
                        tt.labelSmall?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (isGraded)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${assignment.score.toStringAsFixed(0)}/'
                    '${assignment.maxScore.toStringAsFixed(0)}',
                    style: tt.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${assignment.percentage.toStringAsFixed(0)}%',
                    style: tt.labelSmall
                        ?.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              )
            else
              Text(
                '—',
                style: tt.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}
