import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import '../services/auth_webview_service.dart';
import '../services/document_service.dart';
import '../services/native_cookie_bridge.dart';

/// What the browser hands back: the session it captured, and the documents it
/// found on the page.
class DocumentsBrowserResult {
  final Map<String, String> cookies;
  final List<DocumentLink> links;

  const DocumentsBrowserResult({required this.cookies, required this.links});
}

/// The DOE document site, open in the app.
///
/// Scraping the page over plain HTTP finds nothing: the document list is built
/// by JavaScript, so the HTML that arrives is an empty shell. This loads the
/// real page, lets it run, and then finds documents two ways:
///
///   * reading the rendered DOM, which catches links, buttons and rows that
///     carry a URL in an attribute;
///   * intercepting navigation — when a download is tapped the browser tries
///     to navigate to the file, and that request is captured instead.
///
/// The second is the backstop: whatever the page does when a student taps
/// their transcript, the app sees the resulting URL.
class DocumentsBrowserScreen extends StatefulWidget {
  const DocumentsBrowserScreen({super.key});

  @override
  State<DocumentsBrowserScreen> createState() => _DocumentsBrowserScreenState();
}

class _DocumentsBrowserScreenState extends State<DocumentsBrowserScreen> {
  late final WebViewController _controller;
  final List<DocumentLink> _found = [];

  bool _busy = true;
  bool _onLoginPage = false;
  String? _error;
  Map<String, String> _cookies = const {};

  /// Finds anything on the rendered page that leads to a document.
  ///
  /// Looks past anchors on purpose: portals of this vintage put the real URL
  /// on a button's data attribute or build it in an onclick handler.
  static const String _discoveryScript = r'''
(function () {
  var out = [];
  var seen = {};
  function add(url, title) {
    if (!url) return;
    try { url = new URL(url, document.baseURI).href; } catch (e) { return; }
    if (!/^https:/i.test(url)) return;
    if (seen[url]) return;
    seen[url] = 1;
    out.push({ url: url, title: (title || '').replace(/\s+/g, ' ').trim().slice(0, 120) });
  }
  function interesting(text) {
    return /\.pdf(\?|#|$)/i.test(text) ||
           /transcript|report\s*card|progress\s*report|document|download/i.test(text);
  }

  document.querySelectorAll('a[href]').forEach(function (a) {
    if (interesting(a.href + ' ' + a.textContent)) add(a.href, a.textContent);
  });

  var attrs = ['data-url', 'data-href', 'data-link', 'data-file', 'data-path',
               'data-document-url', 'href', 'src'];
  document.querySelectorAll('[data-url],[data-href],[data-link],[data-file],' +
      '[data-path],[data-document-url],button,[role=button],[onclick]')
    .forEach(function (el) {
      for (var i = 0; i < attrs.length; i++) {
        var v = el.getAttribute(attrs[i]);
        if (v && interesting(v)) { add(v, el.textContent); return; }
      }
      var click = el.getAttribute('onclick') || '';
      var m = click.match(/['"]([^'"]*\.pdf[^'"]*)['"]/i) ||
              click.match(/['"](https:\/\/[^'"]+)['"]/i);
      if (m && interesting(m[1])) add(m[1], el.textContent);
    });

  document.querySelectorAll('iframe[src],embed[src],object[data]')
    .forEach(function (el) {
      var v = el.getAttribute('src') || el.getAttribute('data');
      if (v && interesting(v)) add(v, el.getAttribute('title') || '');
    });

  return JSON.stringify(out);
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C0D10))
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigation,
          onPageStarted: (_) {
            if (mounted) setState(() => _busy = true);
          },
          onPageFinished: (url) async {
            if (mounted) setState(() => _busy = false);
            await _afterLoad(url);
          },
          onWebResourceError: (error) {
            if (!mounted || !(error.isForMainFrame ?? false)) return;
            setState(() {
              _busy = false;
              _error = _readableError(error.description);
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(DocumentService.documentsUrl));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.setBackgroundColor(context.palette.background);
  }

  /// Catches a download before the browser follows it.
  ///
  /// A WebView cannot save a file, so navigating to the PDF would either show
  /// it or do nothing. Capturing the URL and staying put is what lets the app
  /// fetch it with the session and keep it.
  NavigationDecision _onNavigation(NavigationRequest request) {
    final url = request.url;
    if (_looksLikeDownload(url)) {
      final link = DocumentLink.from(url, '');
      if (link != null && _record([link]) > 0) {
        _toast('Captured ${link.title}');
      }
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  static bool _looksLikeDownload(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('.pdf')) return true;
    return lower.contains('download') &&
        !lower.contains('/login') &&
        !lower.contains('authsvc');
  }

  Future<void> _afterLoad(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !PortalHosts.isAllowed(uri.host)) return;

    final onLogin = await _pageHasPasswordField();
    if (mounted) setState(() => _onLoginPage = onLogin);
    if (onLogin) return;

    // Past the login: the session is real and the page is the student's own.
    final cookies =
        await AuthWebViewService.captureCookiesFor(PortalHosts.documents);
    if (cookies.isNotEmpty) _cookies = {..._cookies, ...cookies};

    await _discover();
  }

  Future<bool> _pageHasPasswordField() async {
    try {
      final result = await _controller.runJavaScriptReturningResult(
        "document.querySelector('input[type=password]') ? '1' : '0'",
      );
      return result.toString().contains('1');
    } catch (_) {
      return false;
    }
  }

  Future<void> _discover() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(
        _discoveryScript,
      );
      final decoded = _decodeList(raw.toString());
      final links = <DocumentLink>[];
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final link = DocumentLink.from(
          '${entry['url'] ?? ''}',
          '${entry['title'] ?? ''}',
        );
        if (link != null) links.add(link);
      }
      _record(links);
    } catch (_) {
      // A page that will not run the scan can still be used by hand.
    }
  }

  /// iOS hands back a JSON string; some platforms wrap it in quotes again.
  static List<dynamic> _decodeList(String raw) {
    dynamic value = raw;
    for (var i = 0; i < 2; i++) {
      if (value is List) return value;
      if (value is! String) return const [];
      try {
        value = jsonDecode(value);
      } catch (_) {
        return const [];
      }
    }
    return value is List ? value : const [];
  }

  /// Adds links that are new. Returns how many were added.
  int _record(List<DocumentLink> links) {
    final added = links.where((l) => !_found.contains(l)).toList();
    if (added.isEmpty) return 0;
    setState(() => _found.addAll(added));
    return added.length;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static String _readableError(String description) {
    final lower = description.toLowerCase();
    if (lower.contains('tls') ||
        lower.contains('ssl') ||
        lower.contains('secure connection')) {
      return 'The secure connection failed. The DOE document site uses an '
          'older TLS setup than iOS accepts by default. If this keeps '
          'happening, the build is missing its exception for nycenet.edu.';
    }
    return description;
  }

  void _finish() {
    Navigator.of(context).pop(
      DocumentsBrowserResult(cookies: _cookies, links: List.of(_found)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final count = _found.length;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        title: const Text('DOE documents'),
        actions: [
          TextButton(
            onPressed: count == 0 ? null : _finish,
            child: Text(count == 0 ? 'Save' : 'Save ($count)'),
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
              _onLoginPage
                  ? 'Sign in with your NYC Schools Account. Nothing you type '
                      'here is seen by Gradly.'
                  : count == 0
                      ? 'Tap a document the way you would on the website — '
                          'Gradly will catch it and keep a copy.'
                      : '$count document${count == 1 ? '' : 's'} ready. Tap '
                          'more, or press Save.',
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
      bottomNavigationBar: count == 0
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(
                    'Save $count document${count == 1 ? '' : 's'} to this phone',
                  ),
                ),
              ),
            ),
    );
  }
}
