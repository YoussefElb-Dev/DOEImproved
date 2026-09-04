import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/archive_models.dart';
import '../models/portal_snapshot.dart';
import '../models/schedule_models.dart';

/// Everything the app keeps on the device.
///
/// Three separate concerns, three places on disk:
///
/// * `cache/snapshot.json` — the last good sync, so the app opens instantly
///   and still works with no signal.
/// * `archive/YYYY-MM-DD.json` — a dated report per day. The portal clears a
///   marking period's grades when the next opens; these do not disappear.
/// * `documents/` — the PDFs themselves, alongside a JSON index.
///
/// Nothing here ever leaves the phone.
class ArchiveStore {
  /// Overrides the storage root. Tests pass a temporary directory; in the app
  /// this stays null and the documents directory is used.
  final Directory? rootOverride;

  /// Oldest reports beyond this are pruned. Four years of daily syncs fits.
  static const int maxReports = 1500;

  ArchiveStore({this.rootOverride});

  Directory? _root;

  Future<Directory> _dir(String name) async {
    _root ??= rootOverride ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${_root!.path}/$name');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── offline cache ───────────────────────────────────────────────────

  Future<File> _snapshotFile() async =>
      File('${(await _dir('cache')).path}/snapshot.json');

  /// Writes the last good sync. Failures are swallowed: a device with no room
  /// left should not take the app down with it.
  Future<void> saveSnapshot(PortalSnapshot snapshot) async {
    try {
      final file = await _snapshotFile();
      await file.writeAsString(jsonEncode(snapshot.toJson()), flush: true);
    } catch (_) {
      // Caching is a convenience, never a requirement.
    }
  }

  Future<PortalSnapshot?> readSnapshot() async {
    try {
      final file = await _snapshotFile();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return PortalSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // A truncated or stale-format cache is discarded, not repaired.
      return null;
    }
  }

  Future<void> clearSnapshot() async {
    try {
      final file = await _snapshotFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  // ── dated reports ───────────────────────────────────────────────────

  /// Records today's report, replacing an earlier one from the same day.
  ///
  /// Returns true when something was written. A report identical to the most
  /// recent one is skipped, so a day of five-minute refreshes does not rewrite
  /// the same file hundreds of times.
  Future<bool> recordReport(ArchivedReport report) async {
    if (report.courses.isEmpty && report.transcript.isEmpty) return false;
    try {
      final dir = await _dir('archive');
      final file = File('${dir.path}/${report.id}.json');

      if (await file.exists()) {
        final existing = await _readReportFile(file);
        if (existing != null && existing.fingerprint == report.fingerprint) {
          return false;
        }
      }

      await file.writeAsString(jsonEncode(report.toJson()), flush: true);
      await _prune(dir);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Every saved report, newest first.
  Future<List<ArchivedReportMeta>> listReports() async {
    try {
      final dir = await _dir('archive');
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();

      final out = <ArchivedReportMeta>[];
      for (final file in files) {
        final report = await _readReportFile(file);
        if (report != null) out.add(report.meta);
      }
      out.sort((a, b) => b.id.compareTo(a.id));
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<ArchivedReport?> readReport(String id) async {
    try {
      final dir = await _dir('archive');
      return _readReportFile(File('${dir.path}/$id.json'));
    } catch (_) {
      return null;
    }
  }

  Future<ArchivedReport?> _readReportFile(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return ArchivedReport.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// The newest saved transcript, from however far back it was last posted.
  ///
  /// This is the point of the archive: the portal takes a transcript down
  /// between terms, and the app should not forget it just because the DOE did.
  Future<List<TranscriptRecord>> latestTranscript() async {
    for (final meta in await listReports()) {
      if (meta.transcriptCount == 0) continue;
      final report = await readReport(meta.id);
      if (report != null && report.transcript.isNotEmpty) {
        return report.transcript;
      }
    }
    return const [];
  }

  Future<void> deleteReport(String id) async {
    try {
      final dir = await _dir('archive');
      final file = File('${dir.path}/$id.json');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _prune(Directory dir) async {
    try {
      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();
      if (files.length <= maxReports) return;
      files.sort((a, b) => a.path.compareTo(b.path)); // ids sort by date
      for (final file in files.take(files.length - maxReports)) {
        await file.delete();
      }
    } catch (_) {}
  }

  // ── documents ───────────────────────────────────────────────────────

  Future<File> _documentIndexFile() async =>
      File('${(await _dir('documents')).path}/index.json');

  /// Saves a downloaded PDF and records it in the index.
  Future<SavedDocument?> saveDocument({
    required String title,
    required String sourceUrl,
    required List<int> bytes,
    required String kind,
    bool textExtracted = false,
    DateTime? at,
  }) async {
    try {
      final dir = await _dir('documents');
      final id = _fileNameFor(title, sourceUrl);
      await File('${dir.path}/$id').writeAsBytes(bytes, flush: true);

      final doc = SavedDocument(
        id: id,
        title: title,
        sourceUrl: sourceUrl,
        savedAt: at ?? DateTime.now(),
        bytes: bytes.length,
        kind: kind,
        textExtracted: textExtracted,
      );

      final index = await listDocuments();
      index.removeWhere((d) => d.id == id);
      index.add(doc);
      index.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      await (await _documentIndexFile())
          .writeAsString(jsonEncode([for (final d in index) d.toJson()]));
      return doc;
    } catch (_) {
      return null;
    }
  }

  Future<List<SavedDocument>> listDocuments() async {
    try {
      final file = await _documentIndexFile();
      if (!await file.exists()) return [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return [];
      return [
        for (final d in decoded)
          if (d is Map) SavedDocument.fromJson(Map<String, dynamic>.from(d)),
      ];
    } catch (_) {
      return [];
    }
  }

  /// The saved file itself, for opening or sharing.
  Future<File?> documentFile(String id) async {
    try {
      final dir = await _dir('documents');
      final file = File('${dir.path}/$id');
      return await file.exists() ? file : null;
    } catch (_) {
      return null;
    }
  }

  /// A file name that is stable for a given document and safe on disk, so
  /// re-downloading the same transcript replaces it instead of piling up.
  static String _fileNameFor(String title, String sourceUrl) {
    final base = (title.trim().isEmpty ? sourceUrl : title)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = base.length > 60 ? base.substring(0, 60) : base;
    return '${trimmed.isEmpty ? 'document' : trimmed}.pdf';
  }

  // ── housekeeping ────────────────────────────────────────────────────

  /// Bytes used by everything the app has stored.
  Future<int> totalBytes() async {
    var total = 0;
    for (final name in ['cache', 'archive', 'documents']) {
      try {
        final dir = await _dir(name);
        await for (final entry in dir.list()) {
          if (entry is File) total += await entry.length();
        }
      } catch (_) {}
    }
    return total;
  }

  /// Wipes everything. Used by sign-out and by the "clear" action.
  Future<void> clearAll() async {
    for (final name in ['cache', 'archive', 'documents']) {
      try {
        final dir = await _dir(name);
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
