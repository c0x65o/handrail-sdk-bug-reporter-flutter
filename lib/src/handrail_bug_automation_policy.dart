import 'package:flutter/foundation.dart';

@Deprecated('Bug reporters no longer select automation or deployment.')
enum HandrailBugAutomationOption {
  autoVerify('auto_verify', 'Verify this issue'),
  repairProposal('repair_proposal', 'Prepare a repair proposal'),
  fix('fix', 'Fix this issue'),
  deployStaging('deploy_staging', 'Fix and deploy to staging'),
  deployProduction('deploy_production', 'Fix and deploy to production');

  const HandrailBugAutomationOption(this.key, this.label);

  final String key;
  final String label;

  static HandrailBugAutomationOption? fromKey(Object? value) {
    for (final option in values) {
      if (option.key == value) return option;
    }
    return null;
  }
}

@immutable
class HandrailBugAutomationPolicy {
  const HandrailBugAutomationPolicy({
    required this.schemaVersion,
    required this.projectId,
    required this.environment,
    required this.identityVerified,
    required this.accessLevel,
    required this.askOptions,
    this.role,
    this.automaticFixMaxRisk,
    this.productionMaxRiskByImpact = const <String, String>{},
    required this.notificationAvailable,
    this.notificationRecipientHint,
  });

  factory HandrailBugAutomationPolicy.fromJson(Map<String, Object?> json) {
    final reporter = json['reporter'];
    final reporterJson = reporter is Map
        ? Map<String, Object?>.from(reporter)
        : const <String, Object?>{};
    final notification = json['reporter_notifications'];
    final notificationJson = notification is Map
        ? Map<String, Object?>.from(notification)
        : const <String, Object?>{};
    final automationPolicy = json['automation_policy'];
    final automationPolicyJson = automationPolicy is Map
        ? Map<String, Object?>.from(automationPolicy)
        : const <String, Object?>{};
    final productionPolicy =
        automationPolicyJson['production_max_risk_by_impact'];
    final productionPolicyJson = productionPolicy is Map
        ? Map<String, Object?>.from(productionPolicy)
        : const <String, Object?>{};
    return HandrailBugAutomationPolicy(
      schemaVersion:
          json['schema_version'] is int ? json['schema_version']! as int : 1,
      projectId: json['project_id']?.toString() ?? '',
      environment: json['environment']?.toString() ?? '',
      identityVerified: reporterJson['identity_verified'] == true,
      accessLevel: reporterJson['access_level']?.toString() ?? 'default',
      role: reporterJson['role']?.toString(),
      askOptions: const <HandrailBugAutomationOption>{},
      automaticFixMaxRisk:
          automationPolicyJson['automatic_fix_max_risk']?.toString(),
      productionMaxRiskByImpact: Map<String, String>.unmodifiable({
        for (final entry in productionPolicyJson.entries)
          entry.key: entry.value.toString(),
      }),
      notificationAvailable: notificationJson['available'] == true,
      notificationRecipientHint: notificationJson['recipient_hint']?.toString(),
    );
  }

  final int schemaVersion;
  final String projectId;
  final String environment;
  final bool identityVerified;
  final String accessLevel;
  final String? role;
  final Set<HandrailBugAutomationOption> askOptions;
  final String? automaticFixMaxRisk;
  final Map<String, String> productionMaxRiskByImpact;
  final bool notificationAvailable;
  final String? notificationRecipientHint;
}
