import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'native_cookie_bridge.dart';

/// Handles the NYC Public Schools SSO flow (TeachHub / SAML) inside an
/// embedded WebView, captures the authenticated session cookies — first via
/// the native cookie jar (includes HttpOnly), falling back to JS
/// document.cookie — and persists them with flutter_secure_storage.
class AuthWebViewService {
  static const String portalUrl = 'https://teachhub.schools.nyc';
  static const String _sessionKey = 'doe_session_cookies';
  static const String _sessionTimestampKey = 'doe_session_timestamp';

  final FlutterSecureStorage _storage;
  final WebViewCookieManager _cookieManager;

  final void Function(Map<String, String> cookies)? onAuthenticated;
  final void Function(String error)? onAuthError;

  late final WebViewController controller;

  AuthWebViewService({
    FlutterSecureStorage? storage,
    WebViewCookieManager? cookieManager,
    this.onAuthenticated,
    this.onAuthError,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _cookieManager = cookieManager ?? WebViewCookieManager() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _handlePageFinished,
          onWebResourceError: (error) =>
              onAuthError?.call(error.description),
        ),
      );
  }

  Future<void> start() => controller.loadRequest(Uri.parse(portalUrl));

  /// After a page loads, check whether the SSO redirect has landed on an
  /// authenticated host and, if so, harvest the session cookies.
  Future<void> _handlePageFinished(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final isAuthenticated = uri.host.endsWith('schools.nyc') &&
        !uri.path.toLowerCase().contains('login') &&
        !uri.path.toLowerCase().contains('saml');
    if (!isAuthenticated) return;

    final cookies = await captureCookies();
    if (cookies.isNotEmpty) {
      await saveSession(cookies);
      onAuthenticated?.call(cookies);
    }
  }

  /// Captures the authenticated session cookies. Prefers the native cookie
  /// jar (includes HttpOnly SSO tokens invisible to JS); falls back to
  /// document.cookie when the platform channel is unavailable.
  Future<Map<String, String>> captureCookies() async {
    // 1) Native jar — authoritative, includes HttpOnly.
    final native = await NativeCookieBridge.getCookies(portalUrl);
    if (native.isNotEmpty) {
      // Merge in any non-HttpOnly cookies JS can see, too.
      final js = await _captureViaJavaScript();
      if (js.isNotEmpty) {
        return {...js, ...native};
      }
      return native;
    }
    // 2) Fallback: document.cookie (misses HttpOnly).
    return _captureViaJavaScript();
  }

  Future<Map<String, String>> _captureViaJavaScript() async {
    try {
      final result =
          await controller.runJavaScriptReturningResult('document.cookie');
      final raw = result.toString();
      final decoded = raw.startsWith('"') ? jsonDecode(raw) as String : raw;
      if (decoded.trim().isEmpty) return {};
      final map = <String, String>{};
      for (final pair in decoded.split(';')) {
        final idx = pair.indexOf('=');
        if (idx <= 0) continue;
        map[pair.substring(0, idx).trim()] = pair.substring(idx + 1).trim();
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  Future<void> saveSession(Map<String, String> cookies) async {
    await _storage.write(key: _sessionKey, value: jsonEncode(cookies));
    await _storage.write(
      key: _sessionTimestampKey,
      value: DateTime.now().toIso8601String(),
    );
  }

  Future<Map<String, String>> restoreSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  Future<DateTime?> sessionTimestamp() async {
    final raw = await _storage.read(key: _sessionTimestampKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> clearSession() async {
    await _cookieManager.clearCookies();
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _sessionTimestampKey);
  }
}

/// Full-screen login page hosting the TeachHub SSO WebView.
class AuthWebViewScreen extends StatefulWidget {
  final void Function(Map<String, String> cookies) onAuthenticated;

  const AuthWebViewScreen({super.key, required this.onAuthenticated});

  @override
  State<AuthWebViewScreen> createState() => _AuthWebViewScreenState();
}

class _AuthWebViewScreenState extends State<AuthWebViewScreen> {
  late final AuthWebViewService _auth;

  @override
  void initState() {
    super.initState();
    _auth = AuthWebViewService(
      onAuthenticated: widget.onAuthenticated,
      onAuthError: (e) => debugPrint('Auth error: $e'),
    )..start();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F12),
      appBar: AppBar(
        title: const Text('Sign in with NYCAPS'),
        centerTitle: true,
      ),
      body: WebViewWidget(controller: _auth.controller),
    );
  }
}
