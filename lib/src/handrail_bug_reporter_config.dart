import 'package:flutter/foundation.dart';

typedef HandrailProfileKeyProvider = Future<String?> Function();
typedef HandrailRouteProvider = String? Function();

const String defaultHandrailBugReportApiBaseUrl =
    'https://dashboard.handrail-daas.com/api';

@immutable
class HandrailBugReporterTriggers {
  const HandrailBugReporterTriggers({
    this.shake = true,
    this.threeFingerLongPress = true,
    this.visibleEntry = false,
  });

  const HandrailBugReporterTriggers.disabled()
      : shake = false,
        threeFingerLongPress = false,
        visibleEntry = false;

  final bool shake;
  final bool threeFingerLongPress;
  final bool visibleEntry;

  bool get hasGestureTrigger => shake || threeFingerLongPress;
  bool get hasAnyTrigger => hasGestureTrigger || visibleEntry;
}

@immutable
class HandrailBugReporterConfig {
  const HandrailBugReporterConfig({
    this.projectId = '',
    @Deprecated('Use projectId. Slug-based project lookup is ambiguous.')
    this.projectSlug = '',
    required this.environment,
    required this.appVersion,
    required this.buildNumber,
    required this.reportToken,
    this.apiBaseUrl = defaultHandrailBugReportApiBaseUrl,
    this.endpointPath,
    this.appFlavor,
    this.commitSha,
    this.enabled = true,
    this.allowProductionReporting = true,
    this.triggers = const HandrailBugReporterTriggers(),
    this.profileKeyProvider,
    this.routeProvider,
  });

  factory HandrailBugReporterConfig.disabled() {
    return const HandrailBugReporterConfig(
      apiBaseUrl: '',
      projectId: '',
      environment: '',
      appVersion: '',
      buildNumber: '',
      reportToken: '',
      endpointPath: null,
      enabled: false,
      triggers: HandrailBugReporterTriggers.disabled(),
    );
  }

  final String apiBaseUrl;
  final String projectId;
  @Deprecated('Use projectId. Slug-based project lookup is ambiguous.')
  final String projectSlug;
  final String environment;
  final String appVersion;
  final String buildNumber;
  final String reportToken;
  final String? endpointPath;
  final String? appFlavor;
  final String? commitSha;
  final bool enabled;
  final bool allowProductionReporting;
  final HandrailBugReporterTriggers triggers;
  final HandrailProfileKeyProvider? profileKeyProvider;
  final HandrailRouteProvider? routeProvider;

  bool get isProduction => environment.trim().toLowerCase() == 'production';

  bool get hasSubmissionConfig {
    return enabled &&
        apiBaseUrl.trim().isNotEmpty &&
        (projectId.trim().isNotEmpty || projectSlug.trim().isNotEmpty) &&
        environment.trim().isNotEmpty &&
        reportToken.trim().isNotEmpty;
  }

  bool get canInstallGestureHandlers {
    return hasSubmissionConfig && triggers.hasGestureTrigger;
  }

  Future<String?> openBlocker() async {
    if (!enabled) {
      return 'Bug reporting is disabled for this build.';
    }
    if (apiBaseUrl.trim().isEmpty) {
      return 'Bug reporting is missing the API URL.';
    }
    if (projectId.trim().isEmpty && projectSlug.trim().isEmpty) {
      return 'Bug reporting is missing the project ID.';
    }
    if (environment.trim().isEmpty) {
      return 'Bug reporting is missing the environment.';
    }
    if (reportToken.trim().isEmpty) {
      return 'Bug reporting is missing the public report token.';
    }
    if (!isProduction) {
      return null;
    }
    if (allowProductionReporting) return null;
    final key = await profileKeyProvider?.call();
    if (key != null && key.trim().isNotEmpty) {
      return null;
    }
    return 'Production reporting is blocked because no trusted tester profile key is configured.';
  }

  Future<bool> canOpenReporter() async {
    return await openBlocker() == null;
  }

  Future<String?> resolveProfileKey() async {
    final key = await profileKeyProvider?.call();
    final trimmed = key?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
