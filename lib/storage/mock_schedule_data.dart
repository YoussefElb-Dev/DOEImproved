import '../models/schedule_models.dart';

/// Mock schedule/transcript/work data used when the portal has no live data.

DateTime _t(int h, int m) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, h, m);
}

final DaySchedule mockDaySchedule = DaySchedule(
  date: DateTime.now(),
  label: 'A Day',
  periods: [
    ScheduleEntry(period: 1, courseTitle: 'AP Calculus BC', teacherName: 'Ms. Okafor', room: '4W12', startTime: _t(8, 0), endTime: _t(8, 45)),
    ScheduleEntry(period: 2, courseTitle: 'AP English Literature', teacherName: 'Mr. Hewitt', room: '3E08', startTime: _t(8, 50), endTime: _t(9, 35)),
    ScheduleEntry(period: 3, courseTitle: 'AP Physics C: Mechanics', teacherName: 'Dr. Vasquez', room: '5S02', startTime: _t(9, 40), endTime: _t(10, 25)),
    ScheduleEntry(period: 4, courseTitle: 'Lunch', teacherName: '', room: 'Cafeteria', startTime: _t(10, 30), endTime: _t(11, 15)),
    ScheduleEntry(period: 5, courseTitle: 'U.S. History Honors', teacherName: 'Ms. Lindqvist', room: '2N14', startTime: _t(11, 20), endTime: _t(12, 5)),
    ScheduleEntry(period: 6, courseTitle: 'Computer Science', teacherName: 'Mr. Adeyemi', room: '6T01', startTime: _t(12, 10), endTime: _t(12, 55)),
    ScheduleEntry(period: 7, courseTitle: 'Spanish IV', teacherName: 'Sra. Morales', room: '2W09', startTime: _t(13, 0), endTime: _t(13, 45)),
  ],
);

final List<TranscriptRecord> mockTranscript = [
  TranscriptRecord(courseTitle: 'Geometry Honors', courseCode: 'M41', finalScore: 95, letterGrade: 'A', creditsEarned: 1.0, term: 'Fall 2024', gpaPoints: 4.0),
  TranscriptRecord(courseTitle: 'English 10 Honors', courseCode: 'E42', finalScore: 93, letterGrade: 'A', creditsEarned: 1.0, term: 'Fall 2024', gpaPoints: 4.0),
  TranscriptRecord(courseTitle: 'Living Environment', courseCode: 'S41', finalScore: 91, letterGrade: 'A', creditsEarned: 1.0, term: 'Fall 2024', gpaPoints: 4.0),
  TranscriptRecord(courseTitle: 'Global History II', courseCode: 'H42', finalScore: 88, letterGrade: 'B', creditsEarned: 1.0, term: 'Fall 2024', gpaPoints: 3.0),
  TranscriptRecord(courseTitle: 'Algebra II Honors', courseCode: 'M43', finalScore: 90, letterGrade: 'A', creditsEarned: 1.0, term: 'Spring 2025', gpaPoints: 4.0),
  TranscriptRecord(courseTitle: 'Chemistry Honors', courseCode: 'S43', finalScore: 87, letterGrade: 'B', creditsEarned: 1.0, term: 'Spring 2025', gpaPoints: 3.0),
  TranscriptRecord(courseTitle: 'AP Computer Science Principles', courseCode: 'T11', finalScore: 96, letterGrade: 'A', creditsEarned: 1.0, term: 'Spring 2025', gpaPoints: 4.5),
];

List<WorkItem> get mockWorkItems {
  final now = DateTime.now();
  return [
    WorkItem(id: 'w1', title: 'Series Convergence Problem Set', courseTitle: 'AP Calculus BC', type: 'homework', dueDate: now.add(const Duration(days: 1))),
    WorkItem(id: 'w2', title: 'Gatsby Ch. 4–6 Reading Quiz', courseTitle: 'AP English Literature', type: 'quiz', dueDate: now.add(const Duration(days: 2))),
    WorkItem(id: 'w3', title: 'Rotational Motion Lab Report', courseTitle: 'AP Physics C', type: 'homework', dueDate: now.subtract(const Duration(days: 1))),
    WorkItem(id: 'w4', title: 'Reconstruction DBQ Essay', courseTitle: 'U.S. History Honors', type: 'project', dueDate: now.add(const Duration(days: 5))),
    WorkItem(id: 'w5', title: 'Unit 3 Test: Integration', courseTitle: 'AP Calculus BC', type: 'test', dueDate: now.add(const Duration(days: 7))),
    WorkItem(id: 'w6', title: 'Spanish Oral Presentation', courseTitle: 'Spanish IV', type: 'project', dueDate: now.add(const Duration(days: 3)), submitted: true, grade: 'A-'),
  ];
}