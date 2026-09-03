import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/services/calculator_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const calc = CalculatorService();

  Course makeCourse({required List<GradeCategory> cats}) => Course(
        id: 'x',
        title: 'Test',
        code: 'T-1',
        teacherName: 'T',
        currentScore: 0,
        letterGrade: 'F',
        categories: cats,
        assignments: const [],
      );

  group('calculateCourseAverage', () {
    test('single category returns its percentage', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 100, earnedPoints: 80, totalPoints: 100),
      ]);
      expect(calc.calculateCourseAverage(c), closeTo(80.0, 0.001));
    });

    test('weighted categories combine correctly', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 50, earnedPoints: 80, totalPoints: 100),
        const GradeCategory(name: 'HW', weightPercentage: 50, earnedPoints: 100, totalPoints: 100),
      ]);
      expect(calc.calculateCourseAverage(c), closeTo(90.0, 0.001));
    });

    test('empty categories are excluded and weights redistributed', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 50, earnedPoints: 80, totalPoints: 100),
        const GradeCategory(name: 'Labs', weightPercentage: 50, earnedPoints: 0, totalPoints: 0),
      ]);
      expect(calc.calculateCourseAverage(c), closeTo(80.0, 0.001));
    });
  });

  group('calculateWhatIf', () {
    test('perfect hypothetical score lifts the average', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 100, earnedPoints: 80, totalPoints: 100),
      ]);
      final projected = calc.calculateWhatIf(c, [
        Assignment(
          id: 'h',
          title: 'Final',
          category: 'Tests',
          score: 100,
          maxScore: 100,
          dueDate: DateTime.now(),
          status: AssignmentStatus.upcoming,
        ),
      ]);
      expect(projected, closeTo(90.0, 0.001)); // (80+100)/(100+100)
    });

    test('hypothetical in unmatched category has no effect', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 100, earnedPoints: 80, totalPoints: 100),
      ]);
      final projected = calc.calculateWhatIf(c, [
        Assignment(
          id: 'h',
          title: 'X',
          category: 'Other',
          score: 100,
          maxScore: 100,
          dueDate: DateTime.now(),
          status: AssignmentStatus.upcoming,
        ),
      ]);
      expect(projected, closeTo(80.0, 0.001));
    });
  });

  group('requiredScore', () {
    test('finds the score needed to reach a target', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 100, earnedPoints: 80, totalPoints: 100),
      ]);
      final needed = calc.requiredScore(
        course: c,
        categoryName: 'Tests',
        maxScore: 100,
        targetAverage: 90.0,
      );
      expect(needed, isNotNull);
      expect(needed!, greaterThanOrEqualTo(99.0));
    });

    test('returns null when target is unreachable at 100%', () {
      final c = makeCourse(cats: [
        const GradeCategory(name: 'Tests', weightPercentage: 100, earnedPoints: 0, totalPoints: 1000),
      ]);
      expect(
        calc.requiredScore(course: c, categoryName: 'Tests', maxScore: 10, targetAverage: 95.0),
        isNull,
      );
    });
  });

  group('letterGradeFor', () {
    test('boundaries', () {
      expect(calc.letterGradeFor(90), 'A');
      expect(calc.letterGradeFor(89.9), 'B');
      expect(calc.letterGradeFor(80), 'B');
      expect(calc.letterGradeFor(70), 'C');
      expect(calc.letterGradeFor(65), 'D');
      expect(calc.letterGradeFor(64.9), 'F');
    });
  });
}