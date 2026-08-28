import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const payload = HandrailBugReportPayload(
    projectSlug: 'handrail',
    environment: 'staging',
    appFlavor: 'staging',
    appVersion: '1.3.105',
    buildNumber: '217',
    commitSha: 'abc123',
    platform: 'android',
    deviceModel: 'Pixel',
    osVersion: 'Android 15',
    route: '/workspace',
    appBrightness: 'light',
    title: 'Broken screen',
    description: 'Screen fails to load.',
    profileKey: 'profile',
    screenshotBase64: 'base64',
  );

  test('submission success posts bearer token to mobile bug report endpoint',
      () async {
    late http.Request captured;
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 201);
      }),
    );

    final result = await client.submit(payload);

    expect(result.isSuccess, isTrue);
    expect(
        captured.url.toString(), 'https://example.test/api/mobile-bug-reports');
    expect(captured.headers['authorization'], 'Bearer report-token');
    expect(jsonDecode(captured.body), payload.toJson());
  });

  test('submission can use x-handrail-bug-report-token header', () async {
    late http.Request captured;
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      useBearerToken: false,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      }),
    );

    final result = await client.submit(payload);

    expect(result.isSuccess, isTrue);
    expect(captured.headers['x-handrail-bug-report-token'], 'report-token');
    expect(captured.headers.containsKey('authorization'), isFalse);
  });

  test('notification opt-in follows an accepted report as a separate request',
      () async {
    final requests = <http.Request>[];
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/subscription')) {
          return http.Response(
            jsonEncode(<String, Object?>{
              'notification_subscription': <String, Object?>{
                'active': true,
              },
            }),
            201,
          );
        }
        return http.Response('{"bug_id":"bug-notify-1"}', 201);
      }),
    );
    const notificationPayload = HandrailBugReportPayload(
      projectId: 'project-123',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.3.105',
      buildNumber: '217',
      commitSha: 'abc123',
      platform: 'android',
      deviceModel: 'Pixel',
      osVersion: 'Android 15',
      route: '/workspace',
      appBrightness: 'light',
      title: 'Broken screen',
      description: 'Screen fails to load.',
      profileKey: 'profile',
      screenshotBase64: null,
      notifyOnResolution: true,
    );

    final result = await client.submit(
      notificationPayload,
      applicationSessionToken: 'current-session-token',
    );

    expect(result.isSuccess, isTrue);
    expect(result.notificationSubscribed, isTrue);
    expect(result.notificationWarning, isNull);
    expect(requests, hasLength(2));
    expect(requests.first.url.path, '/api/mobile-bug-reports');
    expect(jsonDecode(requests.first.body),
        isNot(contains('reporter_notification')));
    expect(
      requests.last.url.toString(),
      'https://example.test/api/mobile-bug-reports/bugs/bug-notify-1/subscription?project_id=project-123&environment=staging',
    );
    expect(
      requests.last.headers['x-handrail-application-session-token'],
      'current-session-token',
    );
    expect(jsonDecode(requests.last.body), <String, Object?>{
      'reporter_surface': 'mobile',
      'reporter_notification': <String, Object?>{
        'notify_on_resolution': true,
        'consent_version': 'v1',
      },
    });
  });

  test('notification failure does not turn an accepted report into an error',
      () async {
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient((request) async =>
          request.url.path.endsWith('/subscription')
              ? http.Response('unavailable', 503)
              : http.Response('{"bug_id":"bug-notify-2"}', 201)),
    );
    const notificationPayload = HandrailBugReportPayload(
      projectId: 'project-123',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.3.105',
      buildNumber: '217',
      commitSha: null,
      platform: 'ios',
      deviceModel: null,
      osVersion: null,
      route: null,
      appBrightness: null,
      title: 'Broken screen',
      description: 'Screen fails to load.',
      profileKey: null,
      screenshotBase64: null,
      notifyOnResolution: true,
    );

    final result = await client.submit(notificationPayload);

    expect(result.isSuccess, isTrue);
    expect(result.notificationSubscribed, isFalse);
    expect(result.notificationWarning, contains('report was sent'));
  });

  test('submission sends current application session proof only as a header',
      () async {
    late http.Request captured;
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 201);
      }),
    );

    final result = await client.submit(
      payload,
      applicationSessionToken: 'current-session-token',
    );

    expect(result.isSuccess, isTrue);
    expect(
      captured.headers['x-handrail-application-session-token'],
      'current-session-token',
    );
    expect(captured.body, isNot(contains('current-session-token')));
  });

  test('policy discovery reuses report and application session headers',
      () async {
    late http.Request captured;
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'schema_version': 1,
            'project_id': 'project-123',
            'environment': 'staging',
            'reporter': <String, Object?>{
              'identity_verified': true,
              'access_level': 'full_access',
              'role': 'maintainer',
            },
            'reporter_notifications': <String, Object?>{
              'available': true,
              'recipient_hint': 'a***@example.com',
              'lifecycles': <String>['fixed'],
            },
            'ask_options': const <Object?>[],
            'automation_policy': <String, Object?>{
              'schema_version': 3,
              'automatic_fix_max_risk': 'high',
              'production_max_risk_by_impact': <String, Object?>{
                'critical': 'moderate',
                'high': 'low',
                'moderate': 'none',
                'low': 'none',
              },
            },
          }),
          200,
        );
      }),
    );

    final policy = await client.loadPolicy(
      projectId: 'project-123',
      environment: 'staging',
      applicationSessionToken: 'current-session-token',
    );

    expect(captured.method, 'GET');
    expect(
      captured.url.toString(),
      'https://example.test/api/mobile-bug-reports/policy?environment=staging&project_id=project-123',
    );
    expect(captured.headers['authorization'], 'Bearer report-token');
    expect(
      captured.headers['x-handrail-application-session-token'],
      'current-session-token',
    );
    expect(policy?.accessLevel, 'full_access');
    expect(policy?.notificationAvailable, isTrue);
    expect(policy?.notificationRecipientHint, 'a***@example.com');
    expect(policy?.askOptions, isEmpty);
    expect(policy?.role, 'maintainer');
    expect(policy?.automaticFixMaxRisk, 'high');
    expect(policy?.productionMaxRiskByImpact['critical'], 'moderate');
  });

  test('policy discovery falls back when the policy request stalls', () async {
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient(
        (_) => Completer<http.Response>().future,
      ),
    );

    final policy = await client.loadPolicy(
      projectId: 'project-123',
      environment: 'staging',
      timeout: const Duration(milliseconds: 20),
    );

    expect(policy, isNull);
  });

  test('submission honors configured endpoint path override', () async {
    late http.Request captured;
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      endpointPath: '/mobile-bug-reports',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('', 204);
      }),
    );

    final result = await client.submit(payload);

    expect(result.isSuccess, isTrue);
    expect(
        captured.url.toString(), 'https://example.test/api/mobile-bug-reports');
  });

  test('submission can post to a same-origin Mobile Preview endpoint',
      () async {
    late http.Request captured;
    final client = HandrailBugReportClient(
      apiBaseUrl: '/api',
      endpointPath: '/mobile-bug-reports',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"ok":true}', 201);
      }),
    );

    final result = await client.submit(payload);

    expect(result.isSuccess, isTrue);
    expect(captured.method, 'POST');
    expect(captured.url.toString(), '/api/mobile-bug-reports');
    expect(captured.headers['authorization'], 'Bearer report-token');
  });

  test('submission error reports non-2xx responses', () async {
    final client = HandrailBugReportClient(
      apiBaseUrl: 'https://example.test/api',
      reportToken: 'report-token',
      httpClient: MockClient((request) async {
        return http.Response('nope', 403);
      }),
    );

    final result = await client.submit(payload);

    expect(result.isSuccess, isFalse);
    expect(result.status, HandrailBugReportSubmissionStatus.error);
    expect(result.statusCode, 403);
    expect(result.errorMessage, 'nope');
  });
}
