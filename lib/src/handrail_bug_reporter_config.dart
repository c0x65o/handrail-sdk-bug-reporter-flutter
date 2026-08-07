import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

typedef HandrailProfileKeyProvider = Future<String?> Function();
typedef HandrailUsernameProvider = Future<String?> Function();
typedef HandrailApplicationSessionTokenProvider = Future<String?> Function();
typedef HandrailReporterAssertionProvider = Future<HandrailReporterAssertion?>
    Function();
typedef HandrailRouteProvider = String? Function();

@immutable
class HandrailReporterAssertion {
  const HandrailReporterAssertion({
    this.version = 1,
    required this.userIdentifier,
    required this.sessionIdentifier,
    required this.verifier,
    this.issuedAt,
    this.nonce,
  });

  factory HandrailReporterAssertion.fresh({
    required String userIdentifier,
    required String sessionIdentifier,
    required String verifier,
    DateTime? issuedAt,
    String? nonce,
  }) {
    final random = Random.secure();
    final generatedNonce = base64Url
        .encode(List<int>.generate(24, (_) => random.nextInt(256)))
        .replaceAll('=', '');
    return HandrailReporterAssertion(
      userIdentifier: userIdentifier,
      sessionIdentifier: sessionIdentifier,
      verifier: verifier,
      issuedAt: (issuedAt ?? DateTime.now()).toUtc().toIso8601String(),
      nonce: nonce ?? generatedNonce,
    );
  }

  final int version;
  final String userIdentifier;
  final String sessionIdentifier;
  final String verifier;
  final String? issuedAt;
  final String? nonce;

  bool get isUsable {
    final providedIssuedAt = issuedAt?.trim();
    final providedNonce = nonce?.trim();
    return version == 1 &&
        userIdentifier.trim().isNotEmpty &&
        sessionIdentifier.trim().isNotEmpty &&
        verifier.trim().isNotEmpty &&
        (providedIssuedAt == null ||
            providedIssuedAt.isEmpty ||
            DateTime.tryParse(providedIssuedAt) != null) &&
        (providedNonce == null ||
            providedNonce.isEmpty ||
            RegExp(r'^[A-Za-z0-9_-]{22,200}$').hasMatch(providedNonce));
  }

  Map<String, Object?> toJson() {
    final providedIssuedAt = issuedAt?.trim();
    final providedNonce = nonce?.trim();
    final envelope = HandrailReporterAssertion.fresh(
      userIdentifier: userIdentifier,
      sessionIdentifier: sessionIdentifier,
      verifier: verifier,
      issuedAt: providedIssuedAt == null || providedIssuedAt.isEmpty
          ? null
          : DateTime.parse(providedIssuedAt),
      nonce:
          providedNonce == null || providedNonce.isEmpty ? null : providedNonce,
    );
    return <String, Object?>{
      'version': version,
      'user_identifier': userIdentifier.trim(),
      'session_identifier': sessionIdentifier.trim(),
      'verifier': verifier,
      'issued_at': envelope.issuedAt,
      'nonce': envelope.nonce,
    };
  }
}

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
    this.policyDiscoveryTimeout = const Duration(seconds: 5),
    this.triggers = const HandrailBugReporterTriggers(),
    this.username,
    this.usernameProvider,
    this.profileKeyProvider,
    this.applicationSessionTokenProvider,
    this.reporterAssertionProvider,
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

  /// Best-effort optional-action discovery deadline. Submission is unaffected.
  final Duration policyDiscoveryTimeout;
  final HandrailBugReporterTriggers triggers;
  final String? username;
  final HandrailUsernameProvider? usernameProvider;
  final HandrailProfileKeyProvider? profileKeyProvider;
  final HandrailApplicationSessionTokenProvider?
      applicationSessionTokenProvider;
  @Deprecated(
    'Use applicationSessionTokenProvider. Handrail derives identity from the '
    'server-verified session and ignores claimed user IDs.',
  )
  final HandrailReporterAssertionProvider? reporterAssertionProvider;
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

  Future<String?> resolveUsername() async {
    final provided = await usernameProvider?.call();
    final trimmedProvided = provided?.trim();
    if (trimmedProvided != null && trimmedProvided.isNotEmpty) {
      return trimmedProvided;
    }
    final trimmedUsername = username?.trim();
    return trimmedUsername == null || trimmedUsername.isEmpty
        ? null
        : trimmedUsername;
  }

  Future<String?> resolveApplicationSessionToken() async {
    final token = await applicationSessionTokenProvider?.call();
    final trimmed = token?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  Future<HandrailReporterAssertion?> resolveReporterAssertion() async {
    final assertion = await reporterAssertionProvider?.call();
    return assertion?.isUsable == true ? assertion : null;
  }
}
