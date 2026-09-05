import 'normalized_transcript.dart';
import 'schedule_models.dart';

/// One completed class presented consistently whether it came from the live
/// portal, a saved DOE PDF, or a manually imported transcript.
class TakenClassRecord {
  const TakenClassRecord({
    required this.id,
    required this.title,
    required this.courseCode,
    required this.term,
    required this.creditsAttempted,
    required this.creditsEarned,
    this.numericGrade,
    this.letterGrade,
    this.institution,
    this.countsTowardGpa = true,
    this.weighted = false,
  });

  final String id;
  final String title;
  final String courseCode;
  final String term;
  final double creditsAttempted;
  final double creditsEarned;
  final double? numericGrade;
  final String? letterGrade;
  final String? institution;
  final bool countsTowardGpa;
  final bool weighted;

  String get dedupeKey {
    final normalizedCode = courseCode
        .replaceFirst(RegExp(r'^\d{2}[A-Z]\d{3}', caseSensitive: false), '')
        .trim()
        .toLowerCase();
    return <String>[
      term.trim().toLowerCase(),
      normalizedCode.isEmpty ? title.trim().toLowerCase() : normalizedCode,
    ].join('|');
  }

  String get displayGrade {
    final number = numericGrade;
    final numeric = number == null
        ? null
        : number == number.roundToDouble()
            ? number.toStringAsFixed(0)
            : number.toStringAsFixed(1);
    final letter = letterGrade?.trim();
    if (numeric != null && letter != null && letter.isNotEmpty) {
      return '$numeric · $letter';
    }
    return numeric ?? (letter == null || letter.isEmpty ? '—' : letter);
  }

  TranscriptRecord toTranscriptRecord() => TranscriptRecord(
        courseTitle: title,
        courseCode: courseCode,
        finalScore: numericGrade ?? 0,
        letterGrade: countsTowardGpa
            ? letterGrade ?? _letterFor(numericGrade)
            : 'P',
        creditsEarned: creditsEarned,
        term: term,
        gpaPoints:
            countsTowardGpa ? _gpaPoints(letterGrade, numericGrade) : 0,
      );

  static String _letterFor(double? score) {
    if (score == null) return '';
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 65) return 'D';
    return 'F';
  }

  static double _gpaPoints(
    String? letter,
    double? score,
  ) {
    final value = (letter == null || letter.trim().isEmpty
            ? _letterFor(score)
            : letter)
        .toUpperCase();
    final base = switch (value) {
      'A+' || 'A' => 4.0,
      'A-' => 3.7,
      'B+' => 3.3,
      'B' => 3.0,
      'B-' => 2.7,
      'C+' => 2.3,
      'C' => 2.0,
      'C-' => 1.7,
      'D+' => 1.3,
      'D' => 1.0,
      'D-' => 0.7,
      _ => 0.0,
    };
    return base;
  }
}

/// The durable academic record consumed by the Grades and Analytics tabs.
class AcademicHistory {
  const AcademicHistory({
    this.classes = const [],
    this.creditsEarned = 0,
    this.cumulativeAveragePercent,
    this.cumulativeGpa,
    this.institutionCount = 0,
  });

  final List<TakenClassRecord> classes;
  final double creditsEarned;
  final double? cumulativeAveragePercent;
  final double? cumulativeGpa;
  final int institutionCount;

  List<TranscriptRecord> get transcriptRecords =>
      [for (final course in classes) course.toTranscriptRecord()];

  factory AcademicHistory.combine({
    List<NormalizedTranscript> normalized = const [],
    List<TranscriptRecord> legacy = const [],
  }) {
    final classes = <TakenClassRecord>[];
    final seen = <String>{};
    var credits = 0.0;
    double? average;
    double? gpa;
    final institutions = <String>{};

    for (final transcript in normalized) {
      final institution = transcript.institution.name?.trim();
      if (institution != null && institution.isNotEmpty) {
        institutions.add(institution.toLowerCase());
      }
      average ??= transcript.cumulative.cumulativeAveragePercent;
      gpa ??= transcript.cumulative.overallGpa ??
          transcript.cumulative.cumulativeGpa ??
          transcript.cumulative.institutionalGpa;

      final officialCredits = transcript.cumulative.creditsEarned;
      if (officialCredits != null) {
        credits += officialCredits;
      } else {
        credits += transcript.terms.fold<double>(
          0,
          (sum, term) => sum + term.courses.fold<double>(
            0,
            (termSum, course) => termSum + (course.creditsEarned ?? 0),
          ),
        );
      }

      final orderedTerms = [...transcript.terms]
        ..sort((a, b) => _termOrder(b).compareTo(_termOrder(a)));
      for (final term in orderedTerms) {
        final termLabel = term.label?.trim();
        for (final course in term.courses) {
          final title = course.title?.trim();
          if (title == null || title.isEmpty) continue;
          final code = '${course.subjectCode ?? ''}${course.courseNumber ?? ''}'
              .trim();
          final item = TakenClassRecord(
            id: '${transcript.id}|${term.id}|${course.id}',
            title: title,
            courseCode: code,
            term: termLabel == null || termLabel.isEmpty
                ? 'Transcript courses'
                : termLabel,
            creditsAttempted:
                course.creditsAttempted ?? course.creditsEarned ?? 0,
            creditsEarned: course.creditsEarned ?? 0,
            numericGrade: course.numericGrade,
            letterGrade: course.letterGrade,
            institution: institution,
            countsTowardGpa: course.countsTowardGpa ?? true,
            weighted: course.flags.weighted,
          );
          if (seen.add(item.dedupeKey)) classes.add(item);
        }
      }
    }

    for (final course in legacy.reversed) {
      final item = TakenClassRecord(
        id: 'legacy|${course.term}|${course.courseCode}|${course.courseTitle}',
        title: course.courseTitle,
        courseCode: course.courseCode,
        term: course.term.trim().isEmpty ? 'Transcript courses' : course.term,
        creditsAttempted: course.creditsEarned,
        creditsEarned: course.creditsEarned,
        numericGrade: course.finalScore > 0 ? course.finalScore : null,
        letterGrade:
            course.letterGrade.trim().isEmpty ? null : course.letterGrade,
        countsTowardGpa: course.gpaPoints > 0,
      );
      if (seen.add(item.dedupeKey)) classes.add(item);
    }

    if (normalized.isEmpty) {
      credits = classes.fold<double>(
        0,
        (sum, course) => sum + course.creditsEarned,
      );
    }

    return AcademicHistory(
      classes: List.unmodifiable(classes),
      creditsEarned: credits,
      cumulativeAveragePercent: average,
      cumulativeGpa: gpa,
      institutionCount: institutions.length,
    );
  }

  static int _termOrder(NormalizedTerm term) {
    final label = (term.label ?? '').toLowerCase();
    final printedYear = RegExp(r'(19|20)\d{2}').firstMatch(label)?.group(0);
    final year = term.year ?? int.tryParse(printedYear ?? '') ?? 0;
    var part = 0;
    final numbered = RegExp(r'(?:term|semester|quarter|mp|q)\s*(\d{1,2})')
        .firstMatch(label);
    if (numbered != null) {
      part = int.tryParse(numbered.group(1) ?? '') ?? 0;
    } else if (label.contains('spring')) {
      part = 2;
    } else if (label.contains('summer')) {
      part = 3;
    } else if (label.contains('fall') || label.contains('autumn')) {
      part = 4;
    } else if (label.contains('winter')) {
      part = 1;
    }
    return year * 100 + part;
  }
}
