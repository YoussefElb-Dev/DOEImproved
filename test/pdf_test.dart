import 'dart:convert';
import 'dart:io';

import 'package:doe_improved/services/pdf/pdf_text_extractor.dart';
import 'package:doe_improved/services/pdf/transcript_text_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps a content stream in the smallest thing that is still a PDF.
List<int> pdfWith(String content, {bool compress = false}) {
  final body = compress
      ? ZLibCodec().encode(latin1.encode(content))
      : latin1.encode(content);
  final filter = compress ? ' /Filter /FlateDecode' : '';

  return [
    ...latin1.encode('%PDF-1.4\n1 0 obj\n<< /Length ${body.length}$filter >>\n'
        'stream\n'),
    ...body,
    ...latin1.encode('\nendstream\nendobj\n%%EOF\n'),
  ];
}

void main() {
  const extractor = PdfTextExtractor();
  const parser = TranscriptTextParser();

  group('PdfTextExtractor', () {
    test('reads a single line of text', () {
      final pdf = pdfWith('BT /F1 12 Tf 72 720 Td (Official Transcript) Tj ET');
      final result = extractor.extract(pdf);

      expect(result.reliable, isTrue);
      expect(result.text, contains('Official Transcript'));
    });

    test('reads a compressed content stream', () {
      final pdf = pdfWith(
        'BT /F1 12 Tf 72 720 Td (Compressed Transcript) Tj ET',
        compress: true,
      );
      final result = extractor.extract(pdf);

      expect(result.reliable, isTrue);
      expect(result.text, contains('Compressed Transcript'));
    });

    test('a move down the page starts a new row', () {
      final pdf = pdfWith(
        'BT /F1 12 Tf 72 720 Td (Fall 2024) Tj ET\n'
        'BT /F1 12 Tf 72 700 Td (Spring 2025) Tj ET',
      );
      final lines = extractor.extract(pdf).lines;

      expect(lines, contains('Fall 2024'));
      expect(lines, contains('Spring 2025'));
    });

    test('a move across the page keeps cells on one row', () {
      // How a table is drawn: one text run per cell, same baseline.
      final pdf = pdfWith(
        'BT /F1 12 Tf 72 700 Td (MAT41) Tj 90 0 Td (Algebra 2 Honors) Tj '
        '200 0 Td (95) Tj ET',
      );
      final lines = extractor.extract(pdf).lines;

      expect(lines, hasLength(1),
          reason: 'a table row must not become three lines');
      expect(lines.single, 'MAT41 Algebra 2 Honors 95');
    });

    test('reads TJ arrays and treats wide kerning as a space', () {
      final pdf = pdfWith(
        r'BT /F1 12 Tf 72 700 Td [(ENG) -400 (201)] TJ ET',
      );
      expect(extractor.extract(pdf).text, contains('ENG 201'));
    });

    test('decodes escapes and hex strings', () {
      final pdf = pdfWith(
        r'BT 72 700 Td (Smith\, John \(Grade 11\)) Tj ET' '\n'
        'BT 72 680 Td <48656C6C6F> Tj ET',
      );
      final text = extractor.extract(pdf).text;

      expect(text, contains('Smith, John (Grade 11)'));
      expect(text, contains('Hello'));
    });

    test('refuses things that are not PDFs', () {
      final result = extractor.extract(latin1.encode('just some text'));
      expect(result.reliable, isFalse);
      expect(result.failure, contains('Not a PDF'));
    });

    test('reports an encrypted file rather than guessing', () {
      final pdf = [
        ...latin1.encode('%PDF-1.4\n<< /Encrypt 5 0 R >>\n'),
        ...pdfWith('BT (x) Tj ET').skip(9),
      ];
      final result = extractor.extract(pdf);
      expect(result.reliable, isFalse);
      expect(result.failure, contains('encrypted'));
    });

    test('an image-only page is reported, not returned as empty text', () {
      final pdf = pdfWith('');
      final result = extractor.extract(pdf);
      expect(result.reliable, isFalse);
      expect(result.failure, isNotNull);
    });

    test('empty input does not throw', () {
      expect(() => extractor.extract(const []), returnsNormally);
    });
  });

  group('TranscriptTextParser', () {
    test('reads course rows under a term heading', () {
      final records = parser.parse([
        'Official Transcript',
        'Fall 2024',
        'MAT41 Algebra 2 Honors 95 1.0',
        'ENS41 English 11 88 1.0',
        'Spring 2025',
        'SCI43 Chemistry 91 1.0',
      ]);

      expect(records, hasLength(3));
      expect(records[0].courseCode, 'MAT41');
      expect(records[0].courseTitle, 'Algebra 2 Honors');
      expect(records[0].finalScore, 95);
      expect(records[0].letterGrade, 'A');
      expect(records[0].creditsEarned, 1.0);
      expect(records[0].term, 'Fall 2024');
      expect(records[2].term, 'Spring 2025');
    });

    test('keeps non-numeric marks and scores them correctly', () {
      final records = parser.parse([
        'Fall 2024',
        'HED21 Health Education P 0.5',
        'ART11 Studio Art NS 0',
      ]);

      expect(records, hasLength(2));
      expect(records[0].letterGrade, 'P');
      expect(records[0].creditsEarned, 0.5);
      expect(records[0].gpaPoints, 0, reason: 'a pass carries no GPA points');
      expect(records[1].letterGrade, 'NS');
      expect(records[1].gpaPoints, 0);
    });

    test('reads a letter grade with no percentage', () {
      final records = parser.parse(['Fall 2024', 'ENG201 World Literature A- 1.0']);
      expect(records.single.letterGrade, 'A-');
      expect(records.single.gpaPoints, closeTo(3.7, 0.001));
    });

    test('shouting titles are calmed down', () {
      final records = parser.parse(['Fall 2024', 'MAT41 ALGEBRA 2 HONORS 95 1.0']);
      expect(records.single.courseTitle, 'Algebra 2 Honors');
    });

    test('column headings are not read as courses', () {
      final records = parser.parse([
        'Course Description Mark Credits',
        'Student Name School',
      ]);
      expect(records, isEmpty);
    });

    test('summary lines are not read as courses', () {
      final records = parser.parse([
        'Fall 2024',
        'Total Credits Earned 44.5',
        'Cumulative GPA 3.87',
      ]);
      expect(records, isEmpty);
    });

    test('a row with no mark at all is skipped', () {
      expect(parser.parse(['Fall 2024', 'MAT41 Algebra 2 Honors']), isEmpty);
    });

    test('numbered marking periods are recognised as terms', () {
      final records = parser.parse(['MP2', 'MAT41 Algebra 2 90 1.0']);
      expect(records.single.term, 'MP2');
    });

    test('malformed input does not throw', () {
      expect(() => parser.parse(['', '   ', '!!!', '1 2 3']), returnsNormally);
    });
  });
}
