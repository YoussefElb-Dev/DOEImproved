import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

import '../../models/normalized_transcript.dart';
import '../pdf/pdf_text_extractor.dart';
import 'normalized_transcript_parser.dart';

enum TranscriptImportStage {
  idle,
  picker,
  fileHandle,
  bytesRead,
  parse,
  normalize,
  validate,
  aiExtract,
  aiValidate,
  review,
  persist,
  rerender,
  complete,
  cancelled,
  failed,
}

class TranscriptPipelineLog {
  const TranscriptPipelineLog({
    required this.stage,
    required this.message,
    required this.time,
  });

  final TranscriptImportStage stage;
  final String message;
  final DateTime time;
}

class PickedTranscriptFile {
  const PickedTranscriptFile({
    required this.name,
    this.bytes,
    this.path,
    this.size,
  });

  final String name;
  final Uint8List? bytes;
  final String? path;
  final int? size;
}

abstract class TranscriptFileSource {
  Future<PickedTranscriptFile?> pickPdf();
}

class FilePickerTranscriptSource implements TranscriptFileSource {
  const FilePickerTranscriptSource();

  @override
  Future<PickedTranscriptFile?> pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      allowMultiple: false,
      withData: true,
      withReadStream: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.single;
    return PickedTranscriptFile(
      name: file.name,
      bytes: file.bytes,
      path: file.path,
      size: file.size,
    );
  }
}

class TranscriptImportDraft {
  const TranscriptImportDraft({
    required this.transcript,
    required this.sourceBytes,
    required this.logs,
  });

  final NormalizedTranscript transcript;
  /// Null when an already-saved transcript is being reprocessed from its
  /// retained raw text. New imports always include the original PDF bytes.
  final Uint8List? sourceBytes;
  final List<TranscriptPipelineLog> logs;
}

class TranscriptImportException implements Exception {
  const TranscriptImportException({
    required this.stage,
    required this.userMessage,
    this.cause,
  });

  final TranscriptImportStage stage;
  final String userMessage;
  final Object? cause;

  @override
  String toString() => userMessage;
}

typedef TranscriptLogSink = void Function(TranscriptPipelineLog entry);

class TranscriptImportService {
  const TranscriptImportService({
    this.source = const FilePickerTranscriptSource(),
    this.extractor = const PdfTextExtractor(),
    this.parser = const NormalizedTranscriptParser(),
  });

  final TranscriptFileSource source;
  final PdfTextExtractor extractor;
  final NormalizedTranscriptParser parser;

  static const int maximumBytes = 30 * 1024 * 1024;

  Future<TranscriptImportDraft?> pickAndParse({
    TranscriptLogSink? onLog,
    bool allowIncompleteForAi = false,
  }) async {
    final logs = <TranscriptPipelineLog>[];
    void log(TranscriptImportStage stage, String message) {
      final entry = TranscriptPipelineLog(
        stage: stage,
        message: message,
        time: DateTime.now(),
      );
      logs.add(entry);
      debugPrint('[transcript:${stage.name}] $message');
      onLog?.call(entry);
    }

    try {
      log(TranscriptImportStage.picker, 'Opening the PDF picker.');
      final picked = await source.pickPdf();
      if (picked == null) {
        log(TranscriptImportStage.cancelled, 'File selection was cancelled.');
        return null;
      }

      log(
        TranscriptImportStage.fileHandle,
        'Received ${picked.name} (${picked.size ?? 'unknown'} bytes).',
      );
      if (!picked.name.toLowerCase().endsWith('.pdf')) {
        throw const TranscriptImportException(
          stage: TranscriptImportStage.fileHandle,
          userMessage: 'Choose a transcript saved as a PDF file.',
        );
      }

      // `withData: true` asks file_picker to read the provider-backed file
      // while access is valid. The path fallback covers desktop and older
      // plugin implementations without depending on a long-lived iOS or
      // Android document-provider URI.
      Uint8List? bytes = picked.bytes;
      final path = picked.path;
      if ((bytes == null || bytes.isEmpty) && path != null && path.isNotEmpty) {
        bytes = await File(path).readAsBytes();
      }
      if (bytes == null || bytes.isEmpty) {
        throw const TranscriptImportException(
          stage: TranscriptImportStage.bytesRead,
          userMessage: 'The selected file opened, but no bytes could be read.',
        );
      }
      if (bytes.length > maximumBytes) {
        throw const TranscriptImportException(
          stage: TranscriptImportStage.bytesRead,
          userMessage: 'This PDF is larger than the 30 MB import limit.',
        );
      }
      if (bytes.length < 4 || String.fromCharCodes(bytes.take(4)) != '%PDF') {
        throw const TranscriptImportException(
          stage: TranscriptImportStage.bytesRead,
          userMessage: 'The selected file does not contain valid PDF data.',
        );
      }
      log(
        TranscriptImportStage.bytesRead,
        'Read ${bytes.length} bytes successfully.',
      );

      log(TranscriptImportStage.parse, 'Extracting the PDF text layer.');
      final extracted = extractor.extract(bytes);
      if (!extracted.reliable) {
        final reason = extracted.failure ?? 'The PDF text could not be read.';
        final scan = reason.toLowerCase().contains('scan') ||
            reason.toLowerCase().contains('no embedded text');
        throw TranscriptImportException(
          stage: TranscriptImportStage.parse,
          userMessage: scan
              ? 'This PDF appears to be an image scan. Gradly cannot run OCR '
                  'on it yet. Export or download a text-layer PDF and try again.'
              : 'Gradly could not safely read this PDF: $reason',
        );
      }
      log(
        TranscriptImportStage.parse,
        'Extracted ${extracted.text.length} text characters.',
      );

      log(TranscriptImportStage.normalize, 'Normalizing transcript fields.');
      final fingerprint = sha256.convert(bytes).toString();
      final result = parser.parse(
        rawText: extracted.text,
        sourceFileName: picked.name,
        sourceFingerprint: fingerprint,
      );
      log(
        TranscriptImportStage.normalize,
        'Found ${result.transcript.terms.length} terms and '
            '${result.transcript.courseCount} courses.',
      );

      log(TranscriptImportStage.validate, 'Validating the normalized record.');
      if (!result.canSave) {
        if (!allowIncompleteForAi) {
          throw TranscriptImportException(
            stage: TranscriptImportStage.validate,
            userMessage: result.validationErrors.join(' '),
          );
        }
        log(
          TranscriptImportStage.validate,
          'The local parser is incomplete; continuing to Kimi K3 with the '
              'readable document text.',
        );
      }
      log(
        TranscriptImportStage.review,
        'Ready for review. Nothing has been saved yet.',
      );
      return TranscriptImportDraft(
        transcript: result.transcript,
        sourceBytes: bytes,
        logs: List.unmodifiable(logs),
      );
    } on TranscriptImportException {
      rethrow;
    } catch (error, stackTrace) {
      debugPrint('Transcript import failed: $error\n$stackTrace');
      throw TranscriptImportException(
        stage: logs.isEmpty ? TranscriptImportStage.picker : logs.last.stage,
        userMessage: 'Transcript import failed: $error',
        cause: error,
      );
    }
  }
}
