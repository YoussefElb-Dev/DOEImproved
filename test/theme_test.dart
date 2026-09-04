import 'package:doe_improved/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('theme catalogue', () {
    test('every AppThemeId has exactly one palette', () {
      expect(AppPalette.all, hasLength(AppThemeId.values.length));
      final ids = AppPalette.all.map((p) => p.id).toSet();
      expect(ids, hasLength(AppPalette.all.length), reason: 'ids are unique');
      for (final id in AppThemeId.values) {
        expect(ids, contains(id), reason: '$id has no palette');
      }
    });

    test('every palette is named and described', () {
      for (final p in AppPalette.all) {
        expect(p.name.trim(), isNotEmpty, reason: '${p.id} has no name');
        expect(p.blurb.trim(), isNotEmpty, reason: '${p.id} has no blurb');
      }
    });

    test('byId and byName round-trip, and fall back rather than throw', () {
      for (final p in AppPalette.all) {
        expect(AppPalette.byId(p.id).id, p.id);
        expect(AppPalette.byName(p.id.name).id, p.id);
      }
      expect(AppPalette.byName('not-a-theme').id, AppThemeId.midnight);
      expect(AppPalette.byName(null).id, AppThemeId.midnight);
    });

    test('exactly one light theme is offered', () {
      final light =
          AppPalette.all.where((p) => p.brightness == Brightness.light);
      expect(light, hasLength(1));
      expect(light.single.id, AppThemeId.daylight);
      expect(light.single.isDark, isFalse);
    });
  });

  group('grade colours', () {
    const p = AppPalette.midnight;

    test('letters map to their band', () {
      expect(p.forLetter('A'), p.gradeA);
      expect(p.forLetter('A-'), p.gradeA);
      expect(p.forLetter('b+'), p.gradeB);
      expect(p.forLetter('C'), p.gradeC);
      expect(p.forLetter('D'), p.gradeD);
      expect(p.forLetter('F'), p.gradeF);
    });

    test('non-numeric marks are not shown as failures by accident', () {
      // A pass is a pass; a never-showed is not.
      expect(p.forLetter('P'), p.gradeB);
      expect(p.forLetter('CR'), p.gradeB);
      expect(p.forLetter('NS'), p.gradeF);
      expect(p.forLetter('NC'), p.gradeF);
      // Withdrawn and incomplete carry no judgement at all.
      expect(p.forLetter('W'), p.textTertiary);
      expect(p.forLetter('INC'), p.textTertiary);
      expect(p.forLetter(''), p.textTertiary);
    });

    test('scores use the NYC boundaries where 65 passes', () {
      expect(p.forScore(95), p.gradeA);
      expect(p.forScore(90), p.gradeA);
      expect(p.forScore(89.9), p.gradeB);
      expect(p.forScore(80), p.gradeB);
      expect(p.forScore(70), p.gradeC);
      expect(p.forScore(65), p.gradeD);
      expect(p.forScore(64.9), p.gradeF);
    });
  });

  group('lerp', () {
    test('holds each end of the transition', () {
      const a = AppPalette.midnight;
      const b = AppPalette.ocean;
      expect(a.lerp(b, 0).background, a.background);
      expect(a.lerp(b, 1).background, b.background);
      // Identity is preserved past the halfway point, so a theme in transition
      // never reports a name that belongs to neither end.
      expect(a.lerp(b, 0.2).id, a.id);
      expect(a.lerp(b, 0.8).id, b.id);
      expect(a.lerp(null, 0.5), same(a));
    });
  });
}
