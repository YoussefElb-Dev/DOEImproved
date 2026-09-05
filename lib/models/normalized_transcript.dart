/// Versioned, institution-neutral transcript schema.
///
/// Every field that may be absent is nullable. Parsing code must not invent a
/// value merely to make the UI look complete.
const int currentTranscriptSchemaVersion = 2;

enum CreditSystem { semester, quarter, unknown }

enum OfficialStatus { official, unofficial, unknown }

enum RepeatPolicy { replace, average, unknown }

class TranscriptStudent {
  final String? name;
  final String? studentId;
  final DateTime? dateOfBirth;

  const TranscriptStudent({this.name, this.studentId, this.dateOfBirth});

  factory TranscriptStudent.fromJson(Map<String, dynamic> j) =>
      TranscriptStudent(
        name: _string(j['name']),
        studentId: _string(j['studentId']),
        dateOfBirth: _date(j['dateOfBirth']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'studentId': studentId,
        'dateOfBirth': _dateJson(dateOfBirth),
      };
}

class TranscriptInstitution {
  final String? name;
  final String? institutionId;
  final String? address;

  const TranscriptInstitution({this.name, this.institutionId, this.address});

  factory TranscriptInstitution.fromJson(Map<String, dynamic> j) =>
      TranscriptInstitution(
        name: _string(j['name']),
        institutionId: _string(j['institutionId']),
        address: _string(j['address']),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'institutionId': institutionId,
        'address': address,
      };
}

class TranscriptProgram {
  final String? program;
  final String? degreeSought;
  final List<String> majors;
  final List<String> minors;
  final List<String> concentrations;
  final String? catalogYear;
  final double? creditsRequired;

  const TranscriptProgram({
    this.program,
    this.degreeSought,
    this.majors = const [],
    this.minors = const [],
    this.concentrations = const [],
    this.catalogYear,
    this.creditsRequired,
  });

  factory TranscriptProgram.fromJson(Map<String, dynamic> j) =>
      TranscriptProgram(
        program: _string(j['program']),
        degreeSought: _string(j['degreeSought']),
        majors: _strings(j['majors']),
        minors: _strings(j['minors']),
        concentrations: _strings(j['concentrations']),
        catalogYear: _string(j['catalogYear']),
        creditsRequired: _number(j['creditsRequired']),
      );

  Map<String, dynamic> toJson() => {
        'program': program,
        'degreeSought': degreeSought,
        'majors': majors,
        'minors': minors,
        'concentrations': concentrations,
        'catalogYear': catalogYear,
        'creditsRequired': creditsRequired,
      };
}

class GradingScaleEntry {
  final String label;
  final double? minimumPercent;
  final double? maximumPercent;
  final double? gradePoints;
  final String? printedText;

  const GradingScaleEntry({
    required this.label,
    this.minimumPercent,
    this.maximumPercent,
    this.gradePoints,
    this.printedText,
  });

  factory GradingScaleEntry.fromJson(Map<String, dynamic> j) =>
      GradingScaleEntry(
        label: _string(j['label']) ?? '',
        minimumPercent: _number(j['minimumPercent']),
        maximumPercent: _number(j['maximumPercent']),
        gradePoints: _number(j['gradePoints']),
        printedText: _string(j['printedText']),
      );

  Map<String, dynamic> toJson() => {
        'label': label,
        'minimumPercent': minimumPercent,
        'maximumPercent': maximumPercent,
        'gradePoints': gradePoints,
        'printedText': printedText,
      };
}

class CourseFlags {
  final bool passFail;
  final bool audit;
  final bool withdrawn;
  final bool incomplete;
  final bool inProgress;
  final bool repeated;
  final bool gradeReplaced;
  final bool transfer;
  final bool ap;
  final bool ib;
  final bool clep;
  final bool dualEnrollment;
  final bool honors;

  const CourseFlags({
    this.passFail = false,
    this.audit = false,
    this.withdrawn = false,
    this.incomplete = false,
    this.inProgress = false,
    this.repeated = false,
    this.gradeReplaced = false,
    this.transfer = false,
    this.ap = false,
    this.ib = false,
    this.clep = false,
    this.dualEnrollment = false,
    this.honors = false,
  });

  factory CourseFlags.fromJson(Map<String, dynamic> j) => CourseFlags(
        passFail: _bool(j['passFail']),
        audit: _bool(j['audit']),
        withdrawn: _bool(j['withdrawn']),
        incomplete: _bool(j['incomplete']),
        inProgress: _bool(j['inProgress']),
        repeated: _bool(j['repeated']),
        gradeReplaced: _bool(j['gradeReplaced']),
        transfer: _bool(j['transfer']),
        ap: _bool(j['ap']),
        ib: _bool(j['ib']),
        clep: _bool(j['clep']),
        dualEnrollment: _bool(j['dualEnrollment']),
        honors: _bool(j['honors']),
      );

  Map<String, dynamic> toJson() => {
        'passFail': passFail,
        'audit': audit,
        'withdrawn': withdrawn,
        'incomplete': incomplete,
        'inProgress': inProgress,
        'repeated': repeated,
        'gradeReplaced': gradeReplaced,
        'transfer': transfer,
        'ap': ap,
        'ib': ib,
        'clep': clep,
        'dualEnrollment': dualEnrollment,
        'honors': honors,
      };
}

class NormalizedCourse {
  final String id;
  final String? subjectCode;
  final String? courseNumber;
  final String? title;
  final String? section;
  final double? creditsAttempted;
  final double? creditsEarned;
  final String? letterGrade;
  final double? numericGrade;
  final double? gradePoints;
  final double? qualityPoints;
  final bool? countsTowardGpa;
  final CourseFlags flags;
  final String? sourceInstitution;
  final String? rawLine;

  const NormalizedCourse({
    required this.id,
    this.subjectCode,
    this.courseNumber,
    this.title,
    this.section,
    this.creditsAttempted,
    this.creditsEarned,
    this.letterGrade,
    this.numericGrade,
    this.gradePoints,
    this.qualityPoints,
    this.countsTowardGpa,
    this.flags = const CourseFlags(),
    this.sourceInstitution,
    this.rawLine,
  });

  factory NormalizedCourse.fromJson(Map<String, dynamic> j) =>
      NormalizedCourse(
        id: _string(j['id']) ?? '',
        subjectCode: _string(j['subjectCode']),
        courseNumber: _string(j['courseNumber']),
        title: _string(j['title']),
        section: _string(j['section']),
        creditsAttempted: _number(j['creditsAttempted']),
        creditsEarned: _number(j['creditsEarned']),
        letterGrade: _string(j['letterGrade']),
        numericGrade: _number(j['numericGrade']),
        gradePoints: _number(j['gradePoints']),
        qualityPoints: _number(j['qualityPoints']),
        countsTowardGpa: _nullableBool(j['countsTowardGpa']),
        flags: CourseFlags.fromJson(_map(j['flags'])),
        sourceInstitution: _string(j['sourceInstitution']),
        rawLine: _string(j['rawLine']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'subjectCode': subjectCode,
        'courseNumber': courseNumber,
        'title': title,
        'section': section,
        'creditsAttempted': creditsAttempted,
        'creditsEarned': creditsEarned,
        'letterGrade': letterGrade,
        'numericGrade': numericGrade,
        'gradePoints': gradePoints,
        'qualityPoints': qualityPoints,
        'countsTowardGpa': countsTowardGpa,
        'flags': flags.toJson(),
        'sourceInstitution': sourceInstitution,
        'rawLine': rawLine,
      };
}

class NormalizedTerm {
  final String id;
  final String? label;
  final int? year;
  final DateTime? startDate;
  final DateTime? endDate;
  final double? statedGpa;
  final double? creditsAttempted;
  final double? creditsEarned;
  final double? gpaCredits;
  final double? qualityPoints;
  final String? academicStanding;
  final bool? deansList;
  final bool? honorsFlag;
  final bool? probation;
  final List<String> honors;
  final List<NormalizedCourse> courses;

  const NormalizedTerm({
    required this.id,
    this.label,
    this.year,
    this.startDate,
    this.endDate,
    this.statedGpa,
    this.creditsAttempted,
    this.creditsEarned,
    this.gpaCredits,
    this.qualityPoints,
    this.academicStanding,
    this.deansList,
    this.honorsFlag,
    this.probation,
    this.honors = const [],
    this.courses = const [],
  });

  factory NormalizedTerm.fromJson(Map<String, dynamic> j) => NormalizedTerm(
        id: _string(j['id']) ?? '',
        label: _string(j['label']),
        year: (j['year'] as num?)?.toInt(),
        startDate: _date(j['startDate']),
        endDate: _date(j['endDate']),
        statedGpa: _number(j['statedGpa']),
        creditsAttempted: _number(j['creditsAttempted']),
        creditsEarned: _number(j['creditsEarned']),
        gpaCredits: _number(j['gpaCredits']),
        qualityPoints: _number(j['qualityPoints']),
        academicStanding: _string(j['academicStanding']),
        deansList: _nullableBool(j['deansList']),
        honorsFlag: _nullableBool(j['honorsFlag']),
        probation: _nullableBool(j['probation']),
        honors: _strings(j['honors']),
        courses: [
          for (final c in (j['courses'] as List? ?? const []))
            NormalizedCourse.fromJson(_map(c)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'year': year,
        'startDate': _dateJson(startDate),
        'endDate': _dateJson(endDate),
        'statedGpa': statedGpa,
        'creditsAttempted': creditsAttempted,
        'creditsEarned': creditsEarned,
        'gpaCredits': gpaCredits,
        'qualityPoints': qualityPoints,
        'academicStanding': academicStanding,
        'deansList': deansList,
        'honorsFlag': honorsFlag,
        'probation': probation,
        'honors': honors,
        'courses': [for (final c in courses) c.toJson()],
      };
}

class CumulativeSummary {
  final double? creditsAttempted;
  final double? creditsEarned;
  final double? gpaCredits;
  final double? qualityPoints;
  final double? cumulativeGpa;
  final double? majorGpa;
  final double? institutionalGpa;
  final double? overallGpa;
  final double? transferCreditsAccepted;

  const CumulativeSummary({
    this.creditsAttempted,
    this.creditsEarned,
    this.gpaCredits,
    this.qualityPoints,
    this.cumulativeGpa,
    this.majorGpa,
    this.institutionalGpa,
    this.overallGpa,
    this.transferCreditsAccepted,
  });

  factory CumulativeSummary.fromJson(Map<String, dynamic> j) =>
      CumulativeSummary(
        creditsAttempted: _number(j['creditsAttempted']),
        creditsEarned: _number(j['creditsEarned']),
        gpaCredits: _number(j['gpaCredits']),
        qualityPoints: _number(j['qualityPoints']),
        cumulativeGpa: _number(j['cumulativeGpa']),
        majorGpa: _number(j['majorGpa']),
        institutionalGpa: _number(j['institutionalGpa']),
        overallGpa: _number(j['overallGpa']),
        transferCreditsAccepted: _number(j['transferCreditsAccepted']),
      );

  Map<String, dynamic> toJson() => {
        'creditsAttempted': creditsAttempted,
        'creditsEarned': creditsEarned,
        'gpaCredits': gpaCredits,
        'qualityPoints': qualityPoints,
        'cumulativeGpa': cumulativeGpa,
        'majorGpa': majorGpa,
        'institutionalGpa': institutionalGpa,
        'overallGpa': overallGpa,
        'transferCreditsAccepted': transferCreditsAccepted,
      };
}

class TransferBlock {
  final String id;
  final String? sourceInstitution;
  final double? creditsAttempted;
  final double? creditsAccepted;
  final List<NormalizedCourse> courses;

  const TransferBlock({
    required this.id,
    this.sourceInstitution,
    this.creditsAttempted,
    this.creditsAccepted,
    this.courses = const [],
  });

  factory TransferBlock.fromJson(Map<String, dynamic> j) => TransferBlock(
        id: _string(j['id']) ?? '',
        sourceInstitution: _string(j['sourceInstitution']),
        creditsAttempted: _number(j['creditsAttempted']),
        creditsAccepted: _number(j['creditsAccepted']),
        courses: [
          for (final c in (j['courses'] as List? ?? const []))
            NormalizedCourse.fromJson(_map(c)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceInstitution': sourceInstitution,
        'creditsAttempted': creditsAttempted,
        'creditsAccepted': creditsAccepted,
        'courses': [for (final c in courses) c.toJson()],
      };
}

class DegreeAward {
  final String id;
  final String? degree;
  final DateTime? conferralDate;
  final String? latinHonors;
  final List<String> majors;

  const DegreeAward({
    required this.id,
    this.degree,
    this.conferralDate,
    this.latinHonors,
    this.majors = const [],
  });

  factory DegreeAward.fromJson(Map<String, dynamic> j) => DegreeAward(
        id: _string(j['id']) ?? '',
        degree: _string(j['degree']),
        conferralDate: _date(j['conferralDate']),
        latinHonors: _string(j['latinHonors']),
        majors: _strings(j['majors']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'degree': degree,
        'conferralDate': _dateJson(conferralDate),
        'latinHonors': latinHonors,
        'majors': majors,
      };
}

class NormalizedTranscript {
  final int schemaVersion;
  final String id;
  final String sourceFingerprint;
  final String sourceFileName;
  final String? sourceDocumentId;
  final DateTime importedAt;
  final String rawText;
  final TranscriptStudent student;
  final TranscriptInstitution institution;
  final DateTime? issueDate;
  final OfficialStatus officialStatus;
  final TranscriptProgram program;
  final CreditSystem creditSystem;
  final RepeatPolicy repeatPolicy;
  final List<GradingScaleEntry> gradingScale;
  final List<NormalizedTerm> terms;
  final CumulativeSummary cumulative;
  final List<TransferBlock> transfers;
  final List<DegreeAward> degrees;
  final List<String> warnings;

  /// Confidence by JSON-style path, 0 through 1. Missing means not parsed.
  final Map<String, double> confidence;

  const NormalizedTranscript({
    this.schemaVersion = currentTranscriptSchemaVersion,
    required this.id,
    required this.sourceFingerprint,
    required this.sourceFileName,
    this.sourceDocumentId,
    required this.importedAt,
    required this.rawText,
    required this.student,
    required this.institution,
    this.issueDate,
    this.officialStatus = OfficialStatus.unknown,
    this.program = const TranscriptProgram(),
    this.creditSystem = CreditSystem.unknown,
    this.repeatPolicy = RepeatPolicy.unknown,
    this.gradingScale = const [],
    this.terms = const [],
    this.cumulative = const CumulativeSummary(),
    this.transfers = const [],
    this.degrees = const [],
    this.warnings = const [],
    this.confidence = const {},
  });

  factory NormalizedTranscript.fromJson(Map<String, dynamic> original) {
    final j = TranscriptSchemaMigrator.migrate(original);
    return NormalizedTranscript(
      schemaVersion: currentTranscriptSchemaVersion,
      id: _string(j['id']) ?? '',
      sourceFingerprint: _string(j['sourceFingerprint']) ?? '',
      sourceFileName: _string(j['sourceFileName']) ?? 'Transcript.pdf',
      sourceDocumentId: _string(j['sourceDocumentId']),
      importedAt: _date(j['importedAt']) ?? DateTime.now(),
      rawText: _string(j['rawText']) ?? '',
      student: TranscriptStudent.fromJson(_map(j['student'])),
      institution: TranscriptInstitution.fromJson(_map(j['institution'])),
      issueDate: _date(j['issueDate']),
      officialStatus: _enumValue(
        OfficialStatus.values,
        j['officialStatus'],
        OfficialStatus.unknown,
      ),
      program: TranscriptProgram.fromJson(_map(j['program'])),
      creditSystem: _enumValue(
        CreditSystem.values,
        j['creditSystem'],
        CreditSystem.unknown,
      ),
      repeatPolicy: _enumValue(
        RepeatPolicy.values,
        j['repeatPolicy'],
        RepeatPolicy.unknown,
      ),
      gradingScale: [
        for (final e in (j['gradingScale'] as List? ?? const []))
          GradingScaleEntry.fromJson(_map(e)),
      ],
      terms: [
        for (final t in (j['terms'] as List? ?? const []))
          NormalizedTerm.fromJson(_map(t)),
      ],
      cumulative: CumulativeSummary.fromJson(_map(j['cumulative'])),
      transfers: [
        for (final t in (j['transfers'] as List? ?? const []))
          TransferBlock.fromJson(_map(t)),
      ],
      degrees: [
        for (final d in (j['degrees'] as List? ?? const []))
          DegreeAward.fromJson(_map(d)),
      ],
      warnings: _strings(j['warnings']),
      confidence: {
        for (final e in _map(j['confidence']).entries)
          e.key: _number(e.value) ?? 0,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'schemaVersion': currentTranscriptSchemaVersion,
        'id': id,
        'sourceFingerprint': sourceFingerprint,
        'sourceFileName': sourceFileName,
        'sourceDocumentId': sourceDocumentId,
        'importedAt': importedAt.toIso8601String(),
        'rawText': rawText,
        'student': student.toJson(),
        'institution': institution.toJson(),
        'issueDate': _dateJson(issueDate),
        'officialStatus': officialStatus.name,
        'program': program.toJson(),
        'creditSystem': creditSystem.name,
        'repeatPolicy': repeatPolicy.name,
        'gradingScale': [for (final e in gradingScale) e.toJson()],
        'terms': [for (final t in terms) t.toJson()],
        'cumulative': cumulative.toJson(),
        'transfers': [for (final t in transfers) t.toJson()],
        'degrees': [for (final d in degrees) d.toJson()],
        'warnings': warnings,
        'confidence': confidence,
      };

  int get courseCount => terms.fold(0, (n, t) => n + t.courses.length);
}

/// Migration is deliberately pure and incremental. Future schema versions add
/// one `case` here and old imports remain readable.
class TranscriptSchemaMigrator {
  const TranscriptSchemaMigrator._();

  static Map<String, dynamic> migrate(Map<String, dynamic> input) {
    var data = Map<String, dynamic>.from(input);
    var version = (data['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > currentTranscriptSchemaVersion) {
      throw FormatException('Transcript schema $version is newer than this app');
    }
    while (version < currentTranscriptSchemaVersion) {
      switch (version) {
        case 1:
          data = _oneToTwo(data);
          version = 2;
        default:
          throw FormatException('No migration exists for schema $version');
      }
    }
    data['schemaVersion'] = currentTranscriptSchemaVersion;
    return data;
  }

  static Map<String, dynamic> _oneToTwo(Map<String, dynamic> old) => {
        ...old,
        'program': old['program'] ?? <String, dynamic>{},
        'repeatPolicy': old['repeatPolicy'] ?? RepeatPolicy.unknown.name,
        'transfers': old['transfers'] ?? <dynamic>[],
        'degrees': old['degrees'] ?? <dynamic>[],
        'warnings': old['warnings'] ?? <dynamic>[],
        'confidence': old['confidence'] ?? <String, dynamic>{},
        'schemaVersion': 2,
      };
}

Map<String, dynamic> _map(Object? value) => value is Map
    ? Map<String, dynamic>.from(value)
    : <String, dynamic>{};

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double? _number(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value');

bool _bool(Object? value) => value == true;

bool? _nullableBool(Object? value) => value is bool ? value : null;

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.tryParse('$value');

String? _dateJson(DateTime? value) => value?.toIso8601String();

List<String> _strings(Object? value) {
  if (value is! List) return const [];
  final result = <String>[];
  for (final item in value) {
    final text = _string(item);
    if (text != null) result.add(text);
  }
  return result;
}

T _enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = _string(raw);
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
