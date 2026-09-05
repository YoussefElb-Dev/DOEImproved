import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:doe_improved/models/normalized_transcript.dart';
import 'package:doe_improved/services/transcript/normalized_transcript_parser.dart';
import 'package:doe_improved/services/transcript/transcript_analytics.dart';
import 'package:doe_improved/services/transcript/transcript_import_service.dart';
import 'package:doe_improved/storage/transcript_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const transcriptText = '''
OFFICIAL TRANSCRIPT
School: Example State University
Student Name: Jordan Rivera
Student ID: 123456789
Date of Birth: 2007-03-14
Issue Date: 2026-06-20
Program: College Preparatory
Degree Sought: High School Diploma
Major: Computer Science
Catalog Year: 2024
Credits Required: 44
Credit System: Semester Hours
Grading Scale A = 4.0 B = 3.0 C = 2.0 D = 1.0 F = 0.0
Fall 2024
MAT101 Calculus Honors A 3 3 4 12
ENG201 World Literature B 3 3 3 9
HED100 Wellness P 1 1
Term GPA: 3.5
Credits Earned: 7
Academic Standing: Good Standing
Dean's List
Spring 2025
CSC120 Programming A 4 4 4 16
HIS210 World History W 3 0
Cumulative Credits Attempted: 14
Cumulative Credits Earned: 11
Cumulative GPA: 3.7
Degree Awarded: High School Diploma
Conferral Date: 2026-06-26
Magna Cum Laude
''';

  group('normalized parser and schema', () {
    test('extracts labelled, term, course and cumulative fields', () {
      final result = const NormalizedTranscriptParser().parse(
        rawText: transcriptText,
        sourceFileName: 'transcript.pdf',
      );

      expect(result.canSave, isTrue);
      expect(result.transcript.student.name, 'Jordan Rivera');
      expect(result.transcript.student.studentId, '123456789');
      expect(result.transcript.institution.name, 'Example State University');
      expect(result.transcript.officialStatus, OfficialStatus.official);
      expect(result.transcript.creditSystem, CreditSystem.semester);
      expect(result.transcript.program.majors, ['Computer Science']);
      expect(result.transcript.terms, hasLength(2));
      expect(result.transcript.courseCount, 5);
      expect(result.transcript.terms.first.courses.first.flags.honors, isTrue);
      expect(result.transcript.terms.last.courses.last.flags.withdrawn, isTrue);
      expect(result.transcript.cumulative.cumulativeGpa, 3.7);
      expect(result.transcript.degrees.single.degree, 'High School Diploma');
      expect(result.transcript.rawText, contains('Jordan Rivera'));
      expect(result.transcript.gradingScale, isNotEmpty);
    });

    test('round trips and migrates schema version one', () {
      final parsed = const NormalizedTranscriptParser().parse(
        rawText: transcriptText,
        sourceFileName: 'transcript.pdf',
      ).transcript;
      final restored = NormalizedTranscript.fromJson(parsed.toJson());
      expect(restored.student.studentId, parsed.student.studentId);
      expect(restored.courseCount, parsed.courseCount);

      final old = Map<String, dynamic>.from(parsed.toJson())
        ..['schemaVersion'] = 1
        ..remove('repeatPolicy')
        ..remove('degrees');
      final migrated = NormalizedTranscript.fromJson(old);
      expect(migrated.schemaVersion, currentTranscriptSchemaVersion);
      expect(migrated.repeatPolicy, RepeatPolicy.unknown);
      expect(migrated.degrees, isEmpty);
    });
  });

  group('GPA analytics', () {
    test('excludes pass/fail and withdrawals and flags stated mismatch', () {
      final transcript = const NormalizedTranscriptParser().parse(
        rawText: transcriptText,
        sourceFileName: 'transcript.pdf',
      ).transcript;
      final audit = const TranscriptAnalytics().audit(transcript);

      expect(audit.gpaCredits, 10);
      expect(audit.qualityPoints, 37);
      expect(audit.computed, closeTo(3.7, .001));
      expect(audit.mismatched, isFalse);
      expect(audit.excludedCourses, contains('Wellness'));
      expect(audit.excludedCourses, contains('World History'));
    });

    test('converts scales, quarter credits and calculates a target', () {
      const analytics = TranscriptAnalytics();
      final converted = analytics.convert(3.2);
      expect(converted.fivePoint, closeTo(4, .001));
      expect(converted.fourThreePoint, closeTo(3.44, .001));
      expect(analytics.semesterCredits(9, CreditSystem.quarter), 6);

      final result = analytics.whatIf(
        currentGpa: 3,
        currentGpaCredits: 30,
        remainingCredits: 30,
        targetGpa: 3.5,
      );
      expect(result.reachable, isTrue);
      expect(result.requiredGpa, 4);
    });
  });

  group('import pipeline', () {
    test('reads bytes before returning a review draft and logs each boundary',
        () async {
      final bytes = _pdf(transcriptText);
      final stages = <TranscriptImportStage>[];
      final draft = await TranscriptImportService(
        source: _FakeSource(bytes),
      ).pickAndParse(onLog: (entry) => stages.add(entry.stage));

      expect(draft, isNotNull);
      expect(draft!.transcript.courseCount, 5);
      expect(draft.sourceBytes, bytes);
      expect(stages, containsAllInOrder([
        TranscriptImportStage.picker,
        TranscriptImportStage.fileHandle,
        TranscriptImportStage.bytesRead,
        TranscriptImportStage.parse,
        TranscriptImportStage.normalize,
        TranscriptImportStage.validate,
        TranscriptImportStage.review,
      ]));
    });

    test('surfaces an image-only PDF instead of silently saving', () async {
      final service = TranscriptImportService(source: _FakeSource(_pdf('')));
      await expectLater(
        service.pickAndParse(),
        throwsA(
          isA<TranscriptImportException>().having(
            (error) => error.userMessage,
            'message',
            contains('image scan'),
          ),
        ),
      );
    });
  });

  group('local transcript store', () {
    late Directory root;
    late TranscriptStore store;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('gradly_transcripts');
      store = TranscriptStore(directoryProvider: () async => root);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('saves raw PDF and updates the same student/institution in place',
        () async {
      final first = const NormalizedTranscriptParser().parse(
        rawText: transcriptText,
        sourceFileName: 'first.pdf',
      ).transcript;
      await store.save(first, sourceBytes: _pdf(transcriptText));

      final updatedText = transcriptText
          .replaceFirst('Spring 2025', 'Spring 2025\nART110 Studio Art A 2 2 4 8');
      final updated = const NormalizedTranscriptParser().parse(
        rawText: updatedText,
        sourceFileName: 'second.pdf',
      ).transcript;
      await store.save(updated, sourceBytes: _pdf(updatedText));

      final records = await store.list();
      expect(records, hasLength(1));
      expect(records.single.courseCount, 6);
      expect(root.listSync().whereType<File>().any((f) => f.path.endsWith('.pdf')), isTrue);
    });

    test('keeps another institution as a second merged-view record', () async {
      final first = const NormalizedTranscriptParser().parse(
        rawText: transcriptText,
        sourceFileName: 'first.pdf',
      ).transcript;
      final second = const NormalizedTranscriptParser().parse(
        rawText: transcriptText.replaceFirst(
          'Example State University',
          'Other Community College',
        ),
        sourceFileName: 'other.pdf',
      ).transcript;
      await store.save(first);
      await store.save(second);

      expect(await store.list(), hasLength(2));
    });

    test('exports parseable JSON and quoted CSV', () {
      final transcript = const NormalizedTranscriptParser().parse(
        rawText: transcriptText,
        sourceFileName: 'transcript.pdf',
      ).transcript;
      expect(jsonDecode(store.exportJson(transcript)), isA<Map>());
      expect(store.exportCsv(transcript), contains('"student_id"'));
      expect(store.exportCsv(transcript), contains('"123456789"'));
      expect(store.exportCsv(transcript), contains('"Calculus Honors"'));
    });
  });
}

class _FakeSource implements TranscriptFileSource {
  const _FakeSource(this.bytes);

  final Uint8List bytes;

  @override
  Future<PickedTranscriptFile?> pickPdf() async => PickedTranscriptFile(
        name: 'transcript.pdf',
        bytes: bytes,
        size: bytes.length,
      );
}

Uint8List _pdf(String text) {
  final escaped = text
      .replaceAll(r'\', r'\\')
      .replaceAll('(', r'\(')
      .replaceAll(')', r'\)');
  final operators = escaped
      .split('\n')
      .where((line) => line.trim().isNotEmpty)
      .map((line) => 'BT /F1 10 Tf 72 700 Td ($line) Tj ET')
      .join('\n');
  final body = latin1.encode(operators);
  return Uint8List.fromList([
    ...latin1.encode('%PDF-1.4\n1 0 obj\n<< /Length ${body.length} >>\nstream\n'),
    ...body,
    ...latin1.encode('\nendstream\nendobj\n%%EOF\n'),
  ]);
}
