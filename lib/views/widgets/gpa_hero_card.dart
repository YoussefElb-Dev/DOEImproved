import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/portal_snapshot.dart';

/// Glassmorphism hero card: overall GPA with an animated count-up and a
/// progress ring, a glowing term-change badge, and rank/credit stats.
class GpaHeroCard extends StatelessWidget {
  final PortalSnapshot snapshot;

  const GpaHeroCard({super.key, required this.snapshot});

  static const double _gpaScale = 4.0;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final profile = snapshot.profile;
    final gpa = snapshot.computedGpa;
    final change = profile.gpaChange;
    final isPositive = change >= 0;
    final badgeColor = isPositive ? AppColors.gradeA : AppColors.gradeDF;
    final ringColor = _ringColor(gpa);

    return GlassContainer(
      padding: const EdgeInsets.all(24),
      glow: ringColor,
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
                    Text(
                      'OVERALL GPA',
                      style: tt.labelSmall?.copyWith(
                        color: AppColors.textSecondary,
                        letterSpacing: 2.4,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CountUp(
                      value: gpa,
                      builder: (v) => Text(
                        v.toStringAsFixed(2),
                        style: tt.displayLarge?.copyWith(
                          fontSize: 60,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          letterSpacing: -2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (change != 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 11,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: badgeColor.withValues(alpha: 0.4),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: badgeColor.withValues(alpha: 0.3),
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
                              '${change.toStringAsFixed(2)} this term',
                              style: tt.labelMedium?.copyWith(
                                color: badgeColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _GpaRing(
                progress: (gpa / _gpaScale).clamp(0.0, 1.0),
                color: ringColor,
                label: '${gpa.toStringAsFixed(1)}/4',
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'CLASS RANK',
                  value: profile.classRank > 0 ? '#${profile.classRank}' : '—',
                ),
              ),
              _divider,
              Expanded(
                child: _Stat(
                  label: 'CREDITS EARNED',
                  value: snapshot.earnedCredits.toStringAsFixed(1),
                ),
              ),
              _divider,
              Expanded(
                child: _Stat(
                  label: 'COURSES',
                  value: '${snapshot.courses.length}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static const Widget _divider =
      SizedBox(width: 1, height: 34, child: ColoredBox(color: AppColors.surfaceBorder));

  static Color _ringColor(double gpa) {
    if (gpa >= 3.5) return AppColors.gradeA;
    if (gpa >= 3.0) return AppColors.gradeB;
    if (gpa >= 2.0) return AppColors.gradeC;
    return AppColors.gradeDF;
  }
}

/// Animates a number up from zero when it first appears, and tweens between
/// values on refresh so a changed GPA reads as movement rather than a jump.
class _CountUp extends StatelessWidget {
  final double value;
  final Widget Function(double) builder;

  const _CountUp({required this.value, required this.builder});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => builder(v),
    );
  }
}

class _GpaRing extends StatelessWidget {
  final double progress;
  final Color color;
  final String label;

  const _GpaRing({
    required this.progress,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress),
      duration: const Duration(milliseconds: 1000),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: 86,
        height: 86,
        child: CustomPaint(
          painter: _RingPainter(progress: v, color: color),
          child: Center(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 7.0;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = AppColors.surfaceBorder;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [color.withValues(alpha: 0.35), color],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
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
          style: tt.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: tt.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            letterSpacing: 1.2,
            fontSize: 9,
          ),
        ),
      ],
    );
  }
}
