import '../models/grade_models.dart';
import '../models/schedule_models.dart';
import 'grade_scale.dart';

/// One point on the GPA trend chart.
class TermGpa {
  final String term;
  final double gpa;
  final double credits;
  final int courseCount;

  const TermGpa({
    required this.term,
    required this.gpa,
    required this.credits,
    required this.courseCount,
  });
}

/// One spoke of the subject-performance radar.
class SubjectScore {
  final String subject;
  final double score;
  final int courseCount;

  const SubjectScore({
    required this.subject,
    required this.score,
    required this.courseCount,
  });
}

/// Derives the numbers the analytics screens plot.
///
/// Everything here is computed from what the portal actually published — no
/// figure on a chart is invented, and a section with nothing behind it comes
/// back empty so the UI can say so rather than draw a flat line.
class AnalyticsService {
  const AnalyticsService();

  /// Credit-weighted GPA per term, oldest first.
  List<TermGpa> termGpaSeries(List<TranscriptRecord> transcript) {
    final byTerm = <String, List<TranscriptRecord>>{};
    for (final r in transcript) {
      final term = r.term.trim();
      if (term.isEmpty) continue;
      byTerm.putIfAbsent(term, () => []).add(r);
    }

    final out = <TermGpa>[];
    for (final entry in byTerm.entries) {
      var points = 0.0;
      var credits = 0.0;
      for (final r in entry.value) {
        if (r.creditsEarned <= 0) continue;
        if (r.letterGrade.isNotEmpty &&
            !GradeScale.countsTowardGpa(r.letterGrade)) {
          continue;
        }
        points += r.gpaPoints * r.creditsEarned;
        credits += r.creditsEarned;
      }
      if (credits <= 0) continue;
      out.add(TermGpa(
        term: entry.key,
        gpa: points / credits,
        credits: credits,
        courseCount: entry.value.length,
      ));
    }

    out.sort((a, b) => _termOrder(a.term).compareTo(_termOrder(b.term)));
    return out;
  }

  /// Sortable key for a term label.
  ///
  /// Handles "Fall 2024" / "Spring 2025" (an academic year runs autumn into
  /// spring, so autumn sorts *before* the following spring), plus the numbered
  /// forms schools use — "MP2", "Q3", "S1", "Term 4".
  static int _termOrder(String term) {
    final t = term.toLowerCase();
    final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(t);
    final year = int.tryParse(yearMatch?.group(0) ?? '') ?? 0;

    int season = 0;
    if (t.contains('spring')) {
      season = 1;
    } else if (t.contains('summer')) {
      season = 2;
    } else if (t.contains('fall') || t.contains('autumn')) {
      season = 3;
    } else if (t.contains('winter')) {
      season = 4;
    }

    if (season > 0) {
      // Fall 2024 precedes Spring 2025: shift autumn/winter into the year they
      // begin, so ordering follows the academic calendar rather than the digits.
      return year * 10 + season;
    }

    // No season word — fall back to any number in the label ("MP2", "Q3").
    final numberMatch = RegExp(r'\d+').firstMatch(t);
    final number = int.tryParse(numberMatch?.group(0) ?? '') ?? 0;
    return year > 0 ? year * 10 + number : number;
  }

  /// How many marks fall in each letter band, highest first.
  ///
  /// Uses the transcript when there is one, and this term's courses otherwise,
  /// so a student with no transcript posted still sees their spread.
  Map<String, int> gradeDistribution(
    List<TranscriptRecord> transcript,
    List<Course> courses,
  ) {
    const bands = ['A', 'B', 'C', 'D', 'F'];
    final counts = {for (final b in bands) b: 0};

    void add(String letter, double score) {
      var l = letter.trim().toUpperCase();
      if (l.isEmpty || !RegExp(r'^[A-F]').hasMatch(l)) {
        if (score <= 0) return;
        l = GradeScale.letterFor(score);
      }
      final band = l[0];
      if (counts.containsKey(band)) counts[band] = counts[band]! + 1;
    }

    if (transcript.isNotEmpty) {
      for (final r in transcript) {
        add(r.letterGrade, r.finalScore);
      }
    } else {
      for (final c in courses) {
        add(c.letterGrade, c.currentScore);
      }
    }

    counts.removeWhere((_, v) => v == 0);
    return counts;
  }

  /// Average score per subject area, for the radar chart.
  ///
  /// Subjects are inferred from course titles, which is the only signal a
  /// portal reliably gives. A course that matches nothing is grouped under
  /// "Other" rather than dropped.
  List<SubjectScore> subjectPerformance(List<Course> courses) {
    final totals = <String, double>{};
    final counts = <String, int>{};

    for (final c in courses) {
      final score = c.currentScore > 0
          ? c.currentScore
          : (GradeScale.scoreFor(c.letterGrade) ?? 0);
      if (score <= 0) continue;
      final subject = subjectOf(c.title);
      totals[subject] = (totals[subject] ?? 0) + score;
      counts[subject] = (counts[subject] ?? 0) + 1;
    }

    final out = [
      for (final entry in totals.entries)
        SubjectScore(
          subject: entry.key,
          score: entry.value / counts[entry.key]!,
          courseCount: counts[entry.key]!,
        ),
    ];
    out.sort((a, b) => a.subject.compareTo(b.subject));
    return out;
  }

  /// Buckets a course title into a broad subject area.
  static String subjectOf(String title) {
    final t = title.toLowerCase();
    bool has(List<String> words) => words.any(t.contains);

    if (has(['math', 'algebra', 'geometry', 'calculus', 'statistic',
        'trigonometry', 'precalc'])) {
      return 'Math';
    }

    if (has(['english', 'literature', 'writing', 'lit ', 'ela', 'reading'])) {
      return 'English';
    }
    if (has(['history', 'government', 'civics', 'economics', 'social',
        'geography', 'politics'])) {
      return 'History';
    }
    if (has(['spanish', 'french', 'chinese', 'latin', 'italian', 'language',
        'mandarin', 'arabic'])) {
      return 'Language';
    }
    // Checked before Science: "AP Computer Science" is a computing course.
    if (has(['computer', 'programming', 'coding', 'software', 'technology',
        'engineering'])) {
      return 'Tech';
    }
    if (has(['physics', 'chemistry', 'biology', 'science', 'earth',
        'living env', 'anatomy'])) {
      return 'Science';
    }
    if (has(['art', 'music', 'drawing', 'theater', 'theatre', 'ceramics',
        'band', 'chorus', 'studio'])) {
      return 'Arts';
    }
    if (has(['phys ed', 'physical education', 'gym', 'health', 'fitness'])) {
      return 'PE';
    }
    return 'Other';
  }

  /// The course with the highest current score, or null when none are graded.
  Course? topPerformer(List<Course> courses) {
    Course? best;
    for (final c in courses) {
      if (c.currentScore <= 0) continue;
      if (best == null || c.currentScore > best.currentScore) best = c;
    }
    return best;
  }

  /// The soonest unsubmitted item belonging to [course].
  ///
  /// Portals name the course differently between the roster and the work list
  /// ("AP Calculus BC" vs "AP Calc BC"), so matching is loose in both
  /// directions rather than an exact string comparison.
  WorkItem? nextFor(Course course, List<WorkItem> work) {
    final title = course.title.toLowerCase().trim();
    if (title.isEmpty) return null;

    WorkItem? best;
    for (final w in work) {
      if (w.submitted) continue;
      final owner = w.courseTitle.toLowerCase().trim();
      if (owner.isEmpty) continue;
      final matches = owner == title ||
          owner.contains(title) ||
          title.contains(owner) ||
          (course.code.isNotEmpty &&
              owner.contains(course.code.toLowerCase()));
      if (!matches) continue;
      if (best == null || w.dueDate.isBefore(best.dueDate)) best = w;
    }
    return best;
  }
}
