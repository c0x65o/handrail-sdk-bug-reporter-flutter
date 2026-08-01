import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'handrail_app_build_metadata.dart';
import 'handrail_bug_reporter_config.dart';
import 'handrail_bug_reporter_payload.dart';
import 'handrail_bug_reporter_submission.dart';
import 'handrail_device_metadata.dart';

const String handrailFlutterSdkCrashSource = 'handrail_flutter_sdk';
const String _pendingCrashReportsKey =
    'handrail_bug_reporter.pending_crash_reports.v1';
const int _maxPendingCrashReports = 8;

typedef HandrailBugReportClientFactory = HandrailBugReportClient Function(
  HandrailBugReporterConfig config,
);

class HandrailCrashLogBuffer {
  HandrailCrashLogBuffer({this.capacity = 80});

  final int capacity;
  final List<Map<String, Object?>> _entries = <Map<String, Object?>>[];

  void add(
    String message, {
    String level = 'info',
    String? category,
    Map<String, Object?> context = const <String, Object?>{},
    DateTime? at,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty || capacity <= 0) return;
    _entries.add(<String, Object?>{
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'level': _bounded(level, 40),
      if (category != null && category.trim().isNotEmpty)
        'category': _bounded(category, 80),
      'message': _bounded(trimmed, 1000),
      if (context.isNotEmpty) 'context': _normalizeMetadata(context),
    });
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
  }

  List<Map<String, Object?>> snapshot() {
    return _entries
        .map((entry) => Map<String, Object?>.from(entry))
        .toList(growable: false);
  }

  void clear() {
    _entries.clear();
  }
}

class HandrailCrashReporter {
  HandrailCrashReporter({
    required this.config,
    HandrailBugReportClientFactory? clientFactory,
    HandrailDeviceMetadataProvider? metadataProvider,
    HandrailCrashLogBuffer? logBuffer,
    this.captureFlutterErrors = true,
    this.capturePlatformErrors = true,
    this.captureDebugPrint = true,
    this.platformErrorHandledFallback = true,
  })  : clientFactory = clientFactory ?? _defaultClientFactory,
        metadataProvider = metadataProvider ?? HandrailDeviceMetadataProvider(),
        logBuffer = logBuffer ?? _sharedLogBuffer;

  final HandrailBugReporterConfig config;
  final HandrailBugReportClientFactory clientFactory;
  final HandrailDeviceMetadataProvider metadataProvider;
  final HandrailCrashLogBuffer logBuffer;
  final bool captureFlutterErrors;
  final bool capturePlatformErrors;
  final bool captureDebugPrint;
  final bool platformErrorHandledFallback;

  FlutterExceptionHandler? _previousFlutterErrorHandler;
  bool Function(Object error, StackTrace stackTrace)? _previousPlatformHandler;
  DebugPrintCallback? _previousDebugPrint;
  bool _installed = false;
  String? _lastCrashSignature;
  DateTime? _lastCrashAt;

  static final HandrailCrashLogBuffer _sharedLogBuffer =
      HandrailCrashLogBuffer();
  static HandrailCrashReporter? _installedReporter;

  static HandrailCrashReporter install({
    required HandrailBugReporterConfig config,
    HandrailBugReportClientFactory? clientFactory,
    HandrailDeviceMetadataProvider? metadataProvider,
    HandrailCrashLogBuffer? logBuffer,
    bool captureFlutterErrors = true,
    bool capturePlatformErrors = true,
    bool captureDebugPrint = true,
    bool platformErrorHandledFallback = true,
  }) {
    _installedReporter?.dispose();
    final reporter = HandrailCrashReporter(
      config: config,
      clientFactory: clientFactory,
      metadataProvider: metadataProvider,
      logBuffer: logBuffer,
      captureFlutterErrors: captureFlutterErrors,
      capturePlatformErrors: capturePlatformErrors,
      captureDebugPrint: captureDebugPrint,
      platformErrorHandledFallback: platformErrorHandledFallback,
    )..installHandlers();
    _installedReporter = reporter;
    return reporter;
  }

  static void recordLog(
    String message, {
    String level = 'info',
    String? category,
    Map<String, Object?> context = const <String, Object?>{},
  }) {
    (_installedReporter?.logBuffer ?? _sharedLogBuffer).add(
      message,
      level: level,
      category: category,
      context: context,
    );
  }

  void installHandlers() {
    if (_installed) return;
    _installed = true;
    if (captureFlutterErrors) {
      _previousFlutterErrorHandler = FlutterError.onError;
      FlutterError.onError = _handleFlutterError;
    }
    if (capturePlatformErrors) {
      _previousPlatformHandler = ui.PlatformDispatcher.instance.onError;
      ui.PlatformDispatcher.instance.onError = _handlePlatformError;
    }
    if (captureDebugPrint) {
      _previousDebugPrint = debugPrint;
      debugPrint = _handleDebugPrint;
    }
    unawaited(_drainPendingCrashReports());
  }

  void dispose() {
    if (!_installed) return;
    if (captureFlutterErrors) {
      FlutterError.onError = _previousFlutterErrorHandler;
    }
    if (capturePlatformErrors) {
      ui.PlatformDispatcher.instance.onError = _previousPlatformHandler;
    }
    if (captureDebugPrint && _previousDebugPrint != null) {
      debugPrint = _previousDebugPrint!;
    }
    if (identical(_installedReporter, this)) {
      _installedReporter = null;
    }
    _installed = false;
  }

  Future<HandrailBugReportSubmissionResult?> reportError(
    Object error,
    StackTrace stackTrace, {
    String crashType = 'dart_error',
    bool fatal = false,
    bool handled = false,
    String? library,
    String? context,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) async {
    if (!config.hasSubmissionConfig) return null;
    final signature = _crashSignature(error, stackTrace, crashType);
    final now = DateTime.now();
    final lastCrashAt = _lastCrashAt;
    if (_lastCrashSignature == signature &&
        lastCrashAt != null &&
        now.difference(lastCrashAt) < const Duration(seconds: 2)) {
      return null;
    }
    _lastCrashSignature = signature;
    _lastCrashAt = now;

    final recentLogs = logBuffer.snapshot();
    final crashEventId = _newCrashEventId();
    final crashMetadata = <String, Object?>{
      'schema_version': 1,
      'crash_type': crashType,
      'fatal': fatal,
      'handled': handled,
      'library': _nullableBounded(library, 200),
      'context': _nullableBounded(context, 1000),
      'exception_type': error.runtimeType.toString(),
      'exception': _bounded(error.toString(), 4000),
      'stack_trace': stackTrace.toString(),
      'route': config.routeProvider?.call(),
      'captured_at': now.toUtc().toIso8601String(),
      'recent_logs': recentLogs,
      ..._normalizeMetadata(metadata),
      'event_id': crashEventId,
    };

    final preliminaryPayloadJson = _buildCrashPayload(
      error: error,
      stackTrace: stackTrace,
      fatal: fatal,
      context: context,
      recentLogs: recentLogs,
      crashMetadata: crashMetadata,
      device: _fallbackDeviceMetadata(),
      profileKey: null,
      username: config.username,
      appVersion: config.appVersion,
      buildNumber: config.buildNumber,
      commitSha: config.commitSha,
    ).toJson();
    final pendingIdFuture = _storePendingCrashReport(preliminaryPayloadJson);

    final blocker = await config.openBlocker();
    if (blocker != null) {
      final pendingId = await pendingIdFuture;
      if (pendingId != null) {
        await _removePendingCrashReport(pendingId);
      }
      return null;
    }

    final device = await metadataProvider.read();
    final buildMetadata = await HandrailAppBuildMetadata.fromConfig(config);
    final profileKey = await config.resolveProfileKey();
    final username = await config.resolveUsername();
    final payload = _buildCrashPayload(
      error: error,
      stackTrace: stackTrace,
      fatal: fatal,
      context: context,
      recentLogs: recentLogs,
      crashMetadata: crashMetadata,
      device: device,
      profileKey: profileKey,
      username: username,
      appVersion: buildMetadata.appVersion,
      buildNumber: buildMetadata.buildNumber,
      commitSha: buildMetadata.commitSha,
    );
    final payloadJson = payload.toJson();
    final pendingId = await pendingIdFuture;
    if (pendingId != null) {
      await _replacePendingCrashReport(pendingId, payloadJson);
    }
    final client = clientFactory(config);
    try {
      final result = await client.submitJson(payloadJson);
      if (result.isSuccess && pendingId != null) {
        await _removePendingCrashReport(pendingId);
      }
      return result;
    } finally {
      client.close();
    }
  }

  HandrailBugReportPayload _buildCrashPayload({
    required Object error,
    required StackTrace stackTrace,
    required bool fatal,
    required String? context,
    required List<Map<String, Object?>> recentLogs,
    required Map<String, Object?> crashMetadata,
    required HandrailDeviceMetadata device,
    required String? profileKey,
    required String? username,
    required String appVersion,
    required String buildNumber,
    required String? commitSha,
  }) {
    return HandrailBugReportPayload.fromConfig(
      config: config,
      draft: HandrailBugReportDraft(
        title: _crashTitle(error, fatal: fatal),
        description: _crashDescription(
          error,
          stackTrace,
          recentLogs: recentLogs,
          context: context,
        ),
        severity: fatal ? 'sev1' : 'sev2',
        source: handrailFlutterSdkCrashSource,
        metadata: crashMetadata,
      ),
      device: device,
      profileKey: profileKey,
      username: username,
      appVersion: appVersion,
      buildNumber: buildNumber,
      commitSha: commitSha,
    );
  }

  void _handleFlutterError(FlutterErrorDetails details) {
    unawaited(
      reportError(
        details.exception,
        details.stack ?? StackTrace.current,
        crashType: 'flutter_error',
        fatal: false,
        handled: false,
        library: details.library,
        context: details.context?.toDescription(),
        metadata: <String, Object?>{
          'silent': details.silent,
          'information_collector': details.informationCollector != null,
        },
      ),
    );

    final previous = _previousFlutterErrorHandler;
    if (previous != null) {
      previous(details);
    } else {
      FlutterError.presentError(details);
    }
  }

  bool _handlePlatformError(Object error, StackTrace stackTrace) {
    unawaited(
      reportError(
        error,
        stackTrace,
        crashType: 'platform_dispatcher_error',
        fatal: true,
        handled: false,
      ),
    );
    final previous = _previousPlatformHandler;
    if (previous != null) {
      return previous(error, stackTrace);
    }
    return platformErrorHandledFallback;
  }

  void _handleDebugPrint(String? message, {int? wrapWidth}) {
    final text = message?.trim();
    if (text != null && text.isNotEmpty) {
      logBuffer.add(text, level: 'debug', category: 'debugPrint');
    }
    _previousDebugPrint?.call(message, wrapWidth: wrapWidth);
  }

  Future<void> _drainPendingCrashReports() async {
    if (!config.hasSubmissionConfig) return;
    final blocker = await config.openBlocker();
    if (blocker != null) return;

    final entries = await _readPendingCrashReports();
    for (final entry in entries) {
      final id = entry.id;
      final payload = entry.payload;
      final projectId = payload['project_id']?.toString().trim();
      final projectSlug = payload['project_slug']?.toString().trim();
      final environment = payload['environment']?.toString().trim();
      final matchesProject = config.projectId.trim().isNotEmpty
          ? projectId == config.projectId.trim()
          : projectSlug == config.projectSlug.trim();
      if (!matchesProject || environment != config.environment.trim()) {
        await _removePendingCrashReport(id);
        continue;
      }

      final client = clientFactory(config);
      try {
        final result = await client.submitJson(payload);
        if (!result.isSuccess) return;
        await _removePendingCrashReport(id);
      } catch (_) {
        return;
      } finally {
        client.close();
      }
    }
  }
}

String _newCrashEventId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-'
      '${hex(8, 10)}-${hex(10, 16)}';
}

HandrailBugReportClient _defaultClientFactory(
  HandrailBugReporterConfig config,
) {
  return HandrailBugReportClient(
    apiBaseUrl: config.apiBaseUrl,
    reportToken: config.reportToken,
    endpointPath: config.endpointPath,
  );
}

class _PendingCrashReport {
  const _PendingCrashReport({
    required this.id,
    required this.payload,
  });

  final String id;
  final Map<String, Object?> payload;
}

Future<String?> _storePendingCrashReport(Map<String, Object?> payload) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_pendingCrashReportsKey) ?? <String>[];
    final id = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final retained = entries.length >= _maxPendingCrashReports
        ? entries.skip(entries.length - (_maxPendingCrashReports - 1))
        : entries;
    final next = <String>[
      ...retained,
      jsonEncode(<String, Object?>{
        'id': id,
        'payload': payload,
      }),
    ];
    await prefs.setStringList(_pendingCrashReportsKey, next);
    return id;
  } catch (_) {
    return null;
  }
}

Future<List<_PendingCrashReport>> _readPendingCrashReports() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_pendingCrashReportsKey) ?? <String>[];
    final reports = <_PendingCrashReport>[];
    var changed = false;
    for (final encoded in entries) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is! Map) {
          changed = true;
          continue;
        }
        final id = decoded['id']?.toString();
        final payload = decoded['payload'];
        if (id == null || id.isEmpty || payload is! Map) {
          changed = true;
          continue;
        }
        reports.add(
          _PendingCrashReport(
            id: id,
            payload: Map<String, Object?>.from(payload),
          ),
        );
      } catch (_) {
        changed = true;
      }
    }
    if (changed) {
      await prefs.setStringList(
        _pendingCrashReportsKey,
        reports
            .map(
              (report) => jsonEncode(<String, Object?>{
                'id': report.id,
                'payload': report.payload,
              }),
            )
            .toList(growable: false),
      );
    }
    return reports;
  } catch (_) {
    return const <_PendingCrashReport>[];
  }
}

Future<void> _removePendingCrashReport(String id) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_pendingCrashReportsKey) ?? <String>[];
    final next = <String>[];
    for (final encoded in entries) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is Map && decoded['id']?.toString() == id) {
          continue;
        }
      } catch (_) {
        continue;
      }
      next.add(encoded);
    }
    await prefs.setStringList(_pendingCrashReportsKey, next);
  } catch (_) {
    // Persistence is best effort; crash submission should not affect app flow.
  }
}

Future<void> _replacePendingCrashReport(
  String id,
  Map<String, Object?> payload,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_pendingCrashReportsKey) ?? <String>[];
    final replacement = jsonEncode(<String, Object?>{
      'id': id,
      'payload': payload,
    });
    final next = entries
        .map((encoded) {
          try {
            final decoded = jsonDecode(encoded);
            if (decoded is Map && decoded['id']?.toString() == id) {
              return replacement;
            }
          } catch (_) {
            return null;
          }
          return encoded;
        })
        .whereType<String>()
        .toList(growable: false);
    await prefs.setStringList(_pendingCrashReportsKey, next);
  } catch (_) {
    // Persistence is best effort; keep the original pending payload if replace fails.
  }
}

HandrailDeviceMetadata _fallbackDeviceMetadata() {
  if (kIsWeb) {
    return const HandrailDeviceMetadata(platform: 'web');
  }
  return HandrailDeviceMetadata(platform: defaultTargetPlatform.name);
}

String _crashTitle(Object error, {required bool fatal}) {
  final prefix = fatal ? 'Unhandled app error' : 'Flutter error';
  return _bounded('$prefix: ${error.runtimeType}', 240);
}

String _crashDescription(
  Object error,
  StackTrace stackTrace, {
  required List<Map<String, Object?>> recentLogs,
  String? context,
}) {
  final lines = <String>[
    'Exception: ${error.toString()}',
    if (context != null && context.trim().isNotEmpty) 'Context: $context',
    '',
    'Stack trace:',
    stackTrace.toString(),
  ];
  if (recentLogs.isNotEmpty) {
    lines
      ..add('')
      ..add('Recent logs:');
    for (final entry in recentLogs.take(20)) {
      final at = entry['at'];
      final level = entry['level'];
      final category = entry['category'];
      final message = entry['message'];
      lines.add(
        [
          if (at != null) at,
          if (level != null) level,
          if (category != null) category,
          message,
        ].whereType<Object>().join(' '),
      );
    }
  }
  return _bounded(lines.join('\n'), 8000);
}

String _crashSignature(
  Object error,
  StackTrace stackTrace,
  String crashType,
) {
  final stack = stackTrace.toString().split('\n');
  final firstFrame = stack.isNotEmpty ? stack.first : '';
  return '$crashType|${error.runtimeType}|$firstFrame';
}

String _bounded(Object? value, int max) {
  final text = (value ?? '').toString().trim();
  if (text.length <= max) return text;
  return text.substring(0, max);
}

String? _nullableBounded(Object? value, int max) {
  final text = _bounded(value, max);
  return text.isEmpty ? null : text;
}

Map<String, Object?> _normalizeMetadata(Map<String, Object?> metadata) {
  final normalized = <String, Object?>{};
  for (final entry in metadata.entries) {
    final key = entry.key.trim();
    if (key.isEmpty) continue;
    normalized[_bounded(key, 80)] = _normalizeMetadataValue(entry.value);
  }
  return normalized;
}

Object? _normalizeMetadataValue(Object? value) {
  if (value == null || value is num || value is bool) return value;
  if (value is String) return _bounded(value, 2000);
  if (value is Iterable) {
    return value.take(40).map(_normalizeMetadataValue).toList(growable: false);
  }
  if (value is Map) {
    final nested = <String, Object?>{};
    for (final entry in value.entries.take(40)) {
      nested[_bounded(entry.key, 80)] = _normalizeMetadataValue(entry.value);
    }
    return nested;
  }
  return _bounded(value, 2000);
}
