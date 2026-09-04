import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../storage/state_providers.dart';
import 'analytics_tab.dart';
import 'assignments_tab.dart';
import 'calendar_tab.dart';
import 'grades_tab.dart';
import 'settings_tab.dart';

/// Five tabs: Grades, Calendar, Assignments, Analytics, Settings.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  static const _screens = [
    GradesTab(),
    CalendarTab(),
    AssignmentsTab(),
    AnalyticsTab(),
    SettingsTab(),
  ];

  static const _items = [
    (icon: Icons.school_rounded, label: 'Grades'),
    (icon: Icons.calendar_month_rounded, label: 'Calendar'),
    (icon: Icons.assignment_rounded, label: 'Assignments'),
    (icon: Icons.insights_rounded, label: 'Analytics'),
    (icon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // A rejected session drops the cookies, which sends AuthGate back to login.
    listenForExpiredSession(ref);

    final p = context.palette;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.background,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: [
                for (final (i, item) in _items.indexed)
                  Expanded(
                    child: _NavItem(
                      icon: item.icon,
                      label: item.label,
                      active: _index == i,
                      onTap: () => setState(() => _index = i),
                    ),
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
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = active ? p.accent : p.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 7),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color: active ? p.accent.withValues(alpha: 0.10) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 21),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(
                color: color,
                fontSize: 9,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
