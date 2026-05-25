import 'package:http/http.dart' as http;

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
  })  : status = HandrailBugReportSubmissionStatus.success,
        errorMessage = null;

  const HandrailBugReportSubmissionResult.error({
    required this.statusCode,
    required this.errorMessage,
    this.body = '',
  }) : status = HandrailBugReportSubmissionStatus.error;

  final HandrailBugReportSubmissionStatus status;
  final int? statusCode;
  final String body;
  final String? errorMessage;

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

  Future<HandrailBugReportSubmissionResult> submit(
    HandrailBugReportPayload payload,
  ) async {
    try {
      final response = await _httpClient.post(
        endpoint,
        headers: <String, String>{
          'content-type': 'application/json',
          if (_useBearerToken) 'authorization': 'Bearer $_reportToken',
          if (!_useBearerToken) 'x-handrail-bug-report-token': _reportToken,
        },
        body: payload.encode(),
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
