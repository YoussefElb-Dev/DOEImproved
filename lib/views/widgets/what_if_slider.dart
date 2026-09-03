import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/grade_models.dart';
import '../../services/calculator_service.dart';

/// Interactive "What-If" slider: simulates the score on a hypothetical
/// assignment in a chosen category and live-recalculates the class
/// average via [CalculatorService].
class WhatIfSlider extends StatefulWidget {
  final Course course;
  final String categoryName;
  final CalculatorService calculator;

  const WhatIfSlider({
    super.key,
    required this.course,
    required this.categoryName,
    this.calculator = const CalculatorService(),
  });

  @override
  State<WhatIfSlider> createState() => _WhatIfSliderState();
}

class _WhatIfSliderState extends State<WhatIfSlider> {
  double _hypotheticalScore = 85.0; // percentage

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final projected = widget.calculator.calculateWhatIf(
      widget.course,
      [
        Assignment(
          id: 'whatif',
          title: 'Hypothetical ${widget.categoryName}',
          category: widget.categoryName,
          score: _hypotheticalScore,
          maxScore: 100,
          dueDate: DateTime.now(),
          status: AssignmentStatus.upcoming,
        ),
      ],
    );
    final delta = projected - widget.course.currentScore;
    final projectedLetter =
        widget.calculator.letterGradeFor(projected);
    final color = AppColors.forLetterGrade(projectedLetter);

    return GlassContainer(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'WHAT-IF: ${widget.categoryName.toUpperCase()}',
                style: tt.labelSmall?.copyWith(
                  color: AppColors.textSecondary,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${_hypotheticalScore.round()}%',
                style: tt.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: AppColors.surfaceBorder,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: _hypotheticalScore,
              min: 0,
              max: 100,
              divisions: 100,
              onChanged: (v) => setState(() => _hypotheticalScore = v),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Projected average',
                style: tt.bodySmall
                    ?.copyWith(color: AppColors.textSecondary),
              ),
              Row(
                children: [
                  Text(
                    projected.toStringAsFixed(1),
                    style: tt.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: color,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                      style: tt.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
