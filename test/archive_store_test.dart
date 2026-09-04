import 'dart:io';

import 'package:doe_improved/models/archive_models.dart';
import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/models/portal_snapshot.dart';
import 'package:doe_improved/models/schedule_models.dart';
import 'package:doe_improved/storage/archive_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;
  late ArchiveStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('gradly_archive_test');
    store = ArchiveStore(rootOverride: root);
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  PortalSnapshot snapshot({
    List<Course> courses = const [],
    List<TranscriptRecord> transcript = const [],
    DataSource source = DataSource.live,
    DateTime? at,
  }) =>
      PortalSnapshot(
        profile: const StudentProfile(
          name: 'Amara Okonkwo',
          schoolName: 'Bronx Science',
          avatarUrl: '',
          overallGpa: 3.6,
          gpaChange: 0.1,
          totalCredits: 30,
          classRank: 8,
        ),
        courses: courses,
        schedule: DaySchedule.unavailable(DateTime(2026, 9, 4)),
        transcript: transcript,
        work: const [],
        syncedAt: at ?? DateTime(2026, 9, 4, 10, 30),
        source: source,
      );

  Course course(String title, {double score = 91, String letter = 'A'}) =>
      Course(
        id: title,
        title: title,
        code: 'X-1',
        teacherName: 'Ms. Okafor',
        currentScore: score,
        letterGrade: letter,
        categories: const [
          GradeCategory(
            name: 'Tests',
            weightPercentage: 100,
            earnedPoints: 91,
            totalPoints: 100,
          ),
        ],
        assignments: const [],
      );

  TranscriptRecord record(String title, {String term = 'Fall 2024'}) =>
      TranscriptRecord(
        courseTitle: title,
        courseCode: 'M41',
        finalScore: 95,
        letterGrade: 'A',
        creditsEarned: 1,
        term: term,
        gpaPoints: 4,
      );

  group('offline cache', () {
    test('a snapshot survives a round trip through disk', () async {
      final original = snapshot(
        courses: [course('AP Calculus BC')],
        transcript: [record('Geometry Honors')],
      );
      await store.saveSnapshot(original);

      final restored = await store.readSnapshot();
      expect(restored, isNotNull);
      expect(restored!.profile.name, 'Amara Okonkwo');
      expect(restored.courses.single.title, 'AP Calculus BC');
      expect(restored.courses.single.categories.single.name, 'Tests');
      expect(restored.transcript.single.term, 'Fall 2024');
      expect(restored.syncedAt, original.syncedAt);
    });

    test('no cache yet reads as null rather than throwing', () async {
      expect(await store.readSnapshot(), isNull);
    });

    test('a corrupt cache is discarded, not surfaced', () async {
      await store.saveSnapshot(snapshot(courses: [course('X')]));
      final file = File('${root.path}/cache/snapshot.json');
      await file.writeAsString('{ this is not json');
      expect(await store.readSnapshot(), isNull);
    });

    test('clearing the cache leaves the archive alone', () async {
      await store.saveSnapshot(snapshot(courses: [course('X')]));
      await store.recordReport(
        ArchivedReport.fromSnapshot(snapshot(courses: [course('X')])),
      );

      await store.clearSnapshot();

      expect(await store.readSnapshot(), isNull);
      expect(await store.listReports(), hasLength(1));
    });
  });

  group('dated reports', () {
    test('records a report and reads it back', () async {
      final written = await store.recordReport(
        ArchivedReport.fromSnapshot(
          snapshot(
            courses: [course('AP Physics C', score: 88, letter: 'B')],
            transcript: [record('Geometry Honors')],
          ),
          term: 'Fall 2024',
        ),
      );
      expect(written, isTrue);

      final list = await store.listReports();
      expect(list, hasLength(1));
      expect(list.single.id, '2026-09-04');
      expect(list.single.courseCount, 1);
      expect(list.single.transcriptCount, 1);
      expect(list.single.term, 'Fall 2024');

      final report = await store.readReport('2026-09-04');
      expect(report!.courses.single.title, 'AP Physics C');
      expect(report.courses.single.letterGrade, 'B');
    });

    test('an unchanged report on the same day is not rewritten', () async {
      final report = ArchivedReport.fromSnapshot(
        snapshot(courses: [course('AP Calculus BC')]),
      );
      expect(await store.recordReport(report), isTrue);
      expect(await store.recordReport(report), isFalse,
          reason: 'a refresh every five minutes must not rewrite the file');
      expect(await store.listReports(), hasLength(1));
    });

    test('a changed grade on the same day replaces the report', () async {
      await store.recordReport(ArchivedReport.fromSnapshot(
        snapshot(courses: [course('AP Calculus BC', score: 88, letter: 'B')]),
      ));
      final changed = await store.recordReport(ArchivedReport.fromSnapshot(
        snapshot(courses: [course('AP Calculus BC', score: 94, letter: 'A')]),
      ));

      expect(changed, isTrue);
      expect(await store.listReports(), hasLength(1), reason: 'one per day');
      final report = await store.readReport('2026-09-04');
      expect(report!.courses.single.letterGrade, 'A');
    });

    test('reports come back newest first', () async {
      for (final day in [2, 5, 3]) {
        await store.recordReport(ArchivedReport.fromSnapshot(
          snapshot(
            courses: [course('C$day')],
            at: DateTime(2026, 9, day),
          ),
        ));
      }
      final ids = (await store.listReports()).map((m) => m.id).toList();
      expect(ids, ['2026-09-05', '2026-09-03', '2026-09-02']);
    });

    test('an empty report is not worth saving', () async {
      expect(await store.recordReport(ArchivedReport.fromSnapshot(snapshot())),
          isFalse);
      expect(await store.listReports(), isEmpty);
    });

    test('deleting a report removes it', () async {
      await store.recordReport(
        ArchivedReport.fromSnapshot(snapshot(courses: [course('X')])),
      );
      await store.deleteReport('2026-09-04');
      expect(await store.listReports(), isEmpty);
    });
  });

  group('latestTranscript', () {
    test('finds the most recent saved transcript', () async {
      await store.recordReport(ArchivedReport.fromSnapshot(
        snapshot(
          courses: [course('A')],
          transcript: [record('Geometry Honors', term: 'Fall 2023')],
          at: DateTime(2026, 5, 1),
        ),
      ));
      // A later day where the portal had taken the transcript down.
      await store.recordReport(ArchivedReport.fromSnapshot(
        snapshot(courses: [course('B')], at: DateTime(2026, 9, 4)),
      ));

      final remembered = await store.latestTranscript();
      expect(remembered, hasLength(1));
      expect(remembered.single.courseTitle, 'Geometry Honors');
      expect(remembered.single.term, 'Fall 2023');
    });

    test('is empty when nothing was ever saved', () async {
      expect(await store.latestTranscript(), isEmpty);
    });
  });

  group('documents', () {
    test('saves a file and indexes it', () async {
      final doc = await store.saveDocument(
        title: 'Official Transcript',
        sourceUrl: 'https://www.nycenet.edu/studentdocument/1',
        bytes: List<int>.filled(2048, 0x41),
        kind: 'transcript',
        textExtracted: true,
      );

      expect(doc, isNotNull);
      expect(doc!.kind, 'transcript');
      expect(doc.bytes, 2048);

      final list = await store.listDocuments();
      expect(list, hasLength(1));
      expect(list.single.title, 'Official Transcript');
      expect(await store.documentFile(doc.id), isNotNull);
    });

    test('re-downloading the same document replaces it', () async {
      for (var i = 0; i < 3; i++) {
        await store.saveDocument(
          title: 'Official Transcript',
          sourceUrl: 'https://www.nycenet.edu/studentdocument/1',
          bytes: List<int>.filled(10, 0x41),
          kind: 'transcript',
        );
      }
      expect(await store.listDocuments(), hasLength(1));
    });
  });

  group('housekeeping', () {
    test('clearAll wipes everything', () async {
      await store.saveSnapshot(snapshot(courses: [course('X')]));
      await store.recordReport(
        ArchivedReport.fromSnapshot(snapshot(courses: [course('X')])),
      );
      await store.saveDocument(
        title: 'T',
        sourceUrl: 'https://www.nycenet.edu/x',
        bytes: [1, 2, 3],
        kind: 'transcript',
      );

      expect(await store.totalBytes(), greaterThan(0));
      await store.clearAll();

      expect(await store.readSnapshot(), isNull);
      expect(await store.listReports(), isEmpty);
      expect(await store.listDocuments(), isEmpty);
    });

    test('formatBytes is readable at each scale', () {
      expect(ArchiveStore.formatBytes(512), '512 B');
      expect(ArchiveStore.formatBytes(2048), '2 KB');
      expect(ArchiveStore.formatBytes(3 * 1024 * 1024), '3.0 MB');
    });
  });
}
