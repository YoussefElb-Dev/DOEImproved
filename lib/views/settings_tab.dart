import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../models/portal_snapshot.dart';
import '../storage/state_providers.dart';
import 'widgets/portal_shell.dart';

/// Settings tab: profile photo, session state, and about.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final profile = ref.watch(studentProfileProvider);
    final imagePath = ref.watch(profileImageProvider);
    final source = ref.watch(dataSourceProvider);
    final lastSynced = ref.watch(lastSyncedProvider);
    final isLive = source == DataSource.live;

    return PortalScaffold(
      title: 'Settings',
      showHeader: false,
      children: [
        GlassContainer(
          child: Column(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: AppColors.gradeB.withValues(alpha: 0.15),
                    backgroundImage: (imagePath != null && imagePath.isNotEmpty)
                        ? FileImage(File(imagePath)) as ImageProvider
                        : null,
                    child: (imagePath == null || imagePath.isEmpty)
                        ? const Icon(Icons.person_rounded,
                            size: 50, color: AppColors.gradeB)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(profileImageProvider.notifier).pick(),
                      child: Container(
                        width: 33,
                        height: 33,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.gradeB,
                          border: Border.all(
                            color: AppColors.background,
                            width: 2.5,
                          ),
                        ),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 16, color: AppColors.background),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                profile?.name.isNotEmpty == true ? profile!.name : 'Student',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              if (profile?.schoolName.isNotEmpty == true) ...[
                const SizedBox(height: 2),
                Text(
                  profile!.schoolName,
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
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
                      child: const Text(
                        'Remove photo',
                        style: TextStyle(color: AppColors.gradeDF),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassContainer(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Column(
            children: [
              _SettingRow(
                icon: isLive
                    ? Icons.verified_user_rounded
                    : Icons.science_rounded,
                iconColor: isLive ? AppColors.gradeA : AppColors.gradeC,
                title: isLive ? 'Session active' : 'Demo mode',
                subtitle: isLive
                    ? 'Authenticated via TeachHub SSO'
                    : 'Showing sample data — sign in for your own',
                trailing: StatusPill(
                  label: isLive ? 'LIVE' : 'DEMO',
                  color: isLive ? AppColors.gradeA : AppColors.gradeC,
                ),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.sync_rounded,
                title: 'Refresh now',
                subtitle: lastSynced == null
                    ? 'Auto-refreshes every ${kAutoRefreshInterval.inMinutes} minutes'
                    : 'Last updated ${relativeTime(lastSynced)} · auto every '
                        '${kAutoRefreshInterval.inMinutes} min',
                onTap: () => ref.read(portalProvider.notifier).refresh(),
              ),
              const Divider(height: 1),
              _SettingRow(
                icon: Icons.logout_rounded,
                iconColor: AppColors.gradeDF,
                title: 'Sign out',
                subtitle: 'Clears stored cookies and local data',
                onTap: () => _confirmSignOut(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        GlassContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('About',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                'DOEImproved v1.0.0\n'
                'A student-built companion for NYC Public Schools.\n'
                'Not affiliated with the NYC DOE.',
                style: tt.bodySmall
                    ?.copyWith(color: AppColors.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 10),
              Text(
                'Your session stays on this device in the iOS keychain. '
                'DOEImproved has no server and sends your data nowhere.',
                style: tt.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.backgroundLift,
        title: const Text('Sign out?'),
        content: const Text(
          'This clears your saved session and cached portal data from this '
          'device. You can sign in again any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out',
                style: TextStyle(color: AppColors.gradeDF)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    // AuthGate watches the session, so clearing it swaps back to sign-in.
    await ref.read(sessionProvider.notifier).signOut();
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: iconColor ?? AppColors.gradeB),
      title:
          Text(title, style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: tt.bodySmall?.copyWith(color: AppColors.textSecondary)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}
