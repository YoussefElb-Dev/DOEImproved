import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/portal_snapshot.dart';
import '../storage/state_providers.dart';
import 'archive_screen.dart';
import 'theme_picker_screen.dart';
import 'widgets/app_shell.dart';

/// Profile, session, appearance and about.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final profile = ref.watch(studentProfileProvider);
    final imagePath = ref.watch(profileImageProvider);
    final source = ref.watch(dataSourceProvider);
    final lastSynced = ref.watch(lastSyncedProvider);
    final palette = ref.watch(themeProvider);
    final isLive = source == DataSource.live;

    return ScreenScaffold(
      title: 'Settings',
      children: [
        // Profile header
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            children: [
              Stack(
                children: [
                  InitialsAvatar(
                    name: profile?.name ?? 'Student',
                    radius: 42,
                    image: (imagePath != null && imagePath.isNotEmpty)
                        ? FileImage(File(imagePath))
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(profileImageProvider.notifier).pick(),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: p.accent,
                          border: Border.all(color: p.surface, width: 2.5),
                        ),
                        child: Icon(Icons.camera_alt_rounded,
                            size: 14, color: p.onAccent),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Portal values are whatever the school typed in, so both lines
              // are centred, wrapped to two lines and clipped.
              Text(
                profile?.name.isNotEmpty == true ? profile!.name : 'Student',
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: tt.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
              if (profile?.schoolName.isNotEmpty == true) ...[
                const SizedBox(height: 4),
                Text(
                  profile!.schoolName,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodySmall?.copyWith(
                    color: p.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 4,
                children: [
                  TextButton(
                    onPressed: () =>
                        ref.read(profileImageProvider.notifier).pick(),
                    child: const Text('Change photo'),
                  ),
                  if (imagePath != null && imagePath.isNotEmpty)
                    TextButton(
                      onPressed: () =>
                          ref.read(profileImageProvider.notifier).clear(),
                      child: Text('Remove photo',
                          style: TextStyle(color: p.danger)),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        const SectionLabel('Appearance'),
        const SizedBox(height: 10),
        _SettingsGroup(
          rows: [
            _SettingsRow(
              icon: Icons.palette_rounded,
              title: 'Theme',
              value: palette.name,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ThemePickerScreen(),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const SectionLabel('Data'),
        const SizedBox(height: 10),
        _SettingsGroup(
          rows: [
            _SettingsRow(
              icon: isLive
                  ? Icons.verified_user_rounded
                  : Icons.science_rounded,
              iconColor: isLive ? p.gradeA : p.warning,
              title: isLive ? 'Session active' : 'Demo mode',
              subtitle: isLive
                  ? 'Authenticated via TeachHub SSO'
                  : 'Showing sample data — sign in for your own',
              trailing: StatusPill(
                label: isLive ? 'LIVE' : 'DEMO',
                color: isLive ? p.gradeA : p.warning,
              ),
            ),
            _SettingsRow(
              icon: Icons.sync_rounded,
              title: 'Refresh now',
              subtitle: lastSynced == null
                  ? 'Auto-refreshes every ${kAutoRefreshInterval.inMinutes} minutes'
                  : 'Last updated ${relativeTime(lastSynced)} · auto every '
                      '${kAutoRefreshInterval.inMinutes} min',
              onTap: () => ref.read(portalProvider.notifier).refresh(),
            ),
            _SettingsRow(
              icon: Icons.inventory_2_rounded,
              title: 'Saved history',
              subtitle: 'Past grades, transcripts and DOE documents kept '
                  'on this device',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ArchiveScreen(),
                ),
              ),
            ),
            _SettingsRow(
              icon: Icons.logout_rounded,
              iconColor: p.danger,
              title: 'Sign out',
              subtitle: 'Clears your session. Saved history stays on '
                  'this device.',
              onTap: () => _confirmSignOut(context, ref),
            ),
          ],
        ),
        const SizedBox(height: 20),

        const SectionLabel('About'),
        const SizedBox(height: 10),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Gradly v1.0.0\n'
                'A student-built companion for NYC Public Schools.\n'
                'Not affiliated with the NYC DOE.',
                style: tt.bodySmall
                    ?.copyWith(color: p.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 10),
              Text(
                'Your session stays on this device in the iOS keychain. '
                'Gradly has no server and sends your data nowhere.',
                style: tt.bodySmall?.copyWith(
                  color: p.textTertiary,
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final p = context.palette;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This clears your session and the offline copy of the portal. Your '
          'saved history — past grades, transcripts and documents — stays on '
          'this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Sign out', style: TextStyle(color: p.danger)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // AuthGate watches the session, so clearing it swaps back to sign-in.
    await ref.read(sessionProvider.notifier).signOut();
  }
}

/// A card of settings rows separated by hairlines.
class _SettingsGroup extends StatelessWidget {
  final List<Widget> rows;

  const _SettingsGroup({required this.rows});

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i != rows.length - 1)
              Divider(height: 1, indent: 52, color: context.palette.border),
          ],
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor ?? p.textSecondary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(
                          color: p.textTertiary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 10),
                Text(
                  value!,
                  style: tt.bodySmall?.copyWith(color: p.textSecondary),
                ),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 10),
                trailing!,
              ],
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(Icons.chevron_right_rounded,
                    size: 20, color: p.textTertiary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
