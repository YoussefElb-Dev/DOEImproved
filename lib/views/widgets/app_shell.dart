import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/ui_kit.dart';
import '../../models/portal_snapshot.dart';
import '../../storage/state_providers.dart';
import 'search_sheet.dart';

/// Brand row: app name, live/demo state, last-sync stamp, search and avatar.
class BrandRow extends ConsumerWidget {
  const BrandRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final syncing = ref.watch(syncIndicatorProvider);
    final source = ref.watch(dataSourceProvider);
    final profile = ref.watch(studentProfileProvider);
    final imagePath = ref.watch(profileImageProvider);
    final isDemo = source == DataSource.demo;

    return Row(
      children: [
        Text(
          'Gradly',
          style: tt.labelLarge?.copyWith(
            color: p.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        if (source != null)
          StatusPill(
            label: isDemo ? 'DEMO' : 'LIVE',
            color: isDemo ? p.warning : p.accent,
          ),
        const Spacer(),
        if (syncing)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: p.accent),
            ),
          ),
        IconButton(
          tooltip: 'Search',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: const Icon(Icons.search_rounded, size: 21),
          color: p.textSecondary,
          onPressed: () => showSearchSheet(context),
        ),
        const SizedBox(width: 6),
        InitialsAvatar(
          name: profile?.name ?? 'Student',
          image: (imagePath != null && imagePath.isNotEmpty)
              ? FileImage(File(imagePath))
              : null,
        ),
      ],
    );
  }
}

/// Re-renders every half minute so "4m ago" does not go stale on screen.
class LastSyncedLine extends ConsumerStatefulWidget {
  const LastSyncedLine({super.key});

  @override
  ConsumerState<LastSyncedLine> createState() => _LastSyncedLineState();
}

class _LastSyncedLineState extends ConsumerState<LastSyncedLine> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final syncing = ref.watch(syncIndicatorProvider);
    final lastSynced = ref.watch(lastSyncedProvider);
    final text = syncing
        ? 'Syncing…'
        : lastSynced == null
            ? ''
            : 'Updated ${relativeTime(lastSynced)}';
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: p.textTertiary,
            fontSize: 11,
          ),
    );
  }
}

/// States that a section is sample data, not the student's own record.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _Banner(
      icon: Icons.science_rounded,
      color: p.warning,
      message: 'Sample data — sign in to see your own grades.',
    );
  }
}

/// Shown when the sync worked but one section came back empty.
class WarningBanner extends StatelessWidget {
  final String message;
  const WarningBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    return _Banner(
      icon: Icons.cloud_off_rounded,
      color: context.palette.textSecondary,
      message: message,
    );
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;

  const _Banner({
    required this.icon,
    required this.color,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width failure state with a retry.
class PortalErrorState extends ConsumerWidget {
  final Object error;
  const PortalErrorState({super.key, required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(26),
      child: Column(
        children: [
          Icon(Icons.wifi_off_rounded, size: 36, color: p.textTertiary),
          const SizedBox(height: 12),
          Text('Could not reach the portal',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: p.textSecondary),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref.read(portalProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// The frame every tab is built in: brand row, big title, pull-to-refresh.
class ScreenScaffold extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;

  /// Shown to the right of the title — sort controls, month pickers.
  final Widget? titleTrailing;

  const ScreenScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
    this.titleTrailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final snapshot = ref.watch(portalProvider);
    final partial = snapshot.valueOrNull?.partialFailure;
    final isDemo = snapshot.valueOrNull?.isDemo ?? false;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: () => ref.read(portalProvider.notifier).refresh(),
        color: p.accent,
        backgroundColor: p.surface,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 108),
          children: [
            const BrandRow(),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: tt.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.1,
                        ),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall?.copyWith(
                            color: p.textSecondary,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 3),
                        const LastSyncedLine(),
                      ],
                    ],
                  ),
                ),
                if (titleTrailing != null) titleTrailing!,
              ],
            ),
            const SizedBox(height: 18),
            if (isDemo) ...[
              const DemoBanner(),
              const SizedBox(height: 14),
            ],
            if (partial != null) ...[
              WarningBanner(partial),
              const SizedBox(height: 14),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
