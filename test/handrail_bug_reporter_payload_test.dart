import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';

void main() {
  test('payload construction includes route, version, device, and profile key',
      () {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectId: 'project-123',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.3.105',
      buildNumber: '217',
      commitSha: 'abc1234',
      reportToken: 'report-token',
      username: ' alice@example.test ',
      routeProvider: _route,
    );

    final payload = HandrailBugReportPayload.fromConfig(
      config: config,
      draft: const HandrailBugReportDraft(
        title: 'Checkout freezes',
        description: 'The checkout screen locks after tapping submit.',
        severity: 'sev3',
        screenshotBase64: 'png-base64',
        screenshotFilename: 'mobile-screenshot.png',
        screenshotMimeType: 'image/png',
        screenshotCaptureError: null,
        appBrightness: 'dark',
        deployFixedAppToStores: true,
      ),
      device: const HandrailDeviceMetadata(
        platform: 'ios',
        deviceModel: 'iPhone 15',
        osVersion: 'iOS 18.1',
      ),
      profileKey: 'profile-key',
      reporterAssertion: const HandrailReporterAssertion(
        userIdentifier: 'user-123',
        sessionIdentifier: 'session-123',
        verifier: 'session-token',
        issuedAt: '2026-08-03T12:00:00.000Z',
        nonce: 'assertion-nonce-1234567890',
      ),
    );

    expect(payload.toJson(), <String, Object?>{
      'environment': 'staging',
      'app_flavor': 'staging',
      'app_version': '1.3.105',
      'build_number': '217',
      'commit_sha': 'abc1234',
      'platform': 'ios',
      'device_model': 'iPhone 15',
      'os_version': 'iOS 18.1',
      'route': '/checkout',
      'app_brightness': 'dark',
      'title': 'Checkout freezes',
      'description': 'The checkout screen locks after tapping submit.',
      'severity': 'sev3',
      'profile_key': 'profile-key',
      'reporter_assertion': <String, Object?>{
        'version': 1,
        'user_identifier': 'user-123',
        'session_identifier': 'session-123',
        'verifier': 'session-token',
        'issued_at': '2026-08-03T12:00:00.000Z',
        'nonce': 'assertion-nonce-1234567890',
      },
      'screenshot_base64': 'png-base64',
      'screenshot_filename': 'mobile-screenshot.png',
      'screenshot_mime_type': 'image/png',
      'screenshot_capture_error': null,
      'deploy_fixed_app_to_stores': true,
      'reporter_sdk_version': HandrailBugReporterSdkMetadata.version,
      'reporter_sdk_commit': HandrailBugReporterSdkMetadata.commit,
      'reporter_sdk_ref': HandrailBugReporterSdkMetadata.ref,
      'project_id': 'project-123',
      'username': 'alice@example.test',
    });
    expect(payload.toJson(), isNot(contains('project_slug')));
  });

  test('reporter SDK metadata is included and version matches pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final versionMatch =
        RegExp(r'^version:\s*(\S+)\s*$', multiLine: true).firstMatch(pubspec);

    expect(versionMatch, isNotNull);
    expect(HandrailBugReporterSdkMetadata.packageName, 'handrail_bug_reporter');
    expect(HandrailBugReporterSdkMetadata.version, versionMatch!.group(1));
    expect(HandrailBugReporterSdkMetadata.ref, 'release/0.1');

    const payload = HandrailBugReportPayload(
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.3.105',
      buildNumber: '217',
      commitSha: 'abc1234',
      platform: 'ios',
      deviceModel: null,
      osVersion: null,
      route: null,
      appBrightness: null,
      title: 'Checkout freezes',
      description: 'The checkout screen locks after tapping submit.',
      severity: 'sev3',
      profileKey: null,
      screenshotBase64: null,
      reporterSdkCommit: 'sdk-commit',
      reporterSdkRef: 'v0.1.19',
    );

    expect(
      payload.toJson(),
      containsPair(
        'reporter_sdk_version',
        HandrailBugReporterSdkMetadata.version,
      ),
    );
    expect(payload.toJson(), containsPair('reporter_sdk_commit', 'sdk-commit'));
    expect(payload.toJson(), containsPair('reporter_sdk_ref', 'v0.1.19'));
    expect(payload.toJson(), containsPair('app_version', '1.3.105'));
    expect(payload.toJson(), containsPair('build_number', '217'));
    expect(payload.toJson(), containsPair('severity', 'sev3'));
  });

  test('payload omits a blank optional username', () {
    const payload = HandrailBugReportPayload(
      projectId: 'project-123',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      commitSha: null,
      platform: 'ios',
      deviceModel: null,
      osVersion: null,
      route: null,
      appBrightness: null,
      title: 'Checkout freezes',
      description: 'The checkout screen locks.',
      severity: 'sev3',
      profileKey: null,
      screenshotBase64: null,
      username: '   ',
    );

    expect(payload.toJson(), isNot(contains('username')));
  });

  test('payload includes only selected policy Ask options', () {
    const payload = HandrailBugReportPayload(
      projectId: 'project-123',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      commitSha: null,
      platform: 'ios',
      deviceModel: null,
      osVersion: null,
      route: null,
      appBrightness: null,
      title: 'Checkout freezes',
      description: 'The checkout screen locks.',
      profileKey: null,
      screenshotBase64: null,
      automationRequests: <HandrailBugAutomationOption>{
        HandrailBugAutomationOption.autoVerify,
        HandrailBugAutomationOption.deployStaging,
      },
    );

    expect(
      payload.toJson()['automation_requests'],
      <String, Object?>{
        'auto_verify': true,
        'deploy_staging': true,
      },
    );
  });

  test('payload can carry SDK source and structured metadata', () {
    const payload = HandrailBugReportPayload(
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.3.105',
      buildNumber: '217',
      commitSha: 'abc1234',
      platform: 'android',
      deviceModel: null,
      osVersion: null,
      route: '/deployments',
      appBrightness: null,
      title: 'App crashed: StateError',
      description: 'Exception: Bad state',
      severity: 'sev1',
      source: handrailFlutterSdkCrashSource,
      metadata: <String, Object?>{
        'crash_type': 'platform_dispatcher_error',
        'fatal': true,
      },
      profileKey: null,
      screenshotBase64: null,
    );

    expect(payload.toJson(), containsPair('source', 'handrail_flutter_sdk'));
    expect(
      payload.toJson(),
      containsPair(
        'metadata',
        <String, Object?>{
          'crash_type': 'platform_dispatcher_error',
          'fatal': true,
        },
      ),
    );
  });

  test('payload omits unsupported and incomplete reporter assertions', () {
    const config = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'dev',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
    );
    const assertions = <HandrailReporterAssertion>[
      HandrailReporterAssertion(
        version: 2,
        userIdentifier: 'user-123',
        sessionIdentifier: 'session-123',
        verifier: 'session-token',
      ),
      HandrailReporterAssertion(
        userIdentifier: 'user-123',
        sessionIdentifier: '',
        verifier: 'session-token',
      ),
    ];

    for (final assertion in assertions) {
      final payload = HandrailBugReportPayload.fromConfig(
        config: config,
        draft: const HandrailBugReportDraft(
          title: 'Checkout freezes',
          description: 'The checkout screen locks after tapping submit.',
        ),
        device: const HandrailDeviceMetadata(platform: 'ios'),
        profileKey: null,
        reporterAssertion: assertion,
      );

      expect(payload.toJson(), isNot(contains('reporter_assertion')));
    }
  });

  test('payload construction prefers resolved bundle version metadata', () {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.0.87',
      buildNumber: '1',
      commitSha: 'abc1234',
      reportToken: 'report-token',
      routeProvider: _route,
    );

    final payload = HandrailBugReportPayload.fromConfig(
      config: config,
      draft: const HandrailBugReportDraft(
        title: 'Checkout freezes',
        description: 'The checkout screen locks after tapping submit.',
      ),
      device: const HandrailDeviceMetadata(platform: 'ios'),
      profileKey: null,
      appVersion: '1.0.207',
      buildNumber: '207',
    );

    expect(payload.appVersion, '1.0.207');
    expect(payload.buildNumber, '207');
  });

  test('payload construction normalizes and preserves app commit metadata', () {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.0.87',
      buildNumber: '1',
      commitSha: ' configured-sha ',
      reportToken: 'report-token',
      routeProvider: _route,
    );

    final payload = HandrailBugReportPayload.fromConfig(
      config: config,
      draft: const HandrailBugReportDraft(
        title: 'Checkout freezes',
        description: 'The checkout screen locks after tapping submit.',
      ),
      device: const HandrailDeviceMetadata(platform: 'ios'),
      profileKey: null,
      commitSha: ' resolved-sha ',
    );

    expect(payload.commitSha, 'resolved-sha');
    expect(payload.toJson(), containsPair('commit_sha', 'resolved-sha'));

    final fallbackPayload = HandrailBugReportPayload.fromConfig(
      config: config,
      draft: const HandrailBugReportDraft(
        title: 'Checkout freezes',
        description: 'The checkout screen locks after tapping submit.',
      ),
      device: const HandrailDeviceMetadata(platform: 'ios'),
      profileKey: null,
      commitSha: '   ',
    );

    expect(fallbackPayload.commitSha, 'configured-sha');
    expect(
        fallbackPayload.toJson(), containsPair('commit_sha', 'configured-sha'));

    const blankConfig = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.0.87',
      buildNumber: '1',
      commitSha: '   ',
      reportToken: 'report-token',
    );
    final blankPayload = HandrailBugReportPayload.fromConfig(
      config: blankConfig,
      draft: const HandrailBugReportDraft(
        title: 'Checkout freezes',
        description: 'The checkout screen locks after tapping submit.',
      ),
      device: const HandrailDeviceMetadata(platform: 'ios'),
      profileKey: null,
    );

    expect(blankPayload.toJson(), containsPair('commit_sha', null));
  });

  test('payload construction falls back to configured version metadata', () {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.0.87',
      buildNumber: '1',
      commitSha: 'abc1234',
      reportToken: 'report-token',
      routeProvider: _route,
    );

    final payload = HandrailBugReportPayload.fromConfig(
      config: config,
      draft: const HandrailBugReportDraft(
        title: 'Checkout freezes',
        description: 'The checkout screen locks after tapping submit.',
      ),
      device: const HandrailDeviceMetadata(platform: 'ios'),
      profileKey: null,
      appVersion: '   ',
      buildNumber: '',
    );

    expect(payload.appVersion, '1.0.87');
    expect(payload.buildNumber, '1');
  });
}

String? _route() => '/checkout';
