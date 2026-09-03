import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../storage/state_providers.dart';
import 'grades_tab.dart';
import 'schedule_tab.dart';
import 'settings_tab.dart';
import 'work_tab.dart';

/// Root navigation shell with 4 tabs: Grades, Schedule, Work, Settings.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  static const _screens = [
    GradesTab(),
    ScheduleTab(),
    WorkTab(),
    SettingsTab(),
  ];

  static const _items = [
    (icon: Icons.grade_rounded, label: 'Grades'),
    (icon: Icons.calendar_month_rounded, label: 'Schedule'),
    (icon: Icons.assignment_rounded, label: 'Work'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // A rejected session drops the cookies, which sends AuthGate back to login.
    listenForExpiredSession(ref);

    final syncing = ref.watch(syncIndicatorProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: GlassContainer(
        padding: EdgeInsets.zero,
        borderRadius: 0,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final (i, item) in _items.indexed)
                  _NavItem(
                    icon: item.icon,
                    label: item.label,
                    active: _index == i,
                    // Only the Grades tab carries the sync badge.
                    syncing: syncing && i == 0,
                    onTap: () => setState(() => _index = i),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool syncing;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.syncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.gradeB : AppColors.textSecondary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gradeB.withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, color: color, size: 23),
                if (syncing)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.gradeA,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
