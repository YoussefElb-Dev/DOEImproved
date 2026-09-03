import 'package:http/http.dart' as http;

import '../models/grade_models.dart';
import '../models/schedule_models.dart';
import 'grade_parser.dart';
import 'native_cookie_bridge.dart';

/// Fetches live data from the NYC student portal using the captured SSO
/// session cookies, then parses the HTML into typed models.
///
/// Every request is bounded by [timeout]. A response that turns out to be a
/// login page (however the portal chooses to express that) raises
/// [AuthExpiredException] so the UI can prompt for re-authentication instead
/// of rendering an empty dashboard.
class GradeDataService {
  static const String baseUrl = 'https://teachhub.schools.nyc';
  static const Duration timeout = Duration(seconds: 20);

  /// How many course-detail pages to fetch at once. The portal is a shared
  /// public resource — keep concurrency modest and well-behaved.
  static const int _detailConcurrency = 4;

  final GradeParser _parser;
  final http.Client _client;

  GradeDataService({GradeParser? parser, http.Client? client})
      : _parser = parser ?? const GradeParser(),
        _client = client ?? http.Client();

  Map<String, String> _headers(Map<String, String> cookies) => {
        'Cookie': NativeCookieBridge.toHeader(cookies),
        'User-Agent':
            'Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) '
                'AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 '
                'Gradly/1.0',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9',
      };

  /// Resolves a path or link found on a portal page against [baseUrl].
  ///
  /// Returns null for anything that would leave the portal's own domain. The
  /// session cookie is attached to every request this class makes, so an
  /// off-site link — whether a legitimate outbound link or one injected into
  /// the page — must never be followed.
  static Uri? resolve(String pathOrUrl) {
    final uri = Uri.tryParse(pathOrUrl.trim());
    if (uri == null) return null;
    final resolved = Uri.parse(baseUrl).resolveUri(uri);
    if (resolved.scheme != 'https') return null;
    if (!resolved.host.toLowerCase().endsWith('schools.nyc')) return null;
    return resolved;
  }

  Future<http.Response> _get(String path, Map<String, String> cookies) {
    final uri = resolve(path);
    if (uri == null) {
      throw PortalUnreachableException('Refusing to follow off-portal link.');
    }
    return _getUri(uri, cookies);
  }

  Future<http.Response> _getUri(Uri uri, Map<String, String> cookies) async {
    final res = await _client
        .get(uri, headers: _headers(cookies))
        .timeout(
          timeout,
          onTimeout: () => throw PortalUnreachableException(
            'The portal did not respond in ${timeout.inSeconds}s.',
          ),
        );
    _throwIfNotAuthenticated(res);
    return res;
  }

  /// Full sync: profile + every course with its categories and assignments.
  Future<({StudentProfile? profile, List<Course> courses})> sync(
    Map<String, String> cookies,
  ) async {
    final res = await _get('/students/dashboard', cookies);

    final profile = _parser.parseProfile(res.body);
    final stubs = _parser.parseCourseList(res.body);
    if (stubs.isEmpty) return (profile: profile, courses: <Course>[]);

    final courses = await _hydrateCourses(stubs, cookies);
    return (profile: profile, courses: courses);
  }

  /// Fetches each course's detail page, [_detailConcurrency] at a time, and
  /// merges categories + assignments into the stub. A course whose detail
  /// page fails keeps its stub data rather than sinking the whole sync.
  Future<List<Course>> _hydrateCourses(
    List<Course> stubs,
    Map<String, String> cookies,
  ) async {
    final out = List<Course>.from(stubs);

    for (var start = 0; start < stubs.length; start += _detailConcurrency) {
      final end = start + _detailConcurrency < stubs.length
          ? start + _detailConcurrency
          : stubs.length;
      await Future.wait([
        for (var i = start; i < end; i++) _hydrateOne(out, i, cookies),
      ]);
    }
    return out;
  }

  Future<void> _hydrateOne(
    List<Course> out,
    int index,
    Map<String, String> cookies,
  ) async {
    final stub = out[index];
    // Prefer the link the portal itself published; `/courses/{id}` is only a
    // guess at a URL layout, and schools differ.
    final path = stub.detailPath?.isNotEmpty == true
        ? stub.detailPath!
        : (stub.id.isEmpty ? null : '/courses/${stub.id}');
    if (path == null) return;

    try {
      final detail = await _get(path, cookies);
      final parsed = _parser.parseCourseDetail(detail.body);
      out[index] = stub.copyWith(
        categories: parsed.categories,
        assignments: parsed.assignments,
      );
    } on AuthExpiredException {
      rethrow;
    } catch (_) {
      // Keep the stub — a single unreadable course must not fail the sync.
    }
  }

  /// Fetches today's class schedule. Returns [DaySchedule.unavailable] when
  /// the school has not posted one.
  Future<DaySchedule> fetchSchedule(
    Map<String, String> cookies, {
    DateTime? date,
  }) async {
    final d = date ?? DateTime.now();
    final res = await _get('/students/schedule', cookies);
    return _parser.parseSchedule(res.body, d);
  }

  /// Fetches the student's transcript (completed courses).
  Future<List<TranscriptRecord>> fetchTranscript(
    Map<String, String> cookies,
  ) async {
    final res = await _get('/students/transcript', cookies);
    return _parser.parseTranscript(res.body);
  }

  /// Fetches upcoming work (assignments due).
  Future<List<WorkItem>> fetchWork(Map<String, String> cookies) async {
    final res = await _get('/students/upcoming', cookies);
    return _parser.parseWorkDue(res.body);
  }

  /// Cheap liveness probe used to validate a restored session on cold start.
  Future<bool> validateSession(Map<String, String> cookies) async {
    if (cookies.isEmpty) return false;
    try {
      await _get('/students/dashboard', cookies);
      return true;
    } on AuthExpiredException {
      return false;
    } catch (_) {
      // Network trouble is not the same as a bad session — assume still valid
      // and let the next real request surface the error.
      return true;
    }
  }

  /// Login pages are the portal's answer to an expired session, and they can
  /// arrive as a 401/403, as a redirect to an identity provider, or as a
  /// 200 that happens to contain a password field. Check all three.
  void _throwIfNotAuthenticated(http.Response res) {
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw const AuthExpiredException('Session expired');
    }
    if (res.statusCode >= 500) {
      throw PortalUnreachableException('Portal error ${res.statusCode}');
    }

    // `http` follows redirects, so this is the URL we actually landed on.
    final landed = res.request?.url;
    if (landed != null && _looksLikeLoginUrl(landed)) {
      throw const AuthExpiredException('Session expired');
    }

    final body = res.body.toLowerCase();
    final hasPasswordField =
        body.contains('type="password"') || body.contains("type='password'");
    if (hasPasswordField) {
      throw const AuthExpiredException('Session expired');
    }
  }

  static bool _looksLikeLoginUrl(Uri uri) {
    final host = uri.host.toLowerCase();
    if (!host.endsWith('schools.nyc')) return true; // bounced to an IdP
    final path = uri.path.toLowerCase();
    const markers = ['login', 'signin', 'sign-in', 'saml', 'adfs', 'sso', 'auth'];
    return markers.any(path.contains);
  }

  void dispose() => _client.close();
}

/// The stored session is no longer accepted by the portal.
class AuthExpiredException implements Exception {
  final String message;
  const AuthExpiredException(this.message);
  @override
  String toString() => message;
}

/// The portal could not be reached or returned a server error. Distinct from
/// [AuthExpiredException] because the fix is "retry", not "sign in again".
class PortalUnreachableException implements Exception {
  final String message;
  const PortalUnreachableException(this.message);
  @override
  String toString() => message;
}
