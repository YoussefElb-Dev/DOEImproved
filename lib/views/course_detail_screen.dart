import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/grade_models.dart';
import '../storage/state_providers.dart';
import 'widgets/what_if_slider.dart';

/// Full breakdown for one course: weighted categories, a What-If projection,
/// and the graded assignment history.
class CourseDetailScreen extends ConsumerWidget {
  final Course course;

  const CourseDetailScreen({super.key, required this.course});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final calculator = ref.read(calculatorProvider);

    // Prefer the recomputed average — it reflects the same category weights
    // the What-If slider uses, so the two never disagree on screen.
    final computed = calculator.calculateCourseAverage(course);
    final score = computed > 0 ? computed : course.currentScore;
    final letter = course.letterGrade.isNotEmpty
        ? course.letterGrade
        : (score > 0 ? calculator.letterGradeFor(score) : '');
    final colour = letter.isEmpty ? p.textSecondary : p.forLetter(letter);

    return Scaffold(
      appBar: AppBar(
        title: Text(course.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 34),
          children: [
            SurfaceCard(
              child: Column(
                children: [
                  Row(
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
                                  ?.copyWith(color: p.textSecondary),
                            ),
                            if (course.code.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                course.code,
                                style: tt.bodySmall
                                    ?.copyWith(color: p.textTertiary),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (score > 0)
                        Text(
                          '${score.toStringAsFixed(1)}%',
                          style: tt.headlineSmall?.copyWith(
                            color: colour,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                          ),
                        ),
                      const SizedBox(width: 10),
                      Container(
                        width: 42,
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colour.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: colour.withValues(alpha: 0.4),
                            width: 1.4,
                          ),
                        ),
                        child: Text(
                          letter.isEmpty ? '—' : letter,
                          style: tt.titleMedium?.copyWith(
                            color: colour,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (score > 0) ...[
                    const SizedBox(height: 14),
                    ThinProgressBar(value: score / 100, color: colour),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),

            if (course.categories.isEmpty && course.assignments.isEmpty)
              const EmptyState(
                icon: Icons.hourglass_empty_rounded,
                title: 'No breakdown posted',
                message:
                    "This teacher hasn't published categories or assignments yet.",
              ),

            if (course.categories.isNotEmpty) ...[
              const SectionLabel('Category breakdown'),
              const SizedBox(height: 12),
              for (final (i, cat) in course.categories.indexed)
                FadeSlideIn(index: i, child: _CategoryTile(category: cat)),
              const SizedBox(height: 18),
              const SectionLabel('What-if'),
              const SizedBox(height: 5),
              Text(
                'Drag a score to see how one more assignment would move your '
                'average.',
                style: tt.bodySmall?.copyWith(color: p.textSecondary),
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
              const SizedBox(height: 10),
              SectionLabel(
                'Assignments',
                trailing: Text(
                  '${course.assignments.length}',
                  style: tt.labelSmall?.copyWith(
                    color: p.textTertiary,
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
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final pct = category.categoryScore;
    final colour = p.forScore(pct);
    final hasPoints = category.totalPoints > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  hasPoints ? '${pct.toStringAsFixed(1)}%' : 'No grades yet',
                  style: tt.bodyMedium?.copyWith(
                    color: hasPoints ? colour : p.textTertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            ThinProgressBar(
              value: hasPoints ? pct / 100 : 0,
              color: colour,
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
                  style: tt.labelSmall?.copyWith(color: p.textTertiary),
                ),
                Text(
                  'weight ${category.weightPercentage.toStringAsFixed(0)}%',
                  style: tt.labelSmall?.copyWith(color: p.textTertiary),
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

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    final (colour, statusLabel) = switch (assignment.status) {
      AssignmentStatus.missing => (p.danger, 'Missing'),
      AssignmentStatus.pending => (p.warning, 'Pending'),
      AssignmentStatus.upcoming => (p.gradeB, 'Upcoming'),
      AssignmentStatus.graded => (
          p.forScore(assignment.percentage),
          'Graded',
        ),
    };
    final isGraded = assignment.status == AssignmentStatus.graded;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: colour,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${assignment.category} · $statusLabel',
                    style: tt.labelSmall?.copyWith(color: p.textTertiary),
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
                      color: colour,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${assignment.percentage.toStringAsFixed(0)}%',
                    style: tt.labelSmall?.copyWith(color: p.textTertiary),
                  ),
                ],
              )
            else
              Text('—', style: tt.bodyMedium?.copyWith(color: p.textTertiary)),
          ],
        ),
      ),
    );
  }
}
