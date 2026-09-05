import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/normalized_transcript.dart';
import '../grade_scale.dart';
import '../parsing/values.dart';

class TranscriptParseResult {
  final NormalizedTranscript transcript;
  final List<String> validationErrors;

  const TranscriptParseResult({
    required this.transcript,
    this.validationErrors = const [],
  });

  bool get canSave => validationErrors.isEmpty;
}

/// Conservative text-layer transcript parser.
///
/// It extracts labelled fields first, then identifies terms and course rows by
/// their value shapes. A field that is not printed remains null. Confidence is
/// attached to every heuristic field so the review screen can call it out.
class NormalizedTranscriptParser {
  const NormalizedTranscriptParser();

  static final _term = RegExp(
    r'\b(fall|autumn|spring|summer|winter|semester|quarter|term|mp)'
    r'\s*(?:term\s*)?([1-9]|(?:19|20)\d{2})?'
    r'(?:\s*[-/]\s*((?:19|20)\d{2}))?\b',
    caseSensitive: false,
  );

  static final _courseStart = RegExp(
    r'^([A-Z&]{2,10})[\s-]?(\d{1,4}[A-Z]{0,3})'
    r'(?:[\s-]+([A-Z0-9]{1,6}))?\s+(.+)$',
  );

  static final _grade = RegExp(
    r'^(A\+|A-|A|B\+|B-|B|C\+|C-|C|D\+|D-|D|F|P|S|U|W|WF|I|INC|IP|'
    r'AU|AUD|CR|NC|NS|EX|TR)$',
    caseSensitive: false,
  );

  TranscriptParseResult parse({
    required String rawText,
    required String sourceFileName,
    String? sourceDocumentId,
    String? sourceFingerprint,
    DateTime? importedAt,
  }) {
    final text = _normalise(rawText);
    final lines = text
        .split('\n')
        .map(normalizeText)
        .where((line) => line.isNotEmpty)
        .toList();
    final confidence = <String, double>{};
    final warnings = <String>[];

    String? labelled(List<String> labels, {double score = .95}) {
      for (final line in lines) {
        for (final label in labels) {
          final match = RegExp(
            '^\\s*${RegExp.escape(label)}\\s*[:#-]\\s*(.+?)\\s*\$',
            caseSensitive: false,
          ).firstMatch(line);
          if (match != null) return _clean(match.group(1));
        }
      }
      return null;
    }

    final studentName = labelled(const ['student name', 'name']);
    if (studentName != null) confidence['student.name'] = .95;
    final studentId = labelled(
      const ['student id', 'student number', 'osis', 'emplid', 'school id'],
    );
    if (studentId != null) confidence['student.studentId'] = .98;
    final dobText = labelled(const ['date of birth', 'birth date', 'dob']);
    final dob = dobText == null ? null : parseDate(dobText);
    if (dob != null) confidence['student.dateOfBirth'] = .95;

    var institutionName = labelled(
      const ['institution', 'school', 'school name', 'college', 'university'],
    );
    if (institutionName != null) {
      confidence['institution.name'] = .95;
    } else {
      institutionName = _institutionHeading(lines);
      if (institutionName != null) confidence['institution.name'] = .62;
    }

    final issueText = labelled(
      const ['transcript date', 'issue date', 'date issued', 'printed'],
    );
    final issueDate = issueText == null ? null : parseDate(issueText);
    if (issueDate != null) confidence['issueDate'] = .9;

    final lowered = text.toLowerCase();
    final officialStatus = lowered.contains('unofficial transcript')
        ? OfficialStatus.unofficial
        : lowered.contains('official transcript')
            ? OfficialStatus.official
            : OfficialStatus.unknown;
    if (officialStatus != OfficialStatus.unknown) {
      confidence['officialStatus'] = .99;
    }

    final creditSystem = lowered.contains('quarter hour')
        ? CreditSystem.quarter
        : lowered.contains('semester hour')
            ? CreditSystem.semester
            : CreditSystem.unknown;
    if (creditSystem != CreditSystem.unknown) confidence['creditSystem'] = .98;

    final repeatPolicy = lowered.contains('repeat') &&
            (lowered.contains('replace') || lowered.contains('forgiven'))
        ? RepeatPolicy.replace
        : lowered.contains('repeat') && lowered.contains('average')
            ? RepeatPolicy.average
            : RepeatPolicy.unknown;

    final program = TranscriptProgram(
      program: labelled(const ['program', 'academic program']),
      degreeSought: labelled(const ['degree sought', 'degree objective']),
      majors: _splitList(labelled(const ['major', 'majors'])),
      minors: _splitList(labelled(const ['minor', 'minors'])),
      concentrations:
          _splitList(labelled(const ['concentration', 'concentrations'])),
      catalogYear: labelled(const ['catalog year']),
      creditsRequired: _labelledNumber(lines, const [
        'credits required',
        'degree credits required',
      ]),
    );

    final gradingScale = _parseLegend(lines, confidence);
    final termBuilders = <_TermBuilder>[];
    _TermBuilder? current;
    _TransferBuilder? transfer;
    final transfers = <TransferBlock>[];

    for (final line in lines) {
      final transferName = _transferHeading(line);
      if (transferName != null) {
        if (transfer != null) transfers.add(transfer.finish());
        transfer = _TransferBuilder(transferName);
        continue;
      }

      final termLabel = _termHeading(line);
      if (termLabel != null) {
        if (transfer != null) {
          transfers.add(transfer.finish());
          transfer = null;
        }
        current = _TermBuilder(termLabel);
        termBuilders.add(current);
        continue;
      }

      final parsedCourse = _parseCourse(
        line,
        termIndex: termBuilders.isEmpty ? 0 : termBuilders.length - 1,
        confidence: confidence,
      );
      if (parsedCourse != null) {
        if (transfer != null) {
          transfer.courses.add(parsedCourse);
        } else {
          current ??= _TermBuilder(null);
          if (termBuilders.isEmpty) termBuilders.add(current);
          current.courses.add(parsedCourse);
        }
        continue;
      }

      if (current != null) current.consumeSummary(line);
      transfer?.consumeSummary(line);
    }
    if (transfer != null) transfers.add(transfer.finish());

    final terms = [for (final b in termBuilders) b.finish()];
    final cumulative = _parseCumulative(lines, confidence);
    final degrees = _parseDegrees(lines, confidence);

    if (studentName == null) warnings.add('Student name was not identified.');
    if (institutionName == null) {
      warnings.add('Institution name was not identified.');
    }
    if (terms.isEmpty || terms.every((t) => t.courses.isEmpty)) {
      warnings.add('No course rows were identified.');
    }
    if (gradingScale.isEmpty) {
      warnings.add(
        'No printed grading legend was found. GPA validation will use only '
        'printed course points or a clearly marked estimate.',
      );
    }

    final fingerprint = sourceFingerprint ??
        sha256.convert(utf8.encode('$sourceFileName\n$text')).toString();
    final identity = [
      studentId ?? studentName ?? '',
      institutionName ?? '',
    ].join('|').toLowerCase();
    final idSeed = identity.replaceAll('|', '').isEmpty ? fingerprint : identity;
    final id = sha256.convert(utf8.encode(idSeed)).toString().substring(0, 24);

    final transcript = NormalizedTranscript(
      id: id,
      sourceFingerprint: fingerprint,
      sourceFileName: sourceFileName,
      sourceDocumentId: sourceDocumentId,
      importedAt: importedAt ?? DateTime.now(),
      rawText: text,
      student: TranscriptStudent(
        name: studentName,
        studentId: studentId,
        dateOfBirth: dob,
      ),
      institution: TranscriptInstitution(name: institutionName),
      issueDate: issueDate,
      officialStatus: officialStatus,
      program: program,
      creditSystem: creditSystem,
      repeatPolicy: repeatPolicy,
      gradingScale: gradingScale,
      terms: terms,
      cumulative: cumulative,
      transfers: transfers,
      degrees: degrees,
      warnings: warnings,
      confidence: confidence,
    );

    final errors = <String>[];
    if (text.length < 40) errors.add('The file did not contain enough text.');
    if (transcript.courseCount == 0) {
      errors.add('No transcript course rows could be validated.');
    }
    return TranscriptParseResult(
      transcript: transcript,
      validationErrors: errors,
    );
  }

  NormalizedCourse? _parseCourse(
    String line, {
    required int termIndex,
    required Map<String, double> confidence,
  }) {
    if (line.length > 220 || _looksLikeSummary(line)) return null;
    final match = _courseStart.firstMatch(line);
    if (match == null) return null;

    final subject = match.group(1)!;
    final number = match.group(2)!;
    final possibleSection = match.group(3);
    final tail = match.group(4)!;
    final tokens = tail.split(RegExp(r'\s+'));

    var gradeIndex = -1;
    String? letter;
    double? numeric;
    // A grade is the first grade-shaped token whose remaining columns are all
    // numeric. Scanning from the right mistakes an integer quality-points
    // column (for example 12) for a numeric grade.
    for (var i = 1; i < tokens.length; i++) {
      final token = tokens[i].replaceAll(RegExp(r'[,;]$'), '');
      final numericSuffix = tokens
          .skip(i + 1)
          .every((value) => _plainNumber(value) != null);
      if (!numericSuffix) continue;
      if (_grade.hasMatch(token)) {
        gradeIndex = i;
        letter = token.toUpperCase();
        break;
      }
      final numberValue = double.tryParse(token.replaceAll('%', ''));
      if (numberValue != null &&
          numberValue >= 0 &&
          numberValue <= 100 &&
          !token.contains('.')) {
        gradeIndex = i;
        numeric = numberValue;
        break;
      }
    }
    if (gradeIndex <= 0) return null;

    final title = tokens.take(gradeIndex).join(' ').trim();
    if (title.length < 2 || !RegExp(r'[A-Za-z]').hasMatch(title)) return null;

    final trailing = tokens.skip(gradeIndex + 1).map(_plainNumber).whereType<double>().toList();
    double? attempted;
    double? earned;
    double? points;
    double? quality;
    if (trailing.length >= 4) {
      attempted = trailing[0];
      earned = trailing[1];
      points = trailing[2];
      quality = trailing[3];
    } else if (trailing.length == 3) {
      attempted = trailing[0];
      earned = trailing[1];
      quality = trailing[2];
    } else if (trailing.length == 2) {
      attempted = trailing[0];
      earned = trailing[1];
    } else if (trailing.length == 1) {
      earned = trailing.single;
    }

    final flags = _flags('$title ${letter ?? ''}');
    final excluded = flags.passFail ||
        flags.audit ||
        flags.withdrawn ||
        flags.incomplete ||
        flags.inProgress ||
        flags.transfer ||
        flags.gradeReplaced;
    final key = '$subject$number${possibleSection ?? ''}';
    final path = 'terms[$termIndex].courses[$key]';
    confidence['$path.subjectCode'] = .92;
    confidence['$path.courseNumber'] = .92;
    confidence['$path.title'] = .82;
    if (possibleSection != null) confidence['$path.section'] = .55;
    if (letter != null) confidence['$path.letterGrade'] = .95;
    if (numeric != null) confidence['$path.numericGrade'] = .88;
    if (trailing.length == 1) confidence['$path.creditsEarned'] = .48;
    if (trailing.length >= 2) {
      confidence['$path.creditsAttempted'] = .68;
      confidence['$path.creditsEarned'] = .68;
    }

    return NormalizedCourse(
      id: key.toLowerCase(),
      subjectCode: subject,
      courseNumber: number,
      title: _titleCase(title),
      section: possibleSection,
      creditsAttempted: attempted,
      creditsEarned: earned,
      letterGrade: letter,
      numericGrade: numeric,
      gradePoints: points,
      qualityPoints: quality,
      countsTowardGpa: excluded ? false : (letter != null || numeric != null),
      flags: flags,
      rawLine: line,
    );
  }

  CourseFlags _flags(String value) {
    final upper = value.toUpperCase();
    bool word(String token) =>
        RegExp('(^|[^A-Z])${RegExp.escape(token)}([^A-Z]|\$)').hasMatch(upper);
    return CourseFlags(
      passFail: word('P') || upper.contains('PASS/FAIL'),
      audit: word('AU') || word('AUD') || upper.contains('AUDIT'),
      withdrawn: word('W') || word('WF') || upper.contains('WITHDRAW'),
      incomplete: word('I') || word('INC') || upper.contains('INCOMPLETE'),
      inProgress: word('IP') || upper.contains('IN PROGRESS'),
      repeated: word('R') || upper.contains('REPEAT'),
      gradeReplaced: upper.contains('REPLAC') || upper.contains('FORGIV'),
      transfer: word('TR') || upper.contains('TRANSFER'),
      ap: word('AP') || upper.startsWith('AP '),
      ib: word('IB') || upper.startsWith('IB '),
      clep: word('CLEP'),
      dualEnrollment: upper.contains('DUAL ENROLL'),
      honors: word('H') || upper.contains('HONOR'),
    );
  }

  List<GradingScaleEntry> _parseLegend(
    List<String> lines,
    Map<String, double> confidence,
  ) {
    final out = <GradingScaleEntry>[];
    final seen = <String>{};
    final points = RegExp(
      r'\b(A\+|A-|A|B\+|B-|B|C\+|C-|C|D\+|D-|D|F)\s*'
      r'(?:=|:|is)?\s*(\d(?:\.\d{1,3})?)\b',
      caseSensitive: false,
    );
    final range = RegExp(
      r'\b(A\+|A-|A|B\+|B-|B|C\+|C-|C|D\+|D-|D|F)\s*'
      r'(\d{1,3})\s*[-–]\s*(\d{1,3})',
      caseSensitive: false,
    );
    for (final line in lines) {
      if (line.length > 180) continue;
      for (final match in points.allMatches(line)) {
        final label = match.group(1)!.toUpperCase();
        final key = '$label-points';
        if (!seen.add(key)) continue;
        out.add(GradingScaleEntry(
          label: label,
          gradePoints: double.parse(match.group(2)!),
          printedText: line,
        ));
      }
      for (final match in range.allMatches(line)) {
        final label = match.group(1)!.toUpperCase();
        final key = '$label-range';
        if (!seen.add(key)) continue;
        out.add(GradingScaleEntry(
          label: label,
          minimumPercent: double.parse(match.group(2)!),
          maximumPercent: double.parse(match.group(3)!),
          printedText: line,
        ));
      }
    }
    if (out.isNotEmpty) confidence['gradingScale'] = .82;
    return out;
  }

  CumulativeSummary _parseCumulative(
    List<String> lines,
    Map<String, double> confidence,
  ) {
    double? field(List<String> labels, String path) {
      final value = _labelledNumber(lines, labels, cumulativeOnly: true);
      if (value != null) confidence['cumulative.$path'] = .9;
      return value;
    }

    return CumulativeSummary(
      creditsAttempted: field(const [
        'cumulative credits attempted',
        'total credits attempted',
      ], 'creditsAttempted'),
      creditsEarned: field(const [
        'cumulative credits earned',
        'total credits earned',
        'credits earned',
      ], 'creditsEarned'),
      gpaCredits: field(const [
        'cumulative gpa hours',
        'total gpa hours',
        'gpa credits',
      ], 'gpaCredits'),
      qualityPoints: field(const [
        'cumulative quality points',
        'total quality points',
      ], 'qualityPoints'),
      cumulativeGpa: field(const ['cumulative gpa', 'cum gpa'], 'cumulativeGpa'),
      majorGpa: field(const ['major gpa'], 'majorGpa'),
      institutionalGpa:
          field(const ['institutional gpa', 'institution gpa'], 'institutionalGpa'),
      overallGpa: field(const ['overall gpa'], 'overallGpa'),
      transferCreditsAccepted: field(const [
        'transfer credits accepted',
        'accepted transfer credits',
      ], 'transferCreditsAccepted'),
    );
  }

  List<DegreeAward> _parseDegrees(
    List<String> lines,
    Map<String, double> confidence,
  ) {
    final out = <DegreeAward>[];
    for (var i = 0; i < lines.length; i++) {
      final match = RegExp(
        r'^(?:degree awarded|degree conferred|credential)\s*[:#-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(lines[i]);
      if (match == null) continue;
      final nearby = lines.skip(i).take(5).join(' | ');
      final dateMatch = RegExp(
        r'(?:conferral|conferred|awarded)\s*(?:date)?\s*[:#-]\s*([^|]+)',
        caseSensitive: false,
      ).firstMatch(nearby);
      final honorsMatch = RegExp(
        r'\b(summa cum laude|magna cum laude|cum laude)\b',
        caseSensitive: false,
      ).firstMatch(nearby);
      out.add(DegreeAward(
        id: 'degree-${out.length + 1}',
        degree: _clean(match.group(1)),
        conferralDate:
            dateMatch == null ? null : parseDate(dateMatch.group(1) ?? ''),
        latinHonors: honorsMatch?.group(1),
      ));
      confidence['degrees[${out.length - 1}].degree'] = .92;
    }
    return out;
  }

  static String? _termHeading(String line) {
    if (line.length > 70 || line.contains(':')) return null;
    final match = _term.firstMatch(line);
    if (match == null) return null;
    final lower = line.toLowerCase();
    if (lower.contains('gpa') || lower.contains('credit')) return null;
    return _titleCase(line);
  }

  static String? _transferHeading(String line) {
    final match = RegExp(
      r'^(?:transfer(?:red)?\s+(?:from|institution)|prior institution)\s*[:#-]\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    return match == null ? null : _clean(match.group(1));
  }

  static String? _institutionHeading(List<String> lines) {
    for (final line in lines.take(18)) {
      final lower = line.toLowerCase();
      if (line.length <= 90 &&
          (lower.contains(' high school') ||
              lower.contains(' university') ||
              lower.contains(' college') ||
              lower.contains(' academy'))) {
        return line;
      }
    }
    return null;
  }

  static bool _looksLikeSummary(String line) {
    final lower = line.toLowerCase();
    return [
      'gpa',
      'total credits',
      'cumulative',
      'quality points',
      'academic standing',
      'course description',
      'student name',
      'date of birth',
    ].any(lower.contains);
  }

  static double? _labelledNumber(
    List<String> lines,
    List<String> labels, {
    bool cumulativeOnly = false,
  }) {
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (cumulativeOnly &&
          !lower.contains('cumulative') &&
          !lower.contains('total') &&
          labels.every((label) => !label.startsWith('overall'))) {
        continue;
      }
      for (final label in labels) {
        final match = RegExp(
          '${RegExp.escape(label)}\\s*[:#-]?\\s*(-?\\d+(?:\\.\\d+)?)',
          caseSensitive: false,
        ).firstMatch(line);
        if (match != null) return double.tryParse(match.group(1)!);
      }
    }
    return null;
  }

  static List<String> _splitList(String? value) => value == null
      ? const []
      : value
          .split(RegExp(r'[,;/]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();

  static double? _plainNumber(String value) =>
      double.tryParse(value.replaceAll(RegExp(r'[^0-9.-]'), ''));

  static String _normalise(String value) => value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\u0000', '')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  static String? _clean(String? value) {
    final clean = value?.trim().replaceAll(RegExp(r'\s+'), ' ');
    return clean == null || clean.isEmpty ? null : clean;
  }

  static String _titleCase(String value) {
    if (value != value.toUpperCase()) return value;
    return value
        .split(' ')
        .map((word) => word.length <= 2
            ? word
            : '${word[0]}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _TermBuilder {
  _TermBuilder(this.label);

  final String? label;
  final courses = <NormalizedCourse>[];
  double? statedGpa;
  double? attempted;
  double? earned;
  double? gpaCredits;
  double? quality;
  String? standing;
  DateTime? startDate;
  DateTime? endDate;
  bool? deansList;
  bool? honorsFlag;
  bool? probation;
  final honors = <String>[];

  void consumeSummary(String line) {
    statedGpa ??= _numberAfter(line, const ['term gpa', 'semester gpa', 'gpa']);
    attempted ??= _numberAfter(line, const ['credits attempted', 'attempted']);
    earned ??= _numberAfter(line, const ['credits earned', 'earned']);
    gpaCredits ??= _numberAfter(line, const ['gpa hours', 'gpa credits']);
    quality ??= _numberAfter(line, const ['quality points', 'quality pts']);
    standing ??= _textAfter(line, const ['academic standing', 'standing']);
    final start = _textAfter(line, const ['term start', 'start date']);
    final end = _textAfter(line, const ['term end', 'end date']);
    startDate ??= start == null ? null : parseDate(start);
    endDate ??= end == null ? null : parseDate(end);
    final lower = line.toLowerCase();
    if (lower.contains("dean's list") || lower.contains('deans list')) {
      deansList = true;
    }
    if (lower.contains('academic honors') || lower.contains('honor roll')) {
      honorsFlag = true;
    }
    if (lower.contains('probation')) probation = true;
    for (final word in const [
      "dean's list",
      'honor roll',
      'probation',
      'academic honors',
    ]) {
      if (line.toLowerCase().contains(word) && !honors.contains(word)) {
        honors.add(word);
      }
    }
  }

  NormalizedTerm finish() {
    final year = RegExp(r'\b(19|20)\d{2}\b').firstMatch(label ?? '');
    final termId = (label ?? 'Unassigned')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return NormalizedTerm(
      id: termId,
      label: label,
      year: year == null ? null : int.tryParse(year.group(0)!),
      startDate: startDate,
      endDate: endDate,
      statedGpa: statedGpa,
      creditsAttempted: attempted,
      creditsEarned: earned,
      gpaCredits: gpaCredits,
      qualityPoints: quality,
      academicStanding: standing,
      deansList: deansList,
      honorsFlag: honorsFlag,
      probation: probation,
      honors: honors,
      courses: courses,
    );
  }
}

class _TransferBuilder {
  _TransferBuilder(this.name);

  final String name;
  final courses = <NormalizedCourse>[];
  double? attempted;
  double? accepted;

  void consumeSummary(String line) {
    attempted ??= _numberAfter(line, const ['credits attempted', 'attempted']);
    accepted ??= _numberAfter(line, const ['credits accepted', 'accepted']);
  }

  TransferBlock finish() => TransferBlock(
        id: name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-'),
        sourceInstitution: name,
        creditsAttempted: attempted,
        creditsAccepted: accepted,
        courses: courses,
      );
}

double? _numberAfter(String line, List<String> labels) {
  for (final label in labels) {
    final match = RegExp(
      '${RegExp.escape(label)}\\s*[:#-]?\\s*(-?\\d+(?:\\.\\d+)?)',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) return double.tryParse(match.group(1)!);
  }
  return null;
}

String? _textAfter(String line, List<String> labels) {
  for (final label in labels) {
    final match = RegExp(
      '${RegExp.escape(label)}\\s*[:#-]\\s*(.+)',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) return match.group(1)?.trim();
  }
  return null;
}
