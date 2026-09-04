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

  factory PortalSnapshot.fromJson(Map<String, dynamic> json) => PortalSnapshot(
        profile: StudentProfile.fromJson(
          Map<String, dynamic>.from(json['profile'] as Map? ?? const {}),
        ),
        courses: [
          for (final c in (json['courses'] as List? ?? const []))
            Course.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        schedule: json['schedule'] == null
            ? DaySchedule.unavailable(DateTime.now())
            : DaySchedule.fromJson(
                Map<String, dynamic>.from(json['schedule'] as Map),
              ),
        transcript: [
          for (final t in (json['transcript'] as List? ?? const []))
            TranscriptRecord.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
        work: [
          for (final w in (json['work'] as List? ?? const []))
            WorkItem.fromJson(Map<String, dynamic>.from(w as Map)),
        ],
        syncedAt:
            DateTime.tryParse(json['syncedAt'] as String? ?? '') ??
                DateTime.now(),
        source: DataSource.values.firstWhere(
          (s) => s.name == json['source'],
          orElse: () => DataSource.live,
        ),
        partialFailure: json['partialFailure'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'profile': profile.toJson(),
        'courses': [for (final c in courses) c.toJson()],
        'schedule': schedule.toJson(),
        'transcript': [for (final t in transcript) t.toJson()],
        'work': [for (final w in work) w.toJson()],
        'syncedAt': syncedAt.toIso8601String(),
        'source': source.name,
        if (partialFailure != null) 'partialFailure': partialFailure,
      };

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
