import 'grade_models.dart';
import 'portal_snapshot.dart';
import 'schedule_models.dart';

/// A dated record of how things stood, kept on the device.
///
/// The portal drops a marking period's grades when the next one opens, so
/// whatever is on screen today may be gone next month. One of these is written
/// each day the app syncs, which is what turns a live-only portal into a
/// history the student actually owns.
class ArchivedReport {
  /// The calendar day this covers, `YYYY-MM-DD`. Also the file name.
  final String id;
  final DateTime capturedAt;
  final String term;
  final double gpa;
  final double credits;
  final List<Course> courses;
  final List<TranscriptRecord> transcript;

  const ArchivedReport({
    required this.id,
    required this.capturedAt,
    required this.term,
    required this.gpa,
    required this.credits,
    required this.courses,
    required this.transcript,
  });

  factory ArchivedReport.fromSnapshot(
    PortalSnapshot snapshot, {
    String term = '',
    DateTime? at,
  }) {
    final when = at ?? snapshot.syncedAt;
    return ArchivedReport(
      id: dayId(when),
      capturedAt: when,
      term: term,
      gpa: snapshot.computedGpa,
      credits: snapshot.earnedCredits,
      courses: snapshot.courses,
      transcript: snapshot.transcript,
    );
  }

  static String dayId(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  ArchivedReportMeta get meta => ArchivedReportMeta(
        id: id,
        capturedAt: capturedAt,
        term: term,
        gpa: gpa,
        credits: credits,
        courseCount: courses.length,
        transcriptCount: transcript.length,
      );

  factory ArchivedReport.fromJson(Map<String, dynamic> json) => ArchivedReport(
        id: json['id'] as String? ?? '',
        capturedAt: DateTime.tryParse(json['capturedAt'] as String? ?? '') ??
            DateTime.now(),
        term: json['term'] as String? ?? '',
        gpa: (json['gpa'] as num?)?.toDouble() ?? 0,
        credits: (json['credits'] as num?)?.toDouble() ?? 0,
        courses: [
          for (final c in (json['courses'] as List? ?? const []))
            Course.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        transcript: [
          for (final t in (json['transcript'] as List? ?? const []))
            TranscriptRecord.fromJson(Map<String, dynamic>.from(t as Map)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'capturedAt': capturedAt.toIso8601String(),
        'term': term,
        'gpa': gpa,
        'credits': credits,
        'courses': [for (final c in courses) c.toJson()],
        'transcript': [for (final t in transcript) t.toJson()],
      };

  /// A fingerprint of the marks, used to skip writing an identical report.
  String get fingerprint {
    final parts = [
      for (final c in courses)
        '${c.id}|${c.title}|${c.currentScore.toStringAsFixed(2)}|${c.letterGrade}',
      for (final t in transcript)
        '${t.courseTitle}|${t.term}|${t.letterGrade}|${t.creditsEarned}',
    ]..sort();
    return parts.join(';');
  }
}

/// Enough of an [ArchivedReport] to draw a list row without loading the rest.
class ArchivedReportMeta {
  final String id;
  final DateTime capturedAt;
  final String term;
  final double gpa;
  final double credits;
  final int courseCount;
  final int transcriptCount;

  const ArchivedReportMeta({
    required this.id,
    required this.capturedAt,
    required this.term,
    required this.gpa,
    required this.credits,
    required this.courseCount,
    required this.transcriptCount,
  });
}

/// A document downloaded from the DOE and kept on the device.
///
/// The file itself is saved, not just the numbers read out of it: parsing can
/// be wrong or incomplete, but the original transcript is the thing a student
/// actually needs years later.
class SavedDocument {
  /// File name on disk, also the identifier.
  final String id;
  final String title;
  final String sourceUrl;
  final DateTime savedAt;
  final int bytes;

  /// "transcript", "report card", "progress report", or "document".
  final String kind;

  /// Whether text could be read out of the PDF. False means the file is kept
  /// but nothing could be parsed from it.
  final bool textExtracted;

  const SavedDocument({
    required this.id,
    required this.title,
    required this.sourceUrl,
    required this.savedAt,
    required this.bytes,
    required this.kind,
    this.textExtracted = false,
  });

  factory SavedDocument.fromJson(Map<String, dynamic> json) => SavedDocument(
        id: json['id'] as String? ?? '',
        title: json['title'] as String? ?? 'Document',
        sourceUrl: json['sourceUrl'] as String? ?? '',
        savedAt:
            DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        kind: json['kind'] as String? ?? 'document',
        textExtracted: json['textExtracted'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'sourceUrl': sourceUrl,
        'savedAt': savedAt.toIso8601String(),
        'bytes': bytes,
        'kind': kind,
        'textExtracted': textExtracted,
      };
}
