import 'dart:convert';

import 'package:doe_improved/models/normalized_transcript.dart';
import 'package:doe_improved/services/transcript/nim_transcript_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const fakeKey = 'nvapi-test.not-a-real-credential';

  test('uses only parameters supported by the NVIDIA Kimi K3 endpoint', () async {
    final local = _localTranscript();
    late Map<String, dynamic> requestBody;
    final client = MockClient((request) async {
      expect(
        request.url.toString(),
        'https://integrate.api.nvidia.com/v1/chat/completions',
      );
      expect(request.headers['authorization'], 'Bearer $fakeKey');
      requestBody = jsonDecode(request.body) as Map<String, dynamic>;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(_extraction(local))},
            },
          ],
          'usage': {'prompt_tokens': 1200, 'completion_tokens': 700},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final result = await NimTranscriptService(client: client).extract(
      apiKey: fakeKey,
      localDraft: local,
      rawText: local.rawText,
      currentGradeLevel: '12',
    );

    expect(requestBody['model'], NimTranscriptService.model);
    expect(requestBody['reasoning_effort'], 'max');
    expect(requestBody['stream'], isFalse);
    expect(requestBody.containsKey('response_format'), isFalse);
    expect(requestBody.containsKey('top_p'), isFalse);
    expect(jsonEncode(requestBody['messages']), contains('current Gradly grade'));
    expect(jsonEncode(requestBody['messages']), contains('12'));
    expect(result.transcript.courseCount, 2);
    expect(result.transcript.extraFields['aiModel'], 'moonshotai/kimi-k3');
    expect(result.transcript.extraFields['currentAppGradeLevel'], '12');
    expect(result.transcript.rawText, local.rawText.trim());
    expect(result.promptTokens, 1200);
    expect(result.usedStructuredOutput, isFalse);
  });

  test('recovers every locally detectable row from older incomplete JSON', () async {
    final complete = _localTranscript();
    final incompleteJson = complete.toJson();
    final term = Map<String, dynamic>.from(
      (incompleteJson['terms'] as List<dynamic>).single as Map,
    );
    term['courses'] = [(term['courses'] as List<dynamic>).first];
    incompleteJson['terms'] = [term];
    final incomplete = NormalizedTranscript.fromJson(incompleteJson);
    late Map<String, dynamic> requestBody;
    final service = NimTranscriptService(
      client: MockClient((request) async {
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode(_extraction(incomplete)),
                },
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await service.extract(
      apiKey: fakeKey,
      localDraft: incomplete,
      rawText: complete.rawText,
    );

    expect(result.transcript.courseCount, 2);
    expect(result.transcript.terms.single.courses.last.title, 'Precalculus');
    expect(jsonEncode(requestBody['messages']), contains('found 2 distinct'));
    expect(jsonEncode(requestBody['messages']), contains('PRECALCULUS'));
    expect(
      result.transcript.warnings.any((warning) => warning.contains('recovered 1')),
      isTrue,
    );
  });

  test('polls NVIDIA when Kimi K3 returns an asynchronous request id', () async {
    final local = _localTranscript();
    var calls = 0;
    final service = NimTranscriptService(
      client: MockClient((request) async {
        calls++;
        if (request.method == 'POST') {
          return http.Response(jsonEncode({'requestId': 'request-123'}), 202);
        }
        expect(
          request.url.toString(),
          'https://integrate.api.nvidia.com/v1/status/request-123',
        );
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(_extraction(local))},
              },
            ],
          }),
          200,
        );
      }),
    );

    final result = await service.extract(
      apiKey: fakeKey,
      localDraft: local,
      rawText: local.rawText,
    );

    expect(calls, 2);
    expect(result.transcript.courseCount, 2);
  });

  test('restores locally detected rows when the model omits one', () async {
    final local = _localTranscript();
    final extraction = _extraction(local);
    final terms = extraction['terms'] as List<dynamic>;
    final term = terms.single as Map<String, dynamic>;
    term['courses'] = [(term['courses'] as List<dynamic>).first];
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': jsonEncode(extraction)},
              },
            ],
          }),
          200,
        ));

    final result = await NimTranscriptService(client: client).extract(
      apiKey: fakeKey,
      localDraft: local,
      rawText: local.rawText,
    );

    expect(result.transcript.courseCount, 2);
    expect(
      result.transcript.warnings.any((warning) => warning.contains('restored')),
      isTrue,
    );
  });

  test('surfaces an invalid key response without exposing the key', () async {
    final local = _localTranscript();
    final service = NimTranscriptService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Unauthorized'},
            }),
            401,
          )),
    );

    await expectLater(
      service.extract(
        apiKey: fakeKey,
        localDraft: local,
        rawText: local.rawText,
      ),
      throwsA(
        isA<NimTranscriptException>()
            .having((error) => error.statusCode, 'status', 401)
            .having(
              (error) => error.userMessage,
              'message',
              allOf(contains('rejected'), isNot(contains(fakeKey))),
            ),
      ),
    );
  });

  test('does not display null for an empty NVIDIA 400 error', () async {
    final local = _localTranscript();
    final service = NimTranscriptService(
      client: MockClient((_) async => http.Response(
            jsonEncode({'error': null}),
            400,
          )),
    );

    await expectLater(
      service.extract(
        apiKey: fakeKey,
        localDraft: local,
        rawText: local.rawText,
      ),
      throwsA(
        isA<NimTranscriptException>().having(
          (error) => error.userMessage,
          'message',
          allOf(contains('error 400'), isNot(contains('null'))),
        ),
      ),
    );
  });

  test('keeps malformed model output out of the saved schema', () async {
    final local = _localTranscript();
    final service = NimTranscriptService(
      client: MockClient((_) async => http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': 'not json'},
                },
              ],
            }),
            200,
          )),
    );

    await expectLater(
      service.extract(
        apiKey: fakeKey,
        localDraft: local,
        rawText: local.rawText,
      ),
      throwsA(
        isA<NimTranscriptException>().having(
          (error) => error.userMessage,
          'message',
          contains('could not be validated'),
        ),
      ),
    );
  });
}

NormalizedTranscript _localTranscript() => NormalizedTranscript(
      id: 'local-record',
      sourceFingerprint: 'fingerprint',
      sourceFileName: 'Transcript.pdf',
      importedAt: DateTime.utc(2026, 9, 4),
      rawText: '''
2026/ Term 1 Actual
27Q309EES87 ENGLISH 12 95 95 1.00/1.00
27Q309MRS23QA PRECALCULUS 92 92 1.00/1.00
Cumulative Average: 93.50%
''',
      student: const TranscriptStudent(
        name: 'Test Student',
        studentId: '000000000',
        gradeLevel: '12',
      ),
      institution: const TranscriptInstitution(
        name: 'NYC Department of Education',
      ),
      officialStatus: OfficialStatus.official,
      terms: const [
        NormalizedTerm(
          id: '2026-term-1',
          label: '2026/ Term 1 Actual',
          year: 2026,
          creditsAttempted: 2,
          creditsEarned: 2,
          courses: [
            NormalizedCourse(
              id: 'english',
              subjectCode: '27Q309',
              courseNumber: 'EES87',
              title: 'ENGLISH 12',
              numericGrade: 95,
              creditsAttempted: 1,
              creditsEarned: 1,
              countsTowardGpa: true,
              rawLine: '27Q309EES87 ENGLISH 12 95 95 1.00/1.00',
            ),
            NormalizedCourse(
              id: 'math',
              subjectCode: '27Q309',
              courseNumber: 'MRS23QA',
              title: 'PRECALCULUS',
              numericGrade: 92,
              creditsAttempted: 1,
              creditsEarned: 1,
              countsTowardGpa: true,
              rawLine: '27Q309MRS23QA PRECALCULUS 92 92 1.00/1.00',
            ),
          ],
        ),
      ],
      cumulative: const CumulativeSummary(
        creditsAttempted: 2,
        creditsEarned: 2,
        cumulativeAveragePercent: 93.5,
      ),
    );

Map<String, dynamic> _extraction(NormalizedTranscript local) {
  final json = local.toJson();
  return {
    for (final key in const [
      'student',
      'institution',
      'issueDate',
      'officialStatus',
      'program',
      'creditSystem',
      'repeatPolicy',
      'gradingScale',
      'terms',
      'cumulative',
      'transfers',
      'degrees',
      'warnings',
      'extraFields',
      'confidence',
    ])
      key: json[key],
  };
}
