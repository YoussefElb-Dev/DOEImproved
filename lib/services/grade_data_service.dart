import 'package:http/http.dart' as http;

import '../models/grade_models.dart';
import '../models/schedule_models.dart';
import 'grade_parser.dart';
import 'native_cookie_bridge.dart';

/// Fetches live grade data from the NYC portal using the captured SSO
/// session cookies, then parses the HTML into typed models.
class GradeDataService {
  static const String baseUrl = 'https://teachhub.schools.nyc';

  final GradeParser _parser;
  final http.Client _client;

  GradeDataService({GradeParser? parser, http.Client? client})
      : _parser = parser ?? const GradeParser(),
        _client = client ?? http.Client();

  Map<String, String> _headers(Map<String, String> cookies) => {
        'Cookie': NativeCookieBridge.toHeader(cookies),
        'User-Agent': 'DOEImproved/1.0',
        'Accept': 'text/html,application/xhtml+xml',
      };

  /// Full sync: profile + all courses with categories/assignments.
  /// Throws [AuthExpiredException] when the session is no longer valid
  /// (redirect to login), so callers can force a re-auth.
  Future<({StudentProfile? profile, List<Course> courses})> sync(
      Map<String, String> cookies) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/students/dashboard'),
      headers: _headers(cookies),
    );
    _throwIfAuthRedirect(res);

    final profile = _parser.parseProfile(res.body);
    final stubs = _parser.parseCourseList(res.body);

    final courses = <Course>[];
    for (final stub in stubs) {
      final detail = await _client.get(
        Uri.parse('$baseUrl/courses/${stub.id}'),
        headers: _headers(cookies),
      );
      _throwIfAuthRedirect(detail);
      final parsed = _parser.parseCourseDetail(detail.body);
      courses.add(stub.copyWith(
        categories: parsed.categories,
        assignments: parsed.assignments,
      ));
    }
    return (profile: profile, courses: courses);
  }

  /// Fetches today's class schedule. Returns [DaySchedule.unavailable]
  /// when the school hasn't posted one yet.
  Future<DaySchedule> fetchSchedule(Map<String, String> cookies, {DateTime? date}) {
    final d = date ?? DateTime.now();
    return _client
        .get(Uri.parse('$baseUrl/students/schedule'), headers: _headers(cookies))
        .then((res) {
      _throwIfAuthRedirect(res);
      return _parser.parseSchedule(res.body, d);
    });
  }

  /// Fetches the student's transcript (completed courses).
  Future<List<TranscriptRecord>> fetchTranscript(Map<String, String> cookies) =>
      _client
          .get(Uri.parse('$baseUrl/students/transcript'),
              headers: _headers(cookies))
          .then((res) {
        _throwIfAuthRedirect(res);
        return _parser.parseTranscript(res.body);
      });

  /// Fetches upcoming work (assignments due).
  Future<List<WorkItem>> fetchWork(Map<String, String> cookies) => _client
          .get(Uri.parse('$baseUrl/students/upcoming'),
              headers: _headers(cookies))
          .then((res) {
        _throwIfAuthRedirect(res);
        return _parser.parseWorkDue(res.body);
      });

  void _throwIfAuthRedirect(http.Response res) {
    final uri = res.request?.url;
    final redirectedToLogin = res.isRedirect &&
        (uri?.path.toLowerCase().contains('login') ?? false);
    final bodyHasLogin = res.body.toLowerCase().contains('sign in with');
    if (redirectedToLogin || (res.statusCode == 401) || bodyHasLogin) {
      throw const AuthExpiredException('Session expired');
    }
  }

  /// "Documents" app: bell schedule. Null = not published yet.
  Future<List<ScheduleEntry>?> fetchSchedule(Map<String, String> cookies) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/students/schedule'),
      headers: _headers(cookies),
    );
    _throwIfAuthRedirect(res);
    return _parser.parseSchedule(res.body);
  }

  /// "Documents" app: transcript. Null = not published yet.
  Future<List<TranscriptTerm>?> fetchTranscript(Map<String, String> cookies) async {
    final res = await _client.get(
      Uri.parse('$baseUrl/students/transcript'),
      headers: _headers(cookies),
    );
    _throwIfAuthRedirect(res);
    return _parser.parseTranscript(res.body);
  }

  void dispose() => _client.close();
}

class AuthExpiredException implements Exception {
  final String message;
  const AuthExpiredException(this.message);
  @override
  String toString() => 'AuthExpiredException: $message';
}