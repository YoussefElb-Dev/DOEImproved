/// Normalisation and shape-aware parsing of the raw text found in portal
/// markup.
///
/// Everything here is defensive by design: portals differ between schools and
/// change without notice, so a value that cannot be understood becomes `null`
/// rather than throwing.
library;

const String _nbsp = '\u00A0';

/// Collapses whitespace (including non-breaking spaces) and trims.
String normalizeText(String raw) => raw
    .replaceAll(_nbsp, ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Lowercased, punctuation-free form used to match header labels and JSON
/// keys. `"Marking Period"`, `"marking_period"` and `"markingPeriod"` all
/// normalise to `"marking period"`, so one keyword list covers every spelling
/// a portal might use.
String normalizeLabel(String raw) {
  final spaced = raw.replaceAllMapped(
    RegExp(r'([a-z0-9])([A-Z])'),
    (m) => '${m[1]} ${m[2]}',
  );
  return spaced
      .replaceAll(_nbsp, ' ')
      .replaceAll(RegExp(r'[^A-Za-z0-9]+'), ' ')
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// The kind of value a cell holds. Used to infer what a column means when a
/// table gives no usable header row.
enum ValueShape {
  empty,
  percentage,
  fraction,
  letterGrade,
  credits,
  integer,
  decimal,
  date,
  timeRange,
  personName,
  text,
}

/// Letter grades plus the non-numeric marks NYC transcripts use:
/// P(ass), F(ail), NS (never showed), INC/I (incomplete), W/WD (withdrawn),
/// CR/NC (credit / no credit), AUD (audit), EX (exempt).
final RegExp _letterGrade = RegExp(r'^[A-F][+-]?$', caseSensitive: false);
const Set<String> _nonNumericMarks = {
  'P', 'NS', 'INC', 'I', 'W', 'WD', 'CR', 'NC', 'AUD', 'EX', 'NG', 'MED',
};

final RegExp _percent = RegExp(r'^-?\d{1,3}(\.\d+)?\s*%$');
final RegExp _timeRange = RegExp(
  r'\d{1,2}:\d{2}\s*(am|pm)?\s*[-–—to]+\s*\d{1,2}:\d{2}\s*(am|pm)?',
  caseSensitive: false,
);
final RegExp _clock =
    RegExp(r'(\d{1,2}):(\d{2})\s*(a\.?m\.?|p\.?m\.?)?', caseSensitive: false);

const List<String> _months = [
  'january', 'february', 'march', 'april', 'may', 'june',
  'july', 'august', 'september', 'october', 'november', 'december',
];

/// Classifies a single cell value.
ValueShape classifyValue(String raw) {
  final v = normalizeText(raw);
  if (v.isEmpty || v == '-' || v == '—' || v == 'N/A') return ValueShape.empty;

  if (_percent.hasMatch(v)) return ValueShape.percentage;
  // Checked before dates: "8/10" is a score out of ten, not the 8th of October.
  if (parseFraction(v) != null) return ValueShape.fraction;
  if (parseLetterGrade(v) != null) return ValueShape.letterGrade;
  if (_timeRange.hasMatch(v)) return ValueShape.timeRange;
  if (parseDate(v) != null) return ValueShape.date;

  final n = parseNumber(v);
  if (n != null && RegExp(r'^[\d.,\s%/-]+$').hasMatch(v)) {
    // Written form, not numeric value: "1.0" parses equal to 1, but a portal
    // that wrote the decimal meant a credit value, not a count.
    if (!v.contains('.')) return ValueShape.integer;
    // A small decimal in a grades context is almost always credits
    // (0.5, 1.0, 2.5); anything larger is a score.
    return n <= 12 ? ValueShape.credits : ValueShape.decimal;
  }

  if (looksLikePersonName(v)) return ValueShape.personName;
  return ValueShape.text;
}

/// Pulls the first number out of [raw], tolerating currency-style thousands
/// separators, stray percent signs and surrounding words.
double? parseNumber(String raw) {
  final v = normalizeText(raw).replaceAll(',', '');
  final m = RegExp(r'-?\d+(\.\d+)?').firstMatch(v);
  if (m == null) return null;
  return double.tryParse(m.group(0)!);
}

/// A percentage or bare 0–100 score. Returns null for values that are clearly
/// not a score, so a credits column is not mistaken for one.
double? parseScore(String raw) {
  final v = normalizeText(raw);
  if (v.isEmpty) return null;
  final n = parseNumber(v);
  if (n == null) return null;
  // Portals occasionally post scores above 100 for extra credit.
  if (n < 0 || n > 200) return null;
  return n;
}

/// Normalises a letter grade or non-numeric mark to upper case, or returns
/// null when [raw] is not one. Tolerates decoration like `(A-)` and `A- `.
String? parseLetterGrade(String raw) {
  var v = normalizeText(raw).replaceAll(RegExp(r'^[(\[]|[)\]]$'), '').trim();
  if (v.isEmpty || v.length > 4) return null;
  v = v.toUpperCase();
  if (_letterGrade.hasMatch(v)) return v;
  if (_nonNumericMarks.contains(v)) return v;
  return null;
}

/// `"18/20"` — the earned-over-possible form gradebooks use for one
/// assignment. Also matches `"18 / 20"`.
({double earned, double possible})? parseFraction(String raw) {
  final m = RegExp(r'^(\d+(?:\.\d+)?)\s*/\s*(\d+(?:\.\d+)?)$')
      .firstMatch(normalizeText(raw));
  if (m == null) return null;
  final earned = double.tryParse(m.group(1)!);
  final possible = double.tryParse(m.group(2)!);
  if (earned == null || possible == null || possible <= 0) return null;
  return (earned: earned, possible: possible);
}

/// Credit values are small and usually fractional: 0.5, 1, 1.0, 2.
double? parseCredits(String raw) {
  final n = parseNumber(raw);
  if (n == null || n < 0 || n > 20) return null;
  return n;
}

/// A period number from `"3"`, `"Period 3"`, `"P3"`, `"3rd"` or `"Per. 3"`.
/// Returns null for values outside a plausible period range.
int? parsePeriod(String raw) {
  final v = normalizeText(raw);
  if (v.isEmpty) return null;
  final m = RegExp(r'\d{1,2}').firstMatch(v);
  if (m == null) return null;
  final n = int.tryParse(m.group(0)!);
  if (n == null || n < 0 || n > 20) return null;
  return n;
}

/// Parses the date formats portals actually emit: ISO, US numeric, and
/// month-name forms with or without a year. [relativeTo] supplies the year for
/// formats that omit it, and resolves the relative words some portals use.
DateTime? parseDate(String raw, {DateTime? relativeTo}) {
  final now = relativeTo ?? DateTime.now();
  final v = normalizeText(raw);
  if (v.isEmpty) return null;

  final lower = v.toLowerCase();
  if (lower == 'today') return DateTime(now.year, now.month, now.day);
  if (lower == 'tomorrow') {
    final d = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return d;
  }
  if (lower == 'yesterday') {
    return DateTime(now.year, now.month, now.day)
        .subtract(const Duration(days: 1));
  }

  // ISO 8601 (with or without a time component).
  final iso = DateTime.tryParse(v);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  // M/D/YYYY, M-D-YY, M/D
  final numeric =
      RegExp(r'^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2,4}))?').firstMatch(v);
  if (numeric != null) {
    final month = int.parse(numeric.group(1)!);
    final day = int.parse(numeric.group(2)!);
    var year = int.tryParse(numeric.group(3) ?? '') ?? now.year;
    if (year < 100) year += 2000;
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(year, month, day);
    }
  }

  // "Sep 3", "September 3, 2026", "3 Sep 2026"
  final monthIndex = _months.indexWhere((m) => lower.contains(m.substring(0, 3)));
  if (monthIndex >= 0) {
    final dayMatch = RegExp(r'\b(\d{1,2})\b').firstMatch(lower);
    final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(lower);
    if (dayMatch != null) {
      final day = int.parse(dayMatch.group(1)!);
      final year = int.tryParse(yearMatch?.group(1) ?? '') ?? now.year;
      if (day >= 1 && day <= 31) return DateTime(year, monthIndex + 1, day);
    }
  }

  return null;
}

/// Parses `"8:00 AM - 8:45 AM"`, `"08:00–08:45"`, `"8:00 to 8:45 am"` into a
/// start/end pair anchored on [day]. Returns null when no range is present.
///
/// A 12-hour end time without a meridiem inherits the start's, and an end that
/// lands before the start is nudged to PM — which is how `"11:30 - 12:15"`
/// is meant to read.
({DateTime start, DateTime end})? parseTimeRange(String raw, DateTime day) {
  final v = normalizeText(raw);
  final matches = _clock.allMatches(v).toList();
  if (matches.length < 2) return null;

  final first = matches.first;
  final second = matches[1];

  String? meridiem(RegExpMatch m) {
    final g = m.group(3);
    if (g == null) return null;
    return g.toLowerCase().startsWith('a') ? 'am' : 'pm';
  }

  final startMeridiem = meridiem(first) ?? meridiem(second);
  final endMeridiem = meridiem(second) ?? startMeridiem;

  DateTime at(RegExpMatch m, String? ap) {
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    return DateTime(day.year, day.month, day.day, h % 24, min);
  }

  final start = at(first, startMeridiem);
  var end = at(second, endMeridiem);
  if (!end.isAfter(start)) {
    // "11:30 - 12:15" on a 12-hour clock crosses noon.
    end = end.add(const Duration(hours: 12));
    if (!end.isAfter(start)) end = start;
  }
  return (start: start, end: end);
}

/// Heuristic for "this cell holds a person, not a course".
///
/// Catches the honorifics NYC rosters use (including Spanish and French ones)
/// and the `"Last, First"` form, without claiming every two-word string is a
/// name — that would swallow course titles.
bool looksLikePersonName(String raw) {
  final v = normalizeText(raw);
  if (v.isEmpty || v.length > 60) return false;

  if (RegExp(
    r'^(mr|mrs|ms|miss|mx|dr|prof|professor|sr|sra|srta|mme|mlle|m)\b\.?\s+\S',
    caseSensitive: false,
  ).hasMatch(v)) {
    return true;
  }

  // "Okafor, Adaeze" — a comma between two capitalised words.
  if (RegExp(r"^[A-Z][\w'-]+,\s*[A-Z][\w'-]+$").hasMatch(v)) return true;

  return false;
}

/// True when the text reads as "nothing has been posted here", which portals
/// express many different ways.
bool readsAsUnavailable(String bodyText) {
  final t = bodyText.toLowerCase();
  const phrases = [
    'not available',
    'unavailable',
    'no schedule',
    'schedule not posted',
    'not been posted',
    'no data',
    'no records',
    'no results',
    'nothing to display',
    'no information',
    'no courses',
    'no transcript',
    'coming soon',
  ];
  return phrases.any(t.contains);
}
