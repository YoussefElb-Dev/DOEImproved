import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'services/auth_webview_service.dart';
import 'storage/state_providers.dart';
import 'views/root_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );
  runApp(const ProviderScope(child: GradlyApp()));
}

class GradlyApp extends StatelessWidget {
  const GradlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Gradly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}

/// Decides whether to show the SSO login WebView or the dashboard.
///
/// The persisted session is restored by [sessionProvider]; an empty cookie map
/// means "sign in". When the portal later rejects the session,
/// [listenForExpiredSession] clears it and this gate swaps back to login.
class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return session.when(
      loading: () => const _SplashScreen(),
      // A storage read failure shouldn't strand the user — offer sign-in.
      error: (_, __) => _login(ref),
      data: (cookies) => cookies.isEmpty
          ? _login(ref)
          : const PortalLifecycleRefresher(child: RootShell()),
    );
  }

  Widget _login(WidgetRef ref) => AuthWebViewScreen(
        onAuthenticated: (cookies) =>
            ref.read(sessionProvider.notifier).adopt(cookies),
      );
}

/// Brand splash shown while the stored session is read back.
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.gradeB, AppColors.gradeA],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gradeB.withValues(alpha: 0.35),
                    blurRadius: 34,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.school_rounded,
                size: 40,
                color: AppColors.background,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'Gradly',
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 26),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
          ],
        ),
      ),
    );
  }
}
