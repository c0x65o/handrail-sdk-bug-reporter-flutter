import 'dart:convert';

import 'package:http/http.dart' as http;

import 'handrail_bug_automation_policy.dart';
import 'handrail_bug_reporter_payload.dart';

enum HandrailBugReportSubmissionStatus {
  idle,
  submitting,
  success,
  error,
}

class HandrailBugReportSubmissionResult {
  const HandrailBugReportSubmissionResult.success({
    required this.statusCode,
    this.body = '',
    this.notificationSubscribed = false,
    this.notificationWarning,
  })  : status = HandrailBugReportSubmissionStatus.success,
        errorMessage = null;

  const HandrailBugReportSubmissionResult.error({
    required this.statusCode,
    required this.errorMessage,
    this.body = '',
  })  : status = HandrailBugReportSubmissionStatus.error,
        notificationSubscribed = false,
        notificationWarning = null;

  final HandrailBugReportSubmissionStatus status;
  final int? statusCode;
  final String body;
  final String? errorMessage;
  final bool notificationSubscribed;
  final String? notificationWarning;

  bool get isSuccess => status == HandrailBugReportSubmissionStatus.success;
}

class HandrailBugReportClient {
  HandrailBugReportClient({
    required String apiBaseUrl,
    required String reportToken,
    String? endpointPath,
    http.Client? httpClient,
    bool useBearerToken = true,
  })  : _apiBaseUrl = apiBaseUrl,
        _reportToken = reportToken,
        _endpointPath = endpointPath,
        _httpClient = httpClient ?? http.Client(),
        _ownsClient = httpClient == null,
        _useBearerToken = useBearerToken;

  final String _apiBaseUrl;
  final String _reportToken;
  final String? _endpointPath;
  final http.Client _httpClient;
  final bool _ownsClient;
  final bool _useBearerToken;

  Uri get endpoint => _mobileBugReportsEndpoint(
        _apiBaseUrl,
        endpointPath: _endpointPath,
      );

  Future<HandrailBugAutomationPolicy?> loadPolicy({
    required String projectId,
    String? projectSlug,
    required String environment,
    String? applicationSessionToken,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final normalizedProjectId = projectId.trim();
    final normalizedProjectSlug = projectSlug?.trim() ?? '';
    final query = <String, String>{
      'environment': environment.trim(),
      if (normalizedProjectId.isNotEmpty) 'project_id': normalizedProjectId,
      if (normalizedProjectId.isEmpty && normalizedProjectSlug.isNotEmpty)
        'project_slug': normalizedProjectSlug,
    };
    try {
      final response = await _httpClient
          .get(
            endpoint.replace(
              path: '${endpoint.path.replaceFirst(RegExp(r'/+$'), '')}/policy',
              queryParameters: query,
            ),
            headers: _headers(applicationSessionToken: applicationSessionToken),
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      return HandrailBugAutomationPolicy.fromJson(
        Map<String, Object?>.from(decoded),
      );
    } catch (_) {
      // Policy discovery is best-effort. Vanilla bug reporting remains usable.
      return null;
    }
  }

  Future<HandrailBugReportSubmissionResult> submit(
      HandrailBugReportPayload payload,
      {String? applicationSessionToken}) async {
    final result = await submitJson(
      payload.toJson(),
      applicationSessionToken: applicationSessionToken,
    );
    if (!result.isSuccess || !payload.notifyOnResolution) return result;
    final email = payload.notificationEmail?.trim().toLowerCase() ?? '';
    String? bugId;
    try {
      final decoded = jsonDecode(result.body);
      if (decoded is Map) bugId = decoded['bug_id']?.toString().trim();
    } on Object {
      bugId = null;
    }
    if (bugId == null || bugId!.isEmpty || email.isEmpty) {
      return HandrailBugReportSubmissionResult.success(
        statusCode: result.statusCode,
        body: result.body,
        notificationWarning:
            'The report was sent, but update notifications could not be enabled.',
      );
    }
    try {
      final response = await _httpClient.post(
        endpoint.replace(
          path:
              '${endpoint.path.replaceFirst(RegExp(r'/+$'), '')}/bugs/${Uri.encodeComponent(bugId!)}/subscription',
          queryParameters: <String, String>{
            if (payload.projectId?.trim().isNotEmpty == true)
              'project_id': payload.projectId!.trim()
            else if (payload.projectSlug?.trim().isNotEmpty == true)
              'project_slug': payload.projectSlug!.trim(),
            'environment': payload.environment.trim(),
          },
        ),
        headers: _headers(applicationSessionToken: applicationSessionToken),
        body: jsonEncode(<String, Object?>{
          'reporter_surface': 'mobile',
          'reporter_notification': <String, Object?>{
            'email': email,
            'notify_on_resolution': true,
            'consent_version': 'v1',
          },
        }),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return HandrailBugReportSubmissionResult.success(
          statusCode: result.statusCode,
          body: result.body,
          notificationSubscribed: true,
        );
      }
    } on Object {
      // Report acceptance remains successful even when opt-in persistence is
      // temporarily unavailable.
    }
    return HandrailBugReportSubmissionResult.success(
      statusCode: result.statusCode,
      body: result.body,
      notificationWarning:
          'The report was sent, but update notifications could not be enabled.',
    );
  }

  Future<HandrailBugReportSubmissionResult> submitJson(
      Map<String, Object?> payload,
      {String? applicationSessionToken}) async {
    try {
      final response = await _httpClient.post(
        endpoint,
        headers: _headers(applicationSessionToken: applicationSessionToken),
        body: jsonEncode(payload),
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return HandrailBugReportSubmissionResult.success(
          statusCode: response.statusCode,
          body: response.body,
        );
      }
      return HandrailBugReportSubmissionResult.error(
        statusCode: response.statusCode,
        body: response.body,
        errorMessage: response.body.isEmpty
            ? 'Bug report submission failed.'
            : response.body,
      );
    } catch (error) {
      return HandrailBugReportSubmissionResult.error(
        statusCode: null,
        errorMessage: error.toString(),
      );
    }
  }

  Map<String, String> _headers({String? applicationSessionToken}) {
    return <String, String>{
      'content-type': 'application/json',
      if (_useBearerToken) 'authorization': 'Bearer $_reportToken',
      if (!_useBearerToken) 'x-handrail-bug-report-token': _reportToken,
      if (applicationSessionToken?.trim().isNotEmpty == true)
        'x-handrail-application-session-token': applicationSessionToken!.trim(),
    };
  }

  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}

Uri _mobileBugReportsEndpoint(String apiBaseUrl, {String? endpointPath}) {
  final trimmed = apiBaseUrl.trim();
  final base = Uri.parse(trimmed.endsWith('/') ? trimmed : '$trimmed/');
  final configuredEndpoint = endpointPath?.trim();
  final path = configuredEndpoint != null && configuredEndpoint.isNotEmpty
      ? '${base.path}${configuredEndpoint.startsWith('/') ? configuredEndpoint.substring(1) : configuredEndpoint}'
      : base.path.endsWith('/api/')
          ? '${base.path}mobile-bug-reports'
          : '${base.path}api/mobile-bug-reports';
  return base.replace(path: path.replaceAll(RegExp('/+'), '/'));
}
