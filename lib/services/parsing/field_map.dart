import 'values.dart';

/// A piece of information the app needs, independent of what any particular
/// portal calls it in markup.
///
/// Matching is done on human-readable labels — table headers, `<dt>` terms,
/// JSON keys, `data-field` names — never on CSS class names, because those
/// differ between schools and change without notice.
enum SemanticField {
  // Profile
  studentName,
  schoolName,
  gpa,
  gpaChange,
  totalCredits,
  classRank,

  // Course / roster
  courseTitle,
  courseCode,
  teacher,
  room,
  period,
  timeRange,
  term,

  // Marks
  score,
  letterGrade,
  gpaPoints,
  credits,

  // Gradebook
  category,
  weight,
  pointsEarned,
  pointsPossible,

  // Work
  assignmentTitle,
  dueDate,
  status,
  itemType,
}

/// Label keywords per field.
///
/// Every entry is a phrase that could plausibly head a column or key a JSON
/// object in a US school portal. Ordering within a list does not matter —
/// [FieldMatcher.match] does the ranking.
const Map<SemanticField, List<String>> _keywords = {
  SemanticField.studentName: [
    'student name', 'student', 'pupil', 'legal name', 'full name', 'name of student',
  ],
  SemanticField.schoolName: [
    'school name', 'school', 'campus', 'building', 'high school',
  ],
  SemanticField.gpa: [
    'cumulative gpa', 'overall gpa', 'weighted gpa', 'unweighted gpa',
    'grade point average', 'gpa', 'average',
  ],
  SemanticField.gpaChange: [
    'gpa change', 'change', 'delta', 'trend', 'this term change',
  ],
  SemanticField.totalCredits: [
    'total credits', 'credits earned', 'cumulative credits',
    'credits accumulated', 'credits to date', 'credits', 'credit',
  ],
  SemanticField.classRank: [
    'class rank', 'rank in class', 'rank', 'standing',
  ],

  SemanticField.courseTitle: [
    'course title', 'course name', 'class name', 'class title', 'course',
    'class', 'subject', 'description', 'course description', 'title',
  ],
  SemanticField.courseCode: [
    'course code', 'class code', 'course id', 'course number', 'section',
    'code', 'crn', 'course sec', 'section id',
  ],
  SemanticField.teacher: [
    'teacher', 'instructor', 'teacher name', 'staff', 'educator',
    'teacher of record', 'faculty',
  ],
  SemanticField.room: [
    'room', 'room number', 'location', 'rm',
  ],
  SemanticField.period: [
    'period', 'pd', 'per', 'block', 'mod', 'session',
  ],
  SemanticField.timeRange: [
    'time', 'meeting time', 'class time', 'start end', 'schedule time', 'hours',
  ],
  SemanticField.term: [
    'term', 'marking period', 'semester', 'quarter', 'trimester',
    'school year', 'year', 'mp', 'grading period', 'cycle',
  ],

  SemanticField.score: [
    'current average', 'course average', 'average', 'percent', 'percentage',
    'numeric grade', 'number grade', 'final average', 'final score', 'score',
    'pct', 'avg', 'overall',
  ],
  SemanticField.letterGrade: [
    'letter grade', 'final grade', 'grade', 'mark', 'letter',
    'current grade', 'report card grade',
  ],
  SemanticField.gpaPoints: [
    'gpa points', 'quality points', 'grade points', 'points earned toward gpa',
  ],
  SemanticField.credits: [
    'credits', 'credit', 'credit value', 'credits attempted', 'units',
    'credit hours',
  ],

  SemanticField.category: [
    'category', 'assignment type', 'grade category', 'type of work',
    'component', 'group',
  ],
  SemanticField.weight: [
    'weight', 'weighting', 'percent of grade', 'of grade', 'value',
  ],
  SemanticField.pointsEarned: [
    'points earned', 'earned', 'points', 'your score', 'received',
  ],
  SemanticField.pointsPossible: [
    'points possible', 'possible', 'out of', 'max points', 'maximum',
    'total points', 'total', 'max', 'denominator',
  ],

  SemanticField.assignmentTitle: [
    'assignment', 'assignment name', 'assignment title', 'task', 'work',
    'title', 'description', 'item',
  ],
  SemanticField.dueDate: [
    'due date', 'due', 'date due', 'deadline', 'date assigned', 'date',
  ],
  SemanticField.status: [
    'status', 'state', 'submitted', 'turned in', 'completion',
  ],
  SemanticField.itemType: [
    'type', 'kind', 'assignment type', 'work type',
  ],
};

/// Maps human labels to [SemanticField]s within a restricted candidate set.
///
/// Restricting the candidates is what keeps ambiguous words honest: `"name"`
/// means the student on a profile page and the course on a roster, and
/// `"grade"` means a letter on a transcript but can mean a year level
/// elsewhere. Callers pass the fields that make sense for the record they are
/// reading.
class FieldMatcher {
  final Set<SemanticField> candidates;

  /// The field a record of this kind is fundamentally *about*.
  ///
  /// Card layouts often give the name its own heading rather than a label, so
  /// when nothing else identified it, the block's heading fills this field.
  final SemanticField? primary;

  const FieldMatcher(this.candidates, {this.primary});

  /// Best field for [label], or null when nothing plausible matches.
  ///
  /// Ranked by, in order: an exact match, then a match on the *end* of the
  /// label, then the longest keyword. The end rule reflects how English
  /// compounds work — `"period room"` is a room and `"period teacher"` is a
  /// teacher, even though both begin with a word that names another field.
  SemanticField? match(String label) {
    final normalized = normalizeLabel(label);
    if (normalized.isEmpty) return null;

    SemanticField? best;
    var bestRank = (exact: false, atEnd: false, length: 0);

    for (final field in candidates) {
      for (final keyword in _keywords[field] ?? const <String>[]) {
        final exact = normalized == keyword;
        if (!exact && !_containsPhrase(normalized, keyword)) continue;

        final rank = (
          exact: exact,
          atEnd: exact || normalized.endsWith(' $keyword'),
          length: keyword.length,
        );
        if (_outranks(rank, bestRank)) {
          best = field;
          bestRank = rank;
        }
      }
    }
    return best;
  }

  static bool _outranks(
    ({bool exact, bool atEnd, int length}) a,
    ({bool exact, bool atEnd, int length}) b,
  ) {
    if (a.exact != b.exact) return a.exact;
    if (a.atEnd != b.atEnd) return a.atEnd;
    return a.length > b.length;
  }

  /// Whole-word containment, so `"per"` does not match `"performance"`.
  static bool _containsPhrase(String haystack, String needle) {
    final i = haystack.indexOf(needle);
    if (i < 0) return false;
    final startOk = i == 0 || haystack[i - 1] == ' ';
    final end = i + needle.length;
    final endOk = end == haystack.length || haystack[end] == ' ';
    return startOk && endOk;
  }

  // ── Candidate sets, one per kind of record the app reads ──────────────

  static const courseRow = FieldMatcher(
    {
      SemanticField.courseTitle,
      SemanticField.courseCode,
      SemanticField.teacher,
      SemanticField.score,
      SemanticField.letterGrade,
      SemanticField.term,
      SemanticField.period,
      SemanticField.room,
      SemanticField.credits,
    },
    primary: SemanticField.courseTitle,
  );

  static const scheduleRow = FieldMatcher(
    {
      SemanticField.period,
      SemanticField.courseTitle,
      SemanticField.courseCode,
      SemanticField.teacher,
      SemanticField.room,
      SemanticField.timeRange,
      SemanticField.term,
    },
    primary: SemanticField.courseTitle,
  );

  static const transcriptRow = FieldMatcher(
    {
      SemanticField.courseTitle,
      SemanticField.courseCode,
      SemanticField.letterGrade,
      SemanticField.score,
      SemanticField.credits,
      SemanticField.term,
      SemanticField.gpaPoints,
    },
    primary: SemanticField.courseTitle,
  );

  static const workRow = FieldMatcher(
    {
      SemanticField.assignmentTitle,
      SemanticField.courseTitle,
      SemanticField.dueDate,
      SemanticField.status,
      SemanticField.itemType,
      SemanticField.letterGrade,
      SemanticField.score,
    },
    primary: SemanticField.assignmentTitle,
  );

  static const assignmentRow = FieldMatcher(
    {
      SemanticField.assignmentTitle,
      SemanticField.category,
      SemanticField.pointsEarned,
      SemanticField.pointsPossible,
      SemanticField.score,
      SemanticField.letterGrade,
      SemanticField.dueDate,
      SemanticField.status,
    },
    primary: SemanticField.assignmentTitle,
  );

  static const categoryRow = FieldMatcher(
    {
      SemanticField.category,
      SemanticField.weight,
      SemanticField.pointsEarned,
      SemanticField.pointsPossible,
      SemanticField.score,
    },
    primary: SemanticField.category,
  );

  static const profileField = FieldMatcher({
    SemanticField.studentName,
    SemanticField.schoolName,
    SemanticField.gpa,
    SemanticField.gpaChange,
    SemanticField.totalCredits,
    SemanticField.classRank,
  });
}

/// Which [ValueShape]s are plausible for a field, used to infer columns when a
/// table has no header row at all.
const Map<SemanticField, Set<ValueShape>> fieldShapes = {
  SemanticField.letterGrade: {ValueShape.letterGrade},
  SemanticField.score: {ValueShape.percentage, ValueShape.integer, ValueShape.decimal},
  SemanticField.credits: {ValueShape.credits},
  SemanticField.gpaPoints: {ValueShape.credits, ValueShape.decimal},
  SemanticField.period: {ValueShape.integer},
  SemanticField.timeRange: {ValueShape.timeRange},
  SemanticField.dueDate: {ValueShape.date},
  SemanticField.teacher: {ValueShape.personName},
  SemanticField.courseTitle: {ValueShape.text},
  SemanticField.assignmentTitle: {ValueShape.text},
  SemanticField.term: {ValueShape.text},
  SemanticField.category: {ValueShape.text},
  SemanticField.room: {ValueShape.text, ValueShape.integer},
  SemanticField.pointsEarned: {ValueShape.integer, ValueShape.decimal},
  SemanticField.pointsPossible: {ValueShape.integer, ValueShape.decimal},
};
