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
