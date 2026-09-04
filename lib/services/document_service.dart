import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/archive_models.dart';
import '../models/schedule_models.dart';
import '../storage/archive_store.dart';
import 'grade_data_service.dart';
import 'native_cookie_bridge.dart';
import 'pdf/pdf_text_extractor.dart';
import 'pdf/transcript_text_parser.dart';

/// What one document sync produced.
class DocumentSyncResult {
  final List<SavedDocument> saved;
  final List<TranscriptRecord> transcript;
  final String? failure;

  const DocumentSyncResult({
    this.saved = const [],
    this.transcript = const [],
    this.failure,
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

  DocumentService({
    http.Client? client,
    PdfTextExtractor? extractor,
    TranscriptTextParser? transcriptParser,
  })  : _client = client ?? http.Client(),
        _extractor = extractor ?? const PdfTextExtractor(),
        _transcriptParser = transcriptParser ?? const TranscriptTextParser();

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
      return const DocumentSyncResult(failure: 'Not signed in.');
    }

    final http.Response listing;
    try {
      listing = await _get(Uri.parse(documentsUrl), cookies);
    } on AuthExpiredException {
      rethrow;
    } catch (e) {
      return DocumentSyncResult(failure: 'Could not open the documents page: $e');
    }

    if (_looksLikeLogin(listing)) {
      throw const AuthExpiredException('Session expired');
    }

    final links = _pdfLinks(listing.body, listing.request?.url);
    if (links.isEmpty) {
      return const DocumentSyncResult(
        failure: 'No documents are posted for you right now.',
      );
    }

    final saved = <SavedDocument>[];
    final transcript = <TranscriptRecord>[];

    for (final link in links.take(maxDocuments)) {
      try {
        final response = await _get(link.url, cookies);
        final bytes = response.bodyBytes;
        if (bytes.isEmpty || bytes.length > maxDocumentBytes) continue;
        if (!_isPdf(bytes)) continue;

        final text = _extractor.extract(bytes);

        // The document is stored whether or not its text could be read.
        final document = await store.saveDocument(
          title: link.title,
          sourceUrl: link.url.toString(),
          bytes: bytes,
          kind: link.kind,
          textExtracted: text.reliable,
        );
        if (document != null) saved.add(document);

        if (text.reliable && link.kind == 'transcript') {
          transcript.addAll(_transcriptParser.parse(text.lines));
        }
      } catch (_) {
        // One unreadable document must not stop the rest.
        continue;
      }
    }

    if (saved.isEmpty) {
      return const DocumentSyncResult(
        failure: 'Found links, but none of them returned a readable PDF.',
      );
    }
    return DocumentSyncResult(
      saved: saved,
      transcript: _deduplicate(transcript),
    );
  }

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
  List<_DocumentLink> _pdfLinks(String html, Uri? pageUrl) {
    final base = pageUrl ?? Uri.parse(documentsUrl);
    final document = html_parser.parse(html);
    final out = <_DocumentLink>[];
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

      out.add(_DocumentLink(
        url: url,
        title: text.isEmpty ? _titleFromUrl(url) : text,
        kind: _kindOf(haystack),
      ));
    }
    return out;
  }

  static String _titleFromUrl(Uri url) {
    final segments = url.pathSegments.where((s) => s.isNotEmpty);
    return segments.isEmpty ? 'Document' : segments.last;
  }

  static String _kindOf(String haystack) {
    if (haystack.contains('transcript')) return 'transcript';
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

class _DocumentLink {
  final Uri url;
  final String title;
  final String kind;

  const _DocumentLink({
    required this.url,
    required this.title,
    required this.kind,
  });
}
