import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';

void main() {
  test('trigger configuration exposes gesture and visible entry state', () {
    const triggers = HandrailBugReporterTriggers(
      shake: true,
      threeFingerLongPress: false,
      visibleEntry: true,
    );

    expect(triggers.hasGestureTrigger, isTrue);
    expect(triggers.hasAnyTrigger, isTrue);

    const disabled = HandrailBugReporterTriggers.disabled();
    expect(disabled.hasGestureTrigger, isFalse);
    expect(disabled.hasAnyTrigger, isFalse);
  });

  test('environment gating allows non-production with token config', () async {
    const config = HandrailBugReporterConfig(
      projectSlug: 'handrail',
      environment: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
    );

    expect(config.hasSubmissionConfig, isTrue);
    expect(config.apiBaseUrl, defaultHandrailBugReportApiBaseUrl);
    expect(await config.canOpenReporter(), isTrue);
  });

  test('environment gating allows production by default', () async {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'production',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
    );

    expect(await config.canOpenReporter(), isTrue);
  });

  test('environment gating can still require a production policy or profile key',
      () async {
    const config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'production',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      allowProductionReporting: false,
    );

    expect(await config.canOpenReporter(), isFalse);
    expect(
      await config.openBlocker(),
      'Production reporting is blocked because no trusted tester profile key is configured.',
    );
  });

  test('profile key callback trims production reporter profile keys', () async {
    var callbackCalls = 0;
    final config = HandrailBugReporterConfig(
      apiBaseUrl: 'https://example.test/api',
      projectSlug: 'handrail',
      environment: 'production',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      allowProductionReporting: true,
      profileKeyProvider: () async {
        callbackCalls += 1;
        return ' trusted-profile ';
      },
    );

    expect(await config.canOpenReporter(), isTrue);
    expect(await config.resolveProfileKey(), 'trusted-profile');
    expect(callbackCalls, 1);
  });
}
