import '../models/school_calendar_event.dart';

/// NYC Public Schools' published 2026–27 calendar.
/// Source: https://www.schools.nyc.gov/calendar/2026-2027-school-year-calendar
class NycSchoolCalendar {
  const NycSchoolCalendar._();

  static const sourceUrl =
      'https://www.schools.nyc.gov/calendar/2026-2027-school-year-calendar';

  static final events = <SchoolCalendarEvent>[
    _event('First day of school', 2026, 9, 10),
    _event('Yom Kippur — schools closed', 2026, 9, 21,
        kind: SchoolCalendarEventKind.schoolClosed),
    _event('Evening conferences', 2026, 9, 23,
        details: 'Middle schools and District 75'),
    _event('Evening conferences', 2026, 9, 24,
        details: 'High schools, K–12 and 6–12 schools'),
    _event('Evening conferences', 2026, 9, 30,
        details: 'Elementary and Pre-K centers'),
    _event('Italian Heritage / Indigenous Peoples’ Day — schools closed',
        2026, 10, 12,
        kind: SchoolCalendarEventKind.schoolClosed),
    _event('Election Day — remote instruction', 2026, 11, 3,
        kind: SchoolCalendarEventKind.remoteInstruction,
        details: 'Students learn remotely'),
    _event('Parent-teacher conferences — early dismissal', 2026, 11, 5,
        kind: SchoolCalendarEventKind.earlyDismissal,
        details: 'Elementary schools and Pre-K centers'),
    _event('Veterans Day — schools closed', 2026, 11, 11,
        kind: SchoolCalendarEventKind.schoolClosed),
    _event('Parent-teacher conferences — early dismissal', 2026, 11, 12,
        kind: SchoolCalendarEventKind.earlyDismissal,
        details: 'Middle schools and District 75'),
    _event('Evening conferences', 2026, 11, 19,
        details: 'High schools, K–12 and 6–12 schools'),
    _event('Parent-teacher conferences — early dismissal', 2026, 11, 20,
        kind: SchoolCalendarEventKind.earlyDismissal,
        details: 'High schools, K–12 and 6–12 schools'),
    _range('Thanksgiving recess — schools closed', 2026, 11, 26, 2026, 11, 27,
        SchoolCalendarEventKind.schoolClosed),
    _range('Winter recess — schools closed', 2026, 12, 24, 2027, 1, 1,
        SchoolCalendarEventKind.schoolClosed),
    _event('Rev. Dr. Martin Luther King Jr. Day — schools closed',
        2027, 1, 18,
        kind: SchoolCalendarEventKind.schoolClosed),
    _range('Regents administration', 2027, 1, 26, 2027, 1, 29,
        SchoolCalendarEventKind.academicEvent),
    _event('Professional development day', 2027, 2, 1,
        kind: SchoolCalendarEventKind.noStudentAttendance,
        details: 'No attendance for high school students and students in '
            '6–12 schools; other students attend school'),
    _event('Spring semester begins', 2027, 2, 2),
    _range('Midwinter recess — schools closed', 2027, 2, 15, 2027, 2, 19,
        SchoolCalendarEventKind.schoolClosed),
    _event('Parent-teacher conferences — early dismissal', 2027, 3, 3,
        kind: SchoolCalendarEventKind.earlyDismissal,
        details: 'Elementary schools and Pre-K centers'),
    _event('Parent-teacher conferences — early dismissal', 2027, 3, 4,
        kind: SchoolCalendarEventKind.earlyDismissal,
        details: 'Middle schools and District 75'),
    _event('Eid al-Fitr — schools closed', 2027, 3, 9,
        kind: SchoolCalendarEventKind.schoolClosed),
    _event('Evening conferences', 2027, 3, 18,
        details: 'High schools, K–12 and 6–12 schools'),
    _event('Parent-teacher conferences — early dismissal', 2027, 3, 19,
        kind: SchoolCalendarEventKind.earlyDismissal,
        details: 'High schools, K–12 and 6–12 schools'),
    _event('Good Friday — schools closed', 2027, 3, 26,
        kind: SchoolCalendarEventKind.schoolClosed),
    _range('Spring recess — schools closed', 2027, 4, 22, 2027, 4, 30,
        SchoolCalendarEventKind.schoolClosed),
    _event('Evening conferences', 2027, 5, 12,
        details: 'High schools, K–12 and 6–12 schools'),
    _event('Evening conferences', 2027, 5, 13,
        details: 'Middle schools and District 75'),
    _event('Eid al-Adha — schools closed', 2027, 5, 17,
        kind: SchoolCalendarEventKind.schoolClosed),
    _event('Evening conferences', 2027, 5, 26,
        details: 'Elementary schools and Pre-K centers'),
    _event('Memorial Day — schools closed', 2027, 5, 31,
        kind: SchoolCalendarEventKind.schoolClosed),
    _event('Clerical day — no classes for most students', 2027, 6, 8,
        kind: SchoolCalendarEventKind.noStudentAttendance,
        details: 'No classes for 3-K, Pre-K, elementary, middle, K–12 and '
            'standalone District 75 students. Standalone high schools attend.'),
    _event('Anniversary Day — students do not attend', 2027, 6, 10,
        kind: SchoolCalendarEventKind.noStudentAttendance),
    _range('Regents administration', 2027, 6, 15, 2027, 6, 18,
        SchoolCalendarEventKind.academicEvent),
    _range('Regents administration', 2027, 6, 21, 2027, 6, 25,
        SchoolCalendarEventKind.academicEvent),
    _event('Last day of school', 2027, 6, 28),
  ];

  static List<SchoolCalendarEvent> on(DateTime day) =>
      events.where((event) => event.includes(day)).toList(growable: false);

  static SchoolCalendarEvent _event(
    String title,
    int year,
    int month,
    int day, {
    SchoolCalendarEventKind kind = SchoolCalendarEventKind.academicEvent,
    String? details,
  }) => SchoolCalendarEvent(
        title: title,
        start: DateTime(year, month, day),
        kind: kind,
        details: details,
      );

  static SchoolCalendarEvent _range(
    String title,
    int startYear,
    int startMonth,
    int startDay,
    int endYear,
    int endMonth,
    int endDay,
    SchoolCalendarEventKind kind,
  ) => SchoolCalendarEvent(
        title: title,
        start: DateTime(startYear, startMonth, startDay),
        end: DateTime(endYear, endMonth, endDay),
        kind: kind,
      );
}
