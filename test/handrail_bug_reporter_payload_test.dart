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
    });
  });
}

String? _route() => '/checkout';
