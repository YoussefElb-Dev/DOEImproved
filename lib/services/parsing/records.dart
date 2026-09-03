import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import 'field_map.dart';
import 'values.dart';

/// One extracted row: a course, a period, a transcript line, an assignment.
///
/// [fields] holds whatever could be identified semantically; [cells] keeps the
/// raw values in document order so shape-based inference can still work when
/// nothing was labelled.
class PortalRecord {
  final Map<SemanticField, String> fields;
  final List<String> cells;
  final String text;

  /// An identifier the portal gave this row, if any.
  final String? id;

  /// The row's own link — a course's gradebook page, say. Followed verbatim
  /// rather than guessed at, because URL layouts differ between portals.
  final String? link;

  const PortalRecord({
    required this.fields,
    this.cells = const [],
    this.text = '',
    this.id,
    this.link,
  });

  String? operator [](SemanticField field) {
    final v = fields[field];
    return (v == null || v.isEmpty) ? null : v;
  }

  bool has(SemanticField field) => this[field] != null;

  int coverage(Iterable<SemanticField> wanted) => wanted.where(has).length;
}

/// A group of records that came from one structure — a single table, a single
/// JSON array, one run of repeated cards.
class RecordSet {
  final List<PortalRecord> records;

  /// Where these came from, for diagnostics ("table#2", "json:courses").
  final String origin;

  const RecordSet(this.records, this.origin);

  bool get isEmpty => records.isEmpty;
}

/// A fetched portal page, whether it came back as HTML or as JSON.
///
/// The app never assumes which: a portal that serves a rendered page and one
/// that serves an API response are both read through the same interface.
class PortalDocument {
  final Document? _html;
  final Object? _json;

  PortalDocument._(this._html, this._json);

  factory PortalDocument.parse(String body) {
    final trimmed = body.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return PortalDocument._(null, jsonDecode(body));
      } catch (_) {
        // Not valid JSON after all — fall through and treat it as markup.
      }
    }
    return PortalDocument._(html_parser.parse(body), null);
  }

  bool get isJson => _json != null;

  /// All visible text, used for "nothing posted here" detection.
  String get text {
    if (_json != null) return _flattenJson(_json).join(' ');
    return normalizeText(_html?.body?.text ?? '');
  }

  /// Every plausible group of records on the page, best-effort. Callers pick
  /// among them with [selectRecordSet].
  List<RecordSet> extractRecordSets(FieldMatcher matcher) {
    if (_json != null) return _jsonRecordSets(_json, matcher);
    final doc = _html;
    if (doc == null) return const [];
    return [
      ..._tableRecordSets(doc, matcher),
      ..._repeatedBlockRecordSets(doc, matcher),
    ];
  }

  /// Label→value pairs for single-subject pages such as a profile header,
  /// gathered from definition lists, two-column tables, data attributes,
  /// descriptive class names and `"Label: value"` text.
  Map<SemanticField, String> extractLabeledValues(FieldMatcher matcher) {
    final out = <SemanticField, String>{};

    void offer(String label, String value) {
      final v = normalizeText(value);
      if (v.isEmpty || v.length > 120) return;
      if (looksLikeChrome(v)) return;
      final field = matcher.match(label);
      if (field == null) return;
      // First hit wins: pages put the summary before the fine print.
      out.putIfAbsent(field, () => v);
    }

    if (_json != null) {
      _flattenJsonPairs(_json, '', out, matcher, 0);
      return out;
    }

    final doc = _html;
    if (doc == null) return out;

    for (final dl in doc.querySelectorAll('dl')) {
      final terms = dl.querySelectorAll('dt');
      final defs = dl.querySelectorAll('dd');
      for (var i = 0; i < terms.length && i < defs.length; i++) {
        offer(terms[i].text, defs[i].text);
      }
    }

    for (final row in doc.querySelectorAll('tr')) {
      final cells = row.children
          .where((c) => c.localName == 'td' || c.localName == 'th')
          .toList();
      if (cells.length == 2) offer(cells[0].text, cells[1].text);
    }

    for (final el in doc.querySelectorAll('*')) {
      if (el.children.isNotEmpty) continue; // leaf nodes carry the values
      final value = el.text;
      if (normalizeText(value).isEmpty) continue;
      for (final label in _labelHints(el)) {
        offer(label, value);
      }
    }

    // "Overall GPA: 3.92" written as flowing text rather than marked up.
    //
    // Scanned per element and anchored to that element's whole text. Running
    // this over the document instead would let a value run on into whatever
    // the page renders next, turning "School:" into the school name followed
    // by the navigation menu.
    for (final el in doc.querySelectorAll(
      'p, span, div, li, td, th, dd, label, strong, b, h1, h2, h3, h4, h5, h6',
    )) {
      final line = normalizeText(el.text);
      if (line.isEmpty || line.length > _maxLabelledLine) continue;
      final m = _labelledValue.firstMatch(line);
      if (m != null) offer(m.group(1)!, m.group(2)!);
    }

    return out;
  }

  /// Longest element text still treated as a single "Label: value" line.
  /// Anything longer is a paragraph or a run of page chrome, not a field.
  static const int _maxLabelledLine = 80;

  static final RegExp _labelledValue =
      RegExp(r'^([A-Za-z][A-Za-z /]{2,30}?)\s*[:∶]\s*(.{1,60})$');

  /// Navigation, controls and status text that share a page with real data.
  /// A student's name is never "Log Out", and a school is never "Error".
  static final RegExp _chrome = RegExp(
    r'\b(log ?out|sign ?out|log ?in|sign ?in|manage account|my account|'
    r'account settings|home|menu|navigation|settings|preferences|help|support|'
    r'contact us|privacy|terms|copyright|search|skip to|back to|view all|'
    r'see all|show more|loading|error|unavailable|session|timeout)\b',
    caseSensitive: false,
  );

  static bool looksLikeChrome(String value) => _chrome.hasMatch(value);

  /// Text of every heading on the page, outermost first.
  List<String> headings() {
    final doc = _html;
    if (doc == null) return const [];
    return [
      for (final h in doc.querySelectorAll('h1, h2, h3, h4, [role=heading]'))
        normalizeText(h.text),
    ]..removeWhere((t) => t.isEmpty || t.length > 80);
  }

  /// A profile picture, matched on the words portals use around one rather
  /// than on any particular class name.
  String findImageUrl(List<String> hints) {
    final doc = _html;
    if (doc == null) return '';
    for (final img in doc.querySelectorAll('img[src]')) {
      final src = img.attributes['src'] ?? '';
      if (src.isEmpty) continue;
      final haystack = normalizeLabel([
        src,
        img.attributes['alt'] ?? '',
        img.attributes['id'] ?? '',
        img.className,
      ].join(' '));
      if (hints.any(haystack.contains)) return src;
    }
    return '';
  }

  /// The rotating-day label schools print above a schedule — "A Day",
  /// "Day 3", "Cycle 2", "Blue Day". Null when the page names no such thing.
  String? dayLabel() {
    final pattern = RegExp(
      r'\b((?:[A-Z]|Day\s?\d{1,2}|Cycle\s?\d{1,2}|[A-Z][a-z]{2,8})\s?Day|Day\s?\d{1,2}|Cycle\s?\d{1,2})\b',
    );
    for (final candidate in [...headings(), text]) {
      final m = pattern.firstMatch(candidate);
      if (m != null) return normalizeText(m.group(1)!);
    }
    return null;
  }

  // ── HTML: tables ────────────────────────────────────────────────────

  List<RecordSet> _tableRecordSets(Document doc, FieldMatcher matcher) {
    final sets = <RecordSet>[];
    final tables = doc.querySelectorAll('table');

    for (var t = 0; t < tables.length; t++) {
      final rows = tables[t].querySelectorAll('tr');
      if (rows.length < 2) continue;

      final grid = <List<Element>>[];
      final rowElements = <Element>[];
      for (final row in rows) {
        final cells = row.children
            .where((c) => c.localName == 'td' || c.localName == 'th')
            .toList();
        if (cells.isNotEmpty) {
          grid.add(cells);
          rowElements.add(row);
        }
      }
      if (grid.isEmpty) continue;

      final headerIndex = _headerRowIndex(grid);
      final columns = headerIndex == null
          ? _inferColumnsByShape(grid, 0, matcher)
          : _mapHeaderRow(grid[headerIndex], matcher);

      final bodyStart = (headerIndex ?? -1) + 1;
      final records = <PortalRecord>[];
      for (var r = bodyStart; r < grid.length; r++) {
        final record = _rowToRecord(rowElements[r], grid[r], columns, matcher);
        if (record != null) records.add(record);
      }

      // A header that told us nothing is worth a second pass on shapes alone.
      if (records.isNotEmpty &&
          columns.values.whereType<SemanticField>().isEmpty) {
        final inferred = _inferColumnsByShape(grid, bodyStart, matcher);
        if (inferred.isNotEmpty) {
          final rebuilt = <PortalRecord>[];
          for (var r = bodyStart; r < grid.length; r++) {
            final rebuiltRow =
                _rowToRecord(rowElements[r], grid[r], inferred, matcher);
            if (rebuiltRow != null) rebuilt.add(rebuiltRow);
          }
          if (rebuilt.isNotEmpty) {
            records
              ..clear()
              ..addAll(rebuilt);
          }
        }
      }

      if (records.isNotEmpty) sets.add(RecordSet(records, 'table#$t'));
    }
    return sets;
  }

  /// The row that looks like a header: all `<th>`, or a first row whose cells
  /// are short text while later rows carry numbers, grades or dates.
  int? _headerRowIndex(List<List<Element>> grid) {
    for (var r = 0; r < grid.length && r < 3; r++) {
      final row = grid[r];
      if (row.every((c) => c.localName == 'th') && row.length > 1) return r;
    }

    final first = grid.first;
    if (first.length < 2) return null;
    final headerish = first.every((c) {
      final v = normalizeText(c.text);
      return v.isNotEmpty && v.length <= 30 && classifyValue(v) == ValueShape.text;
    });
    if (!headerish) return null;

    // Only a header if the rows beneath it actually differ in shape.
    final below = grid.skip(1).take(3);
    final varied = below.any((row) => row.any((c) {
          final shape = classifyValue(c.text);
          return shape != ValueShape.text && shape != ValueShape.empty;
        }));
    return varied ? 0 : null;
  }

  Map<int, SemanticField?> _mapHeaderRow(
    List<Element> header,
    FieldMatcher matcher,
  ) {
    final columns = <int, SemanticField?>{};
    final taken = <SemanticField>{};
    for (var i = 0; i < header.length; i++) {
      final labels = [header[i].text, ..._labelHints(header[i])];
      SemanticField? field;
      for (final label in labels) {
        field = matcher.match(label);
        if (field != null) break;
      }
      // Two columns claiming the same field: the first one keeps it.
      columns[i] = (field != null && taken.add(field)) ? field : null;
    }
    return columns;
  }

  /// Assigns fields to columns using the shape of their values, for tables
  /// with no header at all. Distinctive shapes claim their column first so a
  /// grade column is never swallowed by a generic text field.
  Map<int, SemanticField?> _inferColumnsByShape(
    List<List<Element>> grid,
    int startRow,
    FieldMatcher matcher,
  ) {
    final width = grid.skip(startRow).fold<int>(0, (w, r) => r.length > w ? r.length : w);
    if (width == 0) return const {};

    final modal = <int, ValueShape>{};
    final avgLength = <int, double>{};
    for (var c = 0; c < width; c++) {
      final counts = <ValueShape, int>{};
      var totalLength = 0;
      var seen = 0;
      for (var r = startRow; r < grid.length; r++) {
        if (c >= grid[r].length) continue;
        final v = normalizeText(grid[r][c].text);
        final shape = classifyValue(v);
        if (shape == ValueShape.empty) continue;
        counts[shape] = (counts[shape] ?? 0) + 1;
        totalLength += v.length;
        seen++;
      }
      if (seen == 0) continue;
      avgLength[c] = totalLength / seen;
      modal[c] = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

      // Names beat the mode: a course-title column never contains an
      // honorific, so even a minority of them identifies a teacher column
      // whose other rows are bare surnames.
      final names = counts[ValueShape.personName] ?? 0;
      if (names > 0 && names * 5 >= seen * 2) {
        modal[c] = ValueShape.personName;
      }
    }

    const priority = [
      SemanticField.timeRange,
      SemanticField.dueDate,
      SemanticField.letterGrade,
      SemanticField.credits,
      SemanticField.score,
      SemanticField.teacher,
      SemanticField.period,
      SemanticField.pointsEarned,
      SemanticField.pointsPossible,
    ];

    final columns = <int, SemanticField?>{};
    final usedColumns = <int>{};

    for (final field in priority) {
      if (!matcher.candidates.contains(field)) continue;
      final allowed = fieldShapes[field];
      if (allowed == null) continue;
      for (var c = 0; c < width; c++) {
        if (usedColumns.contains(c)) continue;
        if (!allowed.contains(modal[c])) continue;
        columns[c] = field;
        usedColumns.add(c);
        break;
      }
    }

    // The wordiest remaining column is the thing the row is about.
    final textColumns = [
      for (var c = 0; c < width; c++)
        if (!usedColumns.contains(c) && modal[c] == ValueShape.text) c,
    ]..sort((a, b) => (avgLength[b] ?? 0).compareTo(avgLength[a] ?? 0));

    const titleOrder = [
      SemanticField.courseTitle,
      SemanticField.assignmentTitle,
      SemanticField.category,
    ];
    for (final field in titleOrder) {
      if (textColumns.isEmpty) break;
      if (!matcher.candidates.contains(field)) continue;
      columns[textColumns.removeAt(0)] = field;
      break;
    }

    return columns;
  }

  PortalRecord? _rowToRecord(
    Element row,
    List<Element> cells,
    Map<int, SemanticField?> columns,
    FieldMatcher matcher,
  ) {
    if (cells.isEmpty) return null;

    final values = [for (final c in cells) normalizeText(c.text)];
    if (values.every((v) => v.isEmpty)) return null;

    final fields = <SemanticField, String>{};
    for (var i = 0; i < cells.length; i++) {
      // A cell can label itself even when the column header did not.
      final field = columns[i] ??
          _firstMatch(_labelHints(cells[i]), matcher) ??
          _firstMatch(_labelHints(cells[i], deep: true), matcher);
      if (field == null || values[i].isEmpty) continue;
      fields.putIfAbsent(field, () => values[i]);
    }

    if (fields.isEmpty && values.where((v) => v.isNotEmpty).length < 2) {
      return null;
    }
    final identity = _identity(row);
    return PortalRecord(
      fields: fields,
      cells: values,
      text: values.where((v) => v.isNotEmpty).join(' · '),
      id: identity.id,
      link: identity.link,
    );
  }

  // ── HTML: repeated blocks (card and list layouts) ────────────────────

  /// How many repeated-block groups to consider before giving up. Deeply
  /// nested layouts can nominate a great many candidates, and the useful ones
  /// always appear early.
  static const int _maxBlockSets = 24;

  List<RecordSet> _repeatedBlockRecordSets(Document doc, FieldMatcher matcher) {
    final sets = <RecordSet>[];
    var index = 0;

    final body = doc.body;
    final parents = <Element>[
      if (body != null) body,
      if (body != null) ...doc.querySelectorAll('body *'),
    ];

    for (final parent in parents) {
      if (sets.length >= _maxBlockSets) break;

      final children = parent.children
          .where((c) => normalizeText(c.text).isNotEmpty)
          .toList();
      if (children.isEmpty || children.length > 300) continue;

      // Siblings sharing a tag and class signature are the same kind of thing.
      // Grouping rather than requiring uniformity matters: real pages put a
      // heading and a footer beside the list of cards.
      final groups = <String, List<Element>>{};
      for (final child in children) {
        groups.putIfAbsent(_classSignature(child), () => []).add(child);
      }

      for (final group in groups.values) {
        if (sets.length >= _maxBlockSets) break;
        if (group.first.children.isEmpty) continue; // a plain text list

        final records = <PortalRecord>[];
        for (final block in group) {
          final record = _blockToRecord(block, matcher);
          if (record != null) records.add(record);
        }
        if (records.isEmpty) continue;

        final labelled = records.where((r) => r.fields.isNotEmpty).length;
        // Either several siblings that each resolved something, or one block
        // that resolved a lot — a card layout holding a single entry is still
        // data, but a lone block needs more evidence to be believed.
        final worthwhile = (group.length >= 2 && labelled >= 2) ||
            (group.length == 1 && records.first.fields.length >= 3);
        if (worthwhile) sets.add(RecordSet(records, 'blocks#${index++}'));
      }
    }
    return sets;
  }

  PortalRecord? _blockToRecord(Element block, FieldMatcher matcher) {
    final fields = <SemanticField, String>{};
    final values = <String>[];

    for (final el in [block, ...block.querySelectorAll('*')]) {
      if (el != block && el.children.isEmpty) {
        final v = normalizeText(el.text);
        if (v.isNotEmpty) values.add(v);
      }
      final value = el.children.isEmpty ? normalizeText(el.text) : '';
      if (value.isEmpty) continue;
      for (final label in _labelHints(el)) {
        final field = matcher.match(label);
        if (field == null) continue;
        fields.putIfAbsent(field, () => value);
        break;
      }
    }

    // "Teacher: Ms. Okafor" written as flowing text inside the card.
    for (final m in RegExp(
      r'([A-Za-z][A-Za-z /]{2,30}?)\s*:\s*([^\n;|]{1,60})',
    ).allMatches(normalizeText(block.text))) {
      final field = matcher.match(m.group(1)!);
      if (field != null) {
        fields.putIfAbsent(field, () => normalizeText(m.group(2)!));
      }
    }

    // Cards usually give the name a heading rather than a label, so a heading
    // may supply the field that says what this record is about.
    //
    // Deliberately a heading and nothing else: guessing at "the first text in
    // the block" invents a name for any block at all, which is enough to make
    // a weighting table look like a list of assignments.
    final primary = matcher.primary;
    if (primary != null && !fields.containsKey(primary)) {
      final heading =
          block.querySelector('h1, h2, h3, h4, h5, h6, [role=heading]');
      final candidate = heading == null ? '' : normalizeText(heading.text);
      if (candidate.isNotEmpty) fields[primary] = candidate;
    }

    if (fields.isEmpty && values.length < 2) return null;
    final identity = _identity(block);
    return PortalRecord(
      fields: fields,
      cells: values,
      text: normalizeText(block.text),
      id: identity.id,
      link: identity.link,
    );
  }

  // ── JSON ────────────────────────────────────────────────────────────

  List<RecordSet> _jsonRecordSets(Object? node, FieldMatcher matcher) {
    final sets = <RecordSet>[];

    void walk(Object? value, String path) {
      if (value is List) {
        final maps = value.whereType<Map>().toList();
        if (maps.isNotEmpty) {
          final records = [
            for (final m in maps) _jsonRecord(m, matcher),
          ].whereType<PortalRecord>().toList();
          if (records.isNotEmpty) {
            sets.add(RecordSet(records, 'json:${path.isEmpty ? 'root' : path}'));
          }
        }
        for (var i = 0; i < value.length; i++) {
          walk(value[i], path);
        }
      } else if (value is Map) {
        for (final entry in value.entries) {
          walk(entry.value, path.isEmpty ? '${entry.key}' : '$path.${entry.key}');
        }
      }
    }

    walk(node, '');
    return sets;
  }

  PortalRecord? _jsonRecord(Map<dynamic, dynamic> map, FieldMatcher matcher) {
    final fields = <SemanticField, String>{};
    final values = <String>[];

    void consume(Map<dynamic, dynamic> m, String prefix, int depth) {
      for (final entry in m.entries) {
        final key = '${entry.key}';
        final path = prefix.isEmpty ? key : '$prefix $key';
        final value = entry.value;

        if (value is Map && depth < 2) {
          consume(value, path, depth + 1);
          continue;
        }
        if (value == null || value is List) continue;

        final text = value is num
            ? _trimNumber(value)
            : normalizeText('$value');
        if (text.isEmpty) continue;
        values.add(text);

        // Try the leaf key first, then the full path — "grade" is clearer
        // than "marks grade", but the path disambiguates when the leaf alone
        // means nothing.
        final field = matcher.match(key) ?? matcher.match(path);
        if (field != null) fields.putIfAbsent(field, () => text);
      }
    }

    consume(map, '', 0);
    if (fields.isEmpty) return null;

    String? pick(Set<String> keys) {
      for (final entry in map.entries) {
        final key = normalizeLabel('${entry.key}');
        final value = entry.value;
        if (keys.contains(key) && value != null && value is! Map && value is! List) {
          final text = value is num ? _trimNumber(value) : normalizeText('$value');
          if (text.isNotEmpty) return text;
        }
      }
      return null;
    }

    return PortalRecord(
      fields: fields,
      cells: values,
      text: values.join(' · '),
      id: pick(const {'id', 'course id', 'section id', 'key', 'guid', 'uid'}),
      link: pick(const {'link', 'url', 'href', 'detail url', 'self'}),
    );
  }

  void _flattenJsonPairs(
    Object? node,
    String prefix,
    Map<SemanticField, String> out,
    FieldMatcher matcher,
    int depth,
  ) {
    if (depth > 3) return;
    if (node is Map) {
      for (final entry in node.entries) {
        final key = '${entry.key}';
        final value = entry.value;
        if (value is Map || value is List) {
          _flattenJsonPairs(value, key, out, matcher, depth + 1);
          continue;
        }
        if (value == null) continue;
        final text = value is num ? _trimNumber(value) : normalizeText('$value');
        if (text.isEmpty) continue;
        final field = matcher.match(key) ??
            matcher.match(prefix.isEmpty ? key : '$prefix $key');
        if (field != null) out.putIfAbsent(field, () => text);
      }
    } else if (node is List) {
      for (final item in node) {
        _flattenJsonPairs(item, prefix, out, matcher, depth + 1);
      }
    }
  }

  static List<String> _flattenJson(Object? node) {
    final out = <String>[];
    void walk(Object? v) {
      if (v is Map) {
        v.forEach((k, value) {
          out.add('$k');
          walk(value);
        });
      } else if (v is List) {
        for (final item in v) {
          walk(item);
        }
      } else if (v != null) {
        out.add('$v');
      }
    }

    walk(node);
    return out;
  }

  static String _trimNumber(num n) =>
      n is int || n == n.roundToDouble() ? '${n.toInt()}' : '$n';

  // ── shared helpers ──────────────────────────────────────────────────

  /// Every string on an element that might name what it holds.
  ///
  /// Class names are used as *hints*, not as a contract: a portal that calls
  /// its column `.gradebook-course-title` still resolves, because the tokens
  /// normalise to `"gradebook course title"` and match on the word "title" —
  /// and a portal with meaningless class names simply falls through to the
  /// other strategies.
  static List<String> _labelHints(Element el, {bool deep = false}) {
    final hints = <String>[];
    for (final entry in el.attributes.entries) {
      final name = '${entry.key}'.toLowerCase();
      if (name == 'class') {
        hints.add(entry.value.replaceAll('-', ' ').replaceAll('_', ' '));
      } else if (name == 'aria-label' || name == 'title' || name == 'headers') {
        hints.add(entry.value);
      } else if (name.startsWith('data-')) {
        hints.add(name.substring(5).replaceAll('-', ' '));
        if (entry.value.isNotEmpty && entry.value.length <= 30) {
          hints.add(entry.value);
        }
      }
    }
    if (deep) {
      for (final child in el.querySelectorAll('*')) {
        hints.addAll(_labelHints(child));
      }
    }
    return hints;
  }

  /// An element's own identity: an explicit id attribute, an id-ish data
  /// attribute, or the row's link. Portals lay out detail URLs differently, so
  /// the link is kept whole and followed as-is rather than reassembled.
  static ({String? id, String? link}) _identity(Element el) {
    String? link = el.attributes['href'];
    link ??= el.querySelector('a[href]')?.attributes['href'];

    String? id = el.attributes['id'];
    if (id != null && id.length > 40) id = null;

    if (id == null) {
      for (final entry in el.attributes.entries) {
        final name = '${entry.key}'.toLowerCase();
        if (!name.startsWith('data-')) continue;
        final label = normalizeLabel(name.substring(5));
        if (label == 'id' ||
            label.endsWith(' id') ||
            label == 'course' ||
            label == 'key') {
          final value = normalizeText(entry.value);
          if (value.isNotEmpty && value.length <= 40) {
            id = value;
            break;
          }
        }
      }
    }

    // Fall back to the last meaningful segment of the link.
    if (id == null && link != null) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) id = segments.last;
        for (final value in uri.queryParameters.entries) {
          if (normalizeLabel(value.key).endsWith('id')) {
            id = value.value;
            break;
          }
        }
      }
    }

    return (id: id, link: link);
  }

  static SemanticField? _firstMatch(List<String> labels, FieldMatcher matcher) {
    for (final label in labels) {
      final field = matcher.match(label);
      if (field != null) return field;
    }
    return null;
  }

  /// Tag plus sorted class tokens — two siblings with the same signature are
  /// almost certainly the same kind of item.
  static String _classSignature(Element el) {
    final classes = el.classes.toList()..sort();
    return '${el.localName}.${classes.join('.')}';
  }
}

/// Chooses the record set that best fits a schema.
///
/// A candidate must supply every field in [mustHave] on most of its rows, and
/// resolve at least [minFields] fields per row — together that is what keeps
/// navigation menus and layout tables from being mistaken for data, since a
/// menu of links resolves one vaguely title-shaped column and nothing else.
/// Among the qualifying sets, the one covering the most of [prefer] across the
/// most rows wins.
RecordSet? selectRecordSet(
  List<RecordSet> sets, {
  required Set<SemanticField> mustHave,
  required Set<SemanticField> prefer,
  int minFields = 2,
}) {
  RecordSet? best;
  var bestScore = 0;

  for (final set in sets) {
    if (set.isEmpty) continue;

    final qualifying = set.records
        .where((r) => r.fields.length >= minFields && mustHave.every(r.has))
        .toList();
    if (qualifying.isEmpty) continue;
    if (qualifying.length < (set.records.length / 2).ceil()) continue;

    var score = 0;
    for (final record in qualifying) {
      score += record.coverage(prefer) * 2 + record.coverage(mustHave) * 3;
    }
    if (score > bestScore) {
      bestScore = score;
      best = RecordSet(qualifying, set.origin);
    }
  }
  return best;
}
