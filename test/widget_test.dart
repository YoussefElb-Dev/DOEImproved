import 'package:doe_improved/core/theme/app_theme.dart';
import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/models/portal_snapshot.dart';
import 'package:doe_improved/models/schedule_models.dart';
import 'package:doe_improved/storage/state_providers.dart';
import 'package:doe_improved/views/dashboard_screen.dart';
import 'package:doe_improved/views/root_shell.dart';
import 'package:doe_improved/views/schedule_tab.dart';
import 'package:doe_improved/views/work_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serves a fixed snapshot so screens render without a network, a session,
/// or the portal.
class _FakePortalController extends PortalController {
  _FakePortalController(this._snapshot);

  final PortalSnapshot _snapshot;

  @override
  Future<PortalSnapshot> build() async => _snapshot;

  @override
  Future<void> refresh() async {}
}

void main() {
  setUp(() {
    // No font downloads and no platform channels during tests.
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
  });

  const profile = StudentProfile(
    name: 'Jordan Alvarez',
    schoolName: 'Brooklyn Technical High School',
    avatarUrl: '',
    overallGpa: 3.5,
    gpaChange: 0.15,
    totalCredits: 42,
    classRank: 12,
  );

  final baseline = PortalSnapshot(
    profile: profile,
    courses: const [
      Course(
        id: 'c1',
        title: 'AP Calculus BC',
        code: 'MATH-410',
        teacherName: 'Ms. Okafor',
        currentScore: 88.8,
        letterGrade: 'B',
        categories: [],
        assignments: [],
      ),
    ],
    schedule: DaySchedule.unavailable(DateTime(2026, 9, 3)),
    transcript: const [],
    work: const [],
    syncedAt: DateTime(2026, 9, 3),
    source: DataSource.live,
  );

  Widget harness(PortalSnapshot data, Widget screen) => ProviderScope(
        overrides: [
          portalProvider.overrideWith(() => _FakePortalController(data)),
        ],
        child: MaterialApp(theme: AppTheme.dark, home: screen),
      );

  /// Renders [screen], lets the async notifier and entry animations resolve,
  /// then disposes the tree so no repeating timer outlives the test.
  Future<void> show(
    WidgetTester tester,
    PortalSnapshot data,
    Widget screen,
  ) async {
    await tester.pumpWidget(harness(data, screen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
  }

  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  group('Grades tab', () {
    testWidgets('renders the header, GPA and course feed', (tester) async {
      await show(tester, baseline, const DashboardScreen());

      expect(find.text('DOEImproved'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('OVERALL GPA'), findsOneWidget);
      expect(find.text('YOUR COURSES'), findsOneWidget);
      expect(find.text('AP Calculus BC'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('an empty course list explains itself', (tester) async {
      await show(
        tester,
        baseline.copyWith(courses: const []),
        const DashboardScreen(),
      );

      expect(find.text('No courses yet'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('demo data is labelled so it is not read as real grades',
        (tester) async {
      await show(
        tester,
        baseline.copyWith(source: DataSource.demo),
        const DashboardScreen(),
      );

      expect(find.text('DEMO'), findsOneWidget);
      expect(
        find.text('Sample data — sign in to see your own grades.'),
        findsOneWidget,
      );

      await teardown(tester);
    });

    testWidgets('a partial outage is surfaced, not hidden', (tester) async {
      await show(
        tester,
        baseline.copyWith(partialFailure: "Couldn't refresh schedule."),
        const DashboardScreen(),
      );

      expect(find.text("Couldn't refresh schedule."), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Schedule tab', () {
    testWidgets('shows the unavailable state when nothing is posted',
        (tester) async {
      await show(tester, baseline, const ScheduleTab());

      expect(find.text('Schedule unavailable'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('highlights the period happening right now', (tester) async {
      final now = DateTime.now();
      final data = baseline.copyWith(
        schedule: DaySchedule(
          date: now,
          label: 'A Day',
          periods: [
            ScheduleEntry(
              period: 1,
              courseTitle: 'AP Calculus BC',
              teacherName: 'Ms. Okafor',
              room: '4W12',
              startTime: now.subtract(const Duration(minutes: 10)),
              endTime: now.add(const Duration(minutes: 30)),
            ),
          ],
        ),
      );

      await show(tester, data, const ScheduleTab());

      expect(find.text('IN CLASS'), findsOneWidget);
      // Exact minutes depend on wall-clock drift between setup and build.
      expect(find.textContaining('min left'), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Work tab', () {
    testWidgets('buckets overdue work separately from later work',
        (tester) async {
      final now = DateTime.now();
      final data = baseline.copyWith(
        work: [
          WorkItem(
            id: 'w1',
            title: 'Rotational Motion Lab Report',
            courseTitle: 'AP Physics C',
            type: 'homework',
            dueDate: now.subtract(const Duration(days: 2)),
          ),
          WorkItem(
            id: 'w2',
            title: 'Series Project',
            courseTitle: 'AP Calculus BC',
            type: 'project',
            dueDate: now.add(const Duration(days: 20)),
          ),
        ],
      );

      await show(tester, data, const WorkTab());

      expect(find.text('OVERDUE'), findsOneWidget);
      expect(find.text('LATER'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Rotational Motion Lab Report'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('groups the transcript by term with a per-term GPA',
        (tester) async {
      final data = baseline.copyWith(
        transcript: const [
          TranscriptRecord(
            courseTitle: 'Geometry Honors',
            courseCode: 'M41',
            finalScore: 95,
            letterGrade: 'A',
            creditsEarned: 1,
            term: 'Fall 2024',
            gpaPoints: 4.0,
          ),
        ],
      );

      await show(tester, data, const WorkTab());

      expect(find.text('Fall 2024'), findsOneWidget);
      expect(find.text('GPA 4.00 · 1.0 cr'), findsOneWidget);
      expect(find.text('Geometry Honors'), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Root shell', () {
    testWidgets('exposes all four tabs and switches between them',
        (tester) async {
      await show(tester, baseline, const RootShell());

      for (final label in ['Grades', 'Schedule', 'Work', 'Settings']) {
        expect(find.text(label), findsWidgets, reason: '$label tab missing');
      }

      // Tap by icon — the tab labels also appear as page titles.
      await tester.tap(find.byIcon(Icons.settings_rounded));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Sign out'), findsOneWidget);

      await teardown(tester);
    });
  });
}
