import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../storage/state_providers.dart';
import 'dashboard_screen.dart' show DashboardScreen;

/// Grades tab = the existing dashboard (GPA hero + course feed + sync dot).
class GradesTab extends ConsumerWidget {
  const GradesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const DashboardScreen();
  }
}

/// Shared scaffold body for tab pages without the nav bar.
class TabBody extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const TabBody({super.key, required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            title,
            style: tt.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

/// The header bar (DOEImproved + avatar + sync dot), reusable across tabs.
class HomeHeaderBar extends ConsumerWidget {
  const HomeHeaderBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(syncIndicatorProvider);
    final profile = ref.watch(studentProfileProvider).valueOrNull;
    final imagePath = ref.watch(profileImageProvider);
    final tt = Theme.of(context).textTheme;

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      borderRadius: 20,
      child: Row(
        children: [
          _SyncDot(active: syncing),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'DOEImproved',
              style: tt.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
          ),
          _Avatar(imageUrl: profile?.avatarUrl, imagePath: imagePath),
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String? imageUrl;
  final String? imagePath;
  const _Avatar({this.imageUrl, this.imagePath});

  @override
  Widget build(BuildContext context) {
    if (imagePath != null && imagePath!.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: FileImage(File(imagePath!)),
      );
    }
    if (imageUrl != null && imageUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: 18,
        backgroundImage: NetworkImage(imageUrl!),
      );
    }
    return CircleAvatar(
      radius: 18,
      backgroundColor: AppColors.gradeB.withValues(alpha: 0.2),
      child: const Icon(Icons.person_rounded, color: AppColors.gradeB, size: 20),
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
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

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
          width: 10,
          height: 10,
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

