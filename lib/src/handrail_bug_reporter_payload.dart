import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'handrail_bug_reporter_config.dart';

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
    this.screenshotBase64,
  });

  final String title;
  final String description;
  final String? screenshotBase64;
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
    required this.title,
    required this.description,
    required this.profileKey,
    required this.screenshotBase64,
  });

  factory HandrailBugReportPayload.fromConfig({
    required HandrailBugReporterConfig config,
    required HandrailBugReportDraft draft,
    required HandrailDeviceMetadata device,
    required String? profileKey,
  }) {
    return HandrailBugReportPayload(
      projectSlug: config.projectSlug,
      environment: config.environment,
      appFlavor: config.appFlavor ?? config.environment,
      appVersion: config.appVersion,
      buildNumber: config.buildNumber,
      commitSha: config.commitSha,
      platform: device.platform,
      deviceModel: device.deviceModel,
      osVersion: device.osVersion,
      route: config.routeProvider?.call(),
      title: draft.title,
      description: draft.description,
      profileKey: profileKey,
      screenshotBase64: draft.screenshotBase64,
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
  final String title;
  final String description;
  final String? profileKey;
  final String? screenshotBase64;

  Map<String, Object?> toJson() {
    return <String, Object?>{
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
      'title': title,
      'description': description,
      'profile_key': profileKey,
      'screenshot_base64': screenshotBase64,
    };
  }

  String encode() => jsonEncode(toJson());
}
