enum SchoolCalendarEventKind {
  schoolClosed,
  remoteInstruction,
  earlyDismissal,
  noStudentAttendance,
  academicEvent,
}

class SchoolCalendarEvent {
  const SchoolCalendarEvent({
    required this.title,
    required this.start,
    required this.kind,
    this.end,
    this.details,
  });

  final String title;
  final DateTime start;
  final DateTime? end;
  final SchoolCalendarEventKind kind;
  final String? details;

  bool includes(DateTime day) {
    final value = DateTime(day.year, day.month, day.day);
    final first = DateTime(start.year, start.month, start.day);
    final lastValue = end ?? start;
    final last = DateTime(lastValue.year, lastValue.month, lastValue.day);
    return !value.isBefore(first) && !value.isAfter(last);
  }
}
