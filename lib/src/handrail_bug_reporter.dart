import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'handrail_bug_reporter_config.dart';
import 'handrail_bug_reporter_payload.dart';
import 'handrail_bug_reporter_submission.dart';
import 'handrail_device_metadata.dart';

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
    final state = context.findAncestorStateOfType<_HandrailBugReporterState>();
    return state?.openReportSheet() ?? Future<bool>.value(false);
  }

  static bool visibleEntryEnabled(BuildContext context) {
    final state = context.findAncestorStateOfType<_HandrailBugReporterState>();
    return state?.widget.config.triggers.visibleEntry == true &&
        state?.widget.config.hasSubmissionConfig == true;
  }

  @override
  State<HandrailBugReporter> createState() => _HandrailBugReporterState();
}

class _HandrailBugReporterState extends State<HandrailBugReporter> {
  final GlobalKey _boundaryKey = GlobalKey();
  final Set<int> _activePointers = <int>{};
  StreamSubscription<AccelerometerEvent>? _shakeSubscription;
  Timer? _threeFingerTimer;
  DateTime? _lastShakeAt;
  bool _opening = false;
  late bool _shakeReportingEnabled;

  @override
  void initState() {
    super.initState();
    _shakeReportingEnabled = widget.config.triggers.shake;
    _syncShakeListener();
  }

  @override
  void didUpdateWidget(covariant HandrailBugReporter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.config != widget.config) {
      if (oldWidget.config.triggers.shake != widget.config.triggers.shake) {
        _shakeReportingEnabled = widget.config.triggers.shake;
      }
      _syncShakeListener();
    }
  }

  @override
  void dispose() {
    _shakeSubscription?.cancel();
    _threeFingerTimer?.cancel();
    super.dispose();
  }

  void _syncShakeListener() {
    _shakeSubscription?.cancel();
    _shakeSubscription = null;
    if (!widget.config.canInstallGestureHandlers ||
        !widget.config.triggers.shake ||
        !_shakeReportingEnabled) {
      return;
    }
    _shakeSubscription =
        accelerometerEventStream().listen(_handleAccelerometer);
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
    final now = DateTime.now();
    final lastShakeAt = _lastShakeAt;
    if (lastShakeAt != null &&
        now.difference(lastShakeAt) < const Duration(seconds: 2)) {
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

  Future<bool> openReportSheet() async {
    if (_opening || !mounted || !await widget.config.canOpenReporter()) {
      return false;
    }
    _opening = true;
    try {
      final screenshot = await _captureScreenshot();
      if (!mounted) {
        return false;
      }
      await showModalBottomSheet<void>(
        context: context,
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
            screenshotFailureReason: screenshot.failureReason,
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
      return true;
    } finally {
      _opening = false;
    }
  }

  Future<_ScreenshotCaptureResult> _captureScreenshot() async {
    const stillRenderingReason =
        'The screen was still rendering when the report opened.';
    try {
      for (var attempt = 0; attempt < 2; attempt += 1) {
        final boundary = _boundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary == null) {
          return const _ScreenshotCaptureResult.failure(
            'The app screen was not ready for screenshot capture.',
          );
        }
        if (boundary.debugNeedsPaint) {
          if (attempt == 0) {
            await WidgetsBinding.instance.endOfFrame;
            if (!mounted) {
              return const _ScreenshotCaptureResult.failure(
                'The reporter closed before screenshot capture finished.',
              );
            }
            continue;
          }
          return const _ScreenshotCaptureResult.failure(stillRenderingReason);
        }
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        if (bytes == null) {
          return const _ScreenshotCaptureResult.failure(
            'Flutter did not return screenshot image bytes.',
          );
        }
        return _ScreenshotCaptureResult.success(
          base64Encode(bytes.buffer.asUint8List()),
        );
      }
      return const _ScreenshotCaptureResult.failure(stillRenderingReason);
    } catch (error) {
      return _ScreenshotCaptureResult.failure(
        'Screenshot capture failed: ${error.runtimeType}.',
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
    required this.failureReason,
  });

  const _ScreenshotCaptureResult.success(String base64)
      : this._(base64: base64, failureReason: null);

  const _ScreenshotCaptureResult.failure(String failureReason)
      : this._(base64: null, failureReason: failureReason);

  final String? base64;
  final String? failureReason;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.config,
    required this.screenshotBase64,
    required this.screenshotFailureReason,
    required this.metadataProvider,
    required this.shakeReportingEnabled,
    this.clientFactory,
    this.onShakeReportingChanged,
  });

  final HandrailBugReporterConfig config;
  final String? screenshotBase64;
  final String? screenshotFailureReason;
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
  late bool _includeScreenshot;
  late bool _shakeReportingEnabled;
  bool _showReportForm = false;
  HandrailBugReportSubmissionStatus _status =
      HandrailBugReportSubmissionStatus.idle;
  String? _errorMessage;

  static const int _descriptionMaxLength = 2000;
  static const BorderRadius _sheetRadius =
      BorderRadius.all(Radius.circular(36));

  @override
  void initState() {
    super.initState();
    _includeScreenshot = widget.screenshotBase64 != null;
    _shakeReportingEnabled = widget.shakeReportingEnabled;
    _descriptionController.addListener(_handleDescriptionChanged);
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
        );
    try {
      final profileKey = await widget.config.resolveProfileKey();
      final metadata = await widget.metadataProvider.read();
      final result = await client.submit(
        HandrailBugReportPayload.fromConfig(
          config: widget.config,
          draft: HandrailBugReportDraft(
            title: _buildTitle(_descriptionController.text),
            description: _descriptionController.text.trim(),
            screenshotBase64:
                _includeScreenshot ? widget.screenshotBase64 : null,
            screenshotCaptureError: widget.screenshotBase64 == null
                ? widget.screenshotFailureReason
                : null,
          ),
          device: metadata,
          profileKey: profileKey,
        ),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, 18 + bottomInset),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: _sheetRadius,
          border: Border.all(color: Colors.white.withValues(alpha: 0.74)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
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
                      color: Colors.black,
                    ),
              ),
              const SizedBox(height: 18),
              Text(
                "If something isn't working correctly, you can report it to help improve this app.",
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: const Color(0xFF606060),
                      height: 1.25,
                    ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
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
                const Divider(height: 1, color: Color(0xFFE8E8E8)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Shake device to report a bug',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Toggle off to disable',
                            style: TextStyle(color: Color(0xFF606060)),
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
    final submitting = _status == HandrailBugReportSubmissionStatus.submitting;
    final canSubmit =
        _descriptionController.text.trim().isNotEmpty && !submitting;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
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
                            ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton.filled(
                          tooltip: 'Close',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFFF7F7F7),
                            foregroundColor: Colors.black,
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
                    'What happened?',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    enabled: !submitting,
                    minLines: 7,
                    maxLines: 7,
                    maxLength: _descriptionMaxLength,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Tell us about the issue you encountered',
                      counterText:
                          '${_descriptionController.text.length} / $_descriptionMaxLength',
                      filled: true,
                      fillColor: const Color(0xFFF4F4F4),
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
                          color: Colors.black54,
                          height: 1.25,
                        ),
                  ),
                  if (widget.screenshotBase64 != null) ...[
                    const SizedBox(height: 24),
                    const Divider(height: 1),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Include screenshot in report',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w500,
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
                    const Divider(height: 1),
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ScreenshotUnavailable extends StatelessWidget {
  const _ScreenshotUnavailable({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        border: Border.all(color: const Color(0xFFFFD48A)),
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
                    color: const Color(0xFF6D4700),
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              reason,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6D4700),
                    height: 1.25,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'The report can still be sent without a screenshot.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF7A5B20),
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
