import 'package:package_info_plus/package_info_plus.dart';

import 'handrail_bug_reporter_config.dart';

const Duration _packageInfoLookupTimeout = Duration(milliseconds: 500);

class HandrailAppBuildMetadata {
  const HandrailAppBuildMetadata({
    required this.appVersion,
    required this.buildNumber,
  });

  final String appVersion;
  final String buildNumber;

  static Future<HandrailAppBuildMetadata> fromConfig(
    HandrailBugReporterConfig config,
  ) async {
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        _packageInfoLookupTimeout,
      );
      return HandrailAppBuildMetadata(
        appVersion: _firstNonBlank(info.version, config.appVersion),
        buildNumber: _firstNonBlank(info.buildNumber, config.buildNumber),
      );
    } catch (_) {
      return HandrailAppBuildMetadata(
        appVersion: config.appVersion,
        buildNumber: config.buildNumber,
      );
    }
  }
}

String _firstNonBlank(String preferred, String fallback) {
  final normalized = preferred.trim();
  return normalized.isNotEmpty ? normalized : fallback;
}
