import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import 'handrail_bug_reporter_payload.dart';

class HandrailDeviceMetadataProvider {
  HandrailDeviceMetadataProvider({DeviceInfoPlugin? plugin})
      : _plugin = plugin ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _plugin;

  Future<HandrailDeviceMetadata> read() async {
    if (kIsWeb) {
      final info = await _plugin.webBrowserInfo;
      return HandrailDeviceMetadata(
        platform: 'web',
        deviceModel: info.browserName.name,
        osVersion: info.platform,
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        final info = await _plugin.androidInfo;
        return HandrailDeviceMetadata(
          platform: 'android',
          deviceModel: '${info.manufacturer} ${info.model}'.trim(),
          osVersion: 'Android ${info.version.release}',
        );
      case TargetPlatform.iOS:
        final info = await _plugin.iosInfo;
        return HandrailDeviceMetadata(
          platform: 'ios',
          deviceModel: info.utsname.machine,
          osVersion: '${info.systemName} ${info.systemVersion}',
        );
      case TargetPlatform.macOS:
        final info = await _plugin.macOsInfo;
        return HandrailDeviceMetadata(
          platform: 'macos',
          deviceModel: info.model,
          osVersion: info.osRelease,
        );
      case TargetPlatform.windows:
        final info = await _plugin.windowsInfo;
        return HandrailDeviceMetadata(
          platform: 'windows',
          deviceModel: info.computerName,
          osVersion: info.displayVersion,
        );
      case TargetPlatform.linux:
        final info = await _plugin.linuxInfo;
        return HandrailDeviceMetadata(
          platform: 'linux',
          deviceModel: info.prettyName,
          osVersion: info.version,
        );
      case TargetPlatform.fuchsia:
        return const HandrailDeviceMetadata(platform: 'fuchsia');
    }
  }
}
