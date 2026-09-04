import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_palette.dart';
import '../../services/analytics_service.dart';

// ── shared text helper ────────────────────────────────────────────────

void _label(
  Canvas canvas,
  String text,
  Offset at, {
  required Color color,
  double size = 9,
  FontWeight weight = FontWeight.w600,
  TextAlign align = TextAlign.center,
}) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size, fontWeight: weight),
    ),
    textAlign: align,
    textDirection: TextDirection.ltr,
  )..layout();
  final dx = switch (align) {
    TextAlign.center => at.dx - tp.width / 2,
    TextAlign.right => at.dx - tp.width,
    _ => at.dx,
  };
  tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
}

// ── GPA trend: bars with a line across their tops ─────────────────────

/// The semester-overview chart: one bar per term with a line tracking the
/// trend. Terms come from the transcript, so this is empty until a school
/// posts one.
class GpaTrendChart extends StatelessWidget {
  final List<TermGpa> series;
  final double height;

  const GpaTrendChart({super.key, required this.series, this.height = 96});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (series.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No term history yet',
            style: TextStyle(color: p.textTertiary, fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _GpaTrendPainter(series: series, palette: p, progress: t),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _GpaTrendPainter extends CustomPainter {
  final List<TermGpa> series;
  final AppPalette palette;
  final double progress;

  _GpaTrendPainter({
    required this.series,
    required this.palette,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftGutter = 26.0;
    const bottomGutter = 14.0;
    final plot = Rect.fromLTRB(
      leftGutter,
      2,
      size.width,
      size.height - bottomGutter,
    );
    if (plot.width <= 0 || plot.height <= 0) return;

    final values = series.map((e) => e.gpa).toList();
    var min = values.reduce(math.min);
    var max = values.reduce(math.max);
    // Pad the range so a flat run of terms is not drawn as a single line.
    if ((max - min).abs() < 0.2) {
      min -= 0.15;
      max += 0.15;
    }
    min = math.max(0, (min * 4).floorToDouble() / 4 - 0.05);
    max = math.min(5, (max * 4).ceilToDouble() / 4 + 0.05);
    final span = (max - min).abs() < 0.01 ? 1.0 : max - min;

    double yFor(double v) => plot.bottom - ((v - min) / span) * plot.height;

    // Gridlines and axis labels.
    final grid = Paint()
      ..color = palette.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final value = min + span * (i / 3);
      final y = yFor(value);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(
        canvas,
        value.toStringAsFixed(2),
        Offset(leftGutter - 5, y),
        color: palette.textTertiary,
        size: 8,
        align: TextAlign.right,
      );
    }

    // Bars.
    final slot = plot.width / series.length;
    final barWidth = math.min(18.0, slot * 0.44);
    final points = <Offset>[];

    for (var i = 0; i < series.length; i++) {
      final centre = plot.left + slot * (i + 0.5);
      final full = yFor(series[i].gpa);
      final y = plot.bottom - (plot.bottom - full) * progress;

      final colour = palette.series[i % palette.series.length];
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(centre - barWidth / 2, y, centre + barWidth / 2,
            plot.bottom),
        topLeft: const Radius.circular(3),
        topRight: const Radius.circular(3),
      );
      canvas.drawRRect(rect, Paint()..color = colour.withValues(alpha: 0.85));

      points.add(Offset(centre, y));
      _label(
        canvas,
        series[i].term.length > 8
            ? series[i].term.substring(0, 8)
            : series[i].term,
        Offset(centre, size.height - bottomGutter / 2),
        color: palette.textTertiary,
        size: 8,
      );
    }

    // Trend line across the bar tops.
    if (points.length > 1) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final pt in points.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..color = palette.textPrimary.withValues(alpha: 0.85),
      );
      for (final pt in points) {
        canvas.drawCircle(pt, 2.6, Paint()..color = palette.textPrimary);
      }
    }
  }

  @override
  bool shouldRepaint(_GpaTrendPainter old) =>
      old.progress != progress ||
      old.series != series ||
      old.palette != palette;
}

// ── grade distribution bars ───────────────────────────────────────────

/// One bar per letter band, tallest first — how the marks are spread.
class GradeDistributionChart extends StatelessWidget {
  final Map<String, int> counts;
  final double height;

  const GradeDistributionChart({
    super.key,
    required this.counts,
    this.height = 130,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (counts.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No grades to chart yet',
            style: TextStyle(color: p.textTertiary, fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _BarsPainter(counts: counts, palette: p, progress: t),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  final Map<String, int> counts;
  final AppPalette palette;
  final double progress;

  _BarsPainter({
    required this.counts,
    required this.palette,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bottomGutter = 16.0;
    const topGutter = 14.0;
    final entries = counts.entries.toList();
    final maxCount =
        entries.map((e) => e.value).reduce(math.max).clamp(1, 1 << 30);

    final plotHeight = size.height - bottomGutter - topGutter;
    final slot = size.width / entries.length;
    final barWidth = math.min(26.0, slot * 0.5);

    for (var i = 0; i < entries.length; i++) {
      final centre = slot * (i + 0.5);
      final ratio = entries[i].value / maxCount;
      final h = plotHeight * ratio * progress;
      final top = topGutter + plotHeight - h;

      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTRB(centre - barWidth / 2, top, centre + barWidth / 2,
              topGutter + plotHeight),
          topLeft: const Radius.circular(4),
          topRight: const Radius.circular(4),
        ),
        Paint()..color = palette.forLetter(entries[i].key),
      );

      if (progress > 0.7) {
        _label(
          canvas,
          '${entries[i].value}',
          Offset(centre, top - 7),
          color: palette.textSecondary,
          size: 9,
        );
      }
      _label(
        canvas,
        entries[i].key,
        Offset(centre, size.height - bottomGutter / 2),
        color: palette.textSecondary,
        size: 10,
        weight: FontWeight.w700,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.progress != progress || old.counts != counts;
}

// ── subject radar ─────────────────────────────────────────────────────

/// Average score per subject, drawn as a polygon. Needs three subjects to be
/// a shape at all; below that the caller shows a list instead.
class SubjectRadarChart extends StatelessWidget {
  final List<SubjectScore> subjects;
  final double size;

  const SubjectRadarChart({
    super.key,
    required this.subjects,
    this.size = 190,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _RadarPainter(
            subjects: subjects,
            palette: p,
            progress: t,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  final List<SubjectScore> subjects;
  final AppPalette palette;
  final double progress;

  _RadarPainter({
    required this.subjects,
    required this.palette,
    required this.progress,
  });

  /// Scores below this are off the bottom of the chart — a 0–100 axis wastes
  /// most of its area on a range no course actually occupies.
  static const double floorScore = 50;

  @override
  void paint(Canvas canvas, Size size) {
    final n = subjects.length;
    if (n < 3) return;

    final centre = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 26;
    if (radius <= 0) return;

    Offset pointAt(int i, double ratio) {
      final angle = -math.pi / 2 + (2 * math.pi * i / n);
      return centre +
          Offset(math.cos(angle), math.sin(angle)) * (radius * ratio);
    }

    // Grid rings.
    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.border;
    for (final ring in [0.34, 0.67, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final pt = pointAt(i, ring);
        i == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path..close(), gridPaint);
    }
    for (var i = 0; i < n; i++) {
      canvas.drawLine(centre, pointAt(i, 1), gridPaint);
    }

    // Data polygon.
    final dataPath = Path();
    for (var i = 0; i < n; i++) {
      final normalised =
          ((subjects[i].score - floorScore) / (100 - floorScore)).clamp(0.08, 1.0);
      final pt = pointAt(i, normalised * progress);
      i == 0 ? dataPath.moveTo(pt.dx, pt.dy) : dataPath.lineTo(pt.dx, pt.dy);
    }
    dataPath.close();

    canvas.drawPath(
      dataPath,
      Paint()..color = palette.accent.withValues(alpha: 0.22),
    );
    canvas.drawPath(
      dataPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = palette.accent,
    );

    // Axis labels, nudged outward.
    for (var i = 0; i < n; i++) {
      final anchor = pointAt(i, 1.0);
      final direction = (anchor - centre);
      final distance = direction.distance;
      final out = distance == 0
          ? anchor
          : anchor + direction / distance * 14;
      _label(
        canvas,
        subjects[i].subject,
        out,
        color: palette.textSecondary,
        size: 9,
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress || old.subjects != subjects;
}

// ── ring gauge ────────────────────────────────────────────────────────

/// Circular progress with a value in the middle — the GPA dial.
class RingGauge extends StatelessWidget {
  final double progress;
  final Color color;
  final String value;
  final String? caption;
  final double diameter;
  final double stroke;

  const RingGauge({
    super.key,
    required this.progress,
    required this.color,
    required this.value,
    this.caption,
    this.diameter = 92,
    this.stroke = 8,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: diameter,
        height: diameter,
        child: CustomPaint(
          painter: _RingPainter(
            progress: v,
            color: color,
            track: p.surfaceAlt,
            stroke: stroke,
          ),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontSize: diameter * 0.24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                if (caption != null)
                  Text(
                    caption!,
                    style: TextStyle(
                      color: p.textTertiary,
                      fontSize: diameter * 0.11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
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
  final Color track;
  final double stroke;

  const _RingPainter({
    required this.progress,
    required this.color,
    required this.track,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - stroke) / 2;

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    if (progress <= 0) return;

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

// ── sparkline ─────────────────────────────────────────────────────────

/// Small multi-series line chart, used under the assignments list.
class Sparkline extends StatelessWidget {
  final List<List<double>> series;
  final List<Color> colors;
  final double height;

  const Sparkline({
    super.key,
    required this.series,
    required this.colors,
    this.height = 84,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final usable = series.where((s) => s.length > 1).toList();
    if (usable.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history to chart',
            style: TextStyle(color: p.textTertiary, fontSize: 11),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (_, t, __) => CustomPaint(
          painter: _SparkPainter(
            series: usable,
            colors: colors,
            palette: p,
            progress: t,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  final List<List<double>> series;
  final List<Color> colors;
  final AppPalette palette;
  final double progress;

  _SparkPainter({
    required this.series,
    required this.colors,
    required this.palette,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final all = series.expand((s) => s).toList();
    if (all.isEmpty) return;
    var min = all.reduce(math.min);
    var max = all.reduce(math.max);
    if ((max - min).abs() < 1) {
      min -= 1;
      max += 1;
    }
    final span = max - min;
    const pad = 8.0;
    final plot = Rect.fromLTRB(pad, pad, size.width - pad, size.height - pad);

    final grid = Paint()
      ..color = palette.border
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = plot.top + plot.height * (i / 2);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    for (var s = 0; s < series.length; s++) {
      final data = series[s];
      final step = plot.width / (data.length - 1);
      final path = Path();
      final shown = (data.length * progress).ceil().clamp(2, data.length);
      for (var i = 0; i < shown; i++) {
        final x = plot.left + step * i;
        final y = plot.bottom - ((data[i] - min) / span) * plot.height;
        i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = colors[s % colors.length],
      );
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || old.series != series;
}
