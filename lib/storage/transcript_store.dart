import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/normalized_transcript.dart';

typedef TranscriptDirectoryProvider = Future<Directory> Function();

class TranscriptStorageException implements Exception {
  const TranscriptStorageException({
    required this.operation,
    required this.message,
    this.path,
    this.cause,
  });

  final String operation;
  final String message;
  final String? path;
  final Object? cause;

  @override
  String toString() => 'TranscriptStorageException($operation): $message'
      '${path == null ? '' : ' [$path]'}'
      '${cause == null ? '' : ' ($cause)'}';
}

class TranscriptStore {
  TranscriptStore({TranscriptDirectoryProvider? directoryProvider})
      : _directoryProvider = directoryProvider ?? _defaultDirectory;

  final TranscriptDirectoryProvider _directoryProvider;

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationDocumentsDirectory();
    return Directory('${root.path}${Platform.pathSeparator}transcripts');
  }

  Future<List<NormalizedTranscript>> list() async {
    final directory = await _ensureDirectory('list');
    final records = <NormalizedTranscript>[];
    try {
      await for (final entity in directory.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        if (name.endsWith('.tmp.json') || name.endsWith('.bak.json')) continue;
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Transcript file is not a JSON object.');
        }
        records.add(NormalizedTranscript.fromJson(decoded));
      }
      records.sort((a, b) => b.importedAt.compareTo(a.importedAt));
      return records;
    } catch (error, stackTrace) {
      debugPrint('Transcript store list failed: $error\n$stackTrace');
      throw TranscriptStorageException(
        operation: 'list',
        message: 'Gradly could not read the saved transcript library.',
        path: directory.path,
        cause: error,
      );
    }
  }

  Future<NormalizedTranscript?> find(String id) async {
    for (final record in await list()) {
      if (record.id == id) return record;
    }
    return null;
  }

  Future<NormalizedTranscript> save(
    NormalizedTranscript incoming, {
    Uint8List? sourceBytes,
  }) async {
    final directory = await _ensureDirectory('save');
    try {
      final records = await list();
      NormalizedTranscript? existing;
      for (final record in records) {
        if (record.sourceFingerprint == incoming.sourceFingerprint ||
            _sameStudentAndInstitution(record, incoming)) {
          existing = record;
          break;
        }
      }

      final merged = existing == null ? incoming : _merge(existing, incoming);
      final target = File(
        '${directory.path}${Platform.pathSeparator}${_safeName(merged.id)}.json',
      );
      await _atomicWrite(
        target,
        const JsonEncoder.withIndent('  ').convert(merged.toJson()),
      );

      if (sourceBytes != null) {
        final source = File(
          '${directory.path}${Platform.pathSeparator}${_safeName(merged.id)}.pdf',
        );
        await _atomicWriteBytes(source, sourceBytes);
      }

      if (existing != null && existing.id != merged.id) {
        await _deleteFilesForId(directory, existing.id);
      }
      return merged;
    } catch (error, stackTrace) {
      if (error is TranscriptStorageException) rethrow;
      debugPrint('Transcript store save failed: $error\n$stackTrace');
      throw TranscriptStorageException(
        operation: 'save',
        message: 'Gradly could not save this transcript to the device.',
        path: directory.path,
        cause: error,
      );
    }
  }

  Future<void> delete(String id) async {
    final directory = await _ensureDirectory('delete');
    try {
      await _deleteFilesForId(directory, id);
    } catch (error, stackTrace) {
      debugPrint('Transcript store delete failed: $error\n$stackTrace');
      throw TranscriptStorageException(
        operation: 'delete',
        message: 'Gradly could not delete this transcript.',
        path: directory.path,
        cause: error,
      );
    }
  }

  String exportJson(NormalizedTranscript record) =>
      const JsonEncoder.withIndent('  ').convert(record.toJson());

  String exportCsv(NormalizedTranscript record) {
    const headers = <String>[
      'transcript_id',
      'student_name',
      'student_id',
      'institution',
      'term',
      'term_start',
      'term_end',
      'subject',
      'course_number',
      'title',
      'section',
      'credits_attempted',
      'credits_earned',
      'letter_grade',
      'numeric_grade',
      'grade_points',
      'quality_points',
      'counts_toward_gpa',
      'pass_fail',
      'audit',
      'withdrawn',
      'incomplete',
      'in_progress',
      'repeated',
      'grade_replaced',
      'transfer',
      'ap',
      'ib',
      'clep',
      'dual_enrollment',
      'honors',
    ];
    final rows = <List<Object?>>[headers];
    for (final term in record.terms) {
      for (final course in term.courses) {
        rows.add(<Object?>[
          record.id,
          record.student.name,
          record.student.studentId,
          record.institution.name,
          term.label,
          term.startDate?.toIso8601String(),
          term.endDate?.toIso8601String(),
          course.subjectCode,
          course.courseNumber,
          course.title,
          course.section,
          course.creditsAttempted,
          course.creditsEarned,
          course.letterGrade,
          course.numericGrade,
          course.gradePoints,
          course.qualityPoints,
          course.countsTowardGpa,
          course.flags.passFail,
          course.flags.audit,
          course.flags.withdrawn,
          course.flags.incomplete,
          course.flags.inProgress,
          course.flags.repeated,
          course.flags.gradeReplaced,
          course.flags.transfer,
          course.flags.ap,
          course.flags.ib,
          course.flags.clep,
          course.flags.dualEnrollment,
          course.flags.honors,
        ]);
      }
    }
    return rows.map((row) => row.map(_csvCell).join(',')).join('\r\n');
  }

  static String _csvCell(Object? value) {
    final text = value?.toString() ?? '';
    return '"${text.replaceAll('"', '""')}"';
  }

  Future<Directory> _ensureDirectory(String operation) async {
    try {
      final directory = await _directoryProvider();
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      return directory;
    } catch (error, stackTrace) {
      debugPrint('Transcript directory $operation failed: $error\n$stackTrace');
      throw TranscriptStorageException(
        operation: operation,
        message: 'Gradly could not open transcript storage on this device.',
        cause: error,
      );
    }
  }

  Future<void> _atomicWrite(File target, String value) async {
    final bytes = Uint8List.fromList(utf8.encode(value));
    await _atomicWriteBytes(target, bytes);
  }

  Future<void> _atomicWriteBytes(File target, Uint8List bytes) async {
    final temp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    try {
      await temp.writeAsBytes(bytes, flush: true);
      if (await backup.exists()) await backup.delete();
      if (await target.exists()) await target.rename(backup.path);
      await temp.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (error) {
      if (await temp.exists()) await temp.delete();
      if (!await target.exists() && await backup.exists()) {
        await backup.rename(target.path);
      }
      rethrow;
    }
  }

  Future<void> _deleteFilesForId(Directory directory, String id) async {
    final safe = _safeName(id);
    for (final extension in const <String>['json', 'pdf']) {
      final file = File(
        '${directory.path}${Platform.pathSeparator}$safe.$extension',
      );
      if (await file.exists()) await file.delete();
    }
  }

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  static bool _sameStudentAndInstitution(
    NormalizedTranscript a,
    NormalizedTranscript b,
  ) {
    final studentA = a.student.studentId?.trim().toLowerCase();
    final studentB = b.student.studentId?.trim().toLowerCase();
    final institutionA = a.institution.name?.trim().toLowerCase();
    final institutionB = b.institution.name?.trim().toLowerCase();
    if (studentA == null || studentA.isEmpty || studentB == null) return false;
    if (institutionA == null || institutionA.isEmpty || institutionB == null) {
      return false;
    }
    return studentA == studentB && institutionA == institutionB;
  }

  static NormalizedTranscript _merge(
    NormalizedTranscript oldRecord,
    NormalizedTranscript newRecord,
  ) {
    final oldJson = oldRecord.toJson();
    final newJson = newRecord.toJson();
    final merged = _mergeMaps(oldJson, newJson);

    final terms = <String, Map<String, dynamic>>{};
    for (final value in <dynamic>[
      ...?oldJson['terms'] as List<dynamic>?,
      ...?newJson['terms'] as List<dynamic>?,
    ]) {
      if (value is! Map<String, dynamic>) continue;
      final key = _termIdentity(value);
      final prior = terms[key];
      terms[key] = prior == null ? value : _mergeTerm(prior, value);
    }
    merged['terms'] = terms.values.toList();
    merged['id'] = oldRecord.id;
    merged['schemaVersion'] = currentTranscriptSchemaVersion;
    merged['importedAt'] = newRecord.importedAt.toIso8601String();
    return NormalizedTranscript.fromJson(merged);
  }

  static Map<String, dynamic> _mergeTerm(
    Map<String, dynamic> oldTerm,
    Map<String, dynamic> newTerm,
  ) {
    final merged = _mergeMaps(oldTerm, newTerm);
    final courses = <Map<String, dynamic>>[];
    for (final value in <dynamic>[
      ...?oldTerm['courses'] as List<dynamic>?,
      ...?newTerm['courses'] as List<dynamic>?,
    ]) {
      if (value is! Map<String, dynamic>) continue;
      final index = courses.indexWhere((prior) => _sameCourse(prior, value));
      if (index < 0) {
        courses.add(value);
      } else {
        courses[index] = _mergeMaps(courses[index], value);
      }
    }
    merged['courses'] = courses;
    return merged;
  }

  static String _termIdentity(Map<String, dynamic> term) {
    final label = _normalized('${term['label'] ?? ''}');
    final year = RegExp(r'(19|20)\d{2}').firstMatch(label)?.group(0) ??
        '${term['year'] ?? ''}';
    final part = RegExp(r'(?:term|semester|quarter|q|mp)(\d{1,2})')
            .firstMatch(label)
            ?.group(1) ??
        (label.contains('fall')
            ? 'fall'
            : label.contains('spring')
                ? 'spring'
                : label.contains('summer')
                    ? 'summer'
                    : label.contains('winter')
                        ? 'winter'
                        : label);
    return '$year|$part';
  }

  static bool _sameCourse(
    Map<String, dynamic> a,
    Map<String, dynamic> b,
  ) {
    final rawA = _normalized('${a['rawLine'] ?? ''}');
    final rawB = _normalized('${b['rawLine'] ?? ''}');
    if (rawA.isNotEmpty && rawA == rawB) return true;

    final codeA = _normalized(
      '${a['subjectCode'] ?? ''}${a['courseNumber'] ?? ''}',
    );
    final codeB = _normalized(
      '${b['subjectCode'] ?? ''}${b['courseNumber'] ?? ''}',
    );
    if (codeA.length >= 4 &&
        codeB.length >= 4 &&
        (codeA == codeB || codeA.endsWith(codeB) || codeB.endsWith(codeA))) {
      return true;
    }

    final titleA = _normalized('${a['title'] ?? ''}');
    final titleB = _normalized('${b['title'] ?? ''}');
    final gradeA = '${a['numericGrade'] ?? a['letterGrade'] ?? ''}';
    final gradeB = '${b['numericGrade'] ?? b['letterGrade'] ?? ''}';
    return titleA.length >= 5 &&
        titleB.length >= 5 &&
        (titleA == titleB || titleA.contains(titleB) || titleB.contains(titleA)) &&
        gradeA == gradeB;
  }

  static String _normalized(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '');

  static Map<String, dynamic> _mergeMaps(
    Map<String, dynamic> oldMap,
    Map<String, dynamic> newMap,
  ) {
    final result = <String, dynamic>{...oldMap};
    for (final entry in newMap.entries) {
      final next = entry.value;
      if (next == null || (next is String && next.trim().isEmpty)) continue;
      final previous = result[entry.key];
      if (next is Map<String, dynamic> && previous is Map<String, dynamic>) {
        result[entry.key] = _mergeMaps(previous, next);
      } else {
        result[entry.key] = next;
      }
    }
    return result;
  }
}
