import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/models/schedule_models.dart';
import 'package:doe_improved/services/analytics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const service = AnalyticsService();

  TranscriptRecord record({
    String title = 'Course',
    String letter = 'A',
    double credits = 1,
    String term = 'Fall 2024',
    double points = 4.0,
    double score = 95,
  }) =>
      TranscriptRecord(
        courseTitle: title,
        courseCode: '',
        finalScore: score,
        letterGrade: letter,
        creditsEarned: credits,
        term: term,
        gpaPoints: points,
      );

  Course course({
    required String title,
    double score = 90,
    String letter = 'A',
    String code = '',
  }) =>
      Course(
        id: title,
        title: title,
        code: code,
        teacherName: '',
        currentScore: score,
        letterGrade: letter,
        categories: const [],
        assignments: const [],
      );

  group('termGpaSeries', () {
    test('weights each course by its credits', () {
      final series = service.termGpaSeries([
        record(letter: 'A', points: 4.0, credits: 1),
        record(letter: 'C', points: 2.0, credits: 3),
      ]);
      // (4x1 + 2x3) / 4 credits = 2.5
      expect(series.single.gpa, closeTo(2.5, 0.001));
      expect(series.single.credits, closeTo(4, 0.001));
    });

    test('orders terms by the academic calendar, not alphabetically', () {
      final series = service.termGpaSeries([
        record(term: 'Spring 2025', letter: 'B', points: 3.0),
        record(term: 'Fall 2024', letter: 'A', points: 4.0),
        record(term: 'Fall 2025', letter: 'C', points: 2.0),
      ]);
      // Autumn precedes the spring that follows it.
      expect(
        series.map((t) => t.term).toList(),
        ['Fall 2024', 'Spring 2025', 'Fall 2025'],
      );
    });

    test('orders numbered marking periods', () {
      final series = service.termGpaSeries([
        record(term: 'MP3'),
        record(term: 'MP1'),
        record(term: 'MP2'),
      ]);
      expect(series.map((t) => t.term).toList(), ['MP1', 'MP2', 'MP3']);
    });

    test('marks that carry no GPA are left out of the average', () {
      final series = service.termGpaSeries([
        record(letter: 'A', points: 4.0, credits: 1),
        // A pass earns credit but must not drag the GPA to zero.
        record(letter: 'P', points: 0, credits: 1),
      ]);
      expect(series.single.gpa, closeTo(4.0, 0.001));
      expect(series.single.credits, closeTo(1, 0.001));
    });

    test('a term with no credits is dropped rather than divided by zero', () {
      final series = service.termGpaSeries([record(credits: 0)]);
      expect(series, isEmpty);
    });

    test('records with no term at all are ignored', () {
      expect(service.termGpaSeries([record(term: '')]), isEmpty);
    });
  });

  group('gradeDistribution', () {
    test('counts transcript letters by band', () {
      final counts = service.gradeDistribution([
        record(letter: 'A'),
        record(letter: 'A-'),
        record(letter: 'B+'),
      ], const []);
      expect(counts['A'], 2);
      expect(counts['B'], 1);
      expect(counts.containsKey('C'), isFalse, reason: 'empty bands dropped');
    });

    test('falls back to this term when no transcript is posted', () {
      final counts = service.gradeDistribution(const [], [
        course(title: 'Math', letter: 'B'),
        course(title: 'Art', letter: 'B'),
      ]);
      expect(counts['B'], 2);
    });

    test('derives a band from the score when no letter was published', () {
      final counts = service.gradeDistribution(const [], [
        course(title: 'Math', letter: '', score: 72),
      ]);
      expect(counts['C'], 1);
    });
  });

  group('subject classification', () {
    test('buckets familiar course titles', () {
      expect(AnalyticsService.subjectOf('AP Calculus BC'), 'Math');
      expect(AnalyticsService.subjectOf('CC Algebra 2'), 'Math');
      expect(AnalyticsService.subjectOf('Living Environment'), 'Science');
      expect(AnalyticsService.subjectOf('AP Physics C'), 'Science');
      expect(AnalyticsService.subjectOf('English 12'), 'English');
      expect(AnalyticsService.subjectOf('US History'), 'History');
      expect(AnalyticsService.subjectOf('AP Government & Politics'), 'History');
      expect(AnalyticsService.subjectOf('Spanish IV'), 'Language');
      expect(AnalyticsService.subjectOf('AP Computer Science'), 'Tech');
      expect(AnalyticsService.subjectOf('Ceramics & Sculpture'), 'Arts');
      expect(AnalyticsService.subjectOf('PHYS ED 5 OF 8'), 'PE');
    });

    test('an unrecognised title is grouped, not dropped', () {
      expect(AnalyticsService.subjectOf('Advanced Basket Weaving'), 'Other');
      final scores = service.subjectPerformance([
        course(title: 'Advanced Basket Weaving', score: 88),
      ]);
      expect(scores.single.subject, 'Other');
      expect(scores.single.score, closeTo(88, 0.001));
    });

    test('averages several courses in the same subject', () {
      final scores = service.subjectPerformance([
        course(title: 'AP Calculus BC', score: 90),
        course(title: 'CC Algebra 2', score: 80),
      ]);
      expect(scores.single.subject, 'Math');
      expect(scores.single.score, closeTo(85, 0.001));
      expect(scores.single.courseCount, 2);
    });
  });

  group('topPerformer', () {
    test('picks the highest scoring course', () {
      final best = service.topPerformer([
        course(title: 'Low', score: 71),
        course(title: 'High', score: 96),
      ]);
      expect(best?.title, 'High');
    });

    test('is null when nothing is graded yet', () {
      expect(service.topPerformer([course(title: 'Ungraded', score: 0)]),
          isNull);
    });
  });

  group('nextFor', () {
    WorkItem work(String title, String courseTitle, int daysOut,
            {bool submitted = false}) =>
        WorkItem(
          id: title,
          title: title,
          courseTitle: courseTitle,
          type: 'homework',
          dueDate: DateTime.now().add(Duration(days: daysOut)),
          submitted: submitted,
        );

    test('returns the soonest outstanding item for the course', () {
      final next = service.nextFor(
        course(title: 'AP Calculus BC'),
        [
          work('Later', 'AP Calculus BC', 9),
          work('Sooner', 'AP Calculus BC', 2),
          work('Other course', 'AP Physics C', 1),
        ],
      );
      expect(next?.title, 'Sooner');
    });

    test('matches when the work list abbreviates the course name', () {
      final next = service.nextFor(
        course(title: 'AP Calculus BC'),
        [work('Problem Set', 'AP Calculus', 3)],
      );
      expect(next?.title, 'Problem Set');
    });

    test('matches on the course code when the names differ', () {
      final next = service.nextFor(
        course(title: 'Intro to Literature', code: 'ENG201'),
        [work('Essay 2', 'ENG201 Section 3', 4)],
      );
      expect(next?.title, 'Essay 2');
    });

    test('ignores work already handed in', () {
      final next = service.nextFor(
        course(title: 'AP Calculus BC'),
        [work('Done', 'AP Calculus BC', 1, submitted: true)],
      );
      expect(next, isNull);
    });
  });
}
