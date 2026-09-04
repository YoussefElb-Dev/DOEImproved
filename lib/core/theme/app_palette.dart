import 'package:flutter/material.dart';

/// The themes a student can pick from in Settings.
enum AppThemeId {
  midnight,
  graphite,
  oled,
  ocean,
  forest,
  sunset,
  violet,
  rose,
  nord,
  daylight,
}

/// Every colour the app draws with, carried on the [ThemeData] so widgets read
/// them from context rather than from global constants.
///
/// Grade colours live here too: a theme is not just a background, and a palette
/// that changed the chrome but left the grade scale untouched would look
/// half-applied.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final AppThemeId id;
  final String name;
  final String blurb;
  final Brightness brightness;

  final Color background;
  final Color surface;
  final Color surfaceAlt;
  final Color border;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  final Color accent;
  final Color onAccent;

  final Color gradeA;
  final Color gradeB;
  final Color gradeC;
  final Color gradeD;
  final Color gradeF;

  const AppPalette({
    required this.id,
    required this.name,
    required this.blurb,
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceAlt,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.onAccent,
    required this.gradeA,
    required this.gradeB,
    required this.gradeC,
    required this.gradeD,
    required this.gradeF,
  });

  Color get success => gradeA;
  Color get warning => gradeC;
  Color get danger => gradeF;

  bool get isDark => brightness == Brightness.dark;

  /// Colours for charts, ordered so adjacent series stay distinguishable.
  List<Color> get series => [gradeA, gradeC, accent, gradeF, gradeB];

  /// Colour for a letter grade, including the non-numeric marks NYC uses.
  Color forLetter(String letter) {
    final l = letter.toUpperCase().trim();
    if (l.isEmpty) return textTertiary;
    switch (l) {
      case 'P':
      case 'CR':
        return gradeB;
      case 'NS':
      case 'NC':
        return gradeF;
      case 'INC':
      case 'I':
      case 'W':
      case 'WD':
      case 'AUD':
      case 'EX':
        return textTertiary;
    }
    switch (l[0]) {
      case 'A':
        return gradeA;
      case 'B':
        return gradeB;
      case 'C':
        return gradeC;
      case 'D':
        return gradeD;
      default:
        return gradeF;
    }
  }

  /// Colour for a raw percentage, on the NYC boundaries where 65 passes.
  Color forScore(double score) {
    if (score >= 90) return gradeA;
    if (score >= 80) return gradeB;
    if (score >= 70) return gradeC;
    if (score >= 65) return gradeD;
    return gradeF;
  }

  @override
  AppPalette copyWith({
    AppThemeId? id,
    String? name,
    String? blurb,
    Brightness? brightness,
    Color? background,
    Color? surface,
    Color? surfaceAlt,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? onAccent,
    Color? gradeA,
    Color? gradeB,
    Color? gradeC,
    Color? gradeD,
    Color? gradeF,
  }) =>
      AppPalette(
        id: id ?? this.id,
        name: name ?? this.name,
        blurb: blurb ?? this.blurb,
        brightness: brightness ?? this.brightness,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceAlt: surfaceAlt ?? this.surfaceAlt,
        border: border ?? this.border,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary ?? this.textSecondary,
        textTertiary: textTertiary ?? this.textTertiary,
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        gradeA: gradeA ?? this.gradeA,
        gradeB: gradeB ?? this.gradeB,
        gradeC: gradeC ?? this.gradeC,
        gradeD: gradeD ?? this.gradeD,
        gradeF: gradeF ?? this.gradeF,
      );

  @override
  AppPalette lerp(covariant AppPalette? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      id: t < 0.5 ? id : other.id,
      name: t < 0.5 ? name : other.name,
      blurb: t < 0.5 ? blurb : other.blurb,
      brightness: t < 0.5 ? brightness : other.brightness,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceAlt: c(surfaceAlt, other.surfaceAlt),
      border: c(border, other.border),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      gradeA: c(gradeA, other.gradeA),
      gradeB: c(gradeB, other.gradeB),
      gradeC: c(gradeC, other.gradeC),
      gradeD: c(gradeD, other.gradeD),
      gradeF: c(gradeF, other.gradeF),
    );
  }

  // ── the themes ──────────────────────────────────────────────────────

  static const midnight = AppPalette(
    id: AppThemeId.midnight,
    name: 'Midnight',
    blurb: 'Near-black with a green accent',
    brightness: Brightness.dark,
    background: Color(0xFF0C0D10),
    surface: Color(0xFF17191D),
    surfaceAlt: Color(0xFF212429),
    border: Color(0xFF2A2E34),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF9AA1AC),
    textTertiary: Color(0xFF6B7280),
    accent: Color(0xFF30D158),
    onAccent: Color(0xFF04170A),
    gradeA: Color(0xFF30D158),
    gradeB: Color(0xFF6FE38B),
    gradeC: Color(0xFFFF9F0A),
    gradeD: Color(0xFFFF7A45),
    gradeF: Color(0xFFFF453A),
  );

  static const graphite = AppPalette(
    id: AppThemeId.graphite,
    name: 'Graphite',
    blurb: 'Warm grey with a blue accent',
    brightness: Brightness.dark,
    background: Color(0xFF141517),
    surface: Color(0xFF1E2023),
    surfaceAlt: Color(0xFF292C30),
    border: Color(0xFF34383D),
    textPrimary: Color(0xFFF5F5F7),
    textSecondary: Color(0xFFA1A5AC),
    textTertiary: Color(0xFF71757C),
    accent: Color(0xFF5AC8FA),
    onAccent: Color(0xFF04202B),
    gradeA: Color(0xFF32D74B),
    gradeB: Color(0xFF5AC8FA),
    gradeC: Color(0xFFFFD60A),
    gradeD: Color(0xFFFF9F0A),
    gradeF: Color(0xFFFF453A),
  );

  static const oled = AppPalette(
    id: AppThemeId.oled,
    name: 'OLED',
    blurb: 'True black, maximum contrast',
    brightness: Brightness.dark,
    background: Color(0xFF000000),
    surface: Color(0xFF0D0D0D),
    surfaceAlt: Color(0xFF171717),
    border: Color(0xFF262626),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFF9E9E9E),
    textTertiary: Color(0xFF6E6E6E),
    accent: Color(0xFF00E676),
    onAccent: Color(0xFF00160A),
    gradeA: Color(0xFF00E676),
    gradeB: Color(0xFF69F0AE),
    gradeC: Color(0xFFFFAB00),
    gradeD: Color(0xFFFF6D00),
    gradeF: Color(0xFFFF1744),
  );

  static const ocean = AppPalette(
    id: AppThemeId.ocean,
    name: 'Ocean',
    blurb: 'Deep navy with a cyan accent',
    brightness: Brightness.dark,
    background: Color(0xFF0A1119),
    surface: Color(0xFF121D28),
    surfaceAlt: Color(0xFF1B2836),
    border: Color(0xFF243545),
    textPrimary: Color(0xFFEAF2F8),
    textSecondary: Color(0xFF8FA6B8),
    textTertiary: Color(0xFF62788A),
    accent: Color(0xFF22D3EE),
    onAccent: Color(0xFF04222A),
    gradeA: Color(0xFF2DD4BF),
    gradeB: Color(0xFF38BDF8),
    gradeC: Color(0xFFFBBF24),
    gradeD: Color(0xFFFB923C),
    gradeF: Color(0xFFF43F5E),
  );

  static const forest = AppPalette(
    id: AppThemeId.forest,
    name: 'Forest',
    blurb: 'Pine dark with a lime accent',
    brightness: Brightness.dark,
    background: Color(0xFF0A1210),
    surface: Color(0xFF121D19),
    surfaceAlt: Color(0xFF1B2A24),
    border: Color(0xFF25392F),
    textPrimary: Color(0xFFEDF5F0),
    textSecondary: Color(0xFF93A89D),
    textTertiary: Color(0xFF667C70),
    accent: Color(0xFFA3E635),
    onAccent: Color(0xFF13230A),
    gradeA: Color(0xFFA3E635),
    gradeB: Color(0xFF4ADE80),
    gradeC: Color(0xFFFACC15),
    gradeD: Color(0xFFFB923C),
    gradeF: Color(0xFFEF4444),
  );

  static const sunset = AppPalette(
    id: AppThemeId.sunset,
    name: 'Sunset',
    blurb: 'Dark plum with a coral accent',
    brightness: Brightness.dark,
    background: Color(0xFF140E14),
    surface: Color(0xFF1F171F),
    surfaceAlt: Color(0xFF2C212C),
    border: Color(0xFF3A2C3A),
    textPrimary: Color(0xFFF7EFF4),
    textSecondary: Color(0xFFB09AA8),
    textTertiary: Color(0xFF836F7D),
    accent: Color(0xFFFF7A5C),
    onAccent: Color(0xFF2B0C05),
    gradeA: Color(0xFF4ADE80),
    gradeB: Color(0xFFFFB07C),
    gradeC: Color(0xFFFF9F0A),
    gradeD: Color(0xFFFF6B6B),
    gradeF: Color(0xFFE11D48),
  );

  static const violet = AppPalette(
    id: AppThemeId.violet,
    name: 'Violet',
    blurb: 'Deep purple with a lavender accent',
    brightness: Brightness.dark,
    background: Color(0xFF0F0D1A),
    surface: Color(0xFF191627),
    surfaceAlt: Color(0xFF241F36),
    border: Color(0xFF322B47),
    textPrimary: Color(0xFFF1EEFB),
    textSecondary: Color(0xFFA49CC4),
    textTertiary: Color(0xFF776F97),
    accent: Color(0xFFA78BFA),
    onAccent: Color(0xFF16092E),
    gradeA: Color(0xFF34D399),
    gradeB: Color(0xFFA78BFA),
    gradeC: Color(0xFFFBBF24),
    gradeD: Color(0xFFFB7185),
    gradeF: Color(0xFFF43F5E),
  );

  static const rose = AppPalette(
    id: AppThemeId.rose,
    name: 'Rose',
    blurb: 'Dark maroon with a pink accent',
    brightness: Brightness.dark,
    background: Color(0xFF150E11),
    surface: Color(0xFF20161A),
    surfaceAlt: Color(0xFF2D2026),
    border: Color(0xFF3C2B32),
    textPrimary: Color(0xFFFAEFF2),
    textSecondary: Color(0xFFBC9AA5),
    textTertiary: Color(0xFF8E6F79),
    accent: Color(0xFFFB7185),
    onAccent: Color(0xFF2C060F),
    gradeA: Color(0xFF34D399),
    gradeB: Color(0xFFFDA4AF),
    gradeC: Color(0xFFFBBF24),
    gradeD: Color(0xFFFB923C),
    gradeF: Color(0xFFE11D48),
  );

  static const nord = AppPalette(
    id: AppThemeId.nord,
    name: 'Nord',
    blurb: 'Arctic slate with a frost accent',
    brightness: Brightness.dark,
    background: Color(0xFF2E3440),
    surface: Color(0xFF3B4252),
    surfaceAlt: Color(0xFF434C5E),
    border: Color(0xFF4C566A),
    textPrimary: Color(0xFFECEFF4),
    textSecondary: Color(0xFFB6BFCE),
    textTertiary: Color(0xFF8C96A8),
    accent: Color(0xFF88C0D0),
    onAccent: Color(0xFF14202B),
    gradeA: Color(0xFFA3BE8C),
    gradeB: Color(0xFF88C0D0),
    gradeC: Color(0xFFEBCB8B),
    gradeD: Color(0xFFD08770),
    gradeF: Color(0xFFBF616A),
  );

  static const daylight = AppPalette(
    id: AppThemeId.daylight,
    name: 'Daylight',
    blurb: 'Light theme for bright rooms',
    brightness: Brightness.light,
    background: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFEDEFF3),
    border: Color(0xFFDDE1E7),
    textPrimary: Color(0xFF14171C),
    textSecondary: Color(0xFF5B6572),
    textTertiary: Color(0xFF8A929E),
    accent: Color(0xFF17A34A),
    onAccent: Color(0xFFFFFFFF),
    gradeA: Color(0xFF17A34A),
    gradeB: Color(0xFF0EA5E9),
    gradeC: Color(0xFFD97706),
    gradeD: Color(0xFFEA580C),
    gradeF: Color(0xFFDC2626),
  );

  /// Every theme, in the order Settings lists them.
  static const List<AppPalette> all = [
    midnight,
    graphite,
    oled,
    ocean,
    forest,
    sunset,
    violet,
    rose,
    nord,
    daylight,
  ];

  static AppPalette byId(AppThemeId id) =>
      all.firstWhere((p) => p.id == id, orElse: () => midnight);

  static AppPalette byName(String? name) => all.firstWhere(
        (p) => p.id.name == name,
        orElse: () => midnight,
      );
}

/// `context.palette` instead of `Theme.of(context).extension<AppPalette>()!`.
extension PaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.midnight;
}
