import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/archive_models.dart';
import '../storage/archive_store.dart';
import '../storage/state_providers.dart';

/// Opens a saved document.
///
/// The PDF is rendered by the platform WebView, which reads PDFs natively — no
/// extra dependency, and it is the same renderer Safari uses. The text that
/// was read out of the file is available alongside it, which is the fallback
/// when a document will not render.
class DocumentViewerScreen extends ConsumerStatefulWidget {
  final SavedDocument document;

  const DocumentViewerScreen({super.key, required this.document});

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  WebViewController? _controller;
  bool _showText = false;
  bool _loading = true;
  String? _error;
  String? _text;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final store = ref.read(archiveStoreProvider);
    _text = await store.readDocumentText(widget.document.id);

    final file = await store.documentFile(widget.document.id);
    if (!mounted) return;

    if (file == null) {
      setState(() {
        _loading = false;
        _error = 'The file is no longer on this device.';
        _showText = _text != null;
      });
      return;
    }

    final controller = WebViewController()
      ..setBackgroundColor(context.palette.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (!mounted || !(error.isForMainFrame ?? false)) return;
            setState(() {
              _loading = false;
              // A PDF the renderer refuses is still readable as text.
              _error = error.description;
              _showText = _text != null;
            });
          },
        ),
      );
    await controller.loadFile(file.path);
    if (!mounted) return;
    setState(() => _controller = controller);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final tt = Theme.of(context).textTheme;
    final hasText = _text != null && _text!.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.document.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (hasText)
            TextButton(
              onPressed: () => setState(() => _showText = !_showText),
              child: Text(_showText ? 'Document' : 'Text'),
            ),
        ],
        bottom: _loading && !_showText
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              color: p.surface,
              child: Text(
                '${widget.document.kind} · '
                '${ArchiveStore.formatBytes(widget.document.bytes)} · '
                'saved ${shortDate(widget.document.savedAt)}',
                style: tt.labelSmall?.copyWith(color: p.textTertiary),
              ),
            ),
            if (_error != null && !_showText)
              Container(
                width: double.infinity,
                color: p.warning.withValues(alpha: 0.12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(
                  hasText
                      ? 'This document will not render here. Tap Text to read '
                          'what was pulled out of it.'
                      : 'This document could not be opened: $_error',
                  style: tt.bodySmall?.copyWith(color: p.warning),
                ),
              ),
            Expanded(child: _body(hasText)),
          ],
        ),
      ),
    );
  }

  Widget _body(bool hasText) {
    final p = context.palette;

    if (_showText && hasText) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
        child: SelectableText(
          _text!,
          style: TextStyle(
            color: p.textPrimary,
            fontSize: 12.5,
            height: 1.55,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : Padding(
                padding: const EdgeInsets.all(28),
                child: EmptyState(
                  icon: Icons.description_outlined,
                  title: 'Cannot open this document',
                  message: _error!,
                ),
              ),
      );
    }
    return WebViewWidget(controller: controller);
  }
}
