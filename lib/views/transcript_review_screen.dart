import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/ui_kit.dart';
import '../models/normalized_transcript.dart';
import '../storage/state_providers.dart';
import 'transcript_library_screen.dart';

class TranscriptReviewScreen extends ConsumerStatefulWidget {
  const TranscriptReviewScreen({super.key});

  @override
  ConsumerState<TranscriptReviewScreen> createState() =>
      _TranscriptReviewScreenState();
}

class _TranscriptReviewScreenState
    extends ConsumerState<TranscriptReviewScreen> {
  late Map<String, dynamic> _data;

  @override
  void initState() {
    super.initState();
    final draft = ref.read(transcriptImportProvider).draft;
    _data = draft == null
        ? <String, dynamic>{}
        : jsonDecode(jsonEncode(draft.transcript.toJson()))
            as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transcriptImportProvider);
    final p = context.palette;
    final confidence = Map<String, double>.from(
      (_data['confidence'] as Map?) ?? const <String, double>{},
    );
    if (state.draft == null || _data.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.description_outlined,
            title: 'No transcript to review',
            message: 'Choose a PDF first.',
          ),
        ),
      );
    }

    final student = _map(_data, 'student');
    final institution = _map(_data, 'institution');
    final program = _map(_data, 'program');
    final cumulative = _map(_data, 'cumulative');
    final terms = _list(_data, 'terms');
    final legend = _list(_data, 'gradingScale');
    final transfers = _list(_data, 'transfers');
    final degrees = _list(_data, 'degrees');

    return Scaffold(
      appBar: AppBar(title: const Text('Review transcript')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 110),
          children: [
            SurfaceCard(
              fill: p.warning.withValues(alpha: .08),
              borderColor: p.warning.withValues(alpha: .45),
              child: Text(
                'Nothing is saved until you confirm. Amber fields have low '
                'parser confidence. Blank fields remain null.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: p.textSecondary, height: 1.5),
              ),
            ),
            const SizedBox(height: 22),
            _ReviewSection(
              title: 'Student',
              child: _EditableFields(
                target: student,
                confidence: confidence,
                onChanged: _changed,
                fields: const [
                  _Field('Name', 'name', 'student.name'),
                  _Field('Student ID', 'studentId', 'student.studentId'),
                  _Field('Date of birth', 'dateOfBirth', 'student.dateOfBirth'),
                  _Field('Address', 'address', 'student.address'),
                  _Field('Grade level', 'gradeLevel', 'student.gradeLevel'),
                ],
              ),
            ),
            _ReviewSection(
              title: 'Institution and document',
              child: Column(
                children: [
                  _EditableFields(
                    target: institution,
                    confidence: confidence,
                    onChanged: _changed,
                    fields: const [
                      _Field('Institution name', 'name', 'institution.name'),
                      _Field('Institution ID', 'institutionId', 'institution.institutionId'),
                      _Field('Address', 'address', 'institution.address'),
                    ],
                  ),
                  _EditableFields(
                    target: _data,
                    confidence: confidence,
                    onChanged: _changed,
                    fields: const [
                      _Field('Transcript issue date', 'issueDate', 'issueDate'),
                    ],
                  ),
                  _ChoiceField(
                    label: 'Official status',
                    value: '${_data['officialStatus'] ?? 'unknown'}',
                    options: OfficialStatus.values.map((e) => e.name).toList(),
                    onChanged: (value) => setState(() => _data['officialStatus'] = value),
                  ),
                  _ChoiceField(
                    label: 'Credit system',
                    value: '${_data['creditSystem'] ?? 'unknown'}',
                    options: CreditSystem.values.map((e) => e.name).toList(),
                    onChanged: (value) => setState(() => _data['creditSystem'] = value),
                  ),
                  _ChoiceField(
                    label: 'Repeat policy',
                    value: '${_data['repeatPolicy'] ?? 'unknown'}',
                    options: RepeatPolicy.values.map((e) => e.name).toList(),
                    onChanged: (value) => setState(() => _data['repeatPolicy'] = value),
                  ),
                ],
              ),
            ),
            _ReviewSection(
              title: 'Program',
              child: _EditableFields(
                target: program,
                confidence: confidence,
                onChanged: _changed,
                fields: const [
                  _Field('Program', 'program', 'program.program'),
                  _Field('Degree sought', 'degreeSought', 'program.degreeSought'),
                  _Field('Majors (comma separated)', 'majors', 'program.majors', list: true),
                  _Field('Minors (comma separated)', 'minors', 'program.minors', list: true),
                  _Field('Concentrations', 'concentrations', 'program.concentrations', list: true),
                  _Field('Catalog year', 'catalogYear', 'program.catalogYear'),
                  _Field('Credits required', 'creditsRequired', 'program.creditsRequired', number: true),
                ],
              ),
            ),
            _ReviewSection(
              title: 'Cumulative totals',
              child: _EditableFields(
                target: cumulative,
                confidence: confidence,
                onChanged: _changed,
                fields: const [
                  _Field('Credits attempted', 'creditsAttempted', 'cumulative.creditsAttempted', number: true),
                  _Field('Credits earned', 'creditsEarned', 'cumulative.creditsEarned', number: true),
                  _Field('GPA hours', 'gpaCredits', 'cumulative.gpaCredits', number: true),
                  _Field('Quality points', 'qualityPoints', 'cumulative.qualityPoints', number: true),
                  _Field('Cumulative GPA', 'cumulativeGpa', 'cumulative.cumulativeGpa', number: true),
                  _Field('Cumulative average (%)', 'cumulativeAveragePercent', 'cumulative.cumulativeAveragePercent', number: true),
                  _Field('Major GPA', 'majorGpa', 'cumulative.majorGpa', number: true),
                  _Field('Institutional GPA', 'institutionalGpa', 'cumulative.institutionalGpa', number: true),
                  _Field('Overall GPA', 'overallGpa', 'cumulative.overallGpa', number: true),
                  _Field('Transfer credits accepted', 'transferCreditsAccepted', 'cumulative.transferCreditsAccepted', number: true),
                ],
              ),
            ),
            _ReviewSection(
              title: 'Grading legend',
              action: TextButton.icon(
                onPressed: () => setState(() => legend.add(<String, dynamic>{
                      'label': '',
                      'minimumPercent': null,
                      'maximumPercent': null,
                      'gradePoints': null,
                      'printedText': null,
                    })),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
              child: legend.isEmpty
                  ? const _NoneParsed('No grading legend was parsed.')
                  : Column(
                      children: [
                        for (final (index, value) in legend.indexed)
                          _ListEditorCard(
                            title: 'Scale row ${index + 1}',
                            onDelete: () => setState(() => legend.removeAt(index)),
                            child: _EditableFields(
                              target: Map<String, dynamic>.from(value as Map),
                              assignTarget: (map) => legend[index] = map,
                              confidence: confidence,
                              onChanged: _changed,
                              fields: const [
                                _Field('Label', 'label', 'gradingScale'),
                                _Field('Minimum %', 'minimumPercent', 'gradingScale', number: true),
                                _Field('Maximum %', 'maximumPercent', 'gradingScale', number: true),
                                _Field('Grade points', 'gradePoints', 'gradingScale', number: true),
                                _Field('Printed legend text', 'printedText', 'gradingScale'),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            _ReviewSection(
              title: 'Terms and courses',
              action: TextButton.icon(
                onPressed: () => setState(() => terms.add(_blankTerm(terms.length))),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add term'),
              ),
              child: terms.isEmpty
                  ? const _NoneParsed('No terms were parsed.')
                  : Column(
                      children: [
                        for (final (termIndex, value) in terms.indexed)
                          _TermEditor(
                            value: Map<String, dynamic>.from(value as Map),
                            termIndex: termIndex,
                            confidence: confidence,
                            onChanged: (next) => setState(() => terms[termIndex] = next),
                            onDelete: () => setState(() => terms.removeAt(termIndex)),
                          ),
                      ],
                    ),
            ),
            _ReviewSection(
              title: 'Transfer credit blocks',
              action: TextButton.icon(
                onPressed: () => setState(() => transfers.add(<String, dynamic>{
                      'id': 'transfer-${transfers.length + 1}',
                      'sourceInstitution': null,
                      'creditsAttempted': null,
                      'creditsAccepted': null,
                      'courses': <dynamic>[],
                    })),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
              child: transfers.isEmpty
                  ? const _NoneParsed('No transfer blocks were parsed.')
                  : Column(
                      children: [
                        for (final (index, value) in transfers.indexed)
                          _TransferEditor(
                            value: Map<String, dynamic>.from(value as Map),
                            confidence: confidence,
                            onChanged: (next) => setState(() => transfers[index] = next),
                            onDelete: () => setState(() => transfers.removeAt(index)),
                          ),
                      ],
                    ),
            ),
            _ReviewSection(
              title: 'Degrees awarded',
              action: TextButton.icon(
                onPressed: () => setState(() => degrees.add(<String, dynamic>{
                      'id': 'degree-${degrees.length + 1}',
                      'degree': null,
                      'conferralDate': null,
                      'latinHonors': null,
                      'majors': <String>[],
                    })),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
              child: degrees.isEmpty
                  ? const _NoneParsed('No awarded degrees were parsed.')
                  : Column(
                      children: [
                        for (final (index, value) in degrees.indexed)
                          _ListEditorCard(
                            title: 'Degree ${index + 1}',
                            onDelete: () => setState(() => degrees.removeAt(index)),
                            child: _EditableFields(
                              target: Map<String, dynamic>.from(value as Map),
                              assignTarget: (map) => degrees[index] = map,
                              confidence: confidence,
                              onChanged: _changed,
                              fields: const [
                                _Field('Degree', 'degree', 'degrees.degree'),
                                _Field('Conferral date', 'conferralDate', 'degrees.conferralDate'),
                                _Field('Latin honors', 'latinHonors', 'degrees.latinHonors'),
                                _Field('Majors', 'majors', 'degrees.majors', list: true),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            _ReviewSection(
              title: 'Raw extracted text',
              child: SelectableText(
                '${_data['rawText'] ?? ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: FilledButton.icon(
            onPressed: state.busy ? null : _save,
            icon: state.busy
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(state.busy ? 'Saving…' : 'Confirm and save'),
          ),
        ),
      ),
    );
  }

  void _changed() => setState(() {});

  Future<void> _save() async {
    try {
      final edited = NormalizedTranscript.fromJson(_data);
      final saved = await ref.read(transcriptImportProvider.notifier).confirm(edited);
      if (!mounted || saved == null) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(
          builder: (_) => TranscriptDetailScreen(transcript: saved),
        ),
        (route) => route.isFirst,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Review data is invalid: $error')),
      );
    }
  }

  static Map<String, dynamic> _blankTerm(int index) => <String, dynamic>{
        'id': 'term-${index + 1}',
        'label': null,
        'year': null,
        'startDate': null,
        'endDate': null,
        'statedGpa': null,
        'statedAveragePercent': null,
        'creditsAttempted': null,
        'creditsEarned': null,
        'gpaCredits': null,
        'qualityPoints': null,
        'academicStanding': null,
        'deansList': null,
        'honorsFlag': null,
        'probation': null,
        'honors': <String>[],
        'courses': <dynamic>[],
      };
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionLabel(title, trailing: action),
            const SizedBox(height: 8),
            SurfaceCard(child: child),
          ],
        ),
      );
}

class _Field {
  const _Field(this.label, this.key, this.path, {this.number = false, this.list = false});

  final String label;
  final String key;
  final String path;
  final bool number;
  final bool list;
}

class _EditableFields extends StatelessWidget {
  const _EditableFields({
    required this.target,
    required this.confidence,
    required this.onChanged,
    required this.fields,
    this.assignTarget,
  });

  final Map<String, dynamic> target;
  final void Function(Map<String, dynamic>)? assignTarget;
  final Map<String, double> confidence;
  final VoidCallback onChanged;
  final List<_Field> fields;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      children: [
        for (final field in fields) ...[
          Builder(builder: (context) {
            final score = _scoreFor(confidence, field.path);
            final low = score != null && score < .75;
            final raw = target[field.key];
            final initial = field.list && raw is List
                ? raw.join(', ')
                : raw?.toString() ?? '';
            return TextFormField(
              initialValue: initial,
              keyboardType: field.number
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: field.label,
                suffixIcon: low
                    ? Tooltip(
                        message: 'Low parser confidence: ${(score * 100).round()}%',
                        child: Icon(Icons.warning_amber_rounded, color: p.warning),
                      )
                    : null,
                enabledBorder: low
                    ? OutlineInputBorder(
                        borderSide: BorderSide(color: p.warning),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
              ),
              onChanged: (value) {
                target[field.key] = field.number
                    ? double.tryParse(value)
                    : field.list
                        ? value
                            .split(',')
                            .map((e) => e.trim())
                            .where((e) => e.isNotEmpty)
                            .toList()
                        : value.trim().isEmpty
                            ? null
                            : value.trim();
                assignTarget?.call(target);
                onChanged();
              },
            );
          }),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ChoiceField extends StatelessWidget {
  const _ChoiceField({required this.label, required this.value, required this.options, required this.onChanged});

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: DropdownButtonFormField<String>(
          value: options.contains(value) ? value : options.first,
          decoration: InputDecoration(labelText: label),
          items: [for (final option in options) DropdownMenuItem(value: option, child: Text(option))],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      );
}

class _TermEditor extends StatefulWidget {
  const _TermEditor({required this.value, required this.termIndex, required this.confidence, required this.onChanged, required this.onDelete});

  final Map<String, dynamic> value;
  final int termIndex;
  final Map<String, double> confidence;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<_TermEditor> createState() => _TermEditorState();
}

class _TermEditorState extends State<_TermEditor> {
  late Map<String, dynamic> value;

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final courses = _list(value, 'courses');
    return _ListEditorCard(
      title: '${value['label'] ?? 'Term ${widget.termIndex + 1}'}',
      onDelete: widget.onDelete,
      child: Column(
        children: [
          _EditableFields(
            target: value,
            confidence: widget.confidence,
            onChanged: () => widget.onChanged(value),
            fields: [
              _Field('Term label', 'label', 'terms[${widget.termIndex}].label'),
              _Field('Year', 'year', 'terms[${widget.termIndex}].year', number: true),
              _Field('Start date', 'startDate', 'terms[${widget.termIndex}].startDate'),
              _Field('End date', 'endDate', 'terms[${widget.termIndex}].endDate'),
              _Field('Term GPA', 'statedGpa', 'terms[${widget.termIndex}].statedGpa', number: true),
              _Field('Term average (%)', 'statedAveragePercent', 'terms[${widget.termIndex}].statedAveragePercent', number: true),
              _Field('Credits attempted', 'creditsAttempted', 'terms[${widget.termIndex}].creditsAttempted', number: true),
              _Field('Credits earned', 'creditsEarned', 'terms[${widget.termIndex}].creditsEarned', number: true),
              _Field('GPA credits', 'gpaCredits', 'terms[${widget.termIndex}].gpaCredits', number: true),
              _Field('Quality points', 'qualityPoints', 'terms[${widget.termIndex}].qualityPoints', number: true),
              _Field('Academic standing', 'academicStanding', 'terms[${widget.termIndex}].academicStanding'),
              _Field('Honors / Dean’s List', 'honors', 'terms[${widget.termIndex}].honors', list: true),
            ],
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            tristate: true,
            title: const Text("Dean's List"),
            value: value['deansList'] as bool?,
            onChanged: (next) {
              setState(() => value['deansList'] = next);
              widget.onChanged(value);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            tristate: true,
            title: const Text('Academic honors'),
            value: value['honorsFlag'] as bool?,
            onChanged: (next) {
              setState(() => value['honorsFlag'] = next);
              widget.onChanged(value);
            },
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            tristate: true,
            title: const Text('Academic probation'),
            value: value['probation'] as bool?,
            onChanged: (next) {
              setState(() => value['probation'] = next);
              widget.onChanged(value);
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () {
                setState(() => courses.add(_blankCourse(courses.length)));
                widget.onChanged(value);
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add course'),
            ),
          ),
          for (final (index, raw) in courses.indexed)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${(raw as Map)['title'] ?? 'Untitled course'}'),
              subtitle: Text('${raw['subjectCode'] ?? ''} ${raw['courseNumber'] ?? ''} · ${raw['letterGrade'] ?? raw['numericGrade'] ?? 'no grade'}'),
              trailing: const Icon(Icons.edit_rounded),
              onTap: () async {
                final next = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (_) => _CourseDialog(
                    initial: Map<String, dynamic>.from(raw),
                    confidence: widget.confidence,
                    termIndex: widget.termIndex,
                  ),
                );
                if (next == null) return;
                setState(() => courses[index] = next);
                widget.onChanged(value);
              },
              onLongPress: () {
                setState(() => courses.removeAt(index));
                widget.onChanged(value);
              },
            ),
        ],
      ),
    );
  }

  static Map<String, dynamic> _blankCourse(int index) => <String, dynamic>{
        'id': 'course-${index + 1}',
        'subjectCode': null,
        'courseNumber': null,
        'title': null,
        'section': null,
        'creditsAttempted': null,
        'creditsEarned': null,
        'letterGrade': null,
        'numericGrade': null,
        'gradePoints': null,
        'qualityPoints': null,
        'countsTowardGpa': null,
        'flags': CourseFlags().toJson(),
        'sourceInstitution': null,
        'rawLine': null,
      };
}

class _TransferEditor extends StatefulWidget {
  const _TransferEditor({required this.value, required this.confidence, required this.onChanged, required this.onDelete});
  final Map<String, dynamic> value;
  final Map<String, double> confidence;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final VoidCallback onDelete;

  @override
  State<_TransferEditor> createState() => _TransferEditorState();
}

class _TransferEditorState extends State<_TransferEditor> {
  late Map<String, dynamic> value;

  @override
  void initState() {
    super.initState();
    value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final courses = _list(value, 'courses');
    return _ListEditorCard(
        title: '${value['sourceInstitution'] ?? 'Transfer block'}',
        onDelete: widget.onDelete,
        child: Column(
          children: [
            _EditableFields(
              target: value,
              confidence: widget.confidence,
              onChanged: () => widget.onChanged(value),
              fields: const [
                _Field('Source institution', 'sourceInstitution', 'transfers.sourceInstitution'),
                _Field('Credits attempted', 'creditsAttempted', 'transfers.creditsAttempted', number: true),
                _Field('Credits accepted', 'creditsAccepted', 'transfers.creditsAccepted', number: true),
              ],
            ),
            for (final (index, raw) in courses.indexed)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${(raw as Map)['title'] ?? 'Transfer course'}'),
                subtitle: Text('${raw['subjectCode'] ?? ''} ${raw['courseNumber'] ?? ''}'),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () async {
                  final next = await showDialog<Map<String, dynamic>>(
                    context: context,
                    builder: (_) => _CourseDialog(
                      initial: Map<String, dynamic>.from(raw),
                      confidence: widget.confidence,
                      termIndex: -1,
                    ),
                  );
                  if (next == null) return;
                  setState(() => courses[index] = next);
                  widget.onChanged(value);
                },
              ),
          ],
        ),
      );
  }
}

class _CourseDialog extends StatefulWidget {
  const _CourseDialog({required this.initial, required this.confidence, required this.termIndex});
  final Map<String, dynamic> initial;
  final Map<String, double> confidence;
  final int termIndex;

  @override
  State<_CourseDialog> createState() => _CourseDialogState();
}

class _CourseDialogState extends State<_CourseDialog> {
  late Map<String, dynamic> course;
  late Map<String, dynamic> flags;

  @override
  void initState() {
    super.initState();
    course = Map<String, dynamic>.from(widget.initial);
    flags = Map<String, dynamic>.from((course['flags'] as Map?) ?? const {});
    course['flags'] = flags;
  }

  @override
  Widget build(BuildContext context) {
    final id = '${course['id'] ?? ''}';
    final path = 'terms[${widget.termIndex}].courses[$id]';
    const flagNames = <String, String>{
      'passFail': 'Pass/fail',
      'audit': 'Audit',
      'withdrawn': 'Withdrawn',
      'incomplete': 'Incomplete',
      'inProgress': 'In progress',
      'repeated': 'Repeated',
      'gradeReplaced': 'Grade replaced / forgiven',
      'transfer': 'Transfer',
      'ap': 'AP',
      'ib': 'IB',
      'clep': 'CLEP',
      'dualEnrollment': 'Dual enrollment',
      'honors': 'Honors section',
    };
    return AlertDialog(
      title: const Text('Edit course'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _EditableFields(
                target: course,
                confidence: widget.confidence,
                onChanged: () {},
                fields: [
                  _Field('Subject code', 'subjectCode', '$path.subjectCode'),
                  _Field('Course number', 'courseNumber', '$path.courseNumber'),
                  _Field('Full title', 'title', '$path.title'),
                  _Field('Section', 'section', '$path.section'),
                  _Field('Credits attempted', 'creditsAttempted', '$path.creditsAttempted', number: true),
                  _Field('Credits earned', 'creditsEarned', '$path.creditsEarned', number: true),
                  _Field('Letter grade', 'letterGrade', '$path.letterGrade'),
                  _Field('Numeric grade', 'numericGrade', '$path.numericGrade', number: true),
                  _Field('Grade points', 'gradePoints', '$path.gradePoints', number: true),
                  _Field('Quality points', 'qualityPoints', '$path.qualityPoints', number: true),
                  _Field('Source institution', 'sourceInstitution', '$path.sourceInstitution'),
                ],
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Counts toward GPA'),
                tristate: true,
                value: course['countsTowardGpa'] as bool?,
                onChanged: (value) => setState(() => course['countsTowardGpa'] = value),
              ),
              for (final entry in flagNames.entries)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: flags[entry.key] == true,
                  onChanged: (value) => setState(() => flags[entry.key] = value),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, course), child: const Text('Done')),
      ],
    );
  }
}

class _ListEditorCard extends StatelessWidget {
  const _ListEditorCard({required this.title, required this.child, required this.onDelete});
  final String title;
  final Widget child;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.palette.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Row(children: [Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))), IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded))]),
              child,
            ],
          ),
        ),
      );
}

class _NoneParsed extends StatelessWidget {
  const _NoneParsed(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.palette.textTertiary),
      );
}

Map<String, dynamic> _map(Map<String, dynamic> parent, String key) {
  final current = parent[key];
  if (current is Map<String, dynamic>) return current;
  final created = <String, dynamic>{};
  parent[key] = created;
  return created;
}

List<dynamic> _list(Map<String, dynamic> parent, String key) {
  final current = parent[key];
  if (current is List<dynamic>) return current;
  final created = <dynamic>[];
  parent[key] = created;
  return created;
}

double? _scoreFor(Map<String, double> confidence, String path) {
  final exact = confidence[path];
  if (exact != null) return exact;
  final lower = path.toLowerCase();
  for (final entry in confidence.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}
