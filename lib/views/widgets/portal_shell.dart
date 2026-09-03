import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/portal_snapshot.dart';
import '../../storage/state_providers.dart';

/// Floating glass header: brand, live/demo state, last-sync stamp, avatar.
class PortalHeader extends ConsumerWidget {
  const PortalHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final syncing = ref.watch(syncIndicatorProvider);
    final source = ref.watch(dataSourceProvider);
    final lastSynced = ref.watch(lastSyncedProvider);
    final profile = ref.watch(studentProfileProvider);
    final localImage = ref.watch(profileImageProvider);

    final isDemo = source == DataSource.demo;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      borderRadius: 20,
      child: Row(
        children: [
          _SyncDot(active: syncing),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'Gradly',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (source != null)
                      StatusPill(
                        label: isDemo ? 'DEMO' : 'LIVE',
                        color: isDemo ? AppColors.gradeC : AppColors.gradeA,
                        icon: isDemo
                            ? Icons.science_rounded
                            : Icons.bolt_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                _LastSyncedLine(syncing: syncing, lastSynced: lastSynced),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 20),
            color: AppColors.textSecondary,
            onPressed: syncing
                ? null
                : () => ref.read(portalProvider.notifier).refresh(),
          ),
          _Avatar(avatarUrl: profile?.avatarUrl, localPath: localImage),
        ],
      ),
    );
  }
}

/// Re-renders once a minute so "4m ago" doesn't go stale on screen.
class _LastSyncedLine extends StatefulWidget {
  final bool syncing;
  final DateTime? lastSynced;

  const _LastSyncedLine({required this.syncing, required this.lastSynced});

  @override
  State<_LastSyncedLine> createState() => _LastSyncedLineState();
}

class _LastSyncedLineState extends State<_LastSyncedLine> {
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
    final text = widget.syncing
        ? 'Syncing…'
        : widget.lastSynced == null
            ? ''
            : 'Updated ${relativeTime(widget.lastSynced)}';
    return Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppColors.textSecondary,
            fontSize: 10.5,
          ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? avatarUrl;
  final String? localPath;

  const _Avatar({this.avatarUrl, this.localPath});

  @override
  Widget build(BuildContext context) {
    if (localPath != null && localPath!.isNotEmpty) {
      return CircleAvatar(radius: 17, backgroundImage: FileImage(File(localPath!)));
    }
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 17,
        backgroundImage: NetworkImage(avatarUrl!),
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: 17,
      backgroundColor: AppColors.gradeB.withValues(alpha: 0.2),
      child: const Icon(Icons.person_rounded, color: AppColors.gradeB, size: 19),
    );
  }
}

class _SyncDot extends StatefulWidget {
  final bool active;
  const _SyncDot({required this.active});

  @override
  State<_SyncDot> createState() => _SyncDotState();
}

class _SyncDotState extends State<_SyncDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? AppColors.gradeA : AppColors.textSecondary;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final glow = widget.active ? _c.value : 0.0;
        return Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5 * glow),
                blurRadius: 10 * glow + 2,
                spreadRadius: 2 * glow,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Explains that nothing on screen is the student's real record.
class DemoBanner extends StatelessWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.gradeC.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gradeC.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.science_rounded, size: 16, color: AppColors.gradeC),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Sample data — sign in to see your own grades.',
              style: tt.bodySmall?.copyWith(color: AppColors.gradeC),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the sync succeeded but one section came back empty.
class WarningBanner extends StatelessWidget {
  final String message;
  const WarningBanner(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded,
              size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-bleed failure state with a retry, used when a sync produced nothing
/// to render at all.
class PortalErrorState extends ConsumerWidget {
  final Object error;
  const PortalErrorState({super.key, required this.error});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded,
              size: 40, color: AppColors.textSecondary),
          const SizedBox(height: 14),
          Text(
            'Could not reach the portal',
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            '$error',
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: () => ref.read(portalProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Empty-state card used by every list.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return GlassContainer(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          Icon(icon, size: 38, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(title,
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Shared page frame: pull-to-refresh, the header, and the demo/partial
/// banners, so all four tabs behave identically.
class PortalScaffold extends ConsumerWidget {
  final String? title;
  final List<Widget> children;
  final bool showHeader;

  const PortalScaffold({
    super.key,
    this.title,
    required this.children,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final snapshot = ref.watch(portalProvider);
    final partial = snapshot.valueOrNull?.partialFailure;
    final isDemo = snapshot.valueOrNull?.isDemo ?? false;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => ref.read(portalProvider.notifier).refresh(),
        color: AppColors.gradeB,
        backgroundColor: AppColors.backgroundLift,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 36),
          children: [
            if (showHeader) ...[
              const PortalHeader(),
              const SizedBox(height: 14),
            ],
            if (isDemo) ...[
              const DemoBanner(),
              const SizedBox(height: 14),
            ],
            if (partial != null) ...[
              WarningBanner(partial),
              const SizedBox(height: 14),
            ],
            if (title != null) ...[
              Text(
                title!,
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}
