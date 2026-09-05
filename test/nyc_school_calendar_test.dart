import 'package:doe_improved/models/school_calendar_event.dart';
import 'package:doe_improved/services/nyc_school_calendar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marks official 2026–27 closure ranges and remote days', () {
    final winter = NycSchoolCalendar.on(DateTime(2026, 12, 29));
    expect(winter.single.kind, SchoolCalendarEventKind.schoolClosed);
    expect(winter.single.title, contains('Winter recess'));

    final election = NycSchoolCalendar.on(DateTime(2026, 11, 3));
    expect(election.single.kind, SchoolCalendarEventKind.remoteInstruction);

    final regularDay = NycSchoolCalendar.on(DateTime(2026, 10, 13));
    expect(regularDay, isEmpty);
  });

  test('includes the first and last school days and all published events', () {
    expect(NycSchoolCalendar.events.length, 36);
    expect(NycSchoolCalendar.on(DateTime(2026, 9, 10)).single.title,
        'First day of school');
    expect(NycSchoolCalendar.on(DateTime(2027, 6, 28)).single.title,
        'Last day of school');
  });
}
