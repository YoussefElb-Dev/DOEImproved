/// Schedule and work models for the Gradly portal.
library schedule_models;

/// One period entry in the daily schedule.
class ScheduleEntry {
  final int period;
  final String courseTitle;
  final String teacherName;
  final String room;
  final DateTime startTime;
  final DateTime endTime;

  const ScheduleEntry({
    required this.period,
    required this.courseTitle,
    required this.teacherName,
    required this.room,
    required this.startTime,
    required this.endTime,
  });

  bool get isCurrent {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  factory ScheduleEntry.fromJson(Map<String, dynamic> json) => ScheduleEntry(
        period: (json['period'] as num?)?.toInt() ?? 0,
        courseTitle: json['courseTitle'] as String? ?? '',
        teacherName: json['teacherName'] as String? ?? '',
        room: json['room'] as String? ?? '',
        startTime: DateTime.tryParse(json['startTime'] as String? ?? '') ??
            DateTime.now(),
        endTime: DateTime.tryParse(json['endTime'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'period': period,
        'courseTitle': courseTitle,
        'teacherName': teacherName,
        'room': room,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
      };
}

/// A day's schedule (or "not posted" status).
class DaySchedule {
  final DateTime date;
  final String label; // e.g. "A Day"
  final List<ScheduleEntry> periods;
  final bool available;

  const DaySchedule({
    required this.date,
    required this.label,
    required this.periods,
    this.available = true,
  });

  static DaySchedule unavailable(DateTime date) =>
      DaySchedule(date: date, label: '', periods: const [], available: false);

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
        date: DateTime.tryParse(json['date'] as String? ?? '') ??
            DateTime.now(),
        label: json['label'] as String? ?? '',
        periods: [
          for (final p in (json['periods'] as List? ?? const []))
            ScheduleEntry.fromJson(Map<String, dynamic>.from(p as Map)),
        ],
        available: json['available'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'label': label,
        'periods': [for (final p in periods) p.toJson()],
        'available': available,
      };
}

/// A transcript record: completed course with final grade + credits.
class TranscriptRecord {
  final String courseTitle;
  final String courseCode;
  final double finalScore;
  final String letterGrade;
  final double creditsEarned;
  final String term; // e.g. "Fall 2025"
  final double gpaPoints;

  const TranscriptRecord({
    required this.courseTitle,
    required this.courseCode,
    required this.finalScore,
    required this.letterGrade,
    required this.creditsEarned,
    required this.term,
    required this.gpaPoints,
  });

  factory TranscriptRecord.fromJson(Map<String, dynamic> json) =>
      TranscriptRecord(
        courseTitle: json['courseTitle'] as String? ?? '',
        courseCode: json['courseCode'] as String? ?? '',
        finalScore: (json['finalScore'] as num?)?.toDouble() ?? 0,
        letterGrade: json['letterGrade'] as String? ?? '',
        creditsEarned: (json['creditsEarned'] as num?)?.toDouble() ?? 0,
        term: json['term'] as String? ?? '',
        gpaPoints: (json['gpaPoints'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'courseTitle': courseTitle,
        'courseCode': courseCode,
        'finalScore': finalScore,
        'letterGrade': letterGrade,
        'creditsEarned': creditsEarned,
        'term': term,
        'gpaPoints': gpaPoints,
      };
}

/// Upcoming work item: homework, test, or project due soon.
class WorkItem {
  final String id;
  final String title;
  final String courseTitle;
  final String type; // 'homework', 'test', 'project', 'quiz'
  final DateTime dueDate;
  final bool submitted;
  final String? grade;

  const WorkItem({
    required this.id,
    required this.title,
    required this.courseTitle,
    required this.type,
    required this.dueDate,
    this.submitted = false,
    this.grade,
  });

  int get daysUntilDue => dueDate.difference(DateTime.now()).inDays;
  bool get isOverdue => !submitted && DateTime.now().isAfter(dueDate);

  factory WorkItem.fromJson(Map<String, dynamic> json) => WorkItem(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? '',
        courseTitle: json['courseTitle'] as String? ?? '',
        type: json['type'] as String? ?? 'homework',
        dueDate:
            DateTime.tryParse(json['dueDate'] as String? ?? '') ?? DateTime.now(),
        submitted: json['submitted'] as bool? ?? false,
        grade: json['grade'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'courseTitle': courseTitle,
        'type': type,
        'dueDate': dueDate.toIso8601String(),
        'submitted': submitted,
        if (grade != null) 'grade': grade,
      };
}