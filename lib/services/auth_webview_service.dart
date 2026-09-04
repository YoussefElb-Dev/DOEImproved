import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import 'grade_data_service.dart';
import 'native_cookie_bridge.dart';

/// Handles the NYC Public Schools SSO flow (TeachHub / SAML) inside an
/// embedded WebView, captures the authenticated session cookies — first via
/// the native cookie jar (which includes HttpOnly cookies), falling back to
/// `document.cookie` — and persists them with `flutter_secure_storage`.
class AuthWebViewService {
  static const String portalUrl = 'https://teachhub.schools.nyc';
  static const String _sessionKey = 'doe_session_cookies';
  static const String _sessionTimestampKey = 'doe_session_timestamp';

  final FlutterSecureStorage _storage;
  final WebViewCookieManager _cookieManager;
  final GradeDataService _probe;

  final void Function(Map<String, String> cookies)? onAuthenticated;
  final void Function(String error)? onAuthError;
  final void Function(bool busy)? onBusyChanged;

  late final WebViewController controller;

  /// Guards against re-entrant capture while a validation probe is running.
  bool _capturing = false;
  bool _completed = false;

  AuthWebViewService({
    FlutterSecureStorage? storage,
    WebViewCookieManager? cookieManager,
    GradeDataService? probe,
    this.onAuthenticated,
    this.onAuthError,
    this.onBusyChanged,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _cookieManager = cookieManager ?? WebViewCookieManager(),
        _probe = probe ?? GradeDataService() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Repainted from the active theme in didChangeDependencies; this is
      // only the colour the view flashes before the first frame.
      ..setBackgroundColor(const Color(0xFF0C0D10))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => onBusyChanged?.call(true),
          onPageFinished: (url) async {
            onBusyChanged?.call(false);
            await _handlePageFinished(url);
          },
          onWebResourceError: (error) {
            onBusyChanged?.call(false);
            // Sub-resource failures are noise; only surface main-frame ones.
            if (error.isForMainFrame ?? false) {
              onAuthError?.call(error.description);
            }
          },
        ),
      );
  }

  Future<void> start() => controller.loadRequest(Uri.parse(portalUrl));

  Future<void> reload() => controller.reload();

  /// After each page load, try to harvest cookies and prove they actually
  /// work. Guessing from the URL alone is unreliable — the portal's pre-login
  /// landing page lives on the same host — so a captured session is only
  /// accepted once the dashboard answers to it.
  Future<void> _handlePageFinished(String url) async {
    if (_completed || _capturing) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.host.toLowerCase().endsWith('schools.nyc')) return;

    _capturing = true;
    try {
      final cookies = await captureCookies();
      if (cookies.isEmpty) return;

      final valid = await _probe.validateSession(cookies);
      if (!valid) return;

      await saveSession(cookies);
      _completed = true;
      onAuthenticated?.call(cookies);
    } finally {
      _capturing = false;
    }
  }

  /// Captures the authenticated session cookies. Prefers the native cookie
  /// jar (which includes the HttpOnly SSO tokens invisible to JavaScript) and
  /// falls back to `document.cookie` when the platform channel is unavailable.
  Future<Map<String, String>> captureCookies() async {
    final out = <String, String>{};

    // Grades and documents live on different DOE hosts, so the jar is read
    // for each and the keys carry their host. That keeps one property's
    // session from ever being sent to another.
    for (final host in PortalHosts.all) {
      final jar = await NativeCookieBridge.getCookies('https://$host');
      jar.forEach((name, value) {
        out[NativeCookieBridge.scopedKey(host, name)] = value;
      });
    }

    // document.cookie only ever sees the page currently loaded, and misses
    // HttpOnly entries — a fallback for when the platform channel is absent.
    final js = await _captureViaJavaScript();
    js.forEach((name, value) {
      out.putIfAbsent(
        NativeCookieBridge.scopedKey(PortalHosts.teachHub, name),
        () => value,
      );
    });

    return out;
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

  /// Cookies for a single DOE host, keyed by that host.
  ///
  /// Used when signing in to the document site separately from the gradebook.
  static Future<Map<String, String>> captureCookiesFor(String host) async {
    final jar = await NativeCookieBridge.getCookies('https://$host');
    return {
      for (final entry in jar.entries)
        NativeCookieBridge.scopedKey(host, entry.key): entry.value,
    };
  }

  /// Adds cookies to the stored session without disturbing the rest, so a
  /// second sign-in never costs the first one.
  Future<Map<String, String>> mergeSession(Map<String, String> extra) async {
    final merged = {...await restoreSession(), ...extra};
    await saveSession(merged);
    return merged;
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
      final decoded = jsonDecode(raw) as Map;
      return decoded.map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  Future<DateTime?> sessionTimestamp() async {
    final raw = await _storage.read(key: _sessionTimestampKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> clearSession() async {
    // Clear both the plugin jar and the native one, so signing out does not
    // leave a live SSO cookie behind for the next person on the device.
    await _cookieManager.clearCookies();
    await NativeCookieBridge.clearCookies();
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
  bool _busy = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Match the WebView's own backdrop to the theme so switching themes does
    // not leave a mismatched frame behind the login page.
    _auth.controller.setBackgroundColor(context.palette.background);
  }

  @override
  void initState() {
    super.initState();
    _auth = AuthWebViewService(
      onAuthenticated: widget.onAuthenticated,
      onAuthError: (e) {
        if (mounted) setState(() => _error = e);
      },
      onBusyChanged: (b) {
        if (mounted) setState(() => _busy = b);
      },
    )..start();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('Sign in with NYCAPS'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              setState(() => _error = null);
              _auth.reload();
            },
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              color: p.danger.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Could not reach the portal: $_error',
                style: tt.bodySmall?.copyWith(color: p.danger),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _auth.controller)),
        ],
      ),
    );
  }
}
