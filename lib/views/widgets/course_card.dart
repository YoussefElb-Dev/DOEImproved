import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui_kit.dart';
import '../../models/grade_models.dart';
import '../../models/schedule_models.dart';

/// Course tile for the grades feed: code, title, teacher, the letter grade and
/// percentage, what is due next, and a progress bar toward the next boundary.
class CourseCard extends StatelessWidget {
  final Course course;
  final WorkItem? next;
  final VoidCallback? onTap;

  /// Compact form drops the teacher line so two fit side by side.
  final bool compact;

  const CourseCard({
    super.key,
    required this.course,
    this.next,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final letter = course.letterGrade;
    final colour = letter.isNotEmpty
        ? p.forLetter(letter)
        : p.forScore(course.currentScore);
    final hasScore = course.currentScore > 0;

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (course.code.isNotEmpty)
                      Text(
                        course.code,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.labelSmall?.copyWith(
                          color: p.textTertiary,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    const SizedBox(height: 2),
                    Text(
                      course.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        height: 1.2,
                      ),
                    ),
                    if (!compact && course.teacherName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        course.teacherName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(color: p.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    letter.isEmpty ? '—' : letter,
                    style: tt.headlineSmall?.copyWith(
                      color: colour,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      height: 1,
                    ),
                  ),
                  if (hasScore) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${course.currentScore.toStringAsFixed(1)}%',
                      style: tt.labelMedium?.copyWith(
                        color: p.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          if (next != null) ...[
            const SizedBox(height: 12),
            Text(
              'NEXT ASSIGNMENT',
              style: tt.labelSmall?.copyWith(
                color: p.textTertiary,
                fontSize: 9,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                Expanded(
                  child: Text(
                    next!.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tt.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: p.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  shortDate(next!.dueDate),
                  style: tt.labelSmall?.copyWith(
                    color: next!.isOverdue ? p.danger : p.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          if (hasScore) ...[
            const SizedBox(height: 12),
            ThinProgressBar(value: course.currentScore / 100, color: colour),
          ],
        ],
      ),
    );
  }
}
