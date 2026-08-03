import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('reportError submits crash evidence through mobile bug intake',
      () async {
    Map<String, Object?>? submittedPayload;

    final logBuffer = HandrailCrashLogBuffer(capacity: 4)
      ..add(
        'Deploy action opened',
        level: 'info',
        category: 'navigation',
        context: const <String, Object?>{'route': '/deployments'},
      );
    final stackTrace = StackTrace.fromString(
      List<String>.generate(
        320,
        (index) =>
            '#$index DeployScreen.build (package:handrail/deploy.dart:${index + 1}:3)',
      ).join('\n'),
    );
    expect(stackTrace.toString().length, greaterThan(12000));
    final reporter = HandrailCrashReporter(
      config: HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectId: 'project-123',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        commitSha: ' crash-commit ',
        reportToken: 'report-token',
        routeProvider: _route,
        usernameProvider: () async => ' crash-user ',
        reporterAssertionProvider: () async => const HandrailReporterAssertion(
          userIdentifier: 'user-123',
          sessionIdentifier: 'session-123',
          verifier: 'session-token',
          issuedAt: '2026-08-03T12:00:00.000Z',
          nonce: 'assertion-nonce-1234567890',
        ),
      ),
      metadataProvider: _FakeMetadataProvider(),
      logBuffer: logBuffer,
      clientFactory: (config) {
        return HandrailBugReportClient(
          apiBaseUrl: config.apiBaseUrl,
          reportToken: config.reportToken,
          endpointPath: config.endpointPath,
          httpClient: MockClient((request) async {
            submittedPayload = jsonDecode(request.body) as Map<String, Object?>;
            return http.Response('{"ok":true}', 201);
          }),
        );
      },
    );

    final result = await reporter.reportError(
      StateError('remote deploy crashed'),
      stackTrace,
      crashType: 'flutter_error',
      fatal: true,
      context: 'building DeployScreen',
      metadata: const <String, Object?>{
        'deploy_target_id': 'target-123',
      },
    );

    expect(result?.isSuccess, isTrue);
    expect(submittedPayload?['source'], handrailFlutterSdkCrashSource);
    expect(submittedPayload?['title'], 'Unhandled app error: StateError');
    expect(submittedPayload?['severity'], 'sev1');
    expect(submittedPayload?['project_id'], 'project-123');
    expect(submittedPayload, isNot(contains('project_slug')));
    expect(submittedPayload?['environment'], 'staging');
    expect(submittedPayload?['route'], '/deployments');
    expect(submittedPayload?['commit_sha'], 'crash-commit');
    expect(submittedPayload?['username'], 'crash-user');
    expect(submittedPayload?['reporter_assertion'], <String, Object?>{
      'version': 1,
      'user_identifier': 'user-123',
      'session_identifier': 'session-123',
      'verifier': 'session-token',
      'issued_at': '2026-08-03T12:00:00.000Z',
      'nonce': 'assertion-nonce-1234567890',
    });

    final metadata = submittedPayload?['metadata'] as Map<String, Object?>?;
    expect(metadata?['crash_type'], 'flutter_error');
    expect(metadata?['fatal'], isTrue);
    expect(metadata?['handled'], isFalse);
    expect(metadata?['exception_type'], 'StateError');
    expect(metadata?['stack_trace'], stackTrace.toString());
    expect(
      metadata?['event_id'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(metadata?['deploy_target_id'], 'target-123');
    expect(metadata?['recent_logs'], isA<List<Object?>>());
    expect(
      submittedPayload?['description'],
      contains('remote deploy crashed'),
    );
  });

  test('pending crash reports drain on next install after reload', () async {
    final firstRequests = <Map<String, Object?>>[];
    final retryRequests = <Map<String, Object?>>[];

    final reporter = HandrailCrashReporter(
      config: HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectSlug: 'handrail',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        reportToken: 'report-token',
        routeProvider: _route,
        reporterAssertionProvider: () async => const HandrailReporterAssertion(
          userIdentifier: 'user-123',
          sessionIdentifier: 'session-123',
          verifier: 'first-session-token',
          issuedAt: '2026-08-03T12:00:00.000Z',
          nonce: 'first-assertion-nonce-12345',
        ),
      ),
      metadataProvider: _FakeMetadataProvider(),
      clientFactory: (config) {
        return HandrailBugReportClient(
          apiBaseUrl: config.apiBaseUrl,
          reportToken: config.reportToken,
          httpClient: MockClient((request) async {
            firstRequests.add(jsonDecode(request.body) as Map<String, Object?>);
            return http.Response('temporarily unavailable', 503);
          }),
        );
      },
    );

    final firstResult = await reporter.reportError(
      StateError('reload before submit finished'),
      StackTrace.fromString('#0 DeployScreen.save (deploy.dart:44:7)'),
      crashType: 'platform_dispatcher_error',
      fatal: true,
    );

    expect(firstResult?.isSuccess, isFalse);
    expect(firstRequests, hasLength(1));
    final preferences = await SharedPreferences.getInstance();
    final persistedCrashEvidence = preferences
        .getStringList('handrail_bug_reporter.pending_crash_reports.v1')
        ?.join('\n');
    expect(persistedCrashEvidence, isNotNull);
    expect(persistedCrashEvidence, isNot(contains('reporter_assertion')));
    expect(persistedCrashEvidence, isNot(contains('user-123')));
    expect(persistedCrashEvidence, isNot(contains('session-123')));
    expect(persistedCrashEvidence, isNot(contains('first-session-token')));
    expect(
      persistedCrashEvidence,
      isNot(contains('first-assertion-nonce-12345')),
    );

    HandrailCrashReporter.install(
      config: HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectSlug: 'handrail',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        reportToken: 'report-token',
        routeProvider: _route,
        reporterAssertionProvider: () async => const HandrailReporterAssertion(
          userIdentifier: 'user-123',
          sessionIdentifier: 'session-456',
          verifier: 'fresh-session-token',
          issuedAt: '2026-08-03T12:01:00.000Z',
          nonce: 'fresh-assertion-nonce-12345',
        ),
      ),
      metadataProvider: _FakeMetadataProvider(),
      captureFlutterErrors: false,
      capturePlatformErrors: false,
      captureDebugPrint: false,
      clientFactory: (config) {
        return HandrailBugReportClient(
          apiBaseUrl: config.apiBaseUrl,
          reportToken: config.reportToken,
          httpClient: MockClient((request) async {
            retryRequests.add(jsonDecode(request.body) as Map<String, Object?>);
            return http.Response('{"ok":true}', 201);
          }),
        );
      },
    );

    for (var i = 0; i < 10 && retryRequests.isEmpty; i += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    expect(retryRequests, hasLength(1));
    expect(retryRequests.single['source'], handrailFlutterSdkCrashSource);
    expect(retryRequests.single['description'],
        contains('reload before submit finished'));
    expect(
      retryRequests.single['reporter_assertion'],
      containsPair('verifier', 'fresh-session-token'),
    );

    HandrailCrashReporter.install(
      config: const HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectSlug: 'handrail',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        reportToken: 'report-token',
      ),
      captureFlutterErrors: false,
      capturePlatformErrors: false,
      captureDebugPrint: false,
      clientFactory: (config) {
        return HandrailBugReportClient(
          apiBaseUrl: config.apiBaseUrl,
          reportToken: config.reportToken,
          httpClient: MockClient((request) async {
            retryRequests.add(jsonDecode(request.body) as Map<String, Object?>);
            return http.Response('{"ok":true}', 201);
          }),
        );
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(retryRequests, hasLength(1));
  });
}

String? _route() => '/deployments';

class _FakeMetadataProvider extends HandrailDeviceMetadataProvider {
  @override
  Future<HandrailDeviceMetadata> read() async {
    return const HandrailDeviceMetadata(
      platform: 'android',
      deviceModel: 'Pixel test',
      osVersion: 'Android 16',
    );
  }
}
