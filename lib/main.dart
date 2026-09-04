import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'services/auth_webview_service.dart';
import 'storage/state_providers.dart';
import 'views/root_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: GradlyApp()));
}

class GradlyApp extends ConsumerWidget {
  const GradlyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(themeProvider);

    // Keep the status bar legible against whichever theme is active.
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            palette.isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: palette.isDark ? Brightness.dark : Brightness.light,
      ),
    );

    return MaterialApp(
      title: 'Gradly',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.from(palette),
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
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: p.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(21),
                color: p.accent,
                boxShadow: [
                  BoxShadow(
                    color: p.accent.withValues(alpha: 0.3),
                    blurRadius: 32,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(Icons.school_rounded, size: 38, color: p.onAccent),
            ),
            const SizedBox(height: 20),
            Text(
              'Gradly',
              style: tt.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: p.accent),
            ),
          ],
        ),
      ),
    );
  }
}
