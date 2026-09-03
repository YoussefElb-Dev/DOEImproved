import '../models/grade_models.dart';
import '../models/portal_snapshot.dart';
import '../models/schedule_models.dart';
import '../storage/mock_data.dart';
import '../storage/mock_schedule_data.dart';
import 'grade_data_service.dart';

/// Orchestrates one complete portal sync.
///
/// The four portal pages are fetched concurrently. The dashboard is the only
/// section allowed to fail the whole sync — it carries the profile and the
/// course list, and its failure is what tells us the session died. The other
/// three degrade individually and are reported through
/// [PortalSnapshot.partialFailure].
class PortalRepository {
  final GradeDataService _service;

  PortalRepository({GradeDataService? service})
      : _service = service ?? GradeDataService();

  /// Sample data shown before sign-in, clearly labelled as a demo.
  static PortalSnapshot demoSnapshot() => PortalSnapshot(
        profile: mockStudentProfile,
        courses: mockCourses,
        schedule: mockDaySchedule,
        transcript: mockTranscript,
        work: mockWorkItems,
        syncedAt: DateTime.now(),
        source: DataSource.demo,
      );

  /// Pulls every section with [cookies].
  ///
  /// Throws [AuthExpiredException] when the session is no longer accepted, so
  /// the caller can route back to the sign-in WebView.
  Future<PortalSnapshot> load(Map<String, String> cookies) async {
    if (cookies.isEmpty) return demoSnapshot();

    // Kick all four off together, then collect. `sync` is awaited first
    // because its AuthExpiredException is the authoritative signal.
    final dashboard = _service.sync(cookies);
    final schedule = _guard(() => _service.fetchSchedule(cookies));
    final transcript = _guard(() => _service.fetchTranscript(cookies));
    final work = _guard(() => _service.fetchWork(cookies));

    final ({StudentProfile? profile, List<Course> courses}) core;
    try {
      core = await dashboard;
    } catch (_) {
      // Drain the others so their results don't surface as unhandled errors.
      // `_guard` never throws, so this cannot mask the dashboard failure.
      await schedule;
      await transcript;
      await work;
      rethrow;
    }

    final scheduleResult = await schedule;
    final transcriptResult = await transcript;
    final workResult = await work;

    final failed = <String>[
      if (scheduleResult.failed) 'schedule',
      if (transcriptResult.failed) 'transcript',
      if (workResult.failed) 'upcoming work',
    ];

    return PortalSnapshot(
      profile: core.profile ?? _unknownProfile,
      courses: core.courses,
      schedule: scheduleResult.value ?? DaySchedule.unavailable(DateTime.now()),
      transcript: transcriptResult.value ?? const <TranscriptRecord>[],
      work: workResult.value ?? const <WorkItem>[],
      syncedAt: DateTime.now(),
      source: DataSource.live,
      partialFailure: failed.isEmpty
          ? null
          : "Couldn't refresh ${_readableList(failed)}.",
    );
  }

  /// Runs [task], converting any failure into a sentinel instead of throwing.
  ///
  /// Deliberately swallows [AuthExpiredException] too: the dashboard call is
  /// the authoritative session check, so a single secondary page rejecting the
  /// cookie is reported as a partial failure rather than forcing a re-login.
  Future<_Section<T>> _guard<T>(Future<T> Function() task) async {
    try {
      return _Section<T>(await task(), failed: false);
    } catch (_) {
      return _Section<T>(null, failed: true);
    }
  }

  static String _readableList(List<String> items) {
    if (items.length == 1) return items.first;
    if (items.length == 2) return '${items[0]} and ${items[1]}';
    return '${items.take(items.length - 1).join(', ')}, and ${items.last}';
  }

  static const StudentProfile _unknownProfile = StudentProfile(
    name: 'Student',
    schoolName: '',
    avatarUrl: '',
    overallGpa: 0,
    gpaChange: 0,
    totalCredits: 0,
    classRank: 0,
  );

  void dispose() => _service.dispose();
}

class _Section<T> {
  final T? value;
  final bool failed;
  const _Section(this.value, {required this.failed});
}
