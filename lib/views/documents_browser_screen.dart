import 'dart:convert';
import 'dart:typed_data';

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
  final Map<String, _PdfAssembly> _assemblies = {};

  bool _busy = true;
  bool _onLoginPage = false;
  String? _error;
  Map<String, String> _cookies = const {};
  Uri _currentPage = Uri.parse(DocumentService.documentsUrl);

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
    return /\.pdf(\?|#|$)/i.test(text) || /download/i.test(text);
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

  /// Captures the response body while it is still inside the authenticated
  /// WebView. This covers target=_blank links, generated blob URLs, fetch/XHR
  /// downloads, and endpoints whose URL does not end in .pdf.
  static const String _captureScript = r'''
(function () {
  if (window.__gradlyPdfCaptureInstalled) return;
  window.__gradlyPdfCaptureInstalled = true;
  var originalFetch = window.fetch.bind(window);
  var sent = {};

  function post(value) {
    try { GradlyDocuments.postMessage(JSON.stringify(value)); } catch (_) {}
  }
  function pdfSignature(bytes) {
    return bytes.length > 4 && bytes[0] === 37 && bytes[1] === 80 &&
           bytes[2] === 68 && bytes[3] === 70;
  }
  function sendBytes(bytes, title, url) {
    var id = String(Date.now()) + '-' + Math.random().toString(36).slice(2);
    var key = String(url || '') + ':' + bytes.length;
    if (sent[key]) return;
    sent[key] = true;
    var size = 24576;
    var count = Math.ceil(bytes.length / size);
    post({type:'start', id:id, title:title || 'DOE document.pdf',
          url:String(url || location.href), count:count, bytes:bytes.length});
    for (var i = 0; i < count; i++) {
      var slice = bytes.subarray(i * size, Math.min(bytes.length, (i + 1) * size));
      var binary = '';
      for (var j = 0; j < slice.length; j += 8192) {
        binary += String.fromCharCode.apply(null, slice.subarray(j, j + 8192));
      }
      post({type:'chunk', id:id, index:i, data:btoa(binary)});
    }
    post({type:'end', id:id});
  }
  function captureUrl(url, title, navigateWhenHtml) {
    if (!url) return;
    var absolute;
    try { absolute = new URL(url, document.baseURI).href; } catch (_) { return; }
    originalFetch(absolute, {credentials:'include', redirect:'follow'})
      .then(function (response) { return response.arrayBuffer(); })
      .then(function (buffer) {
        var bytes = new Uint8Array(buffer);
        if (pdfSignature(bytes)) sendBytes(bytes, title, absolute);
        else if (navigateWhenHtml) location.href = absolute;
      })
      .catch(function () { if (navigateWhenHtml) location.href = absolute; });
  }
  function captureForm(form, title, fallback) {
    var method = String(form.method || 'GET').toUpperCase();
    var action = form.action || location.href;
    var options = {credentials:'include', redirect:'follow', method:method};
    if (method === 'GET') {
      var query = new URLSearchParams(new FormData(form)).toString();
      action += (action.indexOf('?') >= 0 ? '&' : '?') + query;
    } else {
      options.body = new FormData(form);
    }
    originalFetch(action, options)
      .then(function (response) { return response.arrayBuffer(); })
      .then(function (buffer) {
        var bytes = new Uint8Array(buffer);
        if (pdfSignature(bytes)) sendBytes(bytes, title, action);
        else if (fallback) fallback();
      })
      .catch(function () { if (fallback) fallback(); });
  }

  document.addEventListener('click', function (event) {
    var element = event.target && event.target.closest
      ? event.target.closest('a[href],button,[role=button]') : null;
    if (!element) return;
    var rawHref = element.getAttribute('href') || '';
    var href = element.href || element.getAttribute('data-url') ||
               element.getAttribute('data-href') || element.getAttribute('data-file');
    var title = (element.textContent || element.getAttribute('aria-label') || '').trim();
    var documentish = /\.pdf(\?|#|$)|download/i.test(href || '') ||
      /transcript|report\s*card|progress\s*report|schedule|program\s*card/i.test(title);
    if (documentish) window.__gradlyLastDocumentTitle = title;
    // DOE's visible document links all point to "#". Their onclick handlers
    // fill and submit frmLinks, so those handlers must be allowed to run.
    if (rawHref === '#' || /^javascript:/i.test(rawHref) || !href) return;
    if (!documentish && element.target !== '_blank') return;
    event.preventDefault();
    event.stopPropagation();
    captureUrl(href, title, true);
  }, true);

  var originalOpen = window.open;
  window.open = function (url) {
    if (url) captureUrl(url, window.__gradlyLastDocumentTitle || document.title, true);
    return null;
  };

  var originalSubmit = HTMLFormElement.prototype.submit;
  HTMLFormElement.prototype.submit = function () {
    var form = this;
    captureForm(
      form,
      window.__gradlyLastDocumentTitle || document.title,
      function () { originalSubmit.call(form); }
    );
  };
  document.addEventListener('submit', function (event) {
    var form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    event.preventDefault();
    captureForm(
      form,
      window.__gradlyLastDocumentTitle || document.title,
      function () { originalSubmit.call(form); }
    );
  }, true);

  window.fetch = function () {
    return originalFetch.apply(window, arguments).then(function (response) {
      try {
        var type = response.headers.get('content-type') || '';
        var disposition = response.headers.get('content-disposition') || '';
        if (/pdf/i.test(type + ' ' + disposition)) {
          response.clone().arrayBuffer().then(function (buffer) {
            var bytes = new Uint8Array(buffer);
            if (pdfSignature(bytes)) sendBytes(bytes, document.title, response.url);
          });
        }
      } catch (_) {}
      return response;
    });
  };

  var originalOpenXhr = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function (method, url) {
    this.__gradlyUrl = url;
    this.addEventListener('load', function () {
      try {
        var type = this.getResponseHeader('content-type') || '';
        var disposition = this.getResponseHeader('content-disposition') || '';
        if (!/pdf/i.test(type + ' ' + disposition)) return;
        if (this.response instanceof ArrayBuffer) {
          sendBytes(new Uint8Array(this.response), document.title, this.responseURL || this.__gradlyUrl);
        } else if (this.response instanceof Blob) {
          this.response.arrayBuffer().then(function (buffer) {
            sendBytes(new Uint8Array(buffer), document.title, this.responseURL || this.__gradlyUrl);
          }.bind(this));
        }
      } catch (_) {}
    });
    return originalOpenXhr.apply(this, arguments);
  };
})();
''';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0C0D10))
      ..addJavaScriptChannel(
        'GradlyDocuments',
        onMessageReceived: _onDocumentMessage,
      )
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
    _currentPage = uri;

    final onLogin = await _pageHasPasswordField();
    if (mounted) setState(() => _onLoginPage = onLogin);
    if (onLogin) return;

    // Past the login: the session is real and the page is the student's own.
    final cookies =
        await AuthWebViewService.captureCookiesFor(PortalHosts.documents);
    if (cookies.isNotEmpty) _cookies = {..._cookies, ...cookies};

    await _installCapture();
    await _discover();
  }

  Future<void> _installCapture() async {
    try {
      await _controller.runJavaScript(_captureScript);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not enable PDF capture: $error');
    }
  }

  void _onDocumentMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final id = '${data['id'] ?? ''}';
      if (id.isEmpty) return;
      switch ('${data['type'] ?? ''}') {
        case 'start':
          final expectedBytes = (data['bytes'] as num?)?.toInt() ?? 0;
          if (expectedBytes <= 0 || expectedBytes > DocumentService.maxDocumentBytes) {
            setState(() => _error = 'The selected PDF is too large to save.');
            return;
          }
          _assemblies[id] = _PdfAssembly(
            title: '${data['title'] ?? 'DOE document.pdf'}',
            sourceUrl: Uri.tryParse('${data['url'] ?? ''}') ?? _currentPage,
            chunkCount: (data['count'] as num?)?.toInt() ?? 0,
            expectedBytes: expectedBytes,
          );
        case 'chunk':
          final assembly = _assemblies[id];
          final index = (data['index'] as num?)?.toInt();
          if (assembly == null || index == null) return;
          assembly.chunks[index] = base64Decode('${data['data'] ?? ''}');
        case 'end':
          final assembly = _assemblies.remove(id);
          if (assembly == null || !assembly.complete) return;
          final bytes = assembly.join();
          if (bytes.length != assembly.expectedBytes) {
            setState(() => _error = 'The PDF transfer was incomplete. Tap it again.');
            return;
          }
          final link = DocumentLink.captured(
            sourceUrl: assembly.sourceUrl,
            title: assembly.title,
            bytes: bytes,
            captureId: id,
          );
          if (_record([link]) > 0) _toast('Captured ${link.title}');
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not read the selected PDF: $error');
    }
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

class _PdfAssembly {
  _PdfAssembly({
    required this.title,
    required this.sourceUrl,
    required this.chunkCount,
    required this.expectedBytes,
  });

  final String title;
  final Uri sourceUrl;
  final int chunkCount;
  final int expectedBytes;
  final Map<int, Uint8List> chunks = {};

  bool get complete => chunkCount > 0 && chunks.length == chunkCount;

  Uint8List join() {
    final builder = BytesBuilder(copy: false);
    for (var i = 0; i < chunkCount; i++) {
      final chunk = chunks[i];
      if (chunk != null) builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
