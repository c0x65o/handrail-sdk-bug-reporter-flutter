import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
        projectSlug: 'handrail',
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
    expect(submittedPayload?['project_slug'], 'handrail');
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
