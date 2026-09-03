import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/grade_models.dart';

/// Glassmorphism hero card showing the student's overall GPA, a glowing
/// term-change badge, and stats for class rank and credits.
class GpaHeroCard extends StatelessWidget {
  final StudentProfile profile;

  const GpaHeroCard({super.key, required this.profile});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isPositive = profile.gpaChange >= 0;
    final badgeColor =
        isPositive ? AppColors.gradeA : AppColors.gradeDF;

    return GlassContainer(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('OVERALL GPA',
              style: tt.labelSmall?.copyWith(
                color: AppColors.textSecondary,
                letterSpacing: 2.4,
                fontWeight: FontWeight.w600,
              )),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                profile.overallGpa.toStringAsFixed(2),
                style: tt.displayLarge?.copyWith(
                  fontSize: 72,
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 16),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: badgeColor.withValues(alpha: 0.4)),
                    boxShadow: [
                      BoxShadow(
                        color: badgeColor.withValues(alpha: 0.35),
                        blurRadius: 18,
                        spreadRadius: -2,
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPositive
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 14,
                        color: badgeColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${isPositive ? '+' : ''}'
                        '${profile.gpaChange.toStringAsFixed(2)} this term',
                        style: tt.labelMedium?.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'CLASS RANK',
                  value: '#${profile.classRank}',
                ),
              ),
              Container(
                  width: 1, height: 36, color: AppColors.surfaceBorder),
              Expanded(
                child: _Stat(
                  label: 'CREDITS EARNED',
                  value: profile.totalCredits.toStringAsFixed(1),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          value,
          style: tt.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: tt.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.6,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
