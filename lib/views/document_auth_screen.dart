import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_webview_service.dart';
import '../services/document_service.dart';
import '../services/native_cookie_bridge.dart';

/// Signs in to the DOE document site.
///
/// The gradebook and the document site are separate properties behind the same
/// NYC Schools Account, and being signed in to one does not always mean being
/// signed in to the other. This is its own screen so that signing in here
/// never disturbs the gradebook session — it only adds cookies to it.
///
/// Pops with the captured cookies, or null if the student backed out.
class DocumentAuthScreen extends StatefulWidget {
  const DocumentAuthScreen({super.key});

  @override
  State<DocumentAuthScreen> createState() => _DocumentAuthScreenState();
}

class _DocumentAuthScreenState extends State<DocumentAuthScreen> {
  late final WebViewController _controller;
  bool _busy = true;
  bool _finished = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C0D10))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _busy = true);
          },
          onPageFinished: (url) async {
            if (mounted) setState(() => _busy = false);
            await _tryCapture(url);
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            setState(() {
              _busy = false;
              if (error.isForMainFrame ?? false) {
                _error = _readableError(error.description);
              }
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(DocumentService.documentsUrl));
  }

  /// iOS reports an ATS rejection as a bare "TLS error", which tells a
  /// student nothing. Name the actual cause.
  static String _readableError(String description) {
    final lower = description.toLowerCase();
    if (lower.contains('tls') ||
        lower.contains('ssl') ||
        lower.contains('secure connection')) {
      return 'The secure connection failed. The DOE document site uses an '
          'older TLS setup than iOS accepts by default. If this keeps '
          'happening, the app build is missing its security exception for '
          'nycenet.edu.';
    }
    return description;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setBackgroundColor(context.palette.background);
  }

  /// Captures once the page is past the login form.
  ///
  /// A cookie jar with entries in it is not proof of being signed in — the
  /// login page sets cookies too — so the page is checked for a password
  /// field first.
  Future<void> _tryCapture(String url) async {
    if (_finished) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !PortalHosts.isAllowed(uri.host)) return;

    if (await _pageHasPasswordField()) return;
    await _capture(silent: true);
  }

  Future<bool> _pageHasPasswordField() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "document.querySelector('input[type=password]') ? '1' : '0'",
      );
      return result.toString().contains('1');
    } catch (_) {
      // If the page will not answer, fall through and let the capture decide.
      return false;
    }
  }

  Future<void> _capture({required bool silent}) async {
    final cookies =
        await AuthWebViewService.captureCookiesFor(PortalHosts.documents);
    if (!mounted) return;

    if (cookies.isEmpty) {
      if (!silent) {
        setState(() => _error =
            'No session was found yet. Finish signing in, then tap Done.');
      }
      return;
    }
    _finished = true;
    Navigator.of(context).pop(cookies);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('DOE documents'),
        actions: [
          TextButton(
            onPressed: () => _capture(silent: false),
            child: const Text('Done'),
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
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: p.surface,
            child: Text(
              'Sign in with your NYC Schools Account. Gradly captures the '
              'session so it can download your transcript — nothing is sent '
              'anywhere else.',
              style: tt.bodySmall?.copyWith(color: p.textSecondary, height: 1.4),
            ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: p.warning.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _error!,
                style: tt.bodySmall?.copyWith(color: p.warning),
              ),
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
        ],
      ),
    );
  }
}
