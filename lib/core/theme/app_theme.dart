import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_palette.dart';

export 'app_palette.dart';

/// Builds a [ThemeData] from an [AppPalette].
///
/// The palette rides along as a [ThemeExtension] so every widget reads its
/// colours from context — that is what lets the whole app restyle the moment a
/// different theme is picked, with no rebuild of the widget tree by hand.
class AppTheme {
  AppTheme._();

  static ThemeData from(AppPalette p) {
    final base = p.isDark ? ThemeData.dark() : ThemeData.light();
    final text = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: p.textPrimary,
      displayColor: p.textPrimary,
    );

    return base.copyWith(
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.background,
      colorScheme: ColorScheme(
        brightness: p.brightness,
        primary: p.accent,
        onPrimary: p.onAccent,
        secondary: p.gradeB,
        onSecondary: p.onAccent,
        error: p.danger,
        onError: Colors.white,
        surface: p.surface,
        onSurface: p.textPrimary,
      ),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
      iconTheme: IconThemeData(color: p.textSecondary),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceAlt,
        circularTrackColor: p.surfaceAlt,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: p.accent,
        inactiveTrackColor: p.surfaceAlt,
        thumbColor: p.accent,
        overlayColor: p.accent.withValues(alpha: 0.16),
        trackHeight: 3,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.accent,
          foregroundColor: p.onAccent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.accent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surfaceAlt,
        contentTextStyle: text.bodyMedium,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      splashColor: p.accent.withValues(alpha: 0.08),
      highlightColor: p.accent.withValues(alpha: 0.05),
    );
  }
}
