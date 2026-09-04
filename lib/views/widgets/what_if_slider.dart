import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui_kit.dart';
import '../../models/grade_models.dart';
import '../../services/calculator_service.dart';

/// Interactive "What-If" slider: simulates the score on a hypothetical
/// assignment in a chosen category and live-recalculates the class average
/// through [CalculatorService].
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
  double _hypotheticalScore = 85;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    final projected = widget.calculator.calculateWhatIf(widget.course, [
      Assignment(
        id: 'whatif',
        title: 'Hypothetical ${widget.categoryName}',
        category: widget.categoryName,
        score: _hypotheticalScore,
        maxScore: 100,
        dueDate: DateTime.now(),
        status: AssignmentStatus.upcoming,
      ),
    ]);

    // Compare against the recomputed average, not the portal's printed score,
    // so the delta always matches the number the projection derives from.
    final baseline = widget.calculator.calculateCourseAverage(widget.course);
    final delta = projected - baseline;
    final projectedLetter = widget.calculator.letterGradeFor(projected);
    final colour = p.forLetter(projectedLetter);

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.categoryName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.labelSmall?.copyWith(
                    color: p.textTertiary,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_hypotheticalScore.round()}%',
                style: tt.titleMedium?.copyWith(
                  color: colour,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: colour,
              inactiveTrackColor: p.surfaceAlt,
              thumbColor: colour,
              overlayColor: colour.withValues(alpha: 0.15),
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
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Projected average',
                style: tt.bodySmall?.copyWith(color: p.textSecondary),
              ),
              Row(
                children: [
                  Text(
                    projected.toStringAsFixed(1),
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colour,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusPill(
                    label:
                        '${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                    color: delta >= 0 ? p.gradeA : p.danger,
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
