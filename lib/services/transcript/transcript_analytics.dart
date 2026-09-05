import '../../models/normalized_transcript.dart';
import '../grade_scale.dart';

class GpaAudit {
  final double? stated;
  final double? computed;
  final double? difference;
  final double gpaCredits;
  final double qualityPoints;
  final bool usedFallbackScale;
  final List<String> excludedCourses;
  final List<String> warnings;

  const GpaAudit({
    this.stated,
    this.computed,
    this.difference,
    required this.gpaCredits,
    required this.qualityPoints,
    required this.usedFallbackScale,
    this.excludedCourses = const [],
    this.warnings = const [],
  });

  bool get mismatched => difference != null && difference!.abs() > .02;
}

class ScaleConversions {
  final double? fourPoint;
  final double? fivePoint;
  final double? fourThreePoint;
  final double? percentage;
  final String? letter;
  final bool estimated;

  const ScaleConversions({
    this.fourPoint,
    this.fivePoint,
    this.fourThreePoint,
    this.percentage,
    this.letter,
    this.estimated = true,
  });
}

class TranscriptTermMetric {
  final String label;
  final double? gpa;
  final double creditsEarned;

  const TranscriptTermMetric({
    required this.label,
    this.gpa,
    required this.creditsEarned,
  });
}

class WhatIfResult {
  final double? requiredGpa;
  final bool reachable;
  final String? message;

  const WhatIfResult({this.requiredGpa, required this.reachable, this.message});
}

/// Calculations over the normalized schema. Printed values always win;
/// estimates are labelled and never written back into parsed fields.
class TranscriptAnalytics {
  const TranscriptAnalytics();

  GpaAudit audit(NormalizedTranscript transcript) {
    final legend = {
      for (final entry in transcript.gradingScale)
        if (entry.gradePoints != null)
          entry.label.toUpperCase(): entry.gradePoints!,
    };
    var usedFallback = false;
    var credits = 0.0;
    var quality = 0.0;
    final excluded = <String>[];
    final warnings = <String>[];

    for (final term in transcript.terms) {
      for (final course in term.courses) {
        if (!_counts(course, transcript.repeatPolicy)) {
          excluded.add(_courseName(course));
          continue;
        }
        final hours = course.creditsAttempted ?? course.creditsEarned;
        if (hours == null || hours <= 0) {
          excluded.add('${_courseName(course)} (missing GPA hours)');
          continue;
        }

        double? courseQuality = course.qualityPoints;
        if (courseQuality == null) {
          var points = course.gradePoints;
          if (points == null && course.letterGrade != null) {
            points = legend[course.letterGrade!.toUpperCase()];
            if (points == null) {
              points = GradeScale.gpaPointsFor(letter: course.letterGrade);
              usedFallback = true;
            }
          }
          if (points == null && course.numericGrade != null) {
            points = GradeScale.gpaPointsFor(score: course.numericGrade);
            usedFallback = true;
          }
          if (points == null) {
            excluded.add('${_courseName(course)} (missing grade points)');
            continue;
          }
          courseQuality = points * hours;
        }
        credits += hours;
        quality += courseQuality;
      }
    }

    final computed = credits <= 0 ? null : quality / credits;
    final stated = transcript.cumulative.cumulativeGpa ??
        transcript.cumulative.overallGpa ??
        transcript.cumulative.institutionalGpa;
    final difference = computed == null || stated == null ? null : computed - stated;
    if (usedFallback) {
      warnings.add(
        'Some grade points were estimated with a standard 4.0 scale because '
        'the transcript did not print a usable legend.',
      );
    }
    if (transcript.repeatPolicy == RepeatPolicy.unknown &&
        transcript.terms
            .expand((term) => term.courses)
            .any((course) => course.flags.repeated)) {
      warnings.add('A repeated course was found, but its repeat policy is unknown.');
    }
    return GpaAudit(
      stated: stated,
      computed: computed,
      difference: difference,
      gpaCredits: credits,
      qualityPoints: quality,
      usedFallbackScale: usedFallback,
      excludedCourses: excluded,
      warnings: warnings,
    );
  }

  ScaleConversions convert(double? gpa) {
    if (gpa == null) return const ScaleConversions();
    final four = gpa.clamp(0, 4).toDouble();
    final percentage = _percentageFor(four);
    return ScaleConversions(
      fourPoint: four,
      fivePoint: four / 4 * 5,
      fourThreePoint: four / 4 * 4.3,
      percentage: percentage,
      letter: GradeScale.letterFor(percentage),
      estimated: true,
    );
  }

  List<TranscriptTermMetric> termMetrics(NormalizedTranscript transcript) => [
        for (final term in transcript.terms)
          TranscriptTermMetric(
            label: term.label ?? 'Unassigned term',
            gpa: term.statedGpa ?? _termGpa(term, transcript),
            creditsEarned: term.creditsEarned ??
                term.courses.fold(
                  0,
                  (sum, course) => sum + (course.creditsEarned ?? 0),
                ),
          ),
      ];

  Map<String, double> creditsBySubject(NormalizedTranscript transcript) {
    final result = <String, double>{};
    for (final course in transcript.terms.expand((term) => term.courses)) {
      final subject = course.subjectCode ?? 'Other';
      result[subject] =
          (result[subject] ?? 0) + (course.creditsEarned ?? 0);
    }
    return result;
  }

  Map<String, int> gradeDistribution(NormalizedTranscript transcript) {
    final result = <String, int>{};
    for (final course in transcript.terms.expand((term) => term.courses)) {
      final grade = course.letterGrade ??
          (course.numericGrade == null
              ? null
              : GradeScale.letterFor(course.numericGrade!));
      if (grade == null) continue;
      result[grade] = (result[grade] ?? 0) + 1;
    }
    return result;
  }

  double? degreeProgress(NormalizedTranscript transcript) {
    final required = transcript.program.creditsRequired;
    final earned = transcript.cumulative.creditsEarned;
    if (required == null || required <= 0 || earned == null) return null;
    return (earned / required).clamp(0, 1).toDouble();
  }

  WhatIfResult whatIf({
    required double currentGpa,
    required double currentGpaCredits,
    required double remainingCredits,
    required double targetGpa,
    double maximumFutureGpa = 4,
  }) {
    if (remainingCredits <= 0) {
      return const WhatIfResult(
        reachable: false,
        message: 'Remaining credits must be greater than zero.',
      );
    }
    final required =
        (targetGpa * (currentGpaCredits + remainingCredits) -
                currentGpa * currentGpaCredits) /
            remainingCredits;
    if (required < 0) {
      return const WhatIfResult(requiredGpa: 0, reachable: true);
    }
    if (required > maximumFutureGpa) {
      return WhatIfResult(
        requiredGpa: required,
        reachable: false,
        message: 'That target requires more than a '
            '${maximumFutureGpa.toStringAsFixed(1)} GPA over the remaining credits.',
      );
    }
    return WhatIfResult(requiredGpa: required, reachable: true);
  }

  double semesterCredits(double credits, CreditSystem system) =>
      system == CreditSystem.quarter ? credits * 2 / 3 : credits;

  bool _counts(NormalizedCourse course, RepeatPolicy repeatPolicy) {
    if (course.countsTowardGpa == false) return false;
    final flags = course.flags;
    if (flags.passFail ||
        flags.audit ||
        flags.withdrawn ||
        flags.incomplete ||
        flags.inProgress ||
        flags.transfer ||
        flags.gradeReplaced) {
      return false;
    }
    if (flags.repeated && repeatPolicy == RepeatPolicy.replace) {
      // The replaced attempt should be marked gradeReplaced. If it is not,
      // retain it and surface the unknown policy warning rather than guessing
      // which attempt the institution intended to keep.
      return !flags.gradeReplaced;
    }
    return course.countsTowardGpa ?? true;
  }

  double? _termGpa(NormalizedTerm term, NormalizedTranscript transcript) {
    final scoped = NormalizedTranscript(
      id: transcript.id,
      sourceFingerprint: transcript.sourceFingerprint,
      sourceFileName: transcript.sourceFileName,
      importedAt: transcript.importedAt,
      rawText: transcript.rawText,
      student: transcript.student,
      institution: transcript.institution,
      gradingScale: transcript.gradingScale,
      repeatPolicy: transcript.repeatPolicy,
      terms: [term],
      cumulative: const CumulativeSummary(),
    );
    return audit(scoped).computed;
  }

  static String _courseName(NormalizedCourse course) =>
      course.title ?? '${course.subjectCode ?? ''} ${course.courseNumber ?? ''}'.trim();

  static double _percentageFor(double gpa) {
    if (gpa >= 4) return 95;
    if (gpa >= 3.7) return 90 + (gpa - 3.7) / .3 * 4;
    if (gpa >= 3) return 80 + (gpa - 3) / .7 * 9;
    if (gpa >= 2) return 70 + (gpa - 2) * 9;
    if (gpa >= 1) return 65 + (gpa - 1) * 4;
    return gpa * 64;
  }
}
