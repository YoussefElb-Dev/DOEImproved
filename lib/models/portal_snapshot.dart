import 'grade_models.dart';
import 'schedule_models.dart';

/// Where the data on screen came from. Surfaced in the UI so a student is
/// never shown sample data that looks like their own record.
enum DataSource {
  /// Pulled from the portal with a valid session.
  live,

  /// Sample data — no session yet, or the user opted into a preview.
  demo,
}

/// One consistent view of everything the portal returned in a single sync.
///
/// Holding all five sections together means the whole app renders from one
/// fetch, every tab agrees on the same `syncedAt`, and a partial outage
/// degrades one section instead of blanking the app.
class PortalSnapshot {
  final StudentProfile profile;
  final List<Course> courses;
  final DaySchedule schedule;
  final List<TranscriptRecord> transcript;
  final List<WorkItem> work;
  final DateTime syncedAt;
  final DataSource source;

  /// Set when some — but not all — sections failed to load.
  final String? partialFailure;

  const PortalSnapshot({
    required this.profile,
    required this.courses,
    required this.schedule,
    required this.transcript,
    required this.work,
    required this.syncedAt,
    required this.source,
    this.partialFailure,
  });

  bool get isLive => source == DataSource.live;
  bool get isDemo => source == DataSource.demo;

  /// Weighted GPA recomputed from the transcript, falling back to whatever
  /// the portal printed on the dashboard when no transcript is available.
  double get computedGpa {
    var points = 0.0;
    var credits = 0.0;
    for (final r in transcript) {
      if (r.creditsEarned <= 0) continue;
      points += r.gpaPoints * r.creditsEarned;
      credits += r.creditsEarned;
    }
    if (credits <= 0) return profile.overallGpa;
    return points / credits;
  }

  double get earnedCredits {
    if (transcript.isEmpty) return profile.totalCredits;
    return transcript.fold(0.0, (sum, r) => sum + r.creditsEarned);
  }

  /// Work that still needs doing, soonest first.
  List<WorkItem> get openWork {
    final open = work.where((w) => !w.submitted).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return open;
  }

  PortalSnapshot copyWith({
    StudentProfile? profile,
    List<Course>? courses,
    DaySchedule? schedule,
    List<TranscriptRecord>? transcript,
    List<WorkItem>? work,
    DateTime? syncedAt,
    DataSource? source,
    String? partialFailure,
  }) =>
      PortalSnapshot(
        profile: profile ?? this.profile,
        courses: courses ?? this.courses,
        schedule: schedule ?? this.schedule,
        transcript: transcript ?? this.transcript,
        work: work ?? this.work,
        syncedAt: syncedAt ?? this.syncedAt,
        source: source ?? this.source,
        partialFailure: partialFailure ?? this.partialFailure,
      );
}
