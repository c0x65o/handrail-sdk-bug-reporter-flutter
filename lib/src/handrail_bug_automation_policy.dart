import 'package:flutter/foundation.dart';

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
    required this.notificationAvailable,
    this.notificationRecipientHint,
  });

  factory HandrailBugAutomationPolicy.fromJson(Map<String, Object?> json) {
    final reporter = json['reporter'];
    final reporterJson = reporter is Map
        ? Map<String, Object?>.from(reporter)
        : const <String, Object?>{};
    final rawOptions = json['ask_options'];
    final notification = json['reporter_notifications'];
    final notificationJson = notification is Map
        ? Map<String, Object?>.from(notification)
        : const <String, Object?>{};
    final askOptions = <HandrailBugAutomationOption>{};
    if (rawOptions is List) {
      for (final rawOption in rawOptions) {
        final optionJson = rawOption is Map
            ? Map<String, Object?>.from(rawOption)
            : const <String, Object?>{};
        final option = HandrailBugAutomationOption.fromKey(optionJson['key']);
        if (option != null) askOptions.add(option);
      }
    }
    return HandrailBugAutomationPolicy(
      schemaVersion:
          json['schema_version'] is int ? json['schema_version']! as int : 1,
      projectId: json['project_id']?.toString() ?? '',
      environment: json['environment']?.toString() ?? '',
      identityVerified: reporterJson['identity_verified'] == true,
      accessLevel: reporterJson['access_level']?.toString() ?? 'default',
      askOptions: Set<HandrailBugAutomationOption>.unmodifiable(askOptions),
      notificationAvailable: notificationJson['available'] == true,
      notificationRecipientHint:
          notificationJson['recipient_hint']?.toString(),
    );
  }

  final int schemaVersion;
  final String projectId;
  final String environment;
  final bool identityVerified;
  final String accessLevel;
  final Set<HandrailBugAutomationOption> askOptions;
  final bool notificationAvailable;
  final String? notificationRecipientHint;
}
