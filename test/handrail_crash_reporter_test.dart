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
    final reporter = HandrailCrashReporter(
      config: const HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectId: 'project-123',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        commitSha: ' crash-commit ',
        reportToken: 'report-token',
        routeProvider: _route,
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
      StackTrace.fromString('#0 DeployScreen.build (deploy.dart:12:3)'),
      crashType: 'flutter_error',
      fatal: true,
      context: 'building DeployScreen',
      metadata: const <String, Object?>{
        'deploy_target_id': 'target-123',
      },
    );

    expect(result?.isSuccess, isTrue);
    expect(submittedPayload?['source'], handrailFlutterSdkCrashSource);
    expect(submittedPayload?['severity'], 'sev1');
    expect(submittedPayload?['project_id'], 'project-123');
    expect(submittedPayload, isNot(contains('project_slug')));
    expect(submittedPayload?['environment'], 'staging');
    expect(submittedPayload?['route'], '/deployments');
    expect(submittedPayload?['commit_sha'], 'crash-commit');

    final metadata = submittedPayload?['metadata'] as Map<String, Object?>?;
    expect(metadata?['crash_type'], 'flutter_error');
    expect(metadata?['fatal'], isTrue);
    expect(metadata?['handled'], isFalse);
    expect(metadata?['exception_type'], 'StateError');
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
      config: const HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectSlug: 'handrail',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        reportToken: 'report-token',
        routeProvider: _route,
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

    HandrailCrashReporter.install(
      config: const HandrailBugReporterConfig(
        apiBaseUrl: 'https://example.test/api',
        projectSlug: 'handrail',
        environment: 'staging',
        appFlavor: 'staging',
        appVersion: '1.3.305',
        buildNumber: '9',
        reportToken: 'report-token',
        routeProvider: _route,
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
