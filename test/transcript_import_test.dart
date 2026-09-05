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

  const nycTranscriptText = '''
NYC Department Of Educationa
Student Transcript
Name / ID   :STUDENT, TEST /  000000000
Address :1 TEST STREET NEW YORK NY
10001
Ofcl :000 Grade Level :11Status :A
Admit Date :10/25/2023 Discharge Date :
DOB :01/01/2009 Graduation Date :
2025/ Term 2 Actual
27Q309AES22 DRAWING 2 OF 2 90 90 1.00/1.00
27Q309EES86QA ENGLISH 11 CC 2 OF 2 88 88 1.00/1.00
27Q309HUS22 US HISTORY 2 OF 2 82 82 1.00/1.00
27Q309MQS42QEMATH FOR HEALTH PROF 92 92 0.50/0.50
27Q309MRS22QAECC ALGEBRA 2 2 OF 2 92 92 2.00/2.00
27Q309PFSA6 PHYS ED 6 OF 8 11TH 95* 95 0.58/0.58
27Q309SCS22 CHEMISTRY 2 OF 2 96 96 1.00/1.00
27Q309SCS22QL CHEMISTRY LAB 2 OF 2 P* 0.00/0.00
Term Avg :90.15% Term : Actual Credits / Credits Earned : 7.08 / 7.08
Term Credits Averaged :6.50
2025/ Term 1 Actual
27Q309AES21 DRAWING 1 OF 2 90 90 1.00/1.00
27Q309EES85QA ENGLISH 11 CC 1 OF 2 94 94 1.00/1.00
27Q309HUS21 US HISTORY 1 OF 2 92 92 1.00/1.00
27Q309MQS41QEMATH FOR HEALTH PROF 92 92 0.50/0.50
27Q309MRS21QAECC ALGEBRA 2 1 OF 2 92 92 2.00/2.00
27Q309PFSA5 PHYS ED 5 OF 8 11TH 95* 95 0.58/0.58
27Q309SCS21 CHEMISTRY 1 OF 2 94 94 1.00/1.00
27Q309SCS21QL CHEMISTRY LAB 1 OF 2 P* 0.00/0.00
Term Avg :92.31% Term : Actual Credits / Credits Earned : 7.08 / 7.08
Term Credits Averaged :6.50
2024/ Term 2 Actual
27Q309EES84 ENGLISH 10 2 OF 2 90 90 1.00/1.00
27Q309FSS62 SPANISH I 2 OF 2 97 97 1.00/1.00
27Q309HVS11 PART IN GOVT 94 94 1.00/1.00
27Q309MGS22QACC GEOMETRY 2 OF 2 98 98 1.00/1.00
27Q309PFSA4 PHYS ED 4 OF 8 10TH 100* 100 0.58/0.58
27Q309SBS22X** AP BIOLOGY 97 97 1.00/1.00
27Q309SJS22 EARTH AND SPACE SCIE 97 97 1.00/1.00
27Q309SJS22QL EARTH AND SPACE SCIE P* 0.00/0.00
Term Avg :97.12% Term : Actual Credits / Credits Earned : 6.58 / 6.58
Term Credits Averaged :6.00
2024/ Term 1 Actual
27Q309EES83 ENGLISH 10 1 OF 2 95 95 1.00/1.00
27Q309FSS61 SPANISH I 1 OF 2 95 95 1.00/1.00
27Q309HES11 ECONOMICS 88 88 1.00/1.00
27Q309MGS21QACC GEOMETRY 1 OF 2 100 100 1.00/1.00
27Q309PFSA3 PHYS ED 3 OF 8 10TH 100* 100 0.58/0.58
27Q309SBS21X** AP BIOLOGY 100 100 1.00/1.00
27Q309SJS21 EARTH AND SPACE SCIE 100 100 1.00/1.00
27Q309SJS21QL EARTH AND SPACE SCIE P* 0.00/0.00
Term Avg :98.00% Term : Actual Credits / Credits Earned : 6.58 / 6.58
Term Credits Averaged :6.00
2023/ Term 2 Actual
27Q309EES82 ENGLISH 9 2 OF 2 96 96 1.00/1.00
27Q309HGS22QE GLOBAL HISTORY 1 YR 95 95 2.00/2.00
27Q309HQS22QGWORLD CIVICS 2 of 2 95 95 0.50/0.50
27Q309MES22QAECC ALGEBRA 2 of 2 DO 100 100 2.00/2.00
27Q309PFSA2 PHYS ED 2 OF 8 9TH G 99* 99 0.50/0.50
27Q309SLS22 LIVING ENV 2 OF 2 95 95 1.00/1.00
27Q309SLS22QL LIVING ENV LAB 2 OF P* 0.00/0.00
Term Avg :96.69% Term : Actual Credits / Credits Earned : 7.00 / 7.00
Term Credits Averaged :6.50
2023/ Term 1 Actual
27Q309EES81 ENGLISH 9 1 OF 2 100 100 1.00/1.00
27Q309HGS21QE GLOBAL HISTORY 1 YR 96 96 2.00/2.00
27Q309HQS21QGWORLD CIVICS 1 of 2 96 96 0.50/0.50
27Q309MES21QAECC ALGEBRA 1 of 2 DO 98 98 2.00/2.00
27Q309PHS11QA HEALTH AND SAFETY 98 98 1.00/1.00
27Q309SLS21 LIVING ENV 1 OF 2 97 97 1.00/1.00
27Q309SLS21QL LIVING ENV LAB 1 OF P* 0.00/0.00
Term Avg :97.47% Term : Actual Credits / Credits Earned : 7.50 / 7.50
Term Credits Averaged :7.50
Cumulative : Actual Credits / Credits Earned 41.82 / 41.82
Cumulative Average: 95.29% Cumulative Credits Averaged: 39.00
* Not Averaged ** Weighted Courses High School
Page 1 of 1 2026 Copyright NYC Department Of Education 10:00:44 PM July 17, 2026
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

    test('extracts every course and printed average from a NYC transcript', () {
      final parsed = const NormalizedTranscriptParser().parse(
        rawText: nycTranscriptText,
        sourceFileName: 'Transcript.pdf',
      ).transcript;

      expect(parsed.student.name, 'Test Student');
      expect(parsed.student.studentId, '000000000');
      expect(parsed.student.gradeLevel, '11');
      expect(parsed.student.dateOfBirth, DateTime(2009, 1, 1));
      expect(parsed.institution.name, 'NYC Department of Education');
      expect(parsed.issueDate, DateTime(2026, 7, 17));
      expect(parsed.terms, hasLength(6));
      expect(parsed.courseCount, 46);
      expect(parsed.cumulative.creditsEarned, 41.82);
      expect(parsed.cumulative.gpaCredits, 39);
      expect(parsed.cumulative.cumulativeAveragePercent, 95.29);
      expect(parsed.terms.first.statedAveragePercent, 90.15);
      expect(parsed.terms.first.creditsEarned, 7.08);
      expect(
        parsed.terms.expand((term) => term.courses).where((course) => course.flags.weighted),
        hasLength(2),
      );
      expect(
        parsed.terms.first.courses.firstWhere((course) => course.title!.startsWith('Phys Ed')).countsTowardGpa,
        isFalse,
      );
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
