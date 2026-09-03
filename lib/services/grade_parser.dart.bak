import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' show Element;

import '../models/grade_models.dart';
import '../models/schedule_models.dart';

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

  /// Returns null when the schedule isn't published yet.
  List<ScheduleEntry>? parseSchedule(String html) {
    final doc = html_parser.parse(html);
    final body = doc.body?.text.toLowerCase() ?? '';
    if (body.contains('schedule not available') ||
        body.contains('not yet published') ||
        body.contains('no schedule')) {
      return null;
    }
    final rows = doc.querySelectorAll(
        '.schedule-row, tr.period, [data-period], .bell-schedule tr');
    if (rows.isEmpty) return null;
    final out = <ScheduleEntry>[];
    for (final row in rows) {
      final period = int.tryParse(
              row.attributes['data-period'] ??
                  row.querySelector('.period, td:first-child')?.text.trim() ??
                  '') ??
          0;
      out.add(ScheduleEntry(
        period: period,
        courseTitle: row
                .querySelector('.course, .course-title, [data-field="course"]')
                ?.text
                .trim() ??
            '',
        teacherName:
            row.querySelector('.teacher, [data-field="teacher"]')?.text.trim() ??
                '',
        room: row.querySelector('.room, [data-field="room"]')?.text.trim() ?? '',
        startTime:
            row.querySelector('.start, [data-field="start"]')?.text.trim() ?? '',
        endTime:
            row.querySelector('.end, [data-field="end"]')?.text.trim() ?? '',
        dayGroup: row.attributes['data-day'] ?? '',
      ));
    }
    return out.isEmpty ? null : out;
  }

  /// Transcript grouped by term; null if the page says it's unavailable.
  List<TranscriptTerm>? parseTranscript(String html) {
    final doc = html_parser.parse(html);
    final body = doc.body?.text.toLowerCase() ?? '';
    if (body.contains('transcript not available') ||
        body.contains('no transcript')) {
      return null;
    }
    final termBlocks =
        doc.querySelectorAll('.term, .transcript-term, [data-term]');
    if (termBlocks.isEmpty) return null;
    final terms = <TranscriptTerm>[];
    for (final block in termBlocks) {
      final label = block
              .querySelector('.term-label, h3, [data-field="term"]')
              ?.text
              .trim() ??
          'Term';
      final courses = <TranscriptCourse>[];
      for (final row in block.querySelectorAll('tr.course, .transcript-course')) {
        courses.add(TranscriptCourse(
          title: row.querySelector('.course-title, td:first-child')?.text.trim() ?? '',
          code: row.querySelector('.code, [data-field="code"]')?.text.trim() ?? '',
          finalGrade:
              row.querySelector('.grade, [data-field="grade"]')?.text.trim() ?? '',
          credits: double.tryParse(row
                      .querySelector('.credits, [data-field="credits"]')
                      ?.text
                      .trim() ??
                  '') ??
              0,
        ));
      }
      terms.add(TranscriptTerm(
        label: label,
        courses: courses,
        termGpa: _num(block, '.term-gpa, [data-field="gpa"]'),
        termCredits: _num(block, '.term-credits, [data-field="credits-total"]'),
      ));
    }
    return terms;
  }

  double _num(Element root, String selector) {
    final el = root.querySelector(selector);
    if (el == null) return 0;
    return double.tryParse(el.text.replaceAll(RegExp(r'[^0-9.-]'), '')) ?? 0;
  }

  /// Parses the schedule page. Returns [DaySchedule.unavailable] when the
  /// school hasn't posted a schedule for the day (common: "not available yet").
  DaySchedule parseSchedule(String html, DateTime date) {
    final doc = html_parser.parse(html);
    final body = doc.body?.text.toLowerCase() ?? '';
    if (body.contains('not available') ||
        body.contains('no schedule') ||
        body.contains('schedule not posted')) {
      return DaySchedule.unavailable(date);
    }
    final label = doc
            .querySelector('.day-label, .bell-day, [data-field="day-label"]')
            ?.text
            .trim() ??
        'Today';
    final rows = doc.querySelectorAll(
        '.period-row, tr.period, [data-period], .schedule-row');
    if (rows.isEmpty) return DaySchedule.unavailable(date);

    final periods = <ScheduleEntry>[];
    for (final row in rows) {
      final period = int.tryParse(row
                  .querySelector('.period-num, td:first-child')
                  ?.text
                  .replaceAll(RegExp(r'[^0-9]'), '') ??
              '') ??
          0;
      final course = row
              .querySelector('.period-course, .course-name')
              ?.text
              .trim() ??
          '';
      final teacher =
          row.querySelector('.period-teacher, .teacher')?.text.trim() ?? '';
      final room =
          row.querySelector('.period-room, .room')?.text.trim() ?? '';
      final timeText =
          row.querySelector('.period-time, .time')?.text.trim() ?? '';
      final (start, end) = _parseTimeRange(timeText, date);
      periods.add(ScheduleEntry(
        period: period,
        courseTitle: course,
        teacherName: teacher,
        room: room,
        startTime: start,
        endTime: end,
      ));
    }
    return DaySchedule(date: date, label: label, periods: periods);
  }

  (DateTime, DateTime) _parseTimeRange(String text, DateTime date) {
    // Handles "8:00-8:45" / "8:00 AM - 8:45 AM"
    final clean = text.replaceAll(RegExp(r'\s+'), ' ');
    final parts = clean.split(RegExp(r'[-–—]'));
    DateTime start = date, end = date;
    if (parts.length == 2) {
      start = _parseClock(parts[0], date) ?? date;
      end = _parseClock(parts[1], date) ?? date;
    }
    return (start, end);
  }

  DateTime? _parseClock(String t, DateTime date) {
    final m = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false)
        .firstMatch(t.trim());
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final ap = m.group(3)?.toUpperCase();
    if (ap == 'PM' && h < 12) h += 12;
    if (ap == 'AM' && h == 12) h = 0;
    return DateTime(date.year, date.month, date.day, h, min);
  }

  /// Parses the transcript page into [TranscriptRecord] rows.
  List<TranscriptRecord> parseTranscript(String html) {
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll(
        '.transcript-row, tr.transcript, [data-transcript], .credit-row');
    final out = <TranscriptRecord>[];
    for (final row in rows) {
      final title = row
              .querySelector('.course-title, td:nth-child(2)')
              ?.text
              .trim() ??
          '';
      final code =
          row.querySelector('.course-code, td:first-child')?.text.trim() ?? '';
      final letter = row
              .querySelector('.letter, .grade, [data-field="grade"]')
              ?.text
              .trim() ??
          '';
      final credits = _num(row, '.credits, [data-field="credits"]');
      final term =
          row.querySelector('.term, [data-field="term"]')?.text.trim() ?? '';
      final gpa = _num(row, '.gpa-points, [data-field="gpa"]');
      final score = _num(row, '.final, [data-field="final"]');
      if (title.isEmpty) continue;
      out.add(TranscriptRecord(
        courseTitle: title,
        courseCode: code,
        finalScore: score,
        letterGrade: letter,
        creditsEarned: credits,
        term: term,
        gpaPoints: gpa,
      ));
    }
    return out;
  }

  /// Parses an upcoming-work / assignments-due page.
  List<WorkItem> parseWorkDue(String html) {
    final doc = html_parser.parse(html);
    final rows = doc.querySelectorAll(
        '.due-item, .work-row, [data-due], tr.due');
    final out = <WorkItem>[];
    var i = 0;
    for (final row in rows) {
      final title = row
              .querySelector('.due-title, .title, td:first-child')
              ?.text
              .trim() ??
          'Item ${++i}';
      final course = row
              .querySelector('.due-course, .course')
              ?.text
              .trim() ??
          '';
      final type = row
              .querySelector('.due-type, .type')
              ?.text
              .trim()
              .toLowerCase() ??
          'homework';
      final dueText =
          row.querySelector('.due-date, .due')?.text.trim() ?? '';
      final due = DateTime.tryParse(dueText) ?? DateTime.now();
      final submitted = row.querySelector('.submitted') != null;
      final grade = row.querySelector('.due-grade, .grade')?.text.trim();
      out.add(WorkItem(
        id: row.attributes['data-due'] ?? 'w$i',
        title: title,
        courseTitle: course,
        type: type,
        dueDate: due,
        submitted: submitted,
        grade: grade,
      ));
    }
    return out;
  }
}