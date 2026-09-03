/// Conversions between the several ways a school can express a mark.
///
/// NYC high schools post numeric grades where 65 passes, but transcripts also
/// carry letter grades and non-numeric codes, and different schools use
/// different combinations. Everything the app derives — a letter from a
/// percentage, GPA points from a letter, whether a course earned credit — goes
/// through here so the rules live in one place.
library;

class GradeScale {
  GradeScale._();

  /// The NYC passing mark.
  static const double passingScore = 65;

  /// Codes that are marks rather than grades. A course carrying one of these
  /// has no percentage and usually no GPA contribution.
  static const Set<String> nonNumericMarks = {
    'P', 'NS', 'INC', 'I', 'W', 'WD', 'CR', 'NC', 'AUD', 'EX', 'NG', 'MED',
  };

  /// Marks that earn credit without contributing GPA points.
  static const Set<String> creditOnlyMarks = {'P', 'CR'};

  /// Marks that are neither passing nor GPA-bearing.
  static const Set<String> _excludedFromGpa = {
    'P', 'CR', 'NC', 'INC', 'I', 'W', 'WD', 'AUD', 'EX', 'NG', 'MED',
  };

  /// Letter for a percentage, on the NYC boundaries.
  static String letterFor(double score) {
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= passingScore) return 'D';
    return 'F';
  }

  /// A representative percentage for a letter, used when a portal posts only
  /// letters. Midpoints of each band, so a derived average stays honest about
  /// being an approximation rather than overstating.
  static double? scoreFor(String letter) {
    final l = letter.toUpperCase().trim();
    const midpoints = <String, double>{
      'A+': 98, 'A': 95, 'A-': 91,
      'B+': 88, 'B': 85, 'B-': 81,
      'C+': 78, 'C': 75, 'C-': 71,
      'D+': 69, 'D': 67, 'D-': 65,
      'F': 55,
    };
    return midpoints[l];
  }

  /// Unweighted 4.0-scale GPA points.
  ///
  /// Deliberately unweighted: honours and AP weighting differs by school, and
  /// inventing a bonus would silently misstate a student's GPA. When the portal
  /// publishes its own GPA points, the parser uses those instead of this.
  static double? gpaPointsFor({String? letter, double? score}) {
    final l = letter?.toUpperCase().trim();

    if (l != null && l.isNotEmpty) {
      if (_excludedFromGpa.contains(l)) return null;
      const points = <String, double>{
        'A+': 4.0, 'A': 4.0, 'A-': 3.7,
        'B+': 3.3, 'B': 3.0, 'B-': 2.7,
        'C+': 2.3, 'C': 2.0, 'C-': 1.7,
        'D+': 1.3, 'D': 1.0, 'D-': 0.7,
        'F': 0.0, 'NS': 0.0,
      };
      final direct = points[l];
      if (direct != null) return direct;
    }

    if (score != null) return gpaPointsFor(letter: letterFor(score));
    return null;
  }

  /// Whether a mark counts toward GPA at all.
  static bool countsTowardGpa(String letter) {
    final l = letter.toUpperCase().trim();
    if (l.isEmpty) return false;
    return !_excludedFromGpa.contains(l);
  }

  /// Whether the course was passed, by letter or by percentage.
  static bool isPassing({String? letter, double? score}) {
    final l = letter?.toUpperCase().trim();
    if (l != null && l.isNotEmpty) {
      if (creditOnlyMarks.contains(l)) return true;
      if (l == 'F' || l == 'NS' || l == 'NC') return false;
      if (nonNumericMarks.contains(l)) return false;
      return !l.startsWith('F');
    }
    if (score != null) return score >= passingScore;
    return false;
  }

  /// True for a mark with no percentage behind it, so the UI can show the code
  /// itself rather than a meaningless "0%".
  static bool isNonNumeric(String letter) =>
      nonNumericMarks.contains(letter.toUpperCase().trim());
}
