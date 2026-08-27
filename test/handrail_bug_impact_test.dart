import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';

void main() {
  test('bug severity contract uses canonical impact and Handrail severity', () {
    expect(
      handrailBugSeverityOptions
          .map(
            (option) => <String>[
              option.label,
              option.impact.canonicalValue,
              option.handrailSeverity.canonicalValue,
            ],
          )
          .toList(),
      <List<String>>[
        <String>['Critical', 'critical', 'sev1'],
        <String>['High', 'high', 'sev2'],
        <String>['Moderate', 'moderate', 'sev3'],
        <String>['Low', 'low', 'sev4'],
      ],
    );

    expect(normalizeHandrailBugImpact('critical'), HandrailBugImpact.critical);
    expect(normalizeHandrailBugImpact('High'), HandrailBugImpact.high);
    expect(normalizeHandrailBugImpact('medium'), HandrailBugImpact.moderate);
    expect(normalizeHandrailBugImpact('sev3'), HandrailBugImpact.moderate);
    expect(normalizeHandrailBugImpact('sev4'), HandrailBugImpact.low);
    expect(
      normalizeHandrailBugSeverity('moderate'),
      HandrailBugSeverity.sev3,
    );
    expect(handrailBugImpactLabel('sev3'), 'Moderate');
  });

  test('typed and legacy payload inputs both serialize canonical impact', () {
    final typed = _payload(
      impact: HandrailBugImpact.critical,
    );
    final legacy = _payload(
      severity: 'sev3',
    );

    expect(typed.toJson()['severity'], 'critical');
    expect(legacy.toJson()['severity'], 'moderate');
  });
}

HandrailBugReportPayload _payload({
  HandrailBugImpact? impact,
  String? severity,
}) =>
    HandrailBugReportPayload(
      environment: 'staging',
      appFlavor: 'staging',
      appVersion: '1.0.0',
      buildNumber: '1',
      commitSha: null,
      platform: 'test',
      deviceModel: null,
      osVersion: null,
      route: null,
      appBrightness: null,
      title: 'Impact contract',
      description: 'Payload normalization test.',
      profileKey: null,
      screenshotBase64: null,
      impact: impact,
      severity: severity,
    );
