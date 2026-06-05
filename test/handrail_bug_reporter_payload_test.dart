import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';

void main() {
  test('payload construction includes route, version, device, and profile key',
      () {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.3.105',
      buildNumber: '217',
      commitSha: 'abc1234',
      reportToken: 'report-token',
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
      ),
      device: const HandrailDeviceMetadata(
        platform: 'ios',
        deviceModel: 'iPhone 15',
        osVersion: 'iOS 18.1',
      ),
      profileKey: 'profile-key',
    );

    expect(payload.toJson(), <String, Object?>{
      'project_slug': 'handrail',
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
      'screenshot_base64': 'png-base64',
      'screenshot_filename': 'mobile-screenshot.png',
      'screenshot_mime_type': 'image/png',
      'screenshot_capture_error': null,
      'reporter_sdk_version': HandrailBugReporterSdkMetadata.version,
      'reporter_sdk_commit': HandrailBugReporterSdkMetadata.commit,
      'reporter_sdk_ref': HandrailBugReporterSdkMetadata.ref,
    });
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
