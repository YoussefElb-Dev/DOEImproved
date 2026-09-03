import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/services/calculator_service.dart';
import 'package:doe_improved/services/grade_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// The parser must work for any school, any course names, and any markup —
/// so every fixture here deliberately uses class names, headings and key names
/// that appear nowhere in the parser's source.
void main() {
  const parser = GradeParser();

  group('course list — the same roster in four different shapes', () {
    // 1. A table with real headers and machine-generated class names.
    const semanticTable = '''
<html><body>
  <table class="zx-9182 dg--v3">
    <thead>
      <tr>
        <th class="c0">Class</th>
        <th class="c1">Instructor</th>
        <th class="c2">Current Average</th>
        <th class="c3">Mark</th>
      </tr>
    </thead>
    <tbody>
      <tr class="r"><td>AP Física C</td><td>Dra. Vasquez</td><td>91.4%</td><td>A</td></tr>
      <tr class="r"><td>Ceramics &amp; Sculpture</td><td>Mr. Adeyemi</td><td>78%</td><td>C</td></tr>
    </tbody>
  </table>
</body></html>''';

    // 2. A card layout with a bespoke BEM naming scheme and no table at all.
    const cardLayout = '''
<html><body>
  <section class="roster">
    <article class="tile tile--course">
      <h3 class="tile__name">AP Física C</h3>
      <p class="tile__teacher">Dra. Vasquez</p>
      <span class="tile__avg">91.4%</span>
      <span class="tile__mark">A</span>
    </article>
    <article class="tile tile--course">
      <h3 class="tile__name">Ceramics &amp; Sculpture</h3>
      <p class="tile__teacher">Mr. Adeyemi</p>
      <span class="tile__avg">78%</span>
      <span class="tile__mark">C</span>
    </article>
  </section>
</body></html>''';

    // 3. A JSON API response instead of a rendered page.
    const jsonApi = '''
{
  "student": {"name": "Amara Okonkwo", "school": "Bronx Science", "gpa": 3.87},
  "courses": [
    {"courseName": "AP Física C", "teacher": "Dra. Vasquez",
     "average": 91.4, "letterGrade": "A", "courseId": "SCI-401"},
    {"courseName": "Ceramics & Sculpture", "teacher": "Mr. Adeyemi",
     "average": 78, "letterGrade": "C", "courseId": "ART-110"}
  ]
}''';

    // 4. A bare table: no headers, no classes, no attributes whatsoever.
    const bareTable = '''
<html><body>
  <table>
    <tr><td>AP Física C</td><td>Dra. Vasquez</td><td>91.4%</td><td>A</td></tr>
    <tr><td>Ceramics &amp; Sculpture</td><td>Mr. Adeyemi</td><td>78%</td><td>C</td></tr>
  </table>
</body></html>''';

    for (final (name, html) in [
      ('headed table', semanticTable),
      ('card layout', cardLayout),
      ('json api', jsonApi),
      ('bare table', bareTable),
    ]) {
      test('reads both courses from a $name', () {
        final courses = parser.parseCourseList(html);

        expect(courses, hasLength(2), reason: 'both courses found');
        expect(courses[0].title, 'AP Física C');
        expect(courses[0].teacherName, 'Dra. Vasquez');
        expect(courses[0].currentScore, closeTo(91.4, 0.01));
        expect(courses[0].letterGrade, 'A');
        expect(courses[1].title, 'Ceramics & Sculpture');
        expect(courses[1].letterGrade, 'C');
      });
    }

    test('a JSON course id becomes the record id', () {
      final courses = parser.parseCourseList(jsonApi);
      expect(courses[0].id, 'SCI-401');
    });

    test('a course link is captured so the detail page can be followed', () {
      const linked = '''
<html><body><table>
  <tr><td><a href="/gradebook/section/98211">Marine Biology</a></td>
      <td>Ms. Okafor</td><td>96%</td><td>A</td></tr>
  <tr><td><a href="/gradebook/section/44120">Studio Art</a></td>
      <td>Mr. Hewitt</td><td>88%</td><td>B</td></tr>
</table></body></html>''';
      final courses = parser.parseCourseList(linked);
      expect(courses, hasLength(2));
      expect(courses[0].detailPath, '/gradebook/section/98211');
      // The id falls back to the last path segment when none was published.
      expect(courses[0].id, '98211');
    });
  });

  group('profile', () {
    test('reads a definition list', () {
      const html = '''
<html><body><dl>
  <dt>Student</dt><dd>Amara Okonkwo</dd>
  <dt>School</dt><dd>Bronx High School of Science</dd>
  <dt>Cumulative GPA</dt><dd>3.87</dd>
  <dt>Credits Earned</dt><dd>44.5</dd>
  <dt>Class Rank</dt><dd>7 of 812</dd>
</dl></body></html>''';
      final p = parser.parseProfile(html)!;

      expect(p.name, 'Amara Okonkwo');
      expect(p.schoolName, 'Bronx High School of Science');
      expect(p.overallGpa, closeTo(3.87, 0.001));
      expect(p.totalCredits, closeTo(44.5, 0.001));
      expect(p.classRank, 7, reason: 'the rank, not the class size');
    });

    test('reads a JSON profile', () {
      const json = '''
{"student": {"name": "Amara Okonkwo", "school": "Bronx Science", "gpa": 3.87}}''';
      final p = parser.parseProfile(json)!;
      expect(p.name, 'Amara Okonkwo');
      expect(p.overallGpa, closeTo(3.87, 0.001));
    });

    test('a percentage-style average is not shown as a GPA', () {
      const html = '<html><body><dl><dt>Student</dt><dd>A B</dd>'
          '<dt>Average</dt><dd>91.4</dd></dl></body></html>';
      final p = parser.parseProfile(html)!;
      expect(p.overallGpa, 0, reason: '91.4 is not a GPA on any scale');
    });

    test('returns null when the page holds nothing identifiable', () {
      expect(parser.parseProfile('<html><body><p>Hello</p></body></html>'),
          isNull);
    });

    test('a labelled value stops at the end of its own element', () {
      const html = '''
<html><body>
  <p>School: Bronx High School of Science</p>
  <nav><a href="#">Manage Account</a> <a href="#">Log Out</a></nav>
</body></html>''';
      final p = parser.parseProfile(html)!;
      expect(p.schoolName, 'Bronx High School of Science',
          reason: 'the value must not run on into the navigation');
    });

    test('page furniture after a label is rejected, not displayed', () {
      // What a collapsed-whitespace scan of a real portal page produces.
      const html = '''
<html><body>
  <p>School: PS 123 Grade 10 Manage Account Log Out Error 4</p>
  <dl><dt>Student</dt><dd>Amara Okonkwo</dd></dl>
</body></html>''';
      final p = parser.parseProfile(html)!;
      expect(p.name, 'Amara Okonkwo');
      expect(p.schoolName, isEmpty, reason: 'better blank than a menu');
    });

    test('a name that swallowed the menu is dropped', () {
      const html = '<html><body><dl><dt>Student</dt>'
          '<dd>Amara Okonkwo Home Menu Settings Help Log Out</dd>'
          '</dl></body></html>';
      expect(parser.parseProfile(html)?.name ?? '', isNot(contains('Log Out')));
    });

    test('an implausibly long name is dropped', () {
      final html = '<html><body><dl><dt>Student</dt><dd>'
          '${'Wordy ' * 20}</dd></dl></body></html>';
      expect(parser.parseProfile(html)?.name ?? '', isNot(contains('Wordy')));
    });
  });

  group('transcript', () {
    const html = '''
<html><body><table>
  <thead><tr><th>Course</th><th>Term</th><th>Grade</th><th>Credits</th></tr></thead>
  <tbody>
    <tr><td>Health Education</td><td>Fall 2025</td><td>P</td><td>0.5</td></tr>
    <tr><td>Studio Art</td><td>Fall 2025</td><td>NS</td><td>0</td></tr>
    <tr><td>Physics</td><td>Spring 2026</td><td>A-</td><td>1.0</td></tr>
  </tbody>
</table></body></html>''';

    test('reads courses, terms and credits', () {
      final records = parser.parseTranscript(html);
      expect(records, hasLength(3));
      expect(records[0].courseTitle, 'Health Education');
      expect(records[0].term, 'Fall 2025');
      expect(records[0].creditsEarned, closeTo(0.5, 0.001));
      expect(records[2].letterGrade, 'A-');
      expect(records[2].creditsEarned, closeTo(1.0, 0.001));
    });

    test('non-numeric marks are kept and scored correctly', () {
      final records = parser.parseTranscript(html);
      // A pass carries credit but no GPA points.
      expect(records[0].letterGrade, 'P');
      expect(records[0].gpaPoints, 0);
      // A never-showed is a zero, not an exclusion.
      expect(records[1].letterGrade, 'NS');
      expect(records[1].gpaPoints, 0);
      expect(records[2].gpaPoints, closeTo(3.7, 0.001));
    });

    test('the school\'s own GPA points win over derived ones', () {
      const weighted = '''
<html><body><table>
  <thead><tr><th>Course</th><th>Grade</th><th>Credits</th><th>Quality Points</th></tr></thead>
  <tbody><tr><td>AP Physics C</td><td>A</td><td>1.0</td><td>5.0</td></tr></tbody>
</table></body></html>''';
      final records = parser.parseTranscript(weighted);
      expect(records.single.gpaPoints, closeTo(5.0, 0.001),
          reason: 'an AP weighting the school published must not be flattened');
    });
  });

  group('schedule', () {
    test('reads periods, rooms and times with abbreviated headers', () {
      const html = '''
<html><body>
  <h2>Day 3</h2>
  <table>
    <thead><tr><th>Pd</th><th>Subject</th><th>Educator</th><th>Rm</th><th>Meeting Time</th></tr></thead>
    <tbody>
      <tr><td>4</td><td>Lunch</td><td></td><td>Cafeteria</td><td>11:30 - 12:15</td></tr>
      <tr><td>5</td><td>Global History</td><td>Ms. Lindqvist</td><td>214</td><td>12:20 - 1:05 PM</td></tr>
    </tbody>
  </table>
</body></html>''';
      final day = parser.parseSchedule(html, DateTime(2026, 9, 3));

      expect(day.available, isTrue);
      expect(day.label, 'Day 3');
      expect(day.periods, hasLength(2));

      expect(day.periods[0].period, 4);
      expect(day.periods[0].courseTitle, 'Lunch');
      expect(day.periods[0].room, 'Cafeteria');
      // 11:30–12:15 crosses noon without a meridiem on either end.
      expect(day.periods[0].startTime.hour, 11);
      expect(day.periods[0].endTime.hour, 12);

      expect(day.periods[1].teacherName, 'Ms. Lindqvist');
      expect(day.periods[1].startTime.hour, 12);
      expect(day.periods[1].endTime.hour, 13);
    });

    test('an empty schedule page reports unavailable', () {
      final day = parser.parseSchedule(
        '<html><body><p>No schedule has been posted.</p></body></html>',
        DateTime(2026, 9, 3),
      );
      expect(day.available, isFalse);
    });
  });

  group('upcoming work', () {
    test('reads a list layout with mixed date formats', () {
      const html = '''
<html><body><ul class="agenda">
  <li class="agenda-item">
    <span class="agenda-item__task">Ballistics Lab Report</span>
    <span class="agenda-item__class">AP Physics C</span>
    <span class="agenda-item__deadline">3/14/2026</span>
  </li>
  <li class="agenda-item">
    <span class="agenda-item__task">Reconstruction DBQ Essay</span>
    <span class="agenda-item__class">Global History II</span>
    <span class="agenda-item__deadline">Sept 2, 2026</span>
    <span class="agenda-item__state">Submitted</span>
  </li>
</ul></body></html>''';
      final work = parser.parseWorkDue(html);

      expect(work, hasLength(2));
      expect(work[0].title, 'Ballistics Lab Report');
      expect(work[0].courseTitle, 'AP Physics C');
      expect(work[0].dueDate, DateTime(2026, 3, 14));
      expect(work[0].type, 'lab', reason: 'inferred from the title');
      expect(work[0].submitted, isFalse);

      expect(work[1].dueDate, DateTime(2026, 9, 2));
      expect(work[1].type, 'essay');
      expect(work[1].submitted, isTrue);
    });
  });

  group('course detail', () {
    test('reads published categories and assignments', () {
      const html = '''
<html><body>
  <table>
    <thead><tr><th>Category</th><th>Weight</th><th>Earned</th><th>Possible</th></tr></thead>
    <tbody>
      <tr><td>Exams</td><td>60</td><td>170</td><td>200</td></tr>
      <tr><td>Homework</td><td>40</td><td>95</td><td>100</td></tr>
    </tbody>
  </table>
  <table>
    <thead><tr><th>Assignment</th><th>Category</th><th>Score</th><th>Out Of</th></tr></thead>
    <tbody>
      <tr><td>Unit 3 Exam</td><td>Exams</td><td>88</td><td>100</td></tr>
      <tr><td>Problem Set 4</td><td>Homework</td><td>19</td><td>20</td></tr>
    </tbody>
  </table>
</body></html>''';
      final detail = parser.parseCourseDetail(html);

      expect(detail.categories, hasLength(2));
      expect(detail.categories[0].name, 'Exams');
      expect(detail.categories[0].weightPercentage, 60);
      expect(detail.categories[0].earnedPoints, 170);
      expect(detail.categories[0].totalPoints, 200);

      expect(detail.assignments, hasLength(2));
      expect(detail.assignments[0].title, 'Unit 3 Exam');
      expect(detail.assignments[0].score, 88);
      expect(detail.assignments[0].maxScore, 100);
      expect(detail.assignments[1].score, 19);
      expect(detail.assignments[1].maxScore, 20);
    });

    test('points written as a fraction in one cell are understood', () {
      const html = '''
<html><body><table>
  <thead><tr><th>Assignment</th><th>Category</th><th>Points</th></tr></thead>
  <tbody><tr><td>Poetry Quiz</td><td>Quizzes</td><td>17/20</td></tr></tbody>
</table></body></html>''';
      final detail = parser.parseCourseDetail(html);
      expect(detail.assignments.single.score, 17);
      expect(detail.assignments.single.maxScore, 20);
    });

    test('categories are synthesised when only assignments are published', () {
      const html = '''
<html><body><table>
  <thead><tr><th>Assignment</th><th>Category</th><th>Score</th><th>Out Of</th></tr></thead>
  <tbody>
    <tr><td>Quiz 1</td><td>Quizzes</td><td>18</td><td>20</td></tr>
    <tr><td>Test 1</td><td>Tests</td><td>85</td><td>100</td></tr>
  </tbody>
</table></body></html>''';
      final detail = parser.parseCourseDetail(html);

      expect(detail.categories, hasLength(2),
          reason: 'What-If needs categories even when none were published');

      // Weighting by points possible reproduces a total-points gradebook, so
      // the weighted average equals the raw points percentage.
      final course = _courseWith(detail.categories);
      expect(
        const CalculatorService().calculateCourseAverage(course),
        closeTo(103 / 120 * 100, 0.001),
      );
    });

    test('an unreadable page yields nothing rather than throwing', () {
      final detail = parser.parseCourseDetail('<html><body>?</body></html>');
      expect(detail.categories, isEmpty);
      expect(detail.assignments, isEmpty);
    });
  });

  group('resilience', () {
    test('malformed markup does not throw', () {
      for (final body in [
        '',
        '<html',
        '<table><tr><td>unclosed',
        '{"broken": ',
        '[]',
        '{}',
      ]) {
        expect(() => parser.parseCourseList(body), returnsNormally);
        expect(() => parser.parseTranscript(body), returnsNormally);
        expect(() => parser.parseWorkDue(body), returnsNormally);
        expect(() => parser.parseProfile(body), returnsNormally);
        expect(() => parser.parseCourseDetail(body), returnsNormally);
        expect(
          () => parser.parseSchedule(body, DateTime(2026, 9, 3)),
          returnsNormally,
        );
      }
    });

    test('a navigation table is not mistaken for a roster', () {
      const html = '''
<html><body>
  <table><tr><td>Home</td><td>Grades</td></tr><tr><td>Help</td><td>Log out</td></tr></table>
</body></html>''';
      expect(parser.parseCourseList(html), isEmpty);
    });
  });
}

Course _courseWith(List<GradeCategory> categories) => Course(
      id: 'x',
      title: 'x',
      code: '',
      teacherName: '',
      currentScore: 0,
      letterGrade: '',
      categories: categories,
      assignments: const [],
    );
