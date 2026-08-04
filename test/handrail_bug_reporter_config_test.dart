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
      projectId: 'project-123',
      environment: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
    );

    expect(config.hasSubmissionConfig, isTrue);
    expect(config.projectId, 'project-123');
    expect(config.apiBaseUrl, defaultHandrailBugReportApiBaseUrl);
    expect(await config.canOpenReporter(), isTrue);
  });

  test('missing project configuration reports a project ID blocker', () async {
    const config = HandrailBugReporterConfig(
      environment: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
    );

    expect(config.hasSubmissionConfig, isFalse);
    expect(
        await config.openBlocker(), 'Bug reporting is missing the project ID.');
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

  test(
      'environment gating can still require a production policy or profile key',
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

  test('username resolution trims provider values and falls back to config',
      () async {
    final providerConfig = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      username: 'fallback-user',
      usernameProvider: () async => ' current-user ',
    );
    const fallbackConfig = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'staging',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      username: ' fallback-user ',
    );

    expect(await providerConfig.resolveUsername(), 'current-user');
    expect(await fallbackConfig.resolveUsername(), 'fallback-user');
  });

  test(
      'reporter assertion provider accepts only the supported complete version',
      () async {
    final valid = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'dev',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      reporterAssertionProvider: () async => const HandrailReporterAssertion(
        userIdentifier: 'user-123',
        sessionIdentifier: 'session-123',
        verifier: 'session-token',
        issuedAt: '2026-08-03T12:00:00.000Z',
        nonce: 'assertion-nonce-1234567890',
      ),
    );
    final unsupported = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'dev',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      reporterAssertionProvider: () async => const HandrailReporterAssertion(
        version: 2,
        userIdentifier: 'user-123',
        sessionIdentifier: 'session-123',
        verifier: 'session-token',
        issuedAt: '2026-08-03T12:00:00.000Z',
        nonce: 'assertion-nonce-1234567890',
      ),
    );
    final incomplete = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'dev',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      reporterAssertionProvider: () async => const HandrailReporterAssertion(
        userIdentifier: 'user-123',
        sessionIdentifier: '',
        verifier: 'session-token',
      ),
    );

    expect(
      (await valid.resolveReporterAssertion())?.toJson(),
      <String, Object?>{
        'version': 1,
        'user_identifier': 'user-123',
        'session_identifier': 'session-123',
        'verifier': 'session-token',
        'issued_at': '2026-08-03T12:00:00.000Z',
        'nonce': 'assertion-nonce-1234567890',
      },
    );
    expect(await unsupported.resolveReporterAssertion(), isNull);
    expect(await incomplete.resolveReporterAssertion(), isNull);
  });

  test('fresh reporter assertions rotate replay-resistant proof fields', () {
    final first = HandrailReporterAssertion.fresh(
      userIdentifier: 'user-123',
      sessionIdentifier: 'session-123',
      verifier: 'session-token',
    );
    final second = HandrailReporterAssertion.fresh(
      userIdentifier: 'user-123',
      sessionIdentifier: 'session-123',
      verifier: 'session-token',
    );

    expect(first.isUsable, isTrue);
    expect(second.isUsable, isTrue);
    expect(first.nonce, isNot(second.nonce));
    expect(DateTime.tryParse(first.issuedAt!), isNotNull);
  });

  test('application session token provider resolves current transport proof',
      () async {
    final config = HandrailBugReporterConfig(
      projectId: 'project-123',
      environment: 'dev',
      appVersion: '1.2.3',
      buildNumber: '42',
      reportToken: 'report-token',
      applicationSessionTokenProvider: () async => ' current-session ',
    );

    expect(
      await config.resolveApplicationSessionToken(),
      'current-session',
    );
  });
}
