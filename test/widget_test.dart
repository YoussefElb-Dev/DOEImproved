import 'package:doe_improved/core/theme/app_palette.dart';
import 'package:doe_improved/models/grade_models.dart';
import 'package:doe_improved/models/portal_snapshot.dart';
import 'package:doe_improved/models/schedule_models.dart';
import 'package:doe_improved/storage/state_providers.dart';
import 'package:doe_improved/views/analytics_tab.dart';
import 'package:doe_improved/views/assignments_tab.dart';
import 'package:doe_improved/views/calendar_tab.dart';
import 'package:doe_improved/views/grades_tab.dart';
import 'package:doe_improved/views/root_shell.dart';
import 'package:doe_improved/views/schedule_tab.dart';
import 'package:doe_improved/views/settings_tab.dart';
import 'package:doe_improved/views/theme_picker_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    // No platform channels during tests.
    SharedPreferences.setMockInitialValues({});
  });

  // AppTheme is deliberately not built here: it composes its text theme
  // through google_fonts, which reaches the network. `context.palette` falls
  // back to Midnight when no extension is present, so colours still resolve.
  final testTheme = ThemeData.dark(useMaterial3: true);

  final baseline = PortalSnapshot(
    profile: const StudentProfile(
      name: 'Amara Okonkwo',
      schoolName: 'Bronx High School of Science',
      avatarUrl: '',
      overallGpa: 3.5,
      gpaChange: 0.15,
      totalCredits: 42,
      classRank: 12,
    ),
    courses: const [
      Course(
        id: 'c1',
        title: 'AP Calculus BC',
        code: 'MATH-410',
        teacherName: 'Ms. Okafor',
        currentScore: 91.4,
        letterGrade: 'A',
        categories: [],
        assignments: [],
      ),
      Course(
        id: 'c2',
        title: 'AP Physics C',
        code: 'SCI-401',
        teacherName: 'Dr. Vasquez',
        currentScore: 84.2,
        letterGrade: 'B',
        categories: [],
        assignments: [],
      ),
    ],
    schedule: DaySchedule.unavailable(DateTime(2026, 9, 3)),
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
    work: const [],
    syncedAt: DateTime(2026, 9, 3),
    source: DataSource.live,
  );

  Widget harness(PortalSnapshot data, Widget screen) => ProviderScope(
        overrides: [
          portalProvider.overrideWith(() => _FakePortalController(data)),
        ],
        child: MaterialApp(
          theme: testTheme,
          home: Scaffold(body: screen),
        ),
      );

  /// A tall surface so the whole screen mounts.
  ///
  /// `ListView` builds lazily: at phone height everything below the fold is
  /// never created, and `find.text` searches the element tree, so those
  /// sections would be invisible to the test rather than merely off-screen.
  void useTallViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(520, 3400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  /// Renders [screen] and lets the notifier and entry animations resolve.
  Future<void> show(
    WidgetTester tester,
    PortalSnapshot data,
    Widget screen,
  ) async {
    useTallViewport(tester);
    await tester.pumpWidget(harness(data, screen));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
  }

  /// Disposes the tree so no repeating timer outlives the test.
  Future<void> teardown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
  }

  group('Grades tab', () {
    testWidgets('renders the overview and the course feed', (tester) async {
      await show(tester, baseline, const GradesTab());

      expect(find.text('Gradly'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Semester Overview'), findsOneWidget);
      expect(find.text('ALL CLASSES'), findsOneWidget);
      // Named twice: once as a course card, once as the top performer.
      expect(find.text('AP Calculus BC'), findsWidgets);
      expect(find.text('AP Physics C'), findsOneWidget);
      expect(find.text('Current GPA'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('an empty course list explains itself', (tester) async {
      await show(
        tester,
        baseline.copyWith(courses: const []),
        const GradesTab(),
      );

      expect(find.text('No courses yet'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('demo data is labelled so it is not read as real grades',
        (tester) async {
      await show(
        tester,
        baseline.copyWith(source: DataSource.demo),
        const GradesTab(),
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
        const GradesTab(),
      );

      expect(find.text("Couldn't refresh schedule."), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Calendar tab', () {
    testWidgets('shows a month grid and the selected day', (tester) async {
      final now = DateTime.now();
      final data = baseline.copyWith(
        work: [
          WorkItem(
            id: 'w1',
            title: 'Ballistics Lab Report',
            courseTitle: 'AP Physics C',
            type: 'lab',
            dueDate: DateTime(now.year, now.month, now.day),
          ),
        ],
      );

      await show(tester, data, const CalendarTab());

      expect(find.text('Calendar'), findsOneWidget);
      expect(find.text('Su'), findsOneWidget);
      expect(find.text('Sa'), findsOneWidget);
      expect(find.text('TODAY'), findsOneWidget);
      expect(find.text('Ballistics Lab Report'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('a day with nothing due says so', (tester) async {
      await show(tester, baseline, const CalendarTab());
      expect(find.text('Nothing due'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('Assignments tab', () {
    final now = DateTime.now();
    final data = baseline.copyWith(
      work: [
        WorkItem(
          id: 'w1',
          title: 'Rotational Motion Lab',
          courseTitle: 'AP Physics C',
          type: 'lab',
          dueDate: now.subtract(const Duration(days: 2)),
        ),
        WorkItem(
          id: 'w2',
          title: 'Series Project',
          courseTitle: 'AP Calculus BC',
          type: 'project',
          dueDate: now.add(const Duration(days: 20)),
          submitted: true,
        ),
      ],
    );

    testWidgets('lists work with its status', (tester) async {
      await show(tester, data, const AssignmentsTab());

      expect(find.text('Assignments'), findsWidgets);
      expect(find.text('Rotational Motion Lab'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(find.text('Complete'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('the sort control changes the order', (tester) async {
      await show(tester, data, const AssignmentsTab());

      expect(find.textContaining('SORT BY DUE DATE'), findsOneWidget);

      await tester.tap(find.byKey(const Key('sort-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Course').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('SORT BY COURSE'), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Analytics tab', () {
    testWidgets('charts the grade spread and lists the transcript',
        (tester) async {
      await show(tester, baseline, const AnalyticsTab());

      expect(find.text('GRADE DISTRIBUTION'), findsOneWidget);
      expect(find.text('PERFORMANCE BY SUBJECT'), findsOneWidget);
      expect(find.text('TRANSCRIPT'), findsOneWidget);
      expect(find.text('Geometry Honors'), findsOneWidget);
      expect(find.text('Fall 2024'), findsOneWidget);

      await teardown(tester);
    });

    testWidgets('an absent transcript is stated, not faked', (tester) async {
      await show(
        tester,
        baseline.copyWith(transcript: const []),
        const AnalyticsTab(),
      );

      expect(find.text('Transcript unavailable'), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Settings tab', () {
    testWidgets('shows the profile, the active theme and sign out',
        (tester) async {
      await show(tester, baseline, const SettingsTab());

      expect(find.text('Amara Okonkwo'), findsOneWidget);
      expect(find.text('Bronx High School of Science'), findsOneWidget);
      expect(find.text('Theme'), findsOneWidget);
      expect(find.text('Midnight'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);

      await teardown(tester);
    });
  });

  group('Theme picker', () {
    testWidgets('offers every theme and applies the chosen one',
        (tester) async {
      late WidgetRef captured;

      useTallViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            portalProvider.overrideWith(() => _FakePortalController(baseline)),
          ],
          child: MaterialApp(
            theme: testTheme,
            home: Consumer(
              builder: (context, ref, _) {
                captured = ref;
                return const ThemePickerScreen();
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 900));

      for (final palette in AppPalette.all) {
        expect(find.text(palette.name), findsOneWidget,
            reason: '${palette.name} missing from the picker');
      }

      expect(captured.read(themeProvider).id, AppThemeId.midnight);

      await tester.tap(find.text('Ocean'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(captured.read(themeProvider).id, AppThemeId.ocean);

      await teardown(tester);
    });
  });

  group('Schedule tab', () {
    testWidgets('lists the day in period order with the current one marked',
        (tester) async {
      final now = DateTime.now();
      ScheduleEntry at(int period, String title, int startsInMinutes,
              int endsInMinutes) =>
          ScheduleEntry(
            period: period,
            courseTitle: title,
            teacherName: 'Ms. Okafor',
            room: '4W12',
            startTime: now.add(Duration(minutes: startsInMinutes)),
            endTime: now.add(Duration(minutes: endsInMinutes)),
          );

      final data = baseline.copyWith(
        schedule: DaySchedule(
          date: now,
          label: 'A Day',
          // Deliberately out of order: the tab sorts by period.
          periods: [
            at(3, 'Global History', 40, 85),
            at(1, 'AP Calculus BC', -120, -75),
            at(2, 'AP Physics C', -10, 35),
          ],
        ),
      );

      await show(tester, data, const ScheduleTab());

      expect(find.text('A Day'), findsOneWidget);
      expect(find.text('3 classes today'), findsOneWidget);
      // Period 2 is running right now.
      expect(find.text('IN CLASS'), findsOneWidget);
      expect(find.textContaining('min left'), findsOneWidget);
      expect(find.text('AP Physics C'), findsWidgets);

      // Rendered in period order, whatever order the portal listed them in.
      final periodLabels = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .where((d) => d == '1' || d == '2' || d == '3')
          .toList();
      expect(periodLabels, ['1', '2', '3']);

      await teardown(tester);
    });

    testWidgets('says so when the school has posted nothing', (tester) async {
      await show(tester, baseline, const ScheduleTab());
      expect(find.text('Schedule unavailable'), findsOneWidget);
      await teardown(tester);
    });
  });

  group('Root shell', () {
    testWidgets('exposes all five tabs and switches between them',
        (tester) async {
      await show(tester, baseline, const RootShell());

      for (final label in [
        'Grades',
        'Schedule',
        'Calendar',
        'Work',
        'Stats',
        'Settings',
      ]) {
        expect(find.text(label), findsWidgets, reason: '$label tab missing');
      }

      // Tap by icon — the tab labels also appear as page titles.
      await tester.tap(find.byIcon(Icons.settings_rounded).first);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Sign out'), findsOneWidget);

      await teardown(tester);
    });
  });
}
