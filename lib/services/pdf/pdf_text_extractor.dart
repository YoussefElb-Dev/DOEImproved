import 'dart:convert';
import 'dart:io';

/// What came out of a PDF, and how much to trust it.
class PdfText {
  /// Reconstructed text, one line per row of the original layout.
  final String text;

  /// False when the file yielded nothing readable — an image-only scan, or a
  /// font encoding this extractor cannot map. The caller keeps the PDF either
  /// way; it just cannot read numbers out of it.
  final bool reliable;

  final String? failure;

  const PdfText({
    required this.text,
    required this.reliable,
    this.failure,
  });

  List<String> get lines => text
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  static const PdfText empty =
      PdfText(text: '', reliable: false, failure: 'No text found');
}

/// Reads text out of a PDF without any native code or third-party licence.
///
/// Scope is deliberate: the DOE's transcripts and report cards are generated
/// documents with embedded text, which is the case this handles. It inflates
/// FlateDecode content streams, walks the text-showing operators, and uses the
/// text matrix to tell a new row from the next column of the same row — that
/// last part is what makes a table come back as rows instead of one cell per
/// line.
///
/// It does not attempt scanned pages, encrypted files, or subset fonts with
/// custom encodings. Those come back with `reliable: false` rather than as
/// plausible-looking nonsense.
class PdfTextExtractor {
  const PdfTextExtractor();

  /// Vertical movement, in unscaled text units, that counts as a new row.
  static const double _rowThreshold = 2.5;

  PdfText extract(List<int> bytes) {
    if (bytes.isEmpty) return PdfText.empty;

    final raw = latin1.decode(bytes, allowInvalid: true);
    if (!raw.startsWith('%PDF')) {
      return const PdfText(
        text: '',
        reliable: false,
        failure: 'Not a PDF file',
      );
    }
    if (raw.contains('/Encrypt')) {
      return const PdfText(
        text: '',
        reliable: false,
        failure: 'The PDF is encrypted',
      );
    }

    final buffer = StringBuffer();
    for (final stream in _contentStreams(raw, bytes)) {
      buffer.write(_readTextOperators(stream));
      buffer.write('\n');
    }

    final text = _tidy(buffer.toString());
    if (text.trim().isEmpty) {
      return const PdfText(
        text: '',
        reliable: false,
        failure: 'No embedded text — the document may be a scan',
      );
    }
    if (!_looksLikeProse(text)) {
      return PdfText(
        text: text,
        reliable: false,
        failure: 'Text came out unreadable — the fonts use a custom encoding',
      );
    }
    return PdfText(text: text, reliable: true);
  }

  // ── streams ─────────────────────────────────────────────────────────

  /// Every content stream in the file, inflated where necessary.
  Iterable<String> _contentStreams(String raw, List<int> bytes) sync* {
    var index = 0;
    while (true) {
      final start = raw.indexOf('stream', index);
      if (start < 0) break;

      // The dictionary immediately before the keyword says how it is encoded.
      final dictStart = raw.lastIndexOf('<<', start);
      final dict = dictStart < 0 ? '' : raw.substring(dictStart, start);

      var dataStart = start + 'stream'.length;
      if (dataStart < raw.length && raw[dataStart] == '\r') dataStart++;
      if (dataStart < raw.length && raw[dataStart] == '\n') dataStart++;

      final end = raw.indexOf('endstream', dataStart);
      if (end < 0) break;
      index = end + 'endstream'.length;

      // Images and fonts are not text; skipping them keeps the output clean
      // and avoids inflating megabytes for nothing.
      if (dict.contains('/Image') ||
          dict.contains('/DCTDecode') ||
          dict.contains('/JPXDecode') ||
          dict.contains('/FontFile')) {
        continue;
      }

      final data = bytes.sublist(dataStart, end);
      if (dict.contains('/FlateDecode')) {
        final inflated = _inflate(data);
        if (inflated != null) yield latin1.decode(inflated, allowInvalid: true);
      } else if (!dict.contains('/Filter')) {
        yield latin1.decode(data, allowInvalid: true);
      }
    }
  }

  List<int>? _inflate(List<int> data) {
    for (final codec in [ZLibCodec(), ZLibCodec(raw: true)]) {
      try {
        return codec.decode(data);
      } catch (_) {
        // Try the next framing; a truncated stream simply yields nothing.
      }
    }
    return null;
  }

  // ── content stream walking ──────────────────────────────────────────

  /// Walks one content stream, emitting text with rows preserved.
  String _readTextOperators(String content) {
    final out = StringBuffer();
    final operands = <Object>[];

    var x = 0.0;
    var y = 0.0;
    var started = false;
    var leading = 0.0;
    var pendingNewline = false;
    var pendingSpace = false;
    var wroteAnything = false;

    // A move down the page starts a new row; a move across it is the next
    // column of the same row. Without the second case a table comes back with
    // every cell on its own line, and the rows are lost.
    void moveTo(double newX, double newY) {
      if (!started) {
        started = true;
        x = newX;
        y = newY;
        return;
      }
      if ((newY - y).abs() >= _rowThreshold) {
        pendingNewline = true;
      } else if (newX - x > 0.5) {
        pendingSpace = true;
      }
      x = newX;
      y = newY;
    }

    void emit(String text) {
      if (text.isEmpty) return;
      if (pendingNewline && wroteAnything) {
        out.write('\n');
      } else if (pendingSpace && wroteAnything) {
        out.write(' ');
      }
      pendingNewline = false;
      pendingSpace = false;
      out.write(text);
      wroteAnything = true;
    }

    var i = 0;
    while (i < content.length) {
      final ch = content[i];

      if (ch == '(') {
        final (value, next) = _readLiteralString(content, i);
        operands.add(value);
        i = next;
        continue;
      }
      if (ch == '<' && i + 1 < content.length && content[i + 1] != '<') {
        final (value, next) = _readHexString(content, i);
        operands.add(value);
        i = next;
        continue;
      }
      if (ch == '[') {
        final (values, next) = _readArray(content, i);
        operands.add(values);
        i = next;
        continue;
      }
      if (ch == '/' || ch == ')' || ch == ']' || ch == '>') {
        i++;
        continue;
      }
      if (_isWhitespace(ch)) {
        i++;
        continue;
      }

      // A number or an operator keyword.
      final start = i;
      while (i < content.length &&
          !_isWhitespace(content[i]) &&
          !'()<>[]/'.contains(content[i])) {
        i++;
      }
      final token = content.substring(start, i);
      if (token.isEmpty) {
        i++;
        continue;
      }

      final number = double.tryParse(token);
      if (number != null) {
        operands.add(number);
        continue;
      }

      switch (token) {
        case 'Tj':
        case "'":
        case '"':
          if (token != 'Tj') pendingNewline = true;
          final last = operands.isEmpty ? null : operands.last;
          if (last is String) emit(last);
        case 'TJ':
          final last = operands.isEmpty ? null : operands.last;
          if (last is List) {
            final line = StringBuffer();
            for (final part in last) {
              if (part is String) {
                line.write(part);
              } else if (part is double && part <= -120) {
                // A large negative kern is the gap between columns.
                line.write(' ');
              }
            }
            emit(line.toString());
          }
        case 'Td':
        case 'TD':
          if (operands.length >= 2) {
            final tx = operands[operands.length - 2];
            final ty = operands[operands.length - 1];
            if (token == 'TD' && ty is double) leading = -ty;
            if (tx is double && ty is double) moveTo(x + tx, y + ty);
          }
        case 'TL':
          final value = operands.isEmpty ? null : operands.last;
          if (value is double) leading = value;
        case 'T*':
          moveTo(x, y - leading);
        case 'Tm':
          if (operands.length >= 6) {
            final e = operands[operands.length - 2];
            final f = operands[operands.length - 1];
            if (e is double && f is double) moveTo(e, f);
          }
        case 'ET':
          pendingNewline = true;
      }
      operands.clear();
    }

    return out.toString();
  }

  // ── token readers ───────────────────────────────────────────────────

  (String, int) _readLiteralString(String content, int start) {
    final buffer = StringBuffer();
    var depth = 0;
    var i = start;

    while (i < content.length) {
      final ch = content[i];
      if (ch == r'\') {
        i++;
        if (i >= content.length) break;
        final esc = content[i];
        switch (esc) {
          case 'n':
            buffer.write('\n');
          case 'r':
            buffer.write('\r');
          case 't':
            buffer.write('\t');
          case 'b':
          case 'f':
            buffer.write(' ');
          case '(':
          case ')':
          case r'\':
            buffer.write(esc);
          default:
            if (_isDigit(esc)) {
              // Octal escape, up to three digits.
              var octal = esc;
              while (octal.length < 3 &&
                  i + 1 < content.length &&
                  _isDigit(content[i + 1])) {
                i++;
                octal += content[i];
              }
              final code = int.tryParse(octal, radix: 8);
              if (code != null && code > 0) buffer.writeCharCode(code);
            } else {
              buffer.write(esc);
            }
        }
        i++;
        continue;
      }
      if (ch == '(') {
        depth++;
        if (depth > 1) buffer.write(ch);
        i++;
        continue;
      }
      if (ch == ')') {
        depth--;
        if (depth == 0) return (buffer.toString(), i + 1);
        buffer.write(ch);
        i++;
        continue;
      }
      if (depth > 0) buffer.write(ch);
      i++;
    }
    return (buffer.toString(), i);
  }

  (String, int) _readHexString(String content, int start) {
    final end = content.indexOf('>', start);
    if (end < 0) return ('', content.length);
    final hex = content
        .substring(start + 1, end)
        .replaceAll(RegExp(r'[^0-9A-Fa-f]'), '');
    final buffer = StringBuffer();
    for (var i = 0; i + 1 < hex.length; i += 2) {
      final code = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (code != null && code > 0) buffer.writeCharCode(code);
    }
    return (buffer.toString(), end + 1);
  }

  (List<Object>, int) _readArray(String content, int start) {
    final values = <Object>[];
    var i = start + 1;

    while (i < content.length) {
      final ch = content[i];
      if (ch == ']') return (values, i + 1);
      if (ch == '(') {
        final (value, next) = _readLiteralString(content, i);
        values.add(value);
        i = next;
        continue;
      }
      if (ch == '<') {
        final (value, next) = _readHexString(content, i);
        values.add(value);
        i = next;
        continue;
      }
      if (_isWhitespace(ch)) {
        i++;
        continue;
      }
      final tokenStart = i;
      while (i < content.length &&
          !_isWhitespace(content[i]) &&
          !'()<>[]'.contains(content[i])) {
        i++;
      }
      final number = double.tryParse(content.substring(tokenStart, i));
      if (number != null) values.add(number);
      if (i == tokenStart) i++;
    }
    return (values, i);
  }

  // ── output shaping ──────────────────────────────────────────────────

  String _tidy(String text) {
    return text
        .replaceAll('\r', '\n')
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
  }

  /// A crude readability check. Real transcript text is mostly letters,
  /// digits and spaces; a mis-decoded subset font is mostly punctuation and
  /// control characters, and would otherwise be parsed as if it meant
  /// something.
  bool _looksLikeProse(String text) {
    if (text.length < 12) return false;
    var readable = 0;
    for (final rune in text.runes) {
      final isLetter = (rune >= 65 && rune <= 90) || (rune >= 97 && rune <= 122);
      final isDigit = rune >= 48 && rune <= 57;
      if (isLetter || isDigit || rune == 32 || rune == 10) readable++;
    }
    return readable / text.length >= 0.72;
  }

  static bool _isWhitespace(String ch) =>
      ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t' || ch == '\x00';

  static bool _isDigit(String ch) => ch.codeUnitAt(0) >= 48 && ch.codeUnitAt(0) <= 57;
}
