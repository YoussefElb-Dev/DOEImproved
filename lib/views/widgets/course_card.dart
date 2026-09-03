import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/grade_models.dart';

/// Course tile for the dashboard feed: title, teacher, glowing letter
/// grade badge, current percentage, and distance to the next grade.
class CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback? onTap;

  const CourseCard({super.key, required this.course, this.onTap});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final gradeColor = AppColors.forLetterGrade(course.letterGrade);
    final next = course.nextBoundary;

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      onTap: onTap,
      child: Row(
        children: [
          // Letter grade badge with semantic glow
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: gradeColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: gradeColor.withValues(alpha: 0.45), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: gradeColor.withValues(alpha: 0.35),
                  blurRadius: 20,
                  spreadRadius: -4,
                ),
              ],
            ),
            child: Text(
              course.letterGrade,
              style: tt.headlineMedium?.copyWith(
                color: gradeColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${course.teacherName} · ${course.code}',
                  style: tt.bodySmall
                      ?.copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  next == null
                      ? 'Top of the scale'
                      : '${course.distanceToNextGrade.toStringAsFixed(1)}% away from ${next.value}',
                  style: tt.labelSmall?.copyWith(
                    color: gradeColor,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Percentage score
          Text(
            '${course.currentScore.toStringAsFixed(1)}%',
            style: tt.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }
}
