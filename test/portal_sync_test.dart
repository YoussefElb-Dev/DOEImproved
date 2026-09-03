import 'package:doe_improved/models/portal_snapshot.dart';
import 'package:doe_improved/services/grade_data_service.dart';
import 'package:doe_improved/services/portal_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// End-to-end coverage of the live path: HTTP → auth check → parse → snapshot.
void main() {
  const dashboardHtml = '''
<html><body>
  <div class="student-name">Jordan Alvarez</div>
  <div class="school-name">Brooklyn Technical High School</div>
  <span class="gpa-value">3.92</span>
  <span class="gpa-change">0.15</span>
  <span class="credits">42.0</span>
  <span class="class-rank">Rank #12</span>
  <table>
    <tr class="course" data-course="c1">
      <td class="course-title">AP Calculus BC</td>
      <td class="teacher-name">Ms. Okafor</td>
      <td class="average">88.8%</td>
      <td class="letter-grade">B</td>
    </tr>
  </table>
</body></html>''';

  const courseHtml = '''
<html><body>
  <div class="category">
    <span class="category-name">Tests</span>
    <span class="weight">100</span>
    <span class="earned">80</span>
    <span class="total">100</span>
  </div>
</body></html>''';

  const scheduleHtml = '''
<html><body>
  <div class="day-label">A Day</div>
  <table><tbody>
  <tr class="period">
    <td class="period-num">1</td>
    <td class="period-course">AP Calculus BC</td>
    <td class="period-teacher">Ms. Okafor</td>
    <td class="period-room">4W12</td>
    <td class="period-time">8:00 AM - 8:45 AM</td>
  </tr>
  </tbody></table>
</body></html>''';

  const transcriptHtml = '''
<html><body>
  <table><tbody>
  <tr class="transcript">
    <td class="course-code">M41</td>
    <td class="course-title">Geometry Honors</td>
    <td class="letter">A</td>
    <td class="credits">1.0</td>
    <td class="term">Fall 2024</td>
    <td class="gpa-points">4.0</td>
  </tr>
  </tbody></table>
</body></html>''';

  const workHtml = '''
<html><body>
  <table><tbody>
  <tr class="due" data-due="w1">
    <td class="due-title">Problem Set 4</td>
    <td class="due-course">AP Calculus BC</td>
    <td class="due-type">homework</td>
    <td class="due-date">2026-12-01</td>
  </tr>
  </tbody></table>
</body></html>''';

  const loginHtml = '''
<html><body>
  <form><input type="password" name="pw"></form>
</body></html>''';

  const cookies = {'session': 'abc123'};

  http.Client routing({
    String dashboard = dashboardHtml,
    int dashboardStatus = 200,
    String? scheduleOverride,
    int scheduleStatus = 200,
  }) {
    return MockClient((request) async {
      final path = request.url.path;
      if (path.contains('/students/dashboard')) {
        return http.Response(dashboard, dashboardStatus,
            headers: {'content-type': 'text/html'});
      }
      if (path.startsWith('/courses/')) {
        return http.Response(courseHtml, 200);
      }
      if (path.contains('/students/schedule')) {
        return http.Response(scheduleOverride ?? scheduleHtml, scheduleStatus);
      }
      if (path.contains('/students/transcript')) {
        return http.Response(transcriptHtml, 200);
      }
      if (path.contains('/students/upcoming')) {
        return http.Response(workHtml, 200);
      }
      return http.Response('not found', 404);
    });
  }

  group('GradeDataService auth detection', () {
    test('a 401 raises AuthExpiredException', () async {
      final service = GradeDataService(
        client: MockClient((_) async => http.Response('', 401)),
      );
      await expectLater(
        () => service.sync(cookies),
        throwsA(isA<AuthExpiredException>()),
      );
    });

    test('a 200 login page raises AuthExpiredException', () async {
      final service = GradeDataService(
        client: MockClient((_) async => http.Response(loginHtml, 200)),
      );
      await expectLater(
        () => service.sync(cookies),
        throwsA(isA<AuthExpiredException>()),
      );
    });

    test('a 500 raises PortalUnreachableException, not an auth error', () async {
      final service = GradeDataService(
        client: MockClient((_) async => http.Response('boom', 503)),
      );
      await expectLater(
        () => service.sync(cookies),
        throwsA(isA<PortalUnreachableException>()),
      );
    });

    test('validateSession is false for a rejected cookie', () async {
      final service = GradeDataService(
        client: MockClient((_) async => http.Response('', 403)),
      );
      expect(await service.validateSession(cookies), isFalse);
    });

    test('validateSession is false when there is no session at all', () async {
      final service = GradeDataService(client: routing());
      expect(await service.validateSession(const {}), isFalse);
    });
  });

  group('GradeDataService.sync', () {
    test('hydrates course stubs with their detail pages', () async {
      final service = GradeDataService(client: routing());
      final result = await service.sync(cookies);

      expect(result.profile?.name, 'Jordan Alvarez');
      expect(result.courses, hasLength(1));
      expect(result.courses.single.title, 'AP Calculus BC');
      // Categories only exist on the detail page, so this proves hydration ran.
      expect(result.courses.single.categories, hasLength(1));
      expect(result.courses.single.categories.single.name, 'Tests');
    });

    test('a failing detail page leaves the stub intact', () async {
      final client = MockClient((request) async {
        if (request.url.path.contains('/students/dashboard')) {
          return http.Response(dashboardHtml, 200);
        }
        if (request.url.path.startsWith('/courses/')) {
          return http.Response('gone', 404);
        }
        return http.Response('', 200);
      });
      final result = await GradeDataService(client: client).sync(cookies);

      expect(result.courses, hasLength(1));
      expect(result.courses.single.title, 'AP Calculus BC');
      expect(result.courses.single.categories, isEmpty);
    });
  });

  group('PortalRepository', () {
    test('no cookies yields a clearly-labelled demo snapshot', () async {
      final snapshot = await PortalRepository().load(const {});
      expect(snapshot.source, DataSource.demo);
      expect(snapshot.isDemo, isTrue);
      expect(snapshot.courses, isNotEmpty);
    });

    test('a full sync assembles every section as live data', () async {
      final repo =
          PortalRepository(service: GradeDataService(client: routing()));
      final snapshot = await repo.load(cookies);

      expect(snapshot.source, DataSource.live);
      expect(snapshot.profile.name, 'Jordan Alvarez');
      expect(snapshot.courses, hasLength(1));
      expect(snapshot.schedule.available, isTrue);
      expect(snapshot.schedule.periods, hasLength(1));
      expect(snapshot.transcript, hasLength(1));
      expect(snapshot.work, hasLength(1));
      expect(snapshot.partialFailure, isNull);
    });

    test('one broken section degrades instead of failing the sync', () async {
      final repo = PortalRepository(
        service: GradeDataService(client: routing(scheduleStatus: 500)),
      );
      final snapshot = await repo.load(cookies);

      expect(snapshot.source, DataSource.live);
      expect(snapshot.courses, hasLength(1), reason: 'grades still load');
      expect(snapshot.schedule.available, isFalse);
      expect(snapshot.partialFailure, contains('schedule'));
    });

    test('an expired session propagates so the UI can re-authenticate',
        () async {
      final repo = PortalRepository(
        service: GradeDataService(
          client: routing(dashboard: loginHtml),
        ),
      );
      await expectLater(
        () => repo.load(cookies),
        throwsA(isA<AuthExpiredException>()),
      );
    });
  });
}
