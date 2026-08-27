import 'package:flutter/foundation.dart';

@immutable
class HandrailBugSeverityOption {
  const HandrailBugSeverityOption({
    required this.label,
    required this.impact,
    required this.handrailSeverity,
  });

  final String label;
  final HandrailBugImpact impact;
  final HandrailBugSeverity handrailSeverity;
}

enum HandrailBugSeverity {
  sev1,
  sev2,
  sev3,
  sev4;

  String get canonicalValue => name;
}

enum HandrailBugImpact {
  critical(
    label: 'Critical',
    handrailSeverity: HandrailBugSeverity.sev1,
  ),
  high(
    label: 'High',
    handrailSeverity: HandrailBugSeverity.sev2,
  ),
  moderate(
    label: 'Moderate',
    handrailSeverity: HandrailBugSeverity.sev3,
  ),
  low(
    label: 'Low',
    handrailSeverity: HandrailBugSeverity.sev4,
  );

  const HandrailBugImpact({
    required this.label,
    required this.handrailSeverity,
  });

  final String label;
  final HandrailBugSeverity handrailSeverity;

  String get canonicalValue => name;

  HandrailBugSeverityOption get option => HandrailBugSeverityOption(
        label: label,
        impact: this,
        handrailSeverity: handrailSeverity,
      );
}

const handrailBugSeverityOptions = <HandrailBugSeverityOption>[
  HandrailBugSeverityOption(
    label: 'Critical',
    impact: HandrailBugImpact.critical,
    handrailSeverity: HandrailBugSeverity.sev1,
  ),
  HandrailBugSeverityOption(
    label: 'High',
    impact: HandrailBugImpact.high,
    handrailSeverity: HandrailBugSeverity.sev2,
  ),
  HandrailBugSeverityOption(
    label: 'Moderate',
    impact: HandrailBugImpact.moderate,
    handrailSeverity: HandrailBugSeverity.sev3,
  ),
  HandrailBugSeverityOption(
    label: 'Low',
    impact: HandrailBugImpact.low,
    handrailSeverity: HandrailBugSeverity.sev4,
  ),
];

HandrailBugImpact? normalizeHandrailBugImpact(Object? value) {
  if (value is HandrailBugImpact) return value;
  if (value is! String) return null;
  switch (value.trim().toLowerCase()) {
    case 'critical':
    case 'sev1':
      return HandrailBugImpact.critical;
    case 'high':
    case 'sev2':
      return HandrailBugImpact.high;
    case 'moderate':
    case 'medium':
    case 'sev3':
      return HandrailBugImpact.moderate;
    case 'low':
    case 'sev4':
      return HandrailBugImpact.low;
  }
  return null;
}

HandrailBugSeverity? normalizeHandrailBugSeverity(Object? value) =>
    normalizeHandrailBugImpact(value)?.handrailSeverity;

String? handrailBugImpactLabel(Object? value) =>
    normalizeHandrailBugImpact(value)?.label;
