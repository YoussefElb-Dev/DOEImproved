import '../models/grade_models.dart';

/// Core grade math. Recalculates category-weighted course averages and
/// supports real-time "What-If" projections with hypothetical assignments.
class CalculatorService {
  const CalculatorService();

  /// Weighted average of all category scores (weights sum to 100).
  /// Categories with no points are excluded and their weight redistributed
  /// proportionally across categories that do have points.
  double calculateCourseAverage(Course course) =>
      _weightedAverage(course.categories);

  /// Recomputes the course average after applying [hypotheticals]:
  /// hypothetical assignments are merged into their matching category
  /// (added to earned/total points) before weighting.
  double calculateWhatIf(Course course, List<Assignment> hypotheticals) {
    final adjusted = <GradeCategory>[];
    for (final cat in course.categories) {
      double earned = cat.earnedPoints;
      double total = cat.totalPoints;
      for (final a in hypotheticals) {
        if (a.category == cat.name) {
          earned += a.score;
          total += a.maxScore;
        }
      }
      adjusted.add(cat.copyWith(earnedPoints: earned, totalPoints: total));
    }
    return _weightedAverage(adjusted);
  }

  /// What score (out of [maxScore]) on a new assignment in [categoryName]
  /// is needed to reach [targetAverage]? Returns null if impossible even
  /// at 100%.
  double? requiredScore({
    required Course course,
    required String categoryName,
    required double maxScore,
    required double targetAverage,
  }) {
    for (double s = 0; s <= 100.0; s += 0.5) {
      final hypothetical = Assignment(
        id: 'whatif',
        title: 'What-If',
        category: categoryName,
        score: s / 100 * maxScore,
        maxScore: maxScore,
        dueDate: DateTime.now(),
        status: AssignmentStatus.upcoming,
      );
      if (calculateWhatIf(course, [hypothetical]) >= targetAverage) {
        return s;
      }
    }
    return null;
  }

  String letterGradeFor(double score) {
    if (score >= 90) return 'A';
    if (score >= 80) return 'B';
    if (score >= 70) return 'C';
    if (score >= 65) return 'D';
    return 'F';
  }

  double _weightedAverage(List<GradeCategory> categories) {
    double weightedSum = 0;
    double weightTotal = 0;
    for (final c in categories) {
      if (c.totalPoints <= 0) continue;
      weightedSum += c.categoryScore * c.weightPercentage;
      weightTotal += c.weightPercentage;
    }
    return weightTotal == 0 ? 0 : weightedSum / weightTotal;
  }
}
