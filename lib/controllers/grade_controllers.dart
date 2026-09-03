import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/grade_models.dart';
import '../services/calculator_service.dart';

/// State controller exposing grade math and What-If projections for a
/// single course. Kept separate from UI so it can be reused/tested.
class GradeController extends StateNotifier<Course> {
  final CalculatorService calculator;

  GradeController(this.calculator, Course initial) : super(initial);

  /// Projects the average after hypothetical assignments are applied,
  /// without mutating persisted state unless [commit] is true.
  double projectAverage(List<Assignment> hypotheticals) =>
      calculator.calculateWhatIf(state, hypotheticals);

  double get currentAverage => calculator.calculateCourseAverage(state);

  void commitWhatIf(List<Assignment> hypotheticals) {
    state = state.copyWith(
      currentScore: projectAverage(hypotheticals),
      letterGrade: calculator.letterGradeFor(projectAverage(hypotheticals)),
    );
  }
}