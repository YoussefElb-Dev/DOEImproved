import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doe_improved/services/document_service.dart';
import 'package:doe_improved/services/native_cookie_bridge.dart';
import 'package:doe_improved/storage/archive_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The smallest thing that is still a PDF, carrying [content] as text.
List<int> pdf(String content) {
  final body = latin1.encode(content);
  return [
    ...latin1.encode(
        '%PDF-1.4\n1 0 obj\n<< /Length ${body.length} >>\nstream\n'),
    ...body,
    ...latin1.encode('\nendstream\nendobj\n%%EOF\n'),
  ];
}

void main() {
  late Directory root;
  late ArchiveStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gradly_docs_test');
    store = ArchiveStore(rootOverride: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  const cookies = {'www.nycenet.edu|SESSION': 'abc123'};

  const listingHtml = '''
<html><body>
  <a href="/studentdocument/transcript.pdf">Official Transcript</a>
  <a href="/studentdocument/report.pdf">Report Card - Fall 2024</a>
  <a href="https://example.com/elsewhere.pdf">Somewhere else</a>
  <a href="#top">Back to top</a>
</body></html>''';

  const transcriptPdf = 'BT 72 720 Td (Fall 2024) Tj ET\n'
      'BT 72 700 Td (MAT41) Tj 90 0 Td (Algebra 2 Honors) Tj '
      '200 0 Td (95) Tj 40 0 Td (1.0) Tj ET';

  http.Client routing({
    String listing = listingHtml,
    int listingStatus = 200,
    Map<String, String>? listingHeaders,
  }) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('report.pdf')) {
        return http.Response.bytes(
          pdf('BT 72 700 Td (Report Card) Tj ET'),
          200,
        );
      }
      if (path.contains('transcript.pdf')) {
        return http.Response.bytes(pdf(transcriptPdf), 200);
      }
      return http.Response(
        listing,
        listingStatus,
        headers: listingHeaders ?? const {'content-type': 'text/html'},
      );
    });
  }

  group('sign-in handling', () {
    test('no cookies asks for a sign-in rather than failing silently',
        () async {
      final result =
          await DocumentService(client: routing()).sync(const {}, store);
      expect(result.needsSignIn, isTrue);
      expect(result.saved, isEmpty);
    });

    test('a login page asks for a sign-in, not a full sign-out', () async {
      final service = DocumentService(
        client: routing(
          listing: '<html><body><form>'
              '<input type="password" name="pw"></form></body></html>',
        ),
      );
      final result = await service.sync(cookies, store);

      expect(result.needsSignIn, isTrue);
      expect(result.failure, contains('sign-in'));
    });

    test('a 401 asks for a sign-in', () async {
      final service = DocumentService(
        client: MockClient((_) async => http.Response('', 401)),
      );
      final result = await service.sync(cookies, store);
      expect(result.needsSignIn, isTrue);
    });

    test('a server error is reported without demanding a sign-in', () async {
      final service = DocumentService(
        client: MockClient((_) async => http.Response('boom', 503)),
      );
      final result = await service.sync(cookies, store);

      expect(result.needsSignIn, isFalse);
      expect(result.failure, isNotNull);
    });
  });

  group('downloading', () {
    test('saves each document and records what it is', () async {
      final result = await DocumentService(client: routing())
          .sync(cookies, store);

      expect(result.saved, hasLength(2));
      expect(
        result.saved.map((d) => d.kind).toList(),
        containsAll(<String>['transcript', 'report card']),
      );

      final stored = await store.listDocuments();
      expect(stored, hasLength(2));
      // The file itself is on disk, not just its metadata.
      expect(await store.documentFile(stored.first.id), isNotNull);
    });

    test('reads the transcript out of the PDF', () async {
      final result = await DocumentService(client: routing())
          .sync(cookies, store);

      expect(result.transcript, hasLength(1));
      final record = result.transcript.single;
      expect(record.courseCode, 'MAT41');
      expect(record.courseTitle, 'Algebra 2 Honors');
      expect(record.finalScore, 95);
      expect(record.creditsEarned, 1.0);
      expect(record.term, 'Fall 2024');
    });

    test('keeps the extracted text beside the file', () async {
      final result = await DocumentService(client: routing())
          .sync(cookies, store);

      final transcript =
          result.saved.firstWhere((d) => d.kind == 'transcript');
      final text = await store.readDocumentText(transcript.id);
      expect(text, isNotNull);
      expect(text, contains('Algebra 2 Honors'));
    });

    test('a document that is not a PDF is skipped, not stored', () async {
      final service = DocumentService(
        client: MockClient((request) async {
          if (request.url.path.contains('.pdf')) {
            return http.Response('<html>not a pdf</html>', 200);
          }
          return http.Response(listingHtml, 200,
              headers: const {'content-type': 'text/html'});
        }),
      );
      final result = await service.sync(cookies, store);

      expect(result.saved, isEmpty);
      expect(result.failure, isNotNull);
      expect(await store.listDocuments(), isEmpty);
    });

    test('links off the DOE domain are never followed', () async {
      final requested = <String>[];
      final service = DocumentService(
        client: MockClient((request) async {
          requested.add(request.url.toString());
          if (request.url.path.contains('.pdf')) {
            return http.Response.bytes(pdf('BT (x) Tj ET'), 200);
          }
          return http.Response(listingHtml, 200,
              headers: const {'content-type': 'text/html'});
        }),
      );
      await service.sync(cookies, store);

      expect(
        requested.any((u) => u.contains('example.com')),
        isFalse,
        reason: 'the session cookie must not leave DOE property',
      );
    });

    test('a page with no documents says so', () async {
      final service = DocumentService(
        client: routing(listing: '<html><body><p>Nothing here.</p></body></html>'),
      );
      final result = await service.sync(cookies, store);

      expect(result.saved, isEmpty);
      expect(result.failure, contains('No documents'));
      expect(result.needsSignIn, isFalse);
    });
  });

  group('cookie scoping', () {
    test('each host only receives its own cookies', () {
      const jar = {
        'teachhub.schools.nyc|GRADEBOOK': 'g',
        'www.nycenet.edu|DOCUMENTS': 'd',
      };

      final toDocuments =
          NativeCookieBridge.toHeader(jar, host: 'www.nycenet.edu');
      expect(toDocuments, contains('DOCUMENTS=d'));
      expect(toDocuments, isNot(contains('GRADEBOOK')),
          reason: 'the gradebook session must not leak to the document site');

      final toGradebook =
          NativeCookieBridge.toHeader(jar, host: 'teachhub.schools.nyc');
      expect(toGradebook, contains('GRADEBOOK=g'));
      expect(toGradebook, isNot(contains('DOCUMENTS')));
    });

    test('a cookie on www is still sent to the bare domain', () {
      const jar = {'www.nycenet.edu|SESSION': 'x'};
      expect(
        NativeCookieBridge.toHeader(jar, host: 'nycenet.edu'),
        contains('SESSION=x'),
      );
    });

    test('sessions saved before host scoping still reach the gradebook', () {
      const legacy = {'SESSIONID': 'old'};
      expect(
        NativeCookieBridge.toHeader(legacy, host: 'teachhub.schools.nyc'),
        contains('SESSIONID=old'),
      );
      expect(
        NativeCookieBridge.toHeader(legacy, host: 'www.nycenet.edu'),
        isEmpty,
      );
    });

    test('only DOE hosts are allowed at all', () {
      expect(PortalHosts.isAllowed('teachhub.schools.nyc'), isTrue);
      expect(PortalHosts.isAllowed('www.nycenet.edu'), isTrue);
      expect(PortalHosts.isAllowed('example.com'), isFalse);
      expect(PortalHosts.isAllowed('schools.nyc.evil.com'), isFalse);
    });
  });

  group('DocumentLink.from', () {
    test('keeps DOE links and names them', () {
      final link = DocumentLink.from(
        'https://www.nycenet.edu/studentdocument/file/9921',
        '  Official   Transcript  ',
      );
      expect(link, isNotNull);
      expect(link!.title, 'Official Transcript', reason: 'whitespace collapsed');
      expect(link.kind, 'transcript');
    });

    test('falls back to the URL when the element had no text', () {
      final link = DocumentLink.from(
        'https://www.nycenet.edu/studentdocument/report.pdf',
        '',
      );
      expect(link!.title, 'report.pdf');
    });

    test('infers the kind from the link itself', () {
      expect(
        DocumentLink.from('https://www.nycenet.edu/a/reportcard.pdf', 'Report Card')!.kind,
        'report card',
      );
      expect(
        DocumentLink.from('https://www.nycenet.edu/a/x.pdf', 'Progress Report')!.kind,
        'progress report',
      );
      expect(
        DocumentLink.from('https://www.nycenet.edu/a/x.pdf', 'Something')!.kind,
        'document',
      );
    });

    test('refuses anything off DOE property or not over TLS', () {
      expect(DocumentLink.from('https://example.com/x.pdf', 'Transcript'), isNull);
      expect(DocumentLink.from('http://www.nycenet.edu/x.pdf', 'Transcript'), isNull);
      expect(DocumentLink.from('javascript:void(0)', 'Transcript'), isNull);
      expect(DocumentLink.from('not a url at all', 'Transcript'), isNull);
    });

    test('two links to the same file are the same link', () {
      final a = DocumentLink.from('https://www.nycenet.edu/x.pdf', 'One');
      final b = DocumentLink.from('https://www.nycenet.edu/x.pdf', 'Two');
      expect(a, equals(b), reason: 'a rescan must not duplicate what it found');
    });
  });

  group('downloadAll', () {
    test('saves PDF bytes captured inside the authenticated WebView', () async {
      final bytes = Uint8List.fromList(pdf('Fall 2026\nMAT101 Algebra A 1'));
      final link = DocumentLink.captured(
        sourceUrl: Uri.parse(DocumentService.documentsUrl),
        title: 'Official Transcript',
        bytes: bytes,
        captureId: 'capture-1',
      );
      final client = MockClient((_) async => throw StateError('HTTP must not run'));

      final result = await DocumentService(client: client)
          .downloadAll([link], const {}, store);

      expect(result.saved, hasLength(1));
      expect(result.failure, isNull);
    });

    test('saves the links the page scan turned up', () async {
      final links = [
        DocumentLink.from(
          'https://www.nycenet.edu/studentdocument/transcript.pdf',
          'Official Transcript',
        )!,
      ];
      final result = await DocumentService(client: routing())
          .downloadAll(links, cookies, store);

      expect(result.saved, hasLength(1));
      expect(result.saved.single.kind, 'transcript');
      expect(result.transcript, hasLength(1));
      expect(result.transcript.single.courseTitle, 'Algebra 2 Honors');
    });

    test('an empty list says nothing was posted', () async {
      final result = await DocumentService(client: routing())
          .downloadAll(const [], cookies, store);
      expect(result.saved, isEmpty);
      expect(result.failure, contains('No documents'));
    });

    test('links that are not PDFs suggest tapping one instead', () async {
      final service = DocumentService(
        client: MockClient((_) async => http.Response('<html></html>', 200)),
      );
      final result = await service.downloadAll(
        [DocumentLink.from('https://www.nycenet.edu/x.pdf', 'X')!],
        cookies,
        store,
      );

      expect(result.saved, isEmpty);
      expect(result.failure, contains('returned a web page instead of a PDF'));
    });
  });
}
