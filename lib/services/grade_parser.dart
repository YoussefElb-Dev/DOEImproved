import '../models/grade_models.dart';
import '../models/schedule_models.dart';
import 'grade_scale.dart';
import 'parsing/field_map.dart';
import 'parsing/records.dart';
import 'parsing/values.dart';

/// Turns portal pages into typed models.
///
/// The parser makes no assumptions about a school's markup. It locates the
/// data by structure (tables, repeated cards, JSON arrays) and identifies
/// columns by their *labels* and the *shape of their values* — headers, `<dt>`
/// terms, JSON keys, `data-` attributes, `aria-label`s, and descriptive class
/// names as a hint. Nothing depends on a specific CSS class existing, so a
/// school that names its columns differently still parses, and a portal that
/// switches from HTML to a JSON API keeps working.
///
/// Anything that cannot be understood degrades to an empty result rather than
/// throwing.
class GradeParser {
  const GradeParser();

  // ── profile ─────────────────────────────────────────────────────────

  /// Reads the student header from a dashboard. Returns null only when the
  /// page yielded nothing identifiable at all.
  StudentProfile? parseProfile(String body) {
    final doc = PortalDocument.parse(body);
    final values = doc.extractLabeledValues(FieldMatcher.profileField);

    final name = values[SemanticField.studentName] ?? _headingName(doc);
    final school = values[SemanticField.schoolName] ?? '';
    final gpa = _gpaValue(values[SemanticField.gpa]);
    final change = parseNumber(values[SemanticField.gpaChange] ?? '') ?? 0;
    final credits = parseNumber(values[SemanticField.totalCredits] ?? '') ?? 0;
    final rank = parsePeriod(values[SemanticField.classRank] ?? '') ??
        parseNumber(values[SemanticField.classRank] ?? '')?.toInt() ??
        0;

    if ((name == null || name.isEmpty) &&
        school.isEmpty &&
        gpa == 0 &&
        credits == 0) {
      return null;
    }

    return StudentProfile(
      name: name ?? 'Student',
      schoolName: school,
      avatarUrl: doc.findImageUrl(const ['avatar', 'photo', 'profile', 'student']),
      overallGpa: gpa,
      gpaChange: change,
      totalCredits: credits,
      classRank: rank,
    );
  }

  /// GPA is quoted on several scales (4.0, 5.0, 100). Anything above 10 is a
  /// percentage-style average, which the hero card would misrender as a GPA.
  double _gpaValue(String? raw) {
    final n = parseNumber(raw ?? '');
    if (n == null || n < 0) return 0;
    return n > 10 ? 0 : n;
  }

  String? _headingName(PortalDocument doc) {
    for (final heading in doc.headings()) {
      if (looksLikePersonName(heading)) return heading;
    }
    return null;
  }

  // ── courses ─────────────────────────────────────────────────────────

  /// Course stubs from a dashboard or roster. Detail pages are fetched
  /// separately using each stub's [Course.detailPath].
  List<Course> parseCourseList(String body) {
    final doc = PortalDocument.parse(body);
    final sets = doc.extractRecordSets(FieldMatcher.courseRow);

    final chosen = selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.letterGrade},
          prefer: _courseFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.score},
          prefer: _courseFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle},
          prefer: _courseFields,
        );
    if (chosen == null) return const [];

    final out = <Course>[];
    for (var i = 0; i < chosen.records.length; i++) {
      final r = chosen.records[i];
      final title = r[SemanticField.courseTitle];
      if (title == null) continue;

      final letter = parseLetterGrade(r[SemanticField.letterGrade] ?? '') ?? '';
      final score = parseScore(r[SemanticField.score] ?? '') ??
          (letter.isEmpty ? null : GradeScale.scoreFor(letter)) ??
          0;

      out.add(Course(
        id: r.id ?? 'c$i',
        title: title,
        code: r[SemanticField.courseCode] ?? '',
        teacherName: r[SemanticField.teacher] ?? '',
        currentScore: score,
        letterGrade: letter.isNotEmpty
            ? letter
            : (score > 0 ? GradeScale.letterFor(score) : ''),
        categories: const [],
        assignments: const [],
        detailPath: r.link,
      ));
    }
    return out;
  }

  static const Set<SemanticField> _courseFields = {
    SemanticField.score,
    SemanticField.letterGrade,
    SemanticField.teacher,
    SemanticField.courseCode,
    SemanticField.term,
    SemanticField.room,
  };

  // ── course detail ───────────────────────────────────────────────────

  /// Weighted categories and the assignment history for one course.
  ///
  /// Assignments are located first because they are the more distinctive shape
  /// (a title plus points); categories are then taken from a *different*
  /// structure on the page. When a gradebook publishes only assignments,
  /// categories are synthesised from them so the What-If projection still
  /// works.
  ({List<GradeCategory> categories, List<Assignment> assignments})
      parseCourseDetail(String body) {
    final doc = PortalDocument.parse(body);

    final assignmentSets = doc.extractRecordSets(FieldMatcher.assignmentRow);
    final assignmentSet = selectRecordSet(
          assignmentSets,
          mustHave: {SemanticField.assignmentTitle, SemanticField.pointsPossible},
          prefer: _assignmentFields,
        ) ??
        selectRecordSet(
          assignmentSets,
          mustHave: {SemanticField.assignmentTitle, SemanticField.score},
          prefer: _assignmentFields,
        ) ??
        selectRecordSet(
          assignmentSets,
          mustHave: {SemanticField.assignmentTitle},
          prefer: _assignmentFields,
        );

    final assignments = _toAssignments(assignmentSet);

    final categorySets = doc
        .extractRecordSets(FieldMatcher.categoryRow)
        .where((s) => s.origin != assignmentSet?.origin)
        .toList();
    final categorySet = selectRecordSet(
          categorySets,
          mustHave: {SemanticField.category, SemanticField.weight},
          prefer: _categoryFields,
        ) ??
        selectRecordSet(
          categorySets,
          mustHave: {SemanticField.category, SemanticField.pointsPossible},
          prefer: _categoryFields,
        );

    var categories = _toCategories(categorySet);
    if (categories.isEmpty && assignments.isNotEmpty) {
      categories = _synthesizeCategories(assignments);
    }

    return (categories: categories, assignments: assignments);
  }

  static const Set<SemanticField> _assignmentFields = {
    SemanticField.pointsEarned,
    SemanticField.pointsPossible,
    SemanticField.score,
    SemanticField.category,
    SemanticField.dueDate,
    SemanticField.status,
    SemanticField.letterGrade,
  };

  static const Set<SemanticField> _categoryFields = {
    SemanticField.weight,
    SemanticField.pointsEarned,
    SemanticField.pointsPossible,
    SemanticField.score,
  };

  List<GradeCategory> _toCategories(RecordSet? set) {
    if (set == null) return const [];
    final out = <GradeCategory>[];
    for (final r in set.records) {
      final name = r[SemanticField.category];
      if (name == null) continue;

      final weight = parseNumber(r[SemanticField.weight] ?? '') ?? 0;
      var earned = parseNumber(r[SemanticField.pointsEarned] ?? '') ?? 0;
      var possible = parseNumber(r[SemanticField.pointsPossible] ?? '') ?? 0;

      // "84/100" in a single cell.
      final fraction = _fractionIn(r);
      if (possible <= 0 && fraction != null) {
        earned = fraction.earned;
        possible = fraction.possible;
      }
      // A score column alongside a total means the score *is* the earned
      // points; a score on its own is a percentage, which becomes points out
      // of 100 so the weighting maths downstream stays uniform.
      final pct = parseScore(r[SemanticField.score] ?? '');
      if (earned <= 0 && pct != null) {
        if (possible > 0) {
          earned = pct <= possible ? pct : possible;
        } else {
          earned = pct;
          possible = 100;
        }
      }

      if (weight <= 0 && possible <= 0) continue;
      out.add(GradeCategory(
        name: name,
        weightPercentage: weight,
        earnedPoints: earned,
        totalPoints: possible,
      ));
    }
    return out;
  }

  List<Assignment> _toAssignments(RecordSet? set) {
    if (set == null) return const [];
    final out = <Assignment>[];
    var i = 0;
    for (final r in set.records) {
      final title = r[SemanticField.assignmentTitle];
      if (title == null) continue;
      i++;

      var earned = parseNumber(r[SemanticField.pointsEarned] ?? '') ?? 0;
      var possible = parseNumber(r[SemanticField.pointsPossible] ?? '') ?? 0;

      final fraction = _fractionIn(r);
      if (possible <= 0 && fraction != null) {
        earned = fraction.earned;
        possible = fraction.possible;
      }
      // Same reading as categories: "78" next to a max of 100 is 78 points,
      // while "78" with no max is 78 percent.
      final pct = parseScore(r[SemanticField.score] ?? '');
      if (earned <= 0 && pct != null) {
        if (possible > 0) {
          earned = pct <= possible ? pct : possible;
        } else {
          earned = pct;
          possible = 100;
        }
      }

      final statusText =
          '${r[SemanticField.status] ?? ''} ${r[SemanticField.letterGrade] ?? ''}';
      out.add(Assignment(
        id: r.id ?? 'a$i',
        title: title,
        category: r[SemanticField.category] ?? 'Other',
        score: earned,
        maxScore: possible > 0 ? possible : 100,
        dueDate: parseDate(r[SemanticField.dueDate] ?? '') ?? DateTime.now(),
        status: _statusFor(statusText, graded: possible > 0),
      ));
    }
    return out;
  }

  /// Groups assignments into categories weighted by points possible, which
  /// reproduces a total-points gradebook exactly — the common default when a
  /// portal publishes no weights of its own.
  List<GradeCategory> _synthesizeCategories(List<Assignment> assignments) {
    final earned = <String, double>{};
    final possible = <String, double>{};
    for (final a in assignments) {
      if (a.status != AssignmentStatus.graded || a.maxScore <= 0) continue;
      earned[a.category] = (earned[a.category] ?? 0) + a.score;
      possible[a.category] = (possible[a.category] ?? 0) + a.maxScore;
    }
    if (possible.isEmpty) return const [];

    final totalPossible = possible.values.fold<double>(0, (s, v) => s + v);
    return [
      for (final name in possible.keys)
        GradeCategory(
          name: name,
          weightPercentage: totalPossible <= 0
              ? 0
              : possible[name]! / totalPossible * 100,
          earnedPoints: earned[name] ?? 0,
          totalPoints: possible[name]!,
        ),
    ];
  }

  AssignmentStatus _statusFor(String text, {required bool graded}) {
    final t = text.toLowerCase();
    if (t.contains('missing') || t.contains('not submitted') || t.contains('ns')) {
      return AssignmentStatus.missing;
    }
    if (t.contains('pending') || t.contains('ungraded') || t.contains('in progress')) {
      return AssignmentStatus.pending;
    }
    if (t.contains('upcoming') || t.contains('not due') || t.contains('assigned')) {
      return AssignmentStatus.upcoming;
    }
    return graded ? AssignmentStatus.graded : AssignmentStatus.pending;
  }

  ({double earned, double possible})? _fractionIn(PortalRecord r) {
    for (final cell in r.cells) {
      final f = parseFraction(cell);
      if (f != null) return f;
    }
    return null;
  }

  // ── schedule ────────────────────────────────────────────────────────

  /// The day's periods. Returns [DaySchedule.unavailable] when the school has
  /// posted nothing.
  DaySchedule parseSchedule(String body, DateTime date) {
    final doc = PortalDocument.parse(body);
    final sets = doc.extractRecordSets(FieldMatcher.scheduleRow);

    final chosen = selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.period},
          prefer: _scheduleFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.timeRange},
          prefer: _scheduleFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle},
          prefer: _scheduleFields,
        );

    if (chosen == null) {
      return DaySchedule.unavailable(date);
    }
    if (readsAsUnavailable(doc.text) && chosen.records.length < 2) {
      return DaySchedule.unavailable(date);
    }

    final periods = <ScheduleEntry>[];
    var fallbackPeriod = 0;
    for (final r in chosen.records) {
      final title = r[SemanticField.courseTitle];
      if (title == null) continue;
      fallbackPeriod++;

      final range = _timeRangeIn(r, date);
      periods.add(ScheduleEntry(
        period: parsePeriod(r[SemanticField.period] ?? '') ?? fallbackPeriod,
        courseTitle: title,
        teacherName: r[SemanticField.teacher] ?? '',
        room: r[SemanticField.room] ?? '',
        startTime: range?.start ?? date,
        endTime: range?.end ?? date,
      ));
    }
    if (periods.isEmpty) return DaySchedule.unavailable(date);

    periods.sort((a, b) => a.period.compareTo(b.period));
    return DaySchedule(
      date: date,
      label: doc.dayLabel() ?? 'Today',
      periods: periods,
    );
  }

  static const Set<SemanticField> _scheduleFields = {
    SemanticField.period,
    SemanticField.timeRange,
    SemanticField.teacher,
    SemanticField.room,
  };

  ({DateTime start, DateTime end})? _timeRangeIn(PortalRecord r, DateTime day) {
    final labelled = r[SemanticField.timeRange];
    if (labelled != null) {
      final parsed = parseTimeRange(labelled, day);
      if (parsed != null) return parsed;
    }
    // Some portals put start and end in separate columns, or in with the room.
    for (final cell in r.cells) {
      final parsed = parseTimeRange(cell, day);
      if (parsed != null) return parsed;
    }
    return parseTimeRange(r.text, day);
  }

  // ── transcript ──────────────────────────────────────────────────────

  /// Completed courses. An empty list means the transcript is unavailable.
  List<TranscriptRecord> parseTranscript(String body) {
    final doc = PortalDocument.parse(body);
    final sets = doc.extractRecordSets(FieldMatcher.transcriptRow);

    // Credits or a term are what distinguish a transcript from a roster.
    final chosen = selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.credits},
          prefer: _transcriptFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.term},
          prefer: _transcriptFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.courseTitle, SemanticField.letterGrade},
          prefer: _transcriptFields,
        );
    if (chosen == null) return const [];

    final out = <TranscriptRecord>[];
    for (final r in chosen.records) {
      final title = r[SemanticField.courseTitle];
      if (title == null) continue;

      final letter = parseLetterGrade(r[SemanticField.letterGrade] ?? '') ?? '';
      final score = parseScore(r[SemanticField.score] ?? '') ?? 0;
      final credits = parseCredits(r[SemanticField.credits] ?? '') ?? 0;

      // Prefer the school's own GPA points; derive them only when absent, and
      // never for marks that carry no GPA weight.
      final published = parseNumber(r[SemanticField.gpaPoints] ?? '');
      final points = published ??
          GradeScale.gpaPointsFor(
            letter: letter.isEmpty ? null : letter,
            score: score > 0 ? score : null,
          ) ??
          0;

      out.add(TranscriptRecord(
        courseTitle: title,
        courseCode: r[SemanticField.courseCode] ?? '',
        finalScore: score,
        letterGrade: letter.isNotEmpty
            ? letter
            : (score > 0 ? GradeScale.letterFor(score) : ''),
        creditsEarned: credits,
        term: r[SemanticField.term] ?? '',
        gpaPoints: points,
      ));
    }
    return out;
  }

  static const Set<SemanticField> _transcriptFields = {
    SemanticField.letterGrade,
    SemanticField.score,
    SemanticField.credits,
    SemanticField.term,
    SemanticField.gpaPoints,
    SemanticField.courseCode,
  };

  // ── upcoming work ───────────────────────────────────────────────────

  /// Assignments due. An empty list means nothing was posted.
  List<WorkItem> parseWorkDue(String body) {
    final doc = PortalDocument.parse(body);
    final sets = doc.extractRecordSets(FieldMatcher.workRow);

    final chosen = selectRecordSet(
          sets,
          mustHave: {SemanticField.assignmentTitle, SemanticField.dueDate},
          prefer: _workFields,
        ) ??
        selectRecordSet(
          sets,
          mustHave: {SemanticField.assignmentTitle, SemanticField.courseTitle},
          prefer: _workFields,
        );
    if (chosen == null) return const [];

    final out = <WorkItem>[];
    var i = 0;
    for (final r in chosen.records) {
      final title = r[SemanticField.assignmentTitle];
      if (title == null) continue;
      i++;

      final statusText = (r[SemanticField.status] ?? '').toLowerCase();
      final submitted = statusText.contains('submitted') ||
          statusText.contains('turned in') ||
          statusText.contains('complete') ||
          statusText.contains('done');

      out.add(WorkItem(
        id: r.id ?? 'w$i',
        title: title,
        courseTitle: r[SemanticField.courseTitle] ?? '',
        type: _workType(r, title),
        dueDate: parseDate(r[SemanticField.dueDate] ?? '') ?? DateTime.now(),
        submitted: submitted,
        grade: r[SemanticField.letterGrade] ?? r[SemanticField.score],
      ));
    }
    return out;
  }

  static const Set<SemanticField> _workFields = {
    SemanticField.dueDate,
    SemanticField.courseTitle,
    SemanticField.status,
    SemanticField.itemType,
    SemanticField.letterGrade,
  };

  /// Portals name work types inconsistently, and often not at all — so fall
  /// back to reading the assignment's own title.
  String _workType(PortalRecord r, String title) {
    final declared = (r[SemanticField.itemType] ?? '').toLowerCase();
    final haystack = '$declared ${title.toLowerCase()}';
    if (haystack.contains('exam') ||
        haystack.contains('test') ||
        haystack.contains('midterm') ||
        haystack.contains('final')) {
      return 'test';
    }
    if (haystack.contains('quiz')) return 'quiz';
    if (haystack.contains('project') || haystack.contains('presentation')) {
      return 'project';
    }
    if (haystack.contains('essay') ||
        haystack.contains('paper') ||
        haystack.contains('dbq')) {
      return 'essay';
    }
    if (haystack.contains('lab')) return 'lab';
    return 'homework';
  }
}
