import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0D0F12);
  static const Color backgroundLift = Color(0xFF14181D);
  static const Color surface = Color(0x1AFFFFFF); // white @ 10%
  static const Color surfaceBorder = Color(0x14FFFFFF); // white @ 8%
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF9AA3B2);

  // Grade semantics
  static const Color gradeA = Color(0xFF00F5A0);
  static const Color gradeB = Color(0xFF00D2FF);
  static const Color gradeC = Color(0xFFFFB800);
  static const Color gradeDF = Color(0xFFFF4B4B);

  static const LinearGradient brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradeB, gradeA],
  );

  static Color forLetterGrade(String letter) {
    switch (letter.toUpperCase().trim()) {
      case 'A':
      case 'A+':
      case 'A-':
        return gradeA;
      case 'B':
      case 'B+':
      case 'B-':
        return gradeB;
      case 'C':
      case 'C+':
      case 'C-':
        return gradeC;
      default:
        return gradeDF;
    }
  }

  /// Colour for a raw percentage, matching [forLetterGrade]'s boundaries.
  static Color forScore(double score) {
    if (score >= 90) return gradeA;
    if (score >= 80) return gradeB;
    if (score >= 70) return gradeC;
    return gradeDF;
  }
}

/// Reusable glassmorphism container: translucent white at 10% opacity,
/// 1px border at 8% opacity, backdrop blur.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  final Color? glow;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 24,
    this.onTap,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: AppColors.surfaceBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );

    if (glow != null) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          boxShadow: [
            BoxShadow(
              color: glow!.withValues(alpha: 0.18),
              blurRadius: 26,
              spreadRadius: -4,
            ),
          ],
        ),
        child: content,
      );
    }

    final padded =
        margin != null ? Padding(padding: margin!, child: content) : content;
    if (onTap == null) return padded;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: padded,
    );
  }
}

/// Small uppercase heading used above each list section.
class SectionLabel extends StatelessWidget {
  final String text;
  final Widget? trailing;

  const SectionLabel(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: AppColors.textSecondary,
          letterSpacing: 2.2,
          fontWeight: FontWeight.w600,
        );
    if (trailing == null) return Text(text, style: style);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [Text(text, style: style), trailing!],
    );
  }
}

/// LIVE / DEMO badge so sample data is never mistaken for a real record.
class StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
          ),
        ],
      ),
    );
  }
}

/// Shimmering placeholder block used while the first sync is in flight.
/// Far calmer than a spinner, and it previews the shape of what's coming.
class Skeleton extends StatefulWidget {
  final double height;
  final double? width;
  final double radius;

  const Skeleton({
    super.key,
    this.height = 16,
    this.width,
    this.radius = 8,
  });

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Sweep a highlight from left to right across the block.
        final t = _c.value * 2 - 1;
        return Container(
          height: widget.height,
          width: widget.width,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.6, 0),
              end: Alignment(t + 0.6, 0),
              colors: const [
                Color(0x0DFFFFFF),
                Color(0x1FFFFFFF),
                Color(0x0DFFFFFF),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A glass card of shimmering lines, matching the silhouette of a real tile.
class SkeletonCard extends StatelessWidget {
  final int lines;
  final double height;

  const SkeletonCard({super.key, this.lines = 3, this.height = 14});

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < lines; i++) ...[
            Skeleton(
              height: height,
              width: i == lines - 1 ? 120 : null,
            ),
            if (i != lines - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

/// Staggered fade + rise, used to bring lists in without a hard pop.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int index;

  const FadeSlideIn({super.key, required this.child, this.index = 0});

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    // Cap the stagger so a long list doesn't take seconds to finish.
    final delay = Duration(milliseconds: 45 * widget.index.clamp(0, 8));
    Future<void>.delayed(delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

/// "just now" / "4m ago" / "2h ago" — used for the last-sync stamp.
String relativeTime(DateTime? then) {
  if (then == null) return '';
  final d = DateTime.now().difference(then);
  if (d.inSeconds < 45) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);
    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        surface: AppColors.background,
        primary: AppColors.gradeB,
        secondary: AppColors.gradeA,
        onSurface: AppColors.textPrimary,
        error: AppColors.gradeDF,
      ),
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceBorder,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.gradeB,
        linearTrackColor: Colors.transparent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.gradeB,
        inactiveTrackColor: AppColors.surfaceBorder,
        thumbColor: AppColors.gradeB,
        overlayColor: AppColors.gradeB.withValues(alpha: 0.16),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.backgroundLift,
        contentTextStyle: textTheme.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}
