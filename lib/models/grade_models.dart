/// Data models for the Gradly student portal.
library grade_models;

enum AssignmentStatus { graded, pending, missing, upcoming }

class StudentProfile {
  final String name;
  final String schoolName;
  final String avatarUrl;
  final double overallGpa;
  final double gpaChange;
  final double totalCredits;
  final int classRank;

  const StudentProfile({
    required this.name,
    required this.schoolName,
    required this.avatarUrl,
    required this.overallGpa,
    required this.gpaChange,
    required this.totalCredits,
    required this.classRank,
  });

  factory StudentProfile.fromJson(Map<String, dynamic> json) => StudentProfile(
        name: json['name'] as String? ?? 'Unknown Student',
        schoolName: json['schoolName'] as String? ?? '',
        avatarUrl: json['avatarUrl'] as String? ?? '',
        overallGpa: (json['overallGpa'] as num?)?.toDouble() ?? 0.0,
        gpaChange: (json['gpaChange'] as num?)?.toDouble() ?? 0.0,
        totalCredits: (json['totalCredits'] as num?)?.toDouble() ?? 0.0,
        classRank: (json['classRank'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'schoolName': schoolName,
        'avatarUrl': avatarUrl,
        'overallGpa': overallGpa,
        'gpaChange': gpaChange,
        'totalCredits': totalCredits,
        'classRank': classRank,
      };
}

class GradeCategory {
  final String name;
  final double weightPercentage; // 0-100
  final double earnedPoints;
  final double totalPoints;

  const GradeCategory({
    required this.name,
    required this.weightPercentage,
    required this.earnedPoints,
    required this.totalPoints,
  });

  double get categoryScore =>
      totalPoints <= 0 ? 0 : (earnedPoints / totalPoints) * 100;

  factory GradeCategory.fromJson(Map<String, dynamic> json) => GradeCategory(
        name: json['name'] as String? ?? 'Other',
        weightPercentage: (json['weightPercentage'] as num?)?.toDouble() ?? 0,
        earnedPoints: (json['earnedPoints'] as num?)?.toDouble() ?? 0,
        totalPoints: (json['totalPoints'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'weightPercentage': weightPercentage,
        'earnedPoints': earnedPoints,
        'totalPoints': totalPoints,
      };

  GradeCategory copyWith({double? earnedPoints, double? totalPoints}) =>
      GradeCategory(
        name: name,
        weightPercentage: weightPercentage,
        earnedPoints: earnedPoints ?? this.earnedPoints,
        totalPoints: totalPoints ?? this.totalPoints,
      );
}

class Assignment {
  final String id;
  final String title;
  final String category;
  final double score;
  final double maxScore;
  final DateTime dueDate;
  final AssignmentStatus status;

  const Assignment({
    required this.id,
    required this.title,
    required this.category,
    required this.score,
    required this.maxScore,
    required this.dueDate,
    required this.status,
  });

  double get percentage => maxScore <= 0 ? 0 : (score / maxScore) * 100;

  factory Assignment.fromJson(Map<String, dynamic> json) => Assignment(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled',
        category: json['category'] as String? ?? 'Other',
        score: (json['score'] as num?)?.toDouble() ?? 0.0,
        maxScore: (json['maxScore'] as num?)?.toDouble() ?? 100.0,
        dueDate: DateTime.tryParse(json['dueDate'] as String? ?? '') ??
            DateTime.now(),
        status: AssignmentStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => AssignmentStatus.graded,
        ),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'score': score,
        'maxScore': maxScore,
        'dueDate': dueDate.toIso8601String(),
        'status': status.name,
      };
}

class Course {
  final String id;
  final String title;
  final String code;
  final String teacherName;
  final double currentScore;
  final String letterGrade;
  final List<GradeCategory> categories;
  final List<Assignment> assignments;

  /// The portal's own link to this course's gradebook, when it published one.
  /// Followed verbatim, because detail URLs differ between portals; the
  /// `/courses/{id}` convention is only the fallback.
  final String? detailPath;

  const Course({
    required this.id,
    required this.title,
    required this.code,
    required this.teacherName,
    required this.currentScore,
    required this.letterGrade,
    required this.categories,
    required this.assignments,
    this.detailPath,
  });

  factory Course.fromJson(Map<String, dynamic> json) => Course(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Course',
        code: json['code'] as String? ?? '',
        teacherName: json['teacherName'] as String? ?? '',
        currentScore: (json['currentScore'] as num?)?.toDouble() ?? 0,
        letterGrade: json['letterGrade'] as String? ?? '',
        categories: [
          for (final c in (json['categories'] as List? ?? const []))
            GradeCategory.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        assignments: [
          for (final a in (json['assignments'] as List? ?? const []))
            Assignment.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        detailPath: json['detailPath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'code': code,
        'teacherName': teacherName,
        'currentScore': currentScore,
        'letterGrade': letterGrade,
        'categories': [for (final c in categories) c.toJson()],
        'assignments': [for (final a in assignments) a.toJson()],
        if (detailPath != null) 'detailPath': detailPath,
      };

  /// Grade boundaries on the standard NYC scale.
  static const List<MapEntry<double, String>> _boundaries = [
    MapEntry(90, 'A'),
    MapEntry(80, 'B'),
    MapEntry(70, 'C'),
    MapEntry(65, 'D'),
  ];

  /// Next grade boundary above [currentScore], or null if already at top.
  MapEntry<double, String>? get nextBoundary {
    for (final b in _boundaries) {
      if (currentScore < b.key) return b;
    }
    return null;
  }

  double get distanceToNextGrade {
    final b = nextBoundary;
    return b == null ? 0 : b.key - currentScore;
  }

  Course copyWith({
    double? currentScore,
    String? letterGrade,
    List<GradeCategory>? categories,
    List<Assignment>? assignments,
    String? detailPath,
  }) =>
      Course(
        id: id,
        title: title,
        code: code,
        teacherName: teacherName,
        currentScore: currentScore ?? this.currentScore,
        letterGrade: letterGrade ?? this.letterGrade,
        categories: categories ?? this.categories,
        assignments: assignments ?? this.assignments,
        detailPath: detailPath ?? this.detailPath,
      );
}
