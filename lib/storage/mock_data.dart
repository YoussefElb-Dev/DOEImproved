import '../models/grade_models.dart';

/// Realistic mock student data for development and preview.
final StudentProfile mockStudentProfile = StudentProfile(
  name: 'Jordan Alvarez',
  schoolName: 'Brooklyn Technical High School',
  avatarUrl: '',
  overallGpa: 3.92,
  gpaChange: 0.15,
  totalCredits: 42,
  classRank: 12,
);

final List<Course> mockCourses = [
  Course(
    id: 'c1',
    title: 'AP Calculus BC',
    code: 'MATH-410',
    teacherName: 'Ms. Okafor',
    currentScore: 88.8,
    letterGrade: 'B',
    categories: [
      GradeCategory(name: 'Homework', weightPercentage: 20, earnedPoints: 340, totalPoints: 370),
      GradeCategory(name: 'Quizzes', weightPercentage: 25, earnedPoints: 160, totalPoints: 200),
      GradeCategory(name: 'Tests', weightPercentage: 40, earnedPoints: 340, totalPoints: 400),
      GradeCategory(name: 'Participation', weightPercentage: 15, earnedPoints: 95, totalPoints: 100),
    ],
    assignments: [
      Assignment(id: 'a1', title: 'Derivatives Quiz', category: 'Quizzes', score: 42, maxScore: 50, dueDate: _d('2026-08-28'), status: AssignmentStatus.graded),
      Assignment(id: 'a2', title: 'Integrals Test', category: 'Tests', score: 86, maxScore: 100, dueDate: _d('2026-08-15'), status: AssignmentStatus.graded),
      Assignment(id: 'a3', title: 'Series Project', category: 'Homework', score: 0, maxScore: 100, dueDate: _d('2026-09-10'), status: AssignmentStatus.upcoming),
    ],
  ),
  Course(
    id: 'c2',
    title: 'AP English Literature',
    code: 'ENGL-402',
    teacherName: 'Mr. Hewitt',
    currentScore: 94.1,
    letterGrade: 'A',
    categories: [
      GradeCategory(name: 'Essays', weightPercentage: 50, earnedPoints: 470, totalPoints: 500),
      GradeCategory(name: 'Reading', weightPercentage: 30, earnedPoints: 280, totalPoints: 300),
      GradeCategory(name: 'Quizzes', weightPercentage: 20, earnedPoints: 190, totalPoints: 200),
    ],
    assignments: [
      Assignment(id: 'a4', title: 'Hamlet Analysis Essay', category: 'Essays', score: 47, maxScore: 50, dueDate: _d('2026-08-22'), status: AssignmentStatus.graded),
      Assignment(id: 'a5', title: 'Poetry Quiz', category: 'Quizzes', score: 95, maxScore: 100, dueDate: _d('2026-08-30'), status: AssignmentStatus.graded),
      Assignment(id: 'a6', title: 'Gatsby Reading Log', category: 'Reading', score: 0, maxScore: 40, dueDate: _d('2026-09-12'), status: AssignmentStatus.upcoming),
    ],
  ),
  Course(
    id: 'c3',
    title: 'AP Physics C: Mechanics',
    code: 'PHYS-405',
    teacherName: 'Dr. Vasquez',
    currentScore: 79.6,
    letterGrade: 'C',
    categories: [
      GradeCategory(name: 'Labs', weightPercentage: 30, earnedPoints: 140, totalPoints: 180),
      GradeCategory(name: 'Tests', weightPercentage: 50, earnedPoints: 320, totalPoints: 400),
      GradeCategory(name: 'Homework', weightPercentage: 20, earnedPoints: 150, totalPoints: 190),
    ],
    assignments: [
      Assignment(id: 'a7', title: 'Rotational Motion Test', category: 'Tests', score: 78, maxScore: 100, dueDate: _d('2026-08-19'), status: AssignmentStatus.graded),
      Assignment(id: 'a8', title: 'Ballistics Lab Report', category: 'Labs', score: 0, maxScore: 50, dueDate: _d('2026-08-25'), status: AssignmentStatus.missing),
      Assignment(id: 'a9', title: 'Problem Set 4', category: 'Homework', score: 42, maxScore: 50, dueDate: _d('2026-09-05'), status: AssignmentStatus.graded),
    ],
  ),
  Course(
    id: 'c4',
    title: 'U.S. History Honors',
    code: 'HIST-301',
    teacherName: 'Ms. Lindqvist',
    currentScore: 72.3,
    letterGrade: 'C',
    categories: [
      GradeCategory(name: 'Essays', weightPercentage: 35, earnedPoints: 250, totalPoints: 350),
      GradeCategory(name: 'Tests', weightPercentage: 45, earnedPoints: 310, totalPoints: 450),
      GradeCategory(name: 'Homework', weightPercentage: 20, earnedPoints: 160, totalPoints: 200),
    ],
    assignments: [
      Assignment(id: 'a10', title: 'Civil War Essay', category: 'Essays', score: 80, maxScore: 100, dueDate: _d('2026-08-18'), status: AssignmentStatus.graded),
      Assignment(id: 'a11', title: 'Reconstruction Test', category: 'Tests', score: 71, maxScore: 100, dueDate: _d('2026-09-02'), status: AssignmentStatus.pending),
      Assignment(id: 'a12', title: 'Primary Source Analysis', category: 'Homework', score: 18, maxScore: 20, dueDate: _d('2026-08-27'), status: AssignmentStatus.graded),
    ],
  ),
];

DateTime _d(String iso) => DateTime.parse(iso);