import 'dart:io';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/archive_models.dart';
import '../models/normalized_transcript.dart';
import '../models/schedule_models.dart';
import '../storage/archive_store.dart';
import 'grade_data_service.dart';
import 'native_cookie_bridge.dart';
import 'pdf/pdf_text_extractor.dart';
import 'pdf/transcript_text_parser.dart';
import 'transcript/normalized_transcript_parser.dart';

/// What one document sync produced.
class DocumentSyncResult {
  final List<SavedDocument> saved;
  final List<TranscriptRecord> transcript;
  final List<NormalizedTranscript> normalizedTranscripts;
  final String? failure;

  /// The DOE document site wants its own sign-in.
  ///
  /// Deliberately not an [AuthExpiredException]: that signal drops the
  /// session and sends the whole app back to login, and being logged out of
  /// the document site says nothing about the gradebook session.
  final bool needsSignIn;

  const DocumentSyncResult({
    this.saved = const [],
    this.transcript = const [],
    this.normalizedTranscripts = const [],
    this.failure,
    this.needsSignIn = false,
  });

  bool get isEmpty => saved.isEmpty && transcript.isEmpty;
}

/// Fetches the student's own documents from the DOE and keeps them.
///
/// The DOE publishes transcripts and report cards as PDFs at
/// `nycenet.edu/studentdocument`, and takes older ones down. This downloads
/// each one, **saves the file itself**, and then tries to read the transcript
/// out of it.
///
/// Saving comes first deliberately: parsing a PDF can be imperfect, but the
/// original document is the thing a student still needs in three years, and
/// keeping it cannot fail in a way that loses information.
class DocumentService {
  static const String documentsUrl = 'https://www.nycenet.edu/studentdocument';
  static const Duration timeout = Duration(seconds: 45);

  /// Refuse anything implausibly large for a transcript.
  static const int maxDocumentBytes = 20 * 1024 * 1024;

  /// A page listing four years of report cards is still a short list.
  static const int maxDocuments = 24;

  final http.Client _client;
  final PdfTextExtractor _extractor;
  final TranscriptTextParser _transcriptParser;
  final NormalizedTranscriptParser _normalizedTranscriptParser;

  DocumentService({
    http.Client? client,
    PdfTextExtractor? extractor,
    TranscriptTextParser? transcriptParser,
    NormalizedTranscriptParser? normalizedTranscriptParser,
  })  : _client = client ?? http.Client(),
        _extractor = extractor ?? const PdfTextExtractor(),
        _transcriptParser = transcriptParser ?? const TranscriptTextParser(),
        _normalizedTranscriptParser =
            normalizedTranscriptParser ?? const NormalizedTranscriptParser();

  Map<String, String> _headers(Map<String, String> cookies, String host) => {
        'Cookie': NativeCookieBridge.toHeader(cookies, host: host),
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
                'Gradly/1.0',
        'Accept': 'text/html,application/pdf,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  /// Downloads every document listed for the student and stores it.
  Future<DocumentSyncResult> sync(
    Map<String, String> cookies,
    ArchiveStore store,
  ) async {
    if (cookies.isEmpty) {
      return const DocumentSyncResult(
        failure: 'Sign in to the DOE document site to fetch your transcript.',
        needsSignIn: true,
      );
    }

    final http.Response listing;
    try {
      listing = await _get(Uri.parse(documentsUrl), cookies);
    } on AuthExpiredException {
      return const DocumentSyncResult(
        failure: 'The DOE document site needs its own sign-in.',
        needsSignIn: true,
      );
    } on HandshakeException catch (e) {
      return DocumentSyncResult(failure: _tlsFailure(e));
    } on TlsException catch (e) {
      return DocumentSyncResult(failure: _tlsFailure(e));
    } catch (e) {
      return DocumentSyncResult(failure: 'Could not open the documents page: $e');
    }

    if (_looksLikeLogin(listing)) {
      return const DocumentSyncResult(
        failure: 'The DOE document site needs its own sign-in.',
        needsSignIn: true,
      );
    }

    final links = _pdfLinks(listing.body, listing.request?.url);
    if (links.isEmpty) {
      return const DocumentSyncResult(
        failure: 'No documents are posted for you right now.',
      );
    }

    return downloadAll(links, cookies, store);
  }

  /// Downloads, reads and stores each link.
  ///
  /// Shared by the plain HTTP scrape and by the links the WebView finds in the
  /// rendered page, because everything after "here is a URL" is the same.
  Future<DocumentSyncResult> downloadAll(
    List<DocumentLink> links,
    Map<String, String> cookies,
    ArchiveStore store,
  ) async {
    if (links.isEmpty) {
      return const DocumentSyncResult(
        failure: 'No documents are posted for you right now.',
      );
    }

    final saved = <SavedDocument>[];
    final transcript = <TranscriptRecord>[];
    final normalizedTranscripts = <NormalizedTranscript>[];
    var rejected = 0;
    final failures = <String>[];

    for (final link in links.take(maxDocuments)) {
      try {
        final bytes = link.bytes ?? (await _get(link.url, cookies)).bodyBytes;
        if (bytes.isEmpty || bytes.length > maxDocumentBytes) {
          rejected++;
          failures.add('${link.title}: invalid file size (${bytes.length} bytes)');
          continue;
        }
        if (!_isPdf(bytes)) {
          rejected++;
          failures.add('${link.title}: the server returned a web page instead of a PDF');
          continue;
        }

        final text = _extractor.extract(bytes);

        // The document is stored whether or not its text could be read.
        final document = await store.saveDocument(
          title: link.title,
          sourceUrl: link.url.toString(),
          bytes: bytes,
          kind: link.kind,
          textExtracted: text.reliable,
        );
        if (document != null) {
          saved.add(document);
          if (text.text.trim().isNotEmpty) {
            await store.saveDocumentText(document.id, text.text);
          }
        }

        if (text.reliable && link.kind == 'transcript') {
          transcript.addAll(_transcriptParser.parse(text.lines));
          final parsed = _normalizedTranscriptParser.parse(
            rawText: text.text,
            sourceFileName: link.title,
            sourceDocumentId: document?.id,
            importedAt: document?.savedAt,
          );
          if (parsed.canSave) {
            normalizedTranscripts.add(parsed.transcript);
          }
        }
      } catch (error) {
        rejected++;
        failures.add('${link.title}: $error');
        continue;
      }
    }

    if (saved.isEmpty) {
      return DocumentSyncResult(
        failure: rejected > 0
            ? 'Found $rejected document${rejected == 1 ? '' : 's'}, but none '
                'could be saved. ${failures.take(2).join(' ')}'
            : 'No documents are posted for you right now.',
      );
    }
    return DocumentSyncResult(
      saved: saved,
      transcript: _deduplicate(transcript),
      normalizedTranscripts: normalizedTranscripts,
    );
  }

  /// The DOE document site negotiates TLS 1.2 with no forward secrecy, which
  /// iOS refuses by default. The app ships an App Transport Security
  /// exception for it; if this still fires, that exception did not make it
  /// into the build.
  static String _tlsFailure(Object error) =>
      'The secure connection to the DOE document site failed. '
      'Its server uses an older TLS configuration ($error).';

  Future<http.Response> _get(Uri uri, Map<String, String> cookies) async {
    if (!PortalHosts.isAllowed(uri.host) || uri.scheme != 'https') {
      throw PortalUnreachableException('Refusing to follow $uri');
    }
    final response = await _client
        .get(uri, headers: _headers(cookies, uri.host))
        .timeout(
          timeout,
          onTimeout: () => throw PortalUnreachableException(
            'The DOE site did not respond in ${timeout.inSeconds}s.',
          ),
        );
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AuthExpiredException('Session expired');
    }
    if (response.statusCode >= 500) {
      throw PortalUnreachableException('DOE error ${response.statusCode}');
    }
    return response;
  }

  bool _looksLikeLogin(http.Response response) {
    final type = response.headers['content-type'] ?? '';
    if (!type.contains('html')) return false;
    final body = response.body.toLowerCase();
    return body.contains('type="password"') || body.contains("type='password'");
  }

  static bool _isPdf(List<int> bytes) =>
      bytes.length > 4 &&
      bytes[0] == 0x25 && // %
      bytes[1] == 0x50 && // P
      bytes[2] == 0x44 && // D
      bytes[3] == 0x46; //  F

  /// Every link on the page that leads to a document, with a readable title
  /// and a guess at what kind of document it is.
  List<DocumentLink> _pdfLinks(String html, Uri? pageUrl) {
    final base = pageUrl ?? Uri.parse(documentsUrl);
    final document = html_parser.parse(html);
    final out = <DocumentLink>[];
    final seen = <String>{};

    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#')) continue;

      final text = anchor.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final haystack = '$href $text'.toLowerCase();

      final looksLikeDocument = href.toLowerCase().contains('.pdf') ||
          haystack.contains('transcript') ||
          haystack.contains('report card') ||
          haystack.contains('progress report') ||
          haystack.contains('document');
      if (!looksLikeDocument) continue;

      final url = base.resolve(href);
      if (!PortalHosts.isAllowed(url.host) || url.scheme != 'https') continue;
      if (!seen.add(url.toString())) continue;

      out.add(DocumentLink(
        url: url,
        title: text.isEmpty ? titleFromUrl(url) : text,
        kind: kindOf(haystack),
      ));
    }
    return out;
  }

  static String titleFromUrl(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? 'Document' : segments.last;
  }

  static String kindOf(String haystack) {
    if (haystack.contains('transcript')) return 'transcript';
    if (haystack.contains('schedule') || haystack.contains('program card')) {
      return 'schedule';
    }
    if (haystack.contains('report card')) return 'report card';
    if (haystack.contains('progress')) return 'progress report';
    return 'document';
  }

  /// The same course can appear on several documents; keep one of each.
  static List<TranscriptRecord> _deduplicate(List<TranscriptRecord> records) {
    final seen = <String>{};
    final out = <TranscriptRecord>[];
    for (final r in records) {
      final key = '${r.term}|${r.courseTitle}|${r.letterGrade}|${r.finalScore}';
      if (seen.add(key)) out.add(r);
    }
    return out;
  }

  void dispose() => _client.close();
}

/// A document the app has found a URL for, wherever it was found.
class DocumentLink {
  final Uri url;
  final String title;
  final String kind;
  final Uint8List? bytes;

  const DocumentLink({
    required this.url,
    required this.title,
    required this.kind,
    this.bytes,
  });

  factory DocumentLink.captured({
    required Uri sourceUrl,
    required String title,
    required Uint8List bytes,
    required String captureId,
  }) {
    final safeSource = PortalHosts.isAllowed(sourceUrl.host)
        ? sourceUrl
        : Uri.parse(DocumentService.documentsUrl);
    final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final url = safeSource.replace(fragment: 'gradly-capture-$captureId');
    return DocumentLink(
      url: url,
      title: clean.isEmpty ? 'DOE document.pdf' : clean,
      kind: DocumentService.kindOf('$safeSource $clean'.toLowerCase()),
      bytes: bytes,
    );
  }

  /// Builds one from what the in-page scan reported, dropping anything that
  /// points off DOE property.
  static DocumentLink? from(String url, String title) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https') return null;
    if (!PortalHosts.isAllowed(uri.host)) return null;
    final clean = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    return DocumentLink(
      url: uri,
      title: clean.isEmpty ? DocumentService.titleFromUrl(uri) : clean,
      kind: DocumentService.kindOf('$url $clean'.toLowerCase()),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DocumentLink && other.url == url;

  @override
  int get hashCode => url.hashCode;
}
