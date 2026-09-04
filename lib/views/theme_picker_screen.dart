import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../storage/state_providers.dart';

/// Picks the app theme. Each row previews itself in its own colours, so the
/// choice is visible before it is made rather than after.
class ThemePickerScreen extends ConsumerWidget {
  const ThemePickerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(themeProvider);
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
          children: [
            Text(
              'Applies everywhere, straight away. Your choice is remembered.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: p.textSecondary),
            ),
            const SizedBox(height: 18),
            for (final (i, palette) in AppPalette.all.indexed) ...[
              FadeSlideIn(
                index: i,
                child: _ThemeOption(
                  palette: palette,
                  selected: palette.id == active.id,
                  onTap: () =>
                      ref.read(themeProvider.notifier).select(palette.id),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = context.palette;
    final tt = Theme.of(context).textTheme;

    return SurfaceCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      borderColor: selected ? active.accent : null,
      child: Row(
        children: [
          _Preview(palette: palette),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  palette.name,
                  style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  palette.blurb,
                  style: tt.bodySmall?.copyWith(color: active.textSecondary),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (final swatch in [
                      palette.accent,
                      palette.gradeA,
                      palette.gradeB,
                      palette.gradeC,
                      palette.gradeF,
                    ])
                      Container(
                        width: 13,
                        height: 13,
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: swatch,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (selected)
            Icon(Icons.check_circle_rounded, color: active.accent, size: 22)
          else
            Icon(Icons.circle_outlined, color: active.textTertiary, size: 22),
        ],
      ),
    );
  }
}

/// A miniature of the grades screen, painted in the theme being offered.
class _Preview extends StatelessWidget {
  final AppPalette palette;

  const _Preview({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 62,
      height: 74,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 16,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.textSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Spacer(),
              Container(
                width: 9,
                height: 4,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: palette.surface,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _bar(palette.gradeA, 14),
                      _bar(palette.gradeC, 20),
                      _bar(palette.accent, 11),
                      _bar(palette.gradeF, 17),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Four bars at 6pt with a 2pt gutter is 32pt — the preview card leaves 34
  /// once its two borders and padding are taken out, so this fits with room
  /// to spare. Widening either value overflows the card.
  Widget _bar(Color color, double height) => Container(
        width: 6,
        height: height,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
        ),
      );
}
