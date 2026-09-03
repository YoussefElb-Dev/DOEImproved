import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/models/portal_snapshot.dart';
import 'package:doe_improved/models/schedule_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const profile = StudentProfile(
    name: 'Test Student',
    schoolName: 'Test HS',
    avatarUrl: '',
    overallGpa: 2.00,
    gpaChange: 0.1,
    totalCredits: 99,
    classRank: 5,
  );

  PortalSnapshot make({
    List<TranscriptRecord> transcript = const [],
    List<WorkItem> work = const [],
    DataSource source = DataSource.live,
  }) =>
      PortalSnapshot(
        profile: profile,
        courses: const [],
        schedule: DaySchedule.unavailable(DateTime(2026, 9, 3)),
        transcript: transcript,
        work: work,
        syncedAt: DateTime(2026, 9, 3),
        source: source,
      );

  TranscriptRecord record(double gpaPoints, double credits) => TranscriptRecord(
        courseTitle: 'C',
        courseCode: 'C1',
        finalScore: 90,
        letterGrade: 'A',
        creditsEarned: credits,
        term: 'Fall 2025',
        gpaPoints: gpaPoints,
      );

  group('computedGpa', () {
    test('weights each course by its credits', () {
      // 4.0 x 1 credit + 3.0 x 3 credits = 13 / 4 credits = 3.25
      final s = make(transcript: [record(4.0, 1), record(3.0, 3)]);
      expect(s.computedGpa, closeTo(3.25, 0.001));
    });

    test('falls back to the portal GPA when there is no transcript', () {
      expect(make().computedGpa, closeTo(2.00, 0.001));
    });

    test('ignores zero-credit rows rather than dividing by zero', () {
      final s = make(transcript: [record(4.0, 0), record(3.0, 0)]);
      expect(s.computedGpa, closeTo(2.00, 0.001));
    });
  });

  group('earnedCredits', () {
    test('sums transcript credits', () {
      final s = make(transcript: [record(4.0, 1), record(3.0, 2.5)]);
      expect(s.earnedCredits, closeTo(3.5, 0.001));
    });

    test('falls back to the profile total when no transcript exists', () {
      expect(make().earnedCredits, closeTo(99, 0.001));
    });
  });

  group('openWork', () {
    WorkItem item(String id, int daysOut, {bool submitted = false}) => WorkItem(
          id: id,
          title: id,
          courseTitle: 'C',
          type: 'homework',
          dueDate: DateTime.now().add(Duration(days: daysOut)),
          submitted: submitted,
        );

    test('drops submitted work and sorts by due date', () {
      final s = make(work: [
        item('later', 5),
        item('done', 1, submitted: true),
        item('soon', 2),
      ]);
      expect(s.openWork.map((w) => w.id).toList(), ['soon', 'later']);
    });
  });

  test('isLive and isDemo reflect the source', () {
    expect(make().isLive, isTrue);
    expect(make(source: DataSource.demo).isDemo, isTrue);
  });
}
