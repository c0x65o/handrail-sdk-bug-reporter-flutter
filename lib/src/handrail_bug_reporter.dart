import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'handrail_app_build_metadata.dart';
import 'handrail_bug_automation_policy.dart';
import 'handrail_bug_reporter_config.dart';
import 'handrail_bug_reporter_payload.dart';
import 'handrail_bug_reporter_sdk_metadata.dart';
import 'handrail_bug_reporter_submission.dart';
import 'handrail_crash_reporter.dart';
import 'handrail_device_metadata.dart';

const String _webScreenshotUnsupportedReason =
    'Screenshot capture is not supported in Flutter web preview.';
const String _genericScreenshotCaptureFailureReason =
    'Screenshot capture failed before the report opened.';
const List<Duration> _automationPolicyIdentityRetryDelays = <Duration>[
  Duration(milliseconds: 100),
  Duration(milliseconds: 250),
];

class HandrailBugReporter extends StatefulWidget {
  const HandrailBugReporter({
    required this.config,
    required this.child,
    this.clientFactory,
    this.metadataProvider,
    super.key,
  });

  final HandrailBugReporterConfig config;
  final Widget child;
  final HandrailBugReportClient Function(HandrailBugReporterConfig config)?
      clientFactory;
  final HandrailDeviceMetadataProvider? metadataProvider;

  static Future<bool> open(BuildContext context) async {
    final result = await openWithResult(context);
    return result.opened;
  }

  static Future<HandrailBugReporterOpenResult> openWithResult(
    BuildContext context,
  ) async {
    final state = context.findAncestorStateOfType<_HandrailBugReporterState>();
    if (state == null) {
      return const HandrailBugReporterOpenResult.blocked(
        'Bug reporter is not mounted in this part of the app.',
      );
    }
    return state.openReportSheet(sheetContext: context);
  }

  static Future<HandrailBugReporterAvailability> availability(
    BuildContext context,
  ) async {
    final state = context.findAncestorStateOfType<_HandrailBugReporterState>();
    if (state == null) {
      return const HandrailBugReporterAvailability(
        canOpen: false,
        canInstallShakeTrigger: false,
        blocker: 'Bug reporter is not mounted in this part of the app.',
      );
    }
    return state.availability(sheetContext: context);
  }

  static bool visibleEntryEnabled(BuildContext context) {
    final state = context.findAncestorStateOfType<_HandrailBugReporterState>();
    return state?.widget.config.triggers.visibleEntry == true &&
        state?.widget.config.hasSubmissionConfig == true;
  }

  @override
  State<HandrailBugReporter> createState() => _HandrailBugReporterState();
}

@immutable
class HandrailBugReporterOpenResult {
  const HandrailBugReporterOpenResult._({
    required this.opened,
    required this.message,
  });

  const HandrailBugReporterOpenResult.opened()
      : this._(opened: true, message: null);

  const HandrailBugReporterOpenResult.blocked(String message)
      : this._(opened: false, message: message);

  final bool opened;
  final String? message;
}

@immutable
class HandrailBugReporterAvailability {
  const HandrailBugReporterAvailability({
    required this.canOpen,
    required this.canInstallShakeTrigger,
    this.blocker,
    this.shakeBlocker,
  });

  final bool canOpen;
  final bool canInstallShakeTrigger;
  final String? blocker;
  final String? shakeBlocker;
}

class _HandrailBugReporterState extends State<HandrailBugReporter>
    with WidgetsBindingObserver {
  static const EventChannel _iosShakeChannel =
      EventChannel('dev.handrail/bug_reporter/ios_shake');
  static const MethodChannel _screenshotChannel =
      MethodChannel('dev.handrail/bug_reporter/screenshot');
  static const double _maxScreenshotDimension = 1280;
  static const Duration _shakeCooldown = Duration(seconds: 2);
  static const Duration _lifecycleShakeGracePeriod =
      Duration(milliseconds: 900);

  final GlobalKey _boundaryKey = GlobalKey();
  final Set<int> _activePointers = <int>{};
  StreamSubscription<dynamic>? _shakeSubscription;
  Timer? _threeFingerTimer;
  HandrailCrashReporter? _crashReporter;
  DateTime? _lastShakeAt;
  DateTime? _ignoreShakeUntil;
  String? _shakeFailureReason;
  bool _opening = false;
  late bool _shakeReportingEnabled;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _shakeReportingEnabled = widget.config.triggers.shake;
    _ignoreShakeUntil = DateTime.now().add(_lifecycleShakeGracePeriod);
    _syncShakeListener();
    _syncCrashReporter();
  }

  @override
  void didUpdateWidget(covariant HandrailBugReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      if (oldWidget.config.triggers.shake != widget.config.triggers.shake) {
        _shakeReportingEnabled = widget.config.triggers.shake;
      }
      _syncShakeListener();
      _syncCrashReporter();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _crashReporter?.dispose();
    _shakeSubscription?.cancel();
    _threeFingerTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _ignoreShakeUntil = DateTime.now().add(_lifecycleShakeGracePeriod);
    }
  }

  void _syncShakeListener() {
    _shakeSubscription?.cancel();
    _shakeSubscription = null;
    if (!widget.config.canInstallGestureHandlers ||
        !widget.config.triggers.shake ||
        !_shakeReportingEnabled) {
      return;
    }
    _ignoreShakeUntil = DateTime.now().add(_lifecycleShakeGracePeriod);
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _shakeSubscription = _iosShakeChannel.receiveBroadcastStream().listen(
        (_) => _handleShakeDetected(),
        onError: (Object error) {
          _shakeFailureReason = 'iOS shake listener failed.';
        },
      );
      return;
    }
    _shakeSubscription = accelerometerEventStream().listen(
      _handleAccelerometer,
      onError: (Object error) {
        _shakeFailureReason = 'Motion sensor listener failed.';
      },
    );
  }

  void _syncCrashReporter() {
    _crashReporter?.dispose();
    if (!widget.config.hasSubmissionConfig) {
      _crashReporter = null;
      return;
    }
    _crashReporter = HandrailCrashReporter.install(
      config: widget.config,
      metadataProvider:
          widget.metadataProvider ?? HandrailDeviceMetadataProvider(),
      clientFactory: widget.clientFactory,
    );
  }

  void _setShakeReportingEnabled(bool enabled) {
    if (_shakeReportingEnabled == enabled) {
      return;
    }
    setState(() {
      _shakeReportingEnabled = enabled;
    });
    _syncShakeListener();
  }

  void _handleAccelerometer(AccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    if (magnitude < 24) {
      return;
    }
    _handleShakeDetected();
  }

  void _handleShakeDetected() {
    final now = DateTime.now();
    final ignoreShakeUntil = _ignoreShakeUntil;
    if (ignoreShakeUntil != null && now.isBefore(ignoreShakeUntil)) {
      return;
    }
    final lastShakeAt = _lastShakeAt;
    if (lastShakeAt != null && now.difference(lastShakeAt) < _shakeCooldown) {
      return;
    }
    _lastShakeAt = now;
    unawaited(openReportSheet());
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.config.canInstallGestureHandlers ||
        !widget.config.triggers.threeFingerLongPress) {
      return;
    }
    _activePointers.add(event.pointer);
    if (_activePointers.length < 3 || _threeFingerTimer != null) {
      return;
    }
    _threeFingerTimer = Timer(const Duration(milliseconds: 650), () {
      _threeFingerTimer = null;
      if (_activePointers.length >= 3) {
        unawaited(openReportSheet());
      }
    });
  }

  void _handlePointerUp(PointerEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 3) {
      _threeFingerTimer?.cancel();
      _threeFingerTimer = null;
    }
  }

  Future<HandrailBugReporterAvailability> availability({
    BuildContext? sheetContext,
  }) async {
    final configBlocker = await widget.config.openBlocker();
    final targetContext = sheetContext ?? context;
    final navigatorMissing = !targetContext.mounted ||
        Navigator.maybeOf(targetContext, rootNavigator: true) == null;
    final blocker = configBlocker ??
        (navigatorMissing
            ? 'Bug reporter cannot open because no app navigator is available.'
            : null);
    final canInstallShakeTrigger =
        widget.config.canInstallGestureHandlers && _shakeFailureReason == null;
    final shakeBlocker = widget.config.triggers.shake
        ? _shakeFailureReason ??
            (widget.config.canInstallGestureHandlers
                ? null
                : blocker ?? 'Shake reporting is not enabled for this build.')
        : 'Shake reporting is disabled for this build.';

    return HandrailBugReporterAvailability(
      canOpen: blocker == null,
      canInstallShakeTrigger: canInstallShakeTrigger,
      blocker: blocker,
      shakeBlocker: shakeBlocker,
    );
  }

  Future<HandrailBugReporterOpenResult> openReportSheet({
    BuildContext? sheetContext,
  }) async {
    final targetContext = sheetContext ?? context;
    if (_opening) {
      return const HandrailBugReporterOpenResult.blocked(
        'Bug reporter is already opening.',
      );
    }
    if (!mounted || !targetContext.mounted) {
      return const HandrailBugReporterOpenResult.blocked(
        'Bug reporter is not mounted in the current app view.',
      );
    }
    final currentAvailability = await availability(sheetContext: targetContext);
    if (!currentAvailability.canOpen) {
      return HandrailBugReporterOpenResult.blocked(
        currentAvailability.blocker ?? 'Bug reporter is not available.',
      );
    }
    _opening = true;
    try {
      final appBrightness = Theme.of(targetContext).brightness;
      final screenshot = await _captureScreenshot().timeout(
        const Duration(milliseconds: 750),
        onTimeout: () => const _ScreenshotCaptureResult.failure(
          'Screenshot capture timed out before the report opened.',
        ),
      );
      if (!mounted || !targetContext.mounted) {
        return const HandrailBugReporterOpenResult.blocked(
          'Bug reporter closed before the report sheet could open.',
        );
      }
      await showModalBottomSheet<void>(
        context: targetContext,
        useRootNavigator: true,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withValues(alpha: 0.22),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        builder: (context) {
          return _ReportSheet(
            config: widget.config,
            screenshotBase64: screenshot.base64,
            screenshotFilename: screenshot.filename,
            screenshotFailureReason: screenshot.failureReason,
            screenshotMimeType: screenshot.mimeType,
            appBrightness: appBrightness,
            metadataProvider:
                widget.metadataProvider ?? HandrailDeviceMetadataProvider(),
            clientFactory: widget.clientFactory,
            shakeReportingEnabled:
                widget.config.triggers.shake && _shakeReportingEnabled,
            onShakeReportingChanged:
                widget.config.triggers.shake ? _setShakeReportingEnabled : null,
          );
        },
      );
      return const HandrailBugReporterOpenResult.opened();
    } catch (error) {
      return HandrailBugReporterOpenResult.blocked(
        'Bug reporter failed to open.',
      );
    } finally {
      _opening = false;
    }
  }

  Future<_ScreenshotCaptureResult> _captureScreenshot() async {
    if (kIsWeb) {
      return const _ScreenshotCaptureResult.failure(
        _webScreenshotUnsupportedReason,
      );
    }
    const stillRenderingReason =
        'The screen was still rendering when the report opened.';
    try {
      for (var attempt = 0; attempt < 2; attempt += 1) {
        final boundary = _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) {
          return await _captureNativeScreenshot(
            'The app screen was not ready for screenshot capture.',
          );
        }
        if (boundary.debugNeedsPaint) {
          if (attempt == 0) {
            await _waitForEndOfFrame();
            if (!mounted) {
              return const _ScreenshotCaptureResult.failure(
                'The reporter closed before screenshot capture finished.',
              );
            }
            continue;
          }
          return await _captureNativeScreenshot(stillRenderingReason);
        }
        final size = boundary.size;
        final largestSide = math.max(size.width, size.height);
        final pixelRatio = largestSide > _maxScreenshotDimension
            ? _maxScreenshotDimension / largestSide
            : 1.0;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) {
          return await _captureNativeScreenshot(
            'Flutter did not return screenshot image bytes.',
          );
        }
        return _ScreenshotCaptureResult.success(
          base64Encode(bytes.buffer.asUint8List()),
          filename: 'mobile-screenshot.png',
          mimeType: 'image/png',
        );
      }
      return await _captureNativeScreenshot(stillRenderingReason);
    } catch (error) {
      return _captureNativeScreenshot(
        _genericScreenshotCaptureFailureReason,
      );
    }
  }

  Future<void> _waitForEndOfFrame() async {
    try {
      await WidgetsBinding.instance.endOfFrame.timeout(
        const Duration(milliseconds: 250),
      );
    } on TimeoutException {
      // Continue to the fallback path instead of blocking the reporter.
    }
  }

  Future<_ScreenshotCaptureResult> _captureNativeScreenshot(
    String flutterFailureReason,
  ) async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return _ScreenshotCaptureResult.failure(flutterFailureReason);
    }
    try {
      final screenshot =
          await _screenshotChannel.invokeMethod<dynamic>('captureScreenshot');
      final screenshotBase64 = screenshot is Map
          ? screenshot['base64'] as String?
          : screenshot is String
              ? screenshot
              : null;
      if (screenshotBase64 == null || screenshotBase64.isEmpty) {
        return _ScreenshotCaptureResult.failure(flutterFailureReason);
      }
      return _ScreenshotCaptureResult.success(
        screenshotBase64,
        filename: screenshot is Map
            ? screenshot['filename'] as String? ?? 'mobile-screenshot.png'
            : 'mobile-screenshot.png',
        mimeType: screenshot is Map
            ? screenshot['mimeType'] as String? ?? 'image/png'
            : 'image/png',
      );
    } catch (error) {
      return _ScreenshotCaptureResult.failure(
        '$flutterFailureReason Native screenshot fallback was unavailable.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerUp,
      child: RepaintBoundary(
        key: _boundaryKey,
        child: widget.child,
      ),
    );
  }
}

class _ScreenshotCaptureResult {
  const _ScreenshotCaptureResult._({
    required this.base64,
    required this.filename,
    required this.failureReason,
    required this.mimeType,
  });

  const _ScreenshotCaptureResult.success(
    String base64, {
    required String filename,
    required String mimeType,
  }) : this._(
          base64: base64,
          filename: filename,
          failureReason: null,
          mimeType: mimeType,
        );

  const _ScreenshotCaptureResult.failure(String failureReason)
      : this._(
          base64: null,
          filename: null,
          failureReason: failureReason,
          mimeType: null,
        );

  final String? base64;
  final String? filename;
  final String? failureReason;
  final String? mimeType;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.config,
    required this.screenshotBase64,
    required this.screenshotFilename,
    required this.screenshotFailureReason,
    required this.screenshotMimeType,
    required this.appBrightness,
    required this.metadataProvider,
    required this.shakeReportingEnabled,
    this.clientFactory,
    this.onShakeReportingChanged,
  });

  final HandrailBugReporterConfig config;
  final String? screenshotBase64;
  final String? screenshotFilename;
  final String? screenshotFailureReason;
  final String? screenshotMimeType;
  final Brightness appBrightness;
  final HandrailDeviceMetadataProvider metadataProvider;
  final bool shakeReportingEnabled;
  final HandrailBugReportClient Function(HandrailBugReporterConfig config)?
      clientFactory;
  final ValueChanged<bool>? onShakeReportingChanged;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  String _severity = _bugReportSeverityMedium;
  late bool _includeScreenshot;
  final Set<HandrailBugAutomationOption> _automationRequests = {};
  HandrailBugAutomationPolicy? _automationPolicy;
  bool _automationPolicyLoading = true;
  late bool _shakeReportingEnabled;
  HandrailAppBuildMetadata? _buildMetadata;
  bool _showReportForm = false;
  HandrailBugReportSubmissionStatus _status =
      HandrailBugReportSubmissionStatus.idle;
  String? _errorMessage;

  static const int _descriptionMaxLength = 2000;
  static const String _bugReportSeverityHigh = 'High';
  static const String _bugReportSeverityMedium = 'Medium';
  static const String _bugReportSeverityLow = 'Low';
  static const BorderRadius _sheetRadius =
      BorderRadius.all(Radius.circular(36));

  @override
  void initState() {
    super.initState();
    _includeScreenshot = widget.screenshotBase64 != null;
    _shakeReportingEnabled = widget.shakeReportingEnabled;
    _descriptionController.addListener(_handleDescriptionChanged);
    unawaited(_loadBuildMetadata());
    unawaited(_loadAutomationPolicy());
  }

  @override
  void dispose() {
    _descriptionController.removeListener(_handleDescriptionChanged);
    _descriptionController.dispose();
    super.dispose();
  }

  void _handleDescriptionChanged() {
    setState(() {});
  }

  void _setShakeReportingEnabled(bool enabled) {
    widget.onShakeReportingChanged?.call(enabled);
    setState(() {
      _shakeReportingEnabled = enabled;
    });
  }

  Future<void> _loadBuildMetadata() async {
    final metadata = await HandrailAppBuildMetadata.fromConfig(widget.config);
    if (!mounted) return;
    setState(() {
      _buildMetadata = metadata;
    });
  }

  Future<HandrailAppBuildMetadata> _resolveBuildMetadata() async {
    final existing = _buildMetadata;
    if (existing != null) return existing;
    final metadata = await HandrailAppBuildMetadata.fromConfig(widget.config);
    if (mounted) {
      setState(() {
        _buildMetadata = metadata;
      });
    }
    return metadata;
  }

  Future<void> _loadAutomationPolicy() async {
    final client = widget.clientFactory?.call(widget.config) ??
        HandrailBugReportClient(
          apiBaseUrl: widget.config.apiBaseUrl,
          reportToken: widget.config.reportToken,
          endpointPath: widget.config.endpointPath,
        );
    var discoveryActive = true;
    try {
      final policy = await (() async {
        for (var attempt = 0;
            attempt <= _automationPolicyIdentityRetryDelays.length;
            attempt += 1) {
          if (!discoveryActive || !mounted) return null;
          if (attempt > 0) {
            await Future<void>.delayed(
              _automationPolicyIdentityRetryDelays[attempt - 1],
            );
            if (!discoveryActive || !mounted) return null;
          }
          final sessionToken =
              await widget.config.resolveApplicationSessionToken();
          if (!discoveryActive || !mounted) return null;
          final candidate = await client.loadPolicy(
            projectId: widget.config.projectId,
            projectSlug: widget.config.projectSlug,
            environment: widget.config.environment,
            applicationSessionToken: sessionToken,
            timeout: widget.config.policyDiscoveryTimeout,
          );
          if (candidate?.identityVerified == true) return candidate;
          if (widget.config.applicationSessionTokenProvider == null) {
            return null;
          }
        }
        return null;
      })()
          .timeout(widget.config.policyDiscoveryTimeout);
      if (!mounted) return;
      setState(() {
        _automationPolicy = policy;
        _automationPolicyLoading = false;
        _automationRequests.removeWhere(
          (option) => policy?.askOptions.contains(option) != true,
        );
      });
    } catch (_) {
      // Policy discovery must never block vanilla bug reporting.
    } finally {
      discoveryActive = false;
      client.close();
      if (mounted && _automationPolicyLoading) {
        setState(() => _automationPolicyLoading = false);
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _status = HandrailBugReportSubmissionStatus.submitting;
      _errorMessage = null;
    });

    final client = widget.clientFactory?.call(widget.config) ??
        HandrailBugReportClient(
          apiBaseUrl: widget.config.apiBaseUrl,
          reportToken: widget.config.reportToken,
          endpointPath: widget.config.endpointPath,
        );
    try {
      final profileKey = await widget.config.resolveProfileKey();
      final username = await widget.config.resolveUsername();
      final applicationSessionToken =
          await widget.config.resolveApplicationSessionToken();
      final reporterAssertion = await widget.config.resolveReporterAssertion();
      final metadata = await widget.metadataProvider.read();
      final buildMetadata = await _resolveBuildMetadata();
      final result = await client.submit(
        HandrailBugReportPayload.fromConfig(
          config: widget.config,
          draft: HandrailBugReportDraft(
            title: _buildTitle(_descriptionController.text),
            description: _descriptionController.text.trim(),
            severity: _severity,
            screenshotBase64:
                _includeScreenshot ? widget.screenshotBase64 : null,
            screenshotFilename:
                _includeScreenshot ? widget.screenshotFilename : null,
            screenshotMimeType:
                _includeScreenshot ? widget.screenshotMimeType : null,
            screenshotCaptureError: widget.screenshotBase64 == null
                ? widget.screenshotFailureReason
                : null,
            appBrightness: widget.appBrightness.name,
            automationRequests: Set<HandrailBugAutomationOption>.of(
              _automationRequests,
            ),
          ),
          device: metadata,
          profileKey: profileKey,
          reporterAssertion: reporterAssertion,
          username: username,
          appVersion: buildMetadata.appVersion,
          buildNumber: buildMetadata.buildNumber,
          commitSha: buildMetadata.commitSha,
        ),
        applicationSessionToken: applicationSessionToken,
      );
      if (!mounted) {
        return;
      }
      if (result.isSuccess) {
        setState(() => _status = HandrailBugReportSubmissionStatus.success);
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Bug report sent.')),
        );
        return;
      }
      setState(() {
        _status = HandrailBugReportSubmissionStatus.error;
        _errorMessage = result.errorMessage ?? 'Bug report submission failed.';
      });
    } finally {
      client.close();
    }
  }

  String _buildTitle(String description) {
    final normalized = description.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      return 'App issue';
    }
    if (normalized.length <= 80) {
      return normalized;
    }
    return '${normalized.substring(0, 77).trimRight()}...';
  }

  @override
  Widget build(BuildContext context) {
    return _showReportForm ? _buildFormStep(context) : _buildIntroStep(context);
  }

  Widget _buildIntroStep(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final colors = _ReportSheetColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: _sheetRadius,
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.shadow,
              blurRadius: 36,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Report a bug?',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.onSurface,
                    ),
              ),
              const SizedBox(height: 18),
              Text(
                "If something isn't working correctly, you can report it to help improve this app.",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.onSurfaceMuted,
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.primaryButton,
                    foregroundColor: colors.onPrimaryButton,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => setState(() {
                    _showReportForm = true;
                  }),
                  child: const Text(
                    'Report bug',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              if (widget.onShakeReportingChanged != null) ...[
                const SizedBox(height: 28),
                Divider(height: 1, color: colors.divider),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shake device to report a bug',
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Toggle off to disable',
                            style: TextStyle(color: colors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _shakeReportingEnabled,
                      onChanged: _setShakeReportingEnabled,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormStep(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final colors = _ReportSheetColors.of(context);
    final submitting = _status == HandrailBugReportSubmissionStatus.submitting;
    final canSubmit =
        _descriptionController.text.trim().isNotEmpty && !submitting;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(36)),
        ),
        child: Form(
          key: _formKey,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.92,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        'Report app issue',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: colors.onSurface,
                            ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton.filled(
                          tooltip: 'Close',
                          style: IconButton.styleFrom(
                            backgroundColor: colors.controlSurface,
                            foregroundColor: colors.onSurface,
                          ),
                          onPressed: submitting
                              ? null
                              : () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'Severity',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 10),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment<String>(
                        value: _bugReportSeverityHigh,
                        label: Text('High'),
                      ),
                      ButtonSegment<String>(
                        value: _bugReportSeverityMedium,
                        label: Text('Medium'),
                      ),
                      ButtonSegment<String>(
                        value: _bugReportSeverityLow,
                        label: Text('Low'),
                      ),
                    ],
                    selected: <String>{_severity},
                    onSelectionChanged: submitting
                        ? null
                        : (values) {
                            setState(() {
                              _severity = values.first;
                            });
                          },
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'What happened?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    enabled: !submitting,
                    minLines: 7,
                    maxLines: 7,
                    maxLength: _descriptionMaxLength,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Tell us about the issue you encountered',
                      counterText:
                          '${_descriptionController.text.length} / $_descriptionMaxLength',
                      filled: true,
                      fillColor: colors.inputFill,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                    ),
                    validator: (value) {
                      return value == null || value.trim().isEmpty
                          ? 'Tell us what happened.'
                          : null;
                    },
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Any information you share may be reviewed to help improve this app.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colors.onSurfaceMuted,
                          height: 1.25,
                        ),
                  ),
                  if (_automationPolicyLoading) ...[
                    const SizedBox(height: 24),
                    Divider(height: 1, color: colors.divider),
                    const SizedBox(height: 22),
                    Text(
                      'Loading optional actions…',
                      style: TextStyle(color: colors.onSurfaceMuted),
                    ),
                  ] else if (_automationPolicy?.askOptions.isNotEmpty ==
                      true) ...[
                    const SizedBox(height: 24),
                    Divider(height: 1, color: colors.divider),
                    const SizedBox(height: 22),
                    Text(
                      'Optional Handrail actions',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Handrail will still apply project risk and deployment safety rules.',
                      style: TextStyle(color: colors.onSurfaceMuted),
                    ),
                    const SizedBox(height: 10),
                    for (final option in HandrailBugAutomationOption.values)
                      if (_automationPolicy!.askOptions.contains(option))
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.trailing,
                          title: Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                          value: _automationRequests.contains(option),
                          onChanged: submitting
                              ? null
                              : (selected) {
                                  setState(() {
                                    if (selected == true) {
                                      _automationRequests.add(option);
                                    } else {
                                      _automationRequests.remove(option);
                                    }
                                  });
                                },
                        ),
                  ],
                  if (widget.screenshotBase64 != null) ...[
                    const SizedBox(height: 24),
                    Divider(height: 1, color: colors.divider),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Include screenshot in report',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                        ),
                        Switch(
                          value: _includeScreenshot,
                          onChanged: submitting
                              ? null
                              : (value) {
                                  setState(() {
                                    _includeScreenshot = value;
                                  });
                                },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _ScreenshotPreview(
                        screenshotBase64: widget.screenshotBase64!,
                      ),
                    ),
                  ] else if (widget.screenshotFailureReason != null) ...[
                    const SizedBox(height: 24),
                    Divider(height: 1, color: colors.divider),
                    const SizedBox(height: 22),
                    _ScreenshotUnavailable(
                      reason: widget.screenshotFailureReason!,
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 32),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const StadiumBorder(),
                      ),
                      onPressed: canSubmit ? _submit : null,
                      child: submitting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text(
                              'Send',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _buildVersionFooterLabel(),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceMuted,
                          height: 1.2,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _buildVersionFooterLabel() {
    final metadata = _buildMetadata;
    final appVersion = _versionBuildLabel(
      metadata?.appVersion ?? widget.config.appVersion,
      metadata?.buildNumber ?? widget.config.buildNumber,
    );
    return 'App $appVersion · Bug reporter SDK ${HandrailBugReporterSdkMetadata.version}';
  }

  String _versionBuildLabel(String version, String buildNumber) {
    final normalizedVersion =
        version.trim().isEmpty ? 'unknown' : version.trim();
    final normalizedBuild = buildNumber.trim();
    if (normalizedBuild.isEmpty) return normalizedVersion;
    return '$normalizedVersion ($normalizedBuild)';
  }
}

class _ReportSheetColors {
  const _ReportSheetColors({
    required this.surface,
    required this.controlSurface,
    required this.inputFill,
    required this.onSurface,
    required this.onSurfaceMuted,
    required this.border,
    required this.divider,
    required this.shadow,
    required this.primaryButton,
    required this.onPrimaryButton,
  });

  factory _ReportSheetColors.of(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    return _ReportSheetColors(
      surface: colorScheme.surface,
      controlSurface: isDark
          ? Color.alphaBlend(
              colorScheme.onSurface.withValues(alpha: 0.10),
              colorScheme.surface,
            )
          : const Color(0xFFF7F7F7),
      inputFill: isDark
          ? Color.alphaBlend(
              colorScheme.onSurface.withValues(alpha: 0.08),
              colorScheme.surface,
            )
          : const Color(0xFFF4F4F4),
      onSurface: colorScheme.onSurface,
      onSurfaceMuted: colorScheme.onSurface.withValues(alpha: 0.68),
      border:
          colorScheme.outlineVariant.withValues(alpha: isDark ? 0.50 : 0.74),
      divider:
          colorScheme.outlineVariant.withValues(alpha: isDark ? 0.55 : 0.80),
      shadow: Colors.black.withValues(alpha: isDark ? 0.44 : 0.15),
      primaryButton: isDark ? colorScheme.primary : colorScheme.onSurface,
      onPrimaryButton: isDark ? colorScheme.onPrimary : colorScheme.surface,
    );
  }

  final Color surface;
  final Color controlSurface;
  final Color inputFill;
  final Color onSurface;
  final Color onSurfaceMuted;
  final Color border;
  final Color divider;
  final Color shadow;
  final Color primaryButton;
  final Color onPrimaryButton;
}

class _ScreenshotUnavailable extends StatelessWidget {
  const _ScreenshotUnavailable({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = colorScheme.brightness == Brightness.dark;
    final background = isDark
        ? Color.alphaBlend(
            colorScheme.error.withValues(alpha: 0.16),
            colorScheme.surface,
          )
        : const Color(0xFFFFF7E6);
    final border = isDark
        ? colorScheme.error.withValues(alpha: 0.42)
        : const Color(0xFFFFD48A);
    final foreground = isDark ? colorScheme.onSurface : const Color(0xFF6D4700);
    final muted = isDark
        ? colorScheme.onSurface.withValues(alpha: 0.72)
        : const Color(0xFF7A5B20);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Screenshot unavailable',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              reason,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'The report can still be sent without a screenshot.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: muted,
                    height: 1.25,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenshotPreview extends StatelessWidget {
  const _ScreenshotPreview({required this.screenshotBase64});

  final String screenshotBase64;

  @override
  Widget build(BuildContext context) {
    late final Uint8List bytes;
    try {
      bytes = base64Decode(screenshotBase64);
    } catch (_) {
      return const SizedBox.shrink();
    }
    return Container(
      width: 132,
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE6E6E6)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 9 / 19.5,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      ),
    );
  }
}
