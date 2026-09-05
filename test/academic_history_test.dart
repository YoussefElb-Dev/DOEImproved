import 'dart:io';

import 'package:doe_improved/models/academic_history.dart';
import 'package:doe_improved/models/normalized_transcript.dart';
import 'package:doe_improved/models/schedule_models.dart';
import 'package:doe_improved/storage/archive_store.dart';
import 'package:doe_improved/storage/state_providers.dart';
import 'package:doe_improved/storage/transcript_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved transcript courses and official totals become academic history', () {
    final transcript = NormalizedTranscript(
      id: 'record-1',
      sourceFingerprint: 'fingerprint',
      sourceFileName: 'Transcript.pdf',
      importedAt: DateTime(2026, 7, 17),
      rawText: 'transcript text',
      student: const TranscriptStudent(studentId: 'student-1'),
      institution: const TranscriptInstitution(name: 'NYC Public Schools'),
      terms: const [
        NormalizedTerm(
          id: '2024-1',
          label: '2024 Term 1',
          courses: [
            NormalizedCourse(
              id: '27q309eng41',
              subjectCode: 'ENG',
              courseNumber: '41',
              title: 'English 11',
              creditsAttempted: 1,
              creditsEarned: 1,
              numericGrade: 94,
            ),
          ],
        ),
        NormalizedTerm(
          id: '2025-2',
          label: '2025 Term 2',
          courses: [
            NormalizedCourse(
              id: '27q309mat42',
              subjectCode: 'MAT',
              courseNumber: '42',
              title: 'Algebra 2',
              creditsAttempted: 2,
              creditsEarned: 2,
              numericGrade: 97,
              flags: CourseFlags(weighted: true),
            ),
          ],
        ),
      ],
      cumulative: const CumulativeSummary(
        creditsEarned: 41.82,
        cumulativeAveragePercent: 95.29,
      ),
    );

    final history = AcademicHistory.combine(
      normalized: [transcript],
      legacy: const [
        TranscriptRecord(
          courseTitle: 'English 11',
          courseCode: '27Q309ENG41',
          finalScore: 94,
          letterGrade: 'A',
          creditsEarned: 1,
          term: '2024 Term 1',
          gpaPoints: 4,
        ),
      ],
    );

    expect(history.classes, hasLength(2), reason: 'portal duplicates are merged');
    expect(history.classes.first.title, 'Algebra 2', reason: 'newest term is first');
    expect(history.classes.first.displayGrade, '97');
    expect(history.classes.first.weighted, isTrue);
    expect(history.creditsEarned, 41.82, reason: 'the printed cumulative total wins');
    expect(history.cumulativeAveragePercent, 95.29);
    expect(history.transcriptRecords, hasLength(2));
  });

  test('legacy portal rows remain available without a saved transcript', () {
    final history = AcademicHistory.combine(
      legacy: const [
        TranscriptRecord(
          courseTitle: 'Chemistry',
          courseCode: 'SCI43',
          finalScore: 88,
          letterGrade: 'B',
          creditsEarned: 1,
          term: 'Fall 2025',
          gpaPoints: 3,
        ),
      ],
    );

    expect(history.classes.single.title, 'Chemistry');
    expect(history.classes.single.displayGrade, '88 · B');
    expect(history.creditsEarned, 1);
  });

  test('an already-downloaded transcript is normalized on upgrade', () async {
    final root = await Directory.systemTemp.createTemp('gradly_history_test');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final archive = ArchiveStore(rootOverride: root);
    final transcriptStore = TranscriptStore(
      directoryProvider: () async => Directory('${root.path}/transcripts'),
    );
    final document = await archive.saveDocument(
      title: 'Official Transcript',
      sourceUrl: 'https://www.nycenet.edu/studentdocument',
      bytes: const [37, 80, 68, 70, 45, 49, 46, 52],
      kind: 'transcript',
      textExtracted: true,
    );
    expect(document, isNotNull);
    await archive.saveDocumentText(document!.id, '''
OFFICIAL TRANSCRIPT
School: Example High School
Student Name: Test Student
Student ID: 123456789
Fall 2024
MAT101 Algebra I A 1
Cumulative Credits Earned: 1
''');

    final container = ProviderContainer(
      overrides: [
        archiveStoreProvider.overrideWithValue(archive),
        transcriptStoreProvider.overrideWithValue(transcriptStore),
      ],
    );
    addTearDown(container.dispose);

    final records = await container.read(transcriptRecordsProvider.future);
    expect(records, hasLength(1));
    expect(records.single.courseCount, 1);
    expect(records.single.sourceDocumentId, document.id);
    expect(records.single.cumulative.creditsEarned, 1);
  });
}
