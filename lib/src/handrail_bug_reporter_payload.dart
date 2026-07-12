import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'handrail_bug_reporter_config.dart';
import 'handrail_bug_reporter_sdk_metadata.dart';

@immutable
class HandrailDeviceMetadata {
  const HandrailDeviceMetadata({
    required this.platform,
    this.deviceModel,
    this.osVersion,
  });

  final String platform;
  final String? deviceModel;
  final String? osVersion;
}

@immutable
class HandrailBugReportDraft {
  const HandrailBugReportDraft({
    required this.title,
    required this.description,
    this.severity,
    this.source,
    this.metadata = const <String, Object?>{},
    this.screenshotBase64,
    this.screenshotFilename,
    this.screenshotMimeType,
    this.screenshotCaptureError,
    this.appBrightness,
    this.deployFixedAppToStores = false,
  });

  final String title;
  final String description;
  final String? severity;
  final String? source;
  final Map<String, Object?> metadata;
  final String? screenshotBase64;
  final String? screenshotFilename;
  final String? screenshotMimeType;
  final String? screenshotCaptureError;
  final String? appBrightness;
  final bool deployFixedAppToStores;
}

@immutable
class HandrailBugReportPayload {
  const HandrailBugReportPayload({
    required this.projectSlug,
    required this.environment,
    required this.appFlavor,
    required this.appVersion,
    required this.buildNumber,
    required this.commitSha,
    required this.platform,
    required this.deviceModel,
    required this.osVersion,
    required this.route,
    required this.appBrightness,
    required this.title,
    required this.description,
    required this.profileKey,
    required this.screenshotBase64,
    this.deployFixedAppToStores = false,
    this.source,
    this.metadata = const <String, Object?>{},
    this.severity,
    this.screenshotFilename,
    this.screenshotMimeType,
    this.screenshotCaptureError,
    this.reporterSdkVersion = HandrailBugReporterSdkMetadata.version,
    this.reporterSdkCommit = HandrailBugReporterSdkMetadata.commit,
    this.reporterSdkRef = HandrailBugReporterSdkMetadata.ref,
  });

  factory HandrailBugReportPayload.fromConfig({
    required HandrailBugReporterConfig config,
    required HandrailBugReportDraft draft,
    required HandrailDeviceMetadata device,
    required String? profileKey,
    String? appVersion,
    String? buildNumber,
    String? commitSha,
  }) {
    return HandrailBugReportPayload(
      projectSlug: config.projectSlug,
      environment: config.environment,
      appFlavor: config.appFlavor ?? config.environment,
      appVersion: _firstNonBlank(appVersion, config.appVersion),
      buildNumber: _firstNonBlank(buildNumber, config.buildNumber),
      commitSha: _firstNonBlankNullable(commitSha, config.commitSha),
      platform: device.platform,
      deviceModel: device.deviceModel,
      osVersion: device.osVersion,
      route: config.routeProvider?.call(),
      appBrightness: draft.appBrightness,
      title: draft.title,
      description: draft.description,
      severity: draft.severity,
      source: draft.source,
      metadata: draft.metadata,
      profileKey: profileKey,
      screenshotBase64: draft.screenshotBase64,
      screenshotFilename: draft.screenshotFilename,
      screenshotMimeType: draft.screenshotMimeType,
      screenshotCaptureError: draft.screenshotCaptureError,
      deployFixedAppToStores: draft.deployFixedAppToStores,
    );
  }

  final String projectSlug;
  final String environment;
  final String appFlavor;
  final String appVersion;
  final String buildNumber;
  final String? commitSha;
  final String platform;
  final String? deviceModel;
  final String? osVersion;
  final String? route;
  final String? appBrightness;
  final String title;
  final String description;
  final String? severity;
  final String? source;
  final Map<String, Object?> metadata;
  final String? profileKey;
  final String? screenshotBase64;
  final String? screenshotFilename;
  final String? screenshotMimeType;
  final String? screenshotCaptureError;
  final bool deployFixedAppToStores;
  final String reporterSdkVersion;
  final String? reporterSdkCommit;
  final String reporterSdkRef;

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'project_slug': projectSlug,
      'environment': environment,
      'app_flavor': appFlavor,
      'app_version': appVersion,
      'build_number': buildNumber,
      'commit_sha': commitSha,
      'platform': platform,
      'device_model': deviceModel,
      'os_version': osVersion,
      'route': route,
      'app_brightness': appBrightness,
      'title': title,
      'description': description,
      'severity': severity,
      'profile_key': profileKey,
      'screenshot_base64': screenshotBase64,
      'screenshot_filename': screenshotFilename,
      'screenshot_mime_type': screenshotMimeType,
      'screenshot_capture_error': screenshotCaptureError,
      'deploy_fixed_app_to_stores': deployFixedAppToStores,
      'reporter_sdk_version': reporterSdkVersion,
      'reporter_sdk_commit': reporterSdkCommit,
      'reporter_sdk_ref': reporterSdkRef,
    };
    final normalizedSource = source?.trim();
    if (normalizedSource != null && normalizedSource.isNotEmpty) {
      json['source'] = normalizedSource;
    }
    if (metadata.isNotEmpty) {
      json['metadata'] = metadata;
    }
    return json;
  }

  String encode() => jsonEncode(toJson());
}

String _firstNonBlank(String? preferred, String fallback) {
  final normalized = preferred?.trim();
  return normalized != null && normalized.isNotEmpty ? normalized : fallback;
}

String? _firstNonBlankNullable(String? preferred, String? fallback) {
  final normalizedPreferred = preferred?.trim();
  if (normalizedPreferred != null && normalizedPreferred.isNotEmpty) {
    return normalizedPreferred;
  }
  final normalizedFallback = fallback?.trim();
  return normalizedFallback != null && normalizedFallback.isNotEmpty
      ? normalizedFallback
      : null;
}
