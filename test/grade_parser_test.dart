import 'package:doe_improved/services/grade_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = GradeParser();

  const profileHtml = '''
<html><body>
  <div class="student-name">Jordan Alvarez</div>
  <div class="school-name">Brooklyn Technical High School</div>
  <span class="gpa-value">3.92</span>
  <span class="gpa-change">+0.15</span>
  <span class="credits">42.0</span>
  <span class="class-rank">Rank #12</span>
</body></html>''';

  const coursesHtml = '''
<html><body>
  <table>
    <tr class="course" data-course="c1">
      <td class="course-title">AP Calculus BC</td>
      <td class="teacher-name">Ms. Okafor</td>
      <td class="average">88.8%</td>
      <td class="letter-grade">B</td>
    </tr>
    <tr class="course" data-course="c2">
      <td class="course-title">AP English Literature</td>
      <td class="teacher-name">Mr. Hewitt</td>
      <td class="average">94.1%</td>
      <td class="letter-grade">A</td>
    </tr>
  </table>
</body></html>''';

  const detailHtml = '''
<html><body>
  <div class="category" data-category-row>
    <span class="category-name">Tests</span>
    <span class="weight">50</span>
    <span class="earned">320</span>
    <span class="total">400</span>
  </div>
  <div class="category" data-category-row>
    <span class="category-name">Homework</span>
    <span class="weight">20</span>
    <span class="earned">160</span>
    <span class="total">200</span>
  </div>
  <tr class="assignment" data-assignment="a1">
    <td class="assignment-title">Rotational Motion Test</td>
    <td class="category">Tests</td>
    <td class="score">78</td>
    <td class="max">100</td>
    <td class="status">graded</td>
  </tr>
</body></html>''';

  test('parseProfile extracts profile fields', () {
    final p = parser.parseProfile(profileHtml)!;
    expect(p.name, 'Jordan Alvarez');
    expect(p.overallGpa, 3.92);
    expect(p.gpaChange, 0.15);
    expect(p.totalCredits, 42.0);
    expect(p.classRank, 12);
  });

  test('parseCourseList extracts course stubs', () {
    final courses = parser.parseCourseList(coursesHtml);
    expect(courses.length, 2);
    expect(courses[0].id, 'c1');
    expect(courses[0].currentScore, 88.8);
    expect(courses[0].letterGrade, 'B');
    expect(courses[1].title, 'AP English Literature');
  });

  test('parseCourseDetail extracts categories and assignments', () {
    final d = parser.parseCourseDetail(detailHtml);
    expect(d.categories.length, 2);
    expect(d.categories[0].name, 'Tests');
    expect(d.categories[0].weightPercentage, 50);
    expect(d.assignments.length, 1);
    expect(d.assignments[0].score, 78);
    expect(d.assignments[0].maxScore, 100);
  });

  test('parseCourseList returns empty on unknown markup', () {
    expect(parser.parseCourseList('<html><body></body></html>'), isEmpty);
  });
}