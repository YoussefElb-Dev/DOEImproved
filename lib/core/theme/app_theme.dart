import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  static const Color background = Color(0xFF0D0F12);
  static const Color surface = Color(0x1AFFFFFF); // white @ 10%
  static const Color surfaceBorder = Color(0x14FFFFFF); // white @ 8%
  static const Color textPrimary = Color(0xFFF5F7FA);
  static const Color textSecondary = Color(0xFF9AA3B2);

  // Grade semantics
  static const Color gradeA = Color(0xFF00F5A0);
  static const Color gradeB = Color(0xFF00D2FF);
  static const Color gradeC = Color(0xFFFFB800);
  static const Color gradeDF = Color(0xFFFF4B4B);

  static Color forLetterGrade(String letter) {
    switch (letter.toUpperCase()) {
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
}

/// Reusable glassmorphism container: translucent white at 10% opacity,
/// 1px border at 8% opacity, backdrop blur.
class GlassContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;

  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin,
    this.borderRadius = 24,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = ClipRRect(
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
    final padded =
        margin != null ? Padding(padding: margin!, child: content) : content;
    if (onTap == null) return padded;
    return GestureDetector(onTap: onTap, child: padded);
  }
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
      ),
      textTheme: textTheme,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.surfaceBorder,
        thickness: 1,
      ),
    );
  }
}
