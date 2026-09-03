/// Schedule and work models for the DOEImproved portal.
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
}