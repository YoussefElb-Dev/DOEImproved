import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../main.dart' show AuthGate;
import '../storage/state_providers.dart';

/// Settings tab: profile photo picker, session info, sign-out.
class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tt = Theme.of(context).textTheme;
    final profile = ref.watch(studentProfileProvider).valueOrNull;
    final imagePath = ref.watch(profileImageProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text('Settings',
              style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          const SizedBox(height: 24),
          GlassContainer(
            child: Column(
              children: [
                Stack(
                  children: [
                    CircleAvatar(
                      radius: 52,
                      backgroundColor:
                          AppColors.gradeB.withValues(alpha: 0.15),
                      backgroundImage: (imagePath != null &&
                              imagePath.isNotEmpty)
                          ? FileImage(File(imagePath)) as ImageProvider
                          : null,
                      child: (imagePath == null || imagePath.isEmpty)
                          ? const Icon(Icons.person_rounded,
                              size: 52, color: AppColors.gradeB)
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () =>
                            ref.read(profileImageProvider.notifier).pick(),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppColors.gradeB,
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              size: 18, color: Color(0xFF0D0F12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(profile?.name ?? 'Student',
                    style: tt.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(profile?.schoolName ?? '',
                    style: tt.bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () =>
                      ref.read(profileImageProvider.notifier).pick(),
                  child: const Text('Change photo'),
                ),
                if (imagePath != null && imagePath.isNotEmpty)
                  TextButton(
                    onPressed: () =>
                        ref.read(profileImageProvider.notifier).clear(),
                    child: const Text('Remove photo',
                        style: TextStyle(color: AppColors.gradeDF)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          GlassContainer(
            child: Column(
              children: [
                _SettingRow(
                  icon: Icons.verified_user_rounded,
                  title: 'Session',
                  subtitle: 'Authenticated via TeachHub SSO',
                  trailing: const Icon(Icons.check_circle_rounded,
                      color: AppColors.gradeA),
                ),
                const Divider(height: 1),
                _SettingRow(
                  icon: Icons.logout_rounded,
                  title: 'Sign out',
                  subtitle: 'Clears stored cookies and local data',
                  onTap: () async {
                    await ref.read(authServiceProvider).clearSession();
                    ref.invalidate(sessionCookiesProvider);
                    if (context.mounted) {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const AuthGate()),
                        (_) => false,
                      );
                    }
                  },
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
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                  'DOEImproved v1.0.0\nA student-built companion for NYC Public Schools.\nNot affiliated with the NYC DOE.',
                  style: tt.bodySmall
                      ?.copyWith(color: AppColors.textSecondary, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppColors.gradeB),
      title: Text(title,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: tt.bodySmall?.copyWith(color: AppColors.textSecondary)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}