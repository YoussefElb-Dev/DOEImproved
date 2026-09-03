import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' show Element;

import '../models/grade_models.dart';

/// Parses NYC student-portal grade pages (HTML fetched with the
/// authenticated session) into typed models.
///
/// Selector coverage targets the common portal layouts; unknown structures
/// degrade gracefully to empty results instead of throwing.
class GradeParser {
  const GradeParser();

  /// Parses a profile block from the dashboard page.
  StudentProfile? parseProfile(String html) {
    final doc = html_parser.parse(html);
    final nameEl = doc.querySelector('.student-name, #studentName, [data-field="student-name"]');
    if (nameEl == null) return null;
    final root = doc.documentElement!;
    final gpa = _num(root, '.gpa-value, [data-field="gpa"]');
    final change = _num(root, '.gpa-change, [data-field="gpa-change"]');
    final credits = _num(root, '.credits, [data-field="credits"]');
    final rank = doc.querySelector('.class-rank, [data-field="rank"]');
    final school = doc.querySelector('.school-name, [data-field="school"]');
    return StudentProfile(
      name: nameEl.text.trim(),
      schoolName: school?.text.trim() ?? '',
      avatarUrl: doc.querySelector('.avatar img')?.attributes['src'] ?? '',
      overallGpa: gpa,
      gpaChange: change,
      totalCredits: credits,
      classRank: int.tryParse(
              rank?.text.replaceAll(RegExp(r'[^0-9]'), '') ?? '') ??
          0,
    );
  }

  /// Parses a course list page into [Course] stubs (detail fetched later).
  List<Course> parseCourseList(String html) {
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll(
        '.course-row, tr.course, [data-course], .gradebook-course');
    final out = <Course>[];
    for (final row in rows) {
      final id = row.attributes['data-course'] ??
          row.attributes['data-id'] ??
          row.attributes['id'] ??
          '';
      final title = row
              .querySelector('.course-title, .course-name, td:first-child')
              ?.text
              .trim() ??
          'Course';
      final teacher = row
              .querySelector('.teacher, .teacher-name, [data-field="teacher"]')
              ?.text
              .trim() ??
          '';
      final scoreText = row
              .querySelector('.score, .average, [data-field="average"]')
              ?.text ??
          '';
      final score = double.tryParse(
              scoreText.replaceAll(RegExp(r'[^0-9.]'), '')) ??
          0.0;
      final letter = row
              .querySelector('.letter-grade, [data-field="letter"]')
              ?.text
              .trim() ??
          '';
      out.add(Course(
        id: id,
        title: title,
        code: '',
        teacherName: teacher,
        currentScore: score,
        letterGrade: letter,
        categories: const [],
        assignments: const [],
      ));
    }
    return out;
  }

  /// Parses a course detail page: categories + assignments.
  ({List<GradeCategory> categories, List<Assignment> assignments})
      parseCourseDetail(String html) {
    final doc = html_parser.parse(html);
    final categories = <GradeCategory>[];
    final assignments = <Assignment>[];

    for (final el in doc.querySelectorAll(
        '.category, [data-category-row], .weight-row')) {
      final name = el
              .querySelector('.category-name, .name')
              ?.text
              .trim() ??
          'Other';
      final weight = _num(el, '.weight, [data-field="weight"]');
      final earned = _num(el, '.earned, [data-field="earned"]');
      final total = _num(el, '.total, [data-field="total"]');
      categories.add(GradeCategory(
        name: name,
        weightPercentage: weight,
        earnedPoints: earned,
        totalPoints: total,
      ));
    }

    var i = 0;
    for (final el in doc.querySelectorAll(
        '.assignment, tr.assignment, [data-assignment]')) {
      final title = el
              .querySelector('.assignment-title, .title, td:first-child')
              ?.text
              .trim() ??
          'Assignment ${++i}';
      final category =
          el.querySelector('.category, [data-field="category"]')?.text.trim() ??
              'Other';
      final score = _num(el, '.score, [data-field="score"]');
      final max = _num(el, '.max, .points-possible, [data-field="max"]');
      final statusText =
          el.querySelector('.status, [data-field="status"]')?.text.trim() ?? '';
      final status = AssignmentStatus.values.firstWhere(
        (s) => statusText.toLowerCase().contains(s.name),
        orElse: () => AssignmentStatus.graded,
      );
      assignments.add(Assignment(
        id: el.attributes['data-assignment'] ?? 'a$i',
        title: title,
        category: category,
        score: score,
        maxScore: max,
        dueDate: DateTime.now(),
        status: status,
      ));
    }
    return (categories: categories, assignments: assignments);
  }

  double _num(Element root, String selector) {
    final el = root.querySelector(selector);
    if (el == null) return 0;
    return double.tryParse(el.text.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
  }
}