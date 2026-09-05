import '../../models/schedule_models.dart';
import '../grade_scale.dart';
import '../parsing/values.dart';

/// Turns the text of a DOE transcript PDF into typed records.
///
/// A transcript is a table without table markup once it is text: each row is a
/// course code, a title, a mark and a credit value, with term headings between
/// blocks. This reads rows by the *shape* of their trailing values rather than
/// by fixed column positions, so a layout change does not break it outright.
///
/// It is deliberately conservative. A line that does not clearly carry a title
/// and a mark is skipped, because a wrong transcript row is worse than a
/// missing one.
class TranscriptTextParser {
  const TranscriptTextParser();

  static final RegExp _termHeading = RegExp(
    r'^\s*(fall|spring|summer|winter)\s*(term\s*)?((19|20)\d{2}|\d{2})'
    r'(\s*[-–]\s*(19|20)\d{2})?\s*$',
    caseSensitive: false,
  );

  static final RegExp _numberedTerm = RegExp(
    r'^\s*(term|semester|marking\s*period|mp|quarter|q|s)\s*\d{1,2}\s*$',
    caseSensitive: false,
  );

  static final RegExp _nycTerm = RegExp(
    r'^(20\d{2})\s*/\s*term\s*(\d{1,2})\b',
    caseSensitive: false,
  );

  static final RegExp _nycCourse = RegExp(
    r'^(\d{2}[A-Z]\d{3})'
    r'((?:[A-Z]{3}\d{2}|[A-Z]{4}\d)(?:QAE|Q[A-Z]|X\*\*)?)'
    r'\s*(.+?)\s+'
    r'(P\*?|W\*?|I\*?|[0-9]{1,3}\*?)'
    r'(?:\s+(\d{1,3}))?\s+'
    r'(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$',
    caseSensitive: false,
  );

  /// `MAT41`, `ENS21X`, `SCI-401` — a course code, not a word.
  static final RegExp _courseCode =
      RegExp(r'^[A-Z]{1,4}[-]?\d{2,4}[A-Z]{0,2}$');

  /// Lines that head a table rather than fill one.
  static const List<String> _headerWords = [
    'course', 'credit', 'mark', 'grade', 'description', 'subject',
    'transcript', 'student', 'school', 'official', 'page', 'date',
  ];

  List<TranscriptRecord> parse(List<String> lines) {
    final out = <TranscriptRecord>[];
    var currentTerm = '';

    for (final raw in lines) {
      final line = normalizeText(raw);
      if (line.isEmpty || line.length > 160) continue;

      final term = _termIn(line);
      if (term != null) {
        currentTerm = term;
        continue;
      }
      if (_isHeaderRow(line)) continue;

      final record = _rowFrom(line, currentTerm);
      if (record != null) out.add(record);
    }
    return out;
  }

  String? _termIn(String line) {
    final nyc = _nycTerm.firstMatch(line);
    if (nyc != null) return '${nyc.group(1)} Term ${nyc.group(2)}';
    if (_termHeading.hasMatch(line)) return _titleCaseTerm(line);
    if (_numberedTerm.hasMatch(line)) return line.toUpperCase();
    return null;
  }

  static String _titleCaseTerm(String line) {
    return line
        .split(RegExp(r'\s+'))
        .map((w) => w.isEmpty
            ? w
            : w[0].toUpperCase() + w.substring(1).toLowerCase())
        .join(' ');
  }

  /// A row of column titles rather than a course.
  bool _isHeaderRow(String line) {
    final lower = line.toLowerCase();
    final hits = _headerWords.where(lower.contains).length;
    // Two or more heading words and no digits is a header, not a course.
    return hits >= 2 && !RegExp(r'\d').hasMatch(line);
  }

  /// Reads one course row by peeling typed values off the right-hand end.
  TranscriptRecord? _rowFrom(String line, String term) {
    final nyc = _nycCourse.firstMatch(line);
    if (nyc != null) {
      final mark = nyc.group(4)!.toUpperCase();
      final cleanMark = mark.replaceAll('*', '');
      final numeric = double.tryParse(cleanMark) ??
          double.tryParse(nyc.group(5) ?? '') ??
          0;
      final letter = double.tryParse(cleanMark) == null
          ? cleanMark
          : GradeScale.letterFor(numeric);
      final averaged = !mark.endsWith('*') && letter != 'P';
      return TranscriptRecord(
        courseTitle: _titleCase(nyc.group(3)!.trim()),
        courseCode: '${nyc.group(1)}${nyc.group(2)}',
        finalScore: numeric,
        letterGrade: letter,
        creditsEarned: double.parse(nyc.group(7)!),
        term: term,
        gpaPoints: averaged
            ? GradeScale.gpaPointsFor(letter: letter, score: numeric) ?? 0
            : 0,
      );
    }

    final tokens = line.split(' ').where((t) => t.isNotEmpty).toList();
    if (tokens.length < 2) return null;

    double? credits;
    String? letter;
    double? score;

    // Walk backwards: a transcript row ends with its numbers.
    var end = tokens.length;
    var consumed = 0;
    while (end > 0 && consumed < 4) {
      final token = tokens[end - 1];

      if (credits == null && _looksLikeCredits(token)) {
        credits = parseCredits(token);
        end--;
        consumed++;
        continue;
      }
      if (letter == null && parseLetterGrade(token) != null) {
        letter = parseLetterGrade(token);
        end--;
        consumed++;
        continue;
      }
      if (score == null && _looksLikeMark(token)) {
        score = parseScore(token);
        end--;
        consumed++;
        continue;
      }
      break;
    }

    if (letter == null && score == null) return null;

    // What is left is the code and the title.
    var titleTokens = tokens.sublist(0, end);
    var code = '';
    if (titleTokens.isNotEmpty && _courseCode.hasMatch(titleTokens.first)) {
      code = titleTokens.first;
      titleTokens = titleTokens.sublist(1);
    }

    final title = titleTokens.join(' ').trim();
    if (!_isPlausibleTitle(title)) return null;

    final resolvedLetter = letter ??
        (score != null && score > 0 ? GradeScale.letterFor(score) : '');
    final points = GradeScale.gpaPointsFor(
          letter: resolvedLetter.isEmpty ? null : resolvedLetter,
          score: score,
        ) ??
        0;

    return TranscriptRecord(
      courseTitle: _titleCase(title),
      courseCode: code,
      finalScore: score ?? 0,
      letterGrade: resolvedLetter,
      creditsEarned: credits ?? 0,
      term: term,
      gpaPoints: points,
    );
  }

  /// Credits are small and written with a decimal: 0.5, 1, 1.0, 2.
  bool _looksLikeCredits(String token) {
    if (!RegExp(r'^\d{1,2}(\.\d{1,2})?$').hasMatch(token)) return false;
    final value = double.tryParse(token);
    if (value == null) return false;
    // A bare integer above 12 is a mark, not a credit value.
    return token.contains('.') ? value <= 20 : value <= 12;
  }

  /// A numeric mark on the NYC scale, or one of its bracketing values.
  bool _looksLikeMark(String token) {
    if (!RegExp(r'^\d{1,3}$').hasMatch(token)) return false;
    final value = int.tryParse(token);
    return value != null && value >= 0 && value <= 100;
  }

  /// A course title has words in it, not just punctuation or a stray number.
  bool _isPlausibleTitle(String title) {
    if (title.length < 3 || title.length > 80) return false;
    final letters = RegExp(r'[A-Za-z]').allMatches(title).length;
    if (letters < 3) return false;
    final lower = title.toLowerCase();
    const noise = ['total', 'gpa', 'cumulative', 'average', 'credits earned'];
    return !noise.any(lower.contains);
  }

  /// Transcripts shout; the app does not.
  static String _titleCase(String value) {
    if (value != value.toUpperCase()) return value;
    return value
        .split(' ')
        .map((w) => w.length <= 2
            ? w
            : w[0] + w.substring(1).toLowerCase())
        .join(' ');
  }
}
