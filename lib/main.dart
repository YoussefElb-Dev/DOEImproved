import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'services/auth_webview_service.dart';
import 'views/root_shell.dart';

void main() {
  runApp(const ProviderScope(child: DOEImprovedApp()));
}

class DOEImprovedApp extends StatelessWidget {
  const DOEImprovedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DOEImproved',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const AuthGate(),
    );
  }
}

/// Decides whether to show the SSO login WebView or the dashboard.
/// On cold start it attempts to restore a persisted session first.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthWebViewService _auth;
  bool _checking = true;
  bool _authenticated = false;

  @override
  void initState() {
    super.initState();
    _auth = AuthWebViewService();
    _restore();
  }

  Future<void> _restore() async {
    final cookies = await _auth.restoreSession();
    if (!mounted) return;
    setState(() {
      _authenticated = cookies.isNotEmpty;
      _checking = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_authenticated) {
      return const RootShell();
    }
    return AuthWebViewScreen(
      onAuthenticated: (_) => setState(() => _authenticated = true),
    );
  }
}