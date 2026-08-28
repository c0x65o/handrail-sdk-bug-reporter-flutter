import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _config = HandrailBugReporterConfig(
  projectSlug: 'handrail',
  environment: 'staging',
  appVersion: '1.2.3',
  buildNumber: '42',
  reportToken: 'report-token',
);

void main() {
  testWidgets('openWithResult reports a missing reporter wrapper',
      (tester) async {
    HandrailBugReporterOpenResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  result = await HandrailBugReporter.openWithResult(context);
                },
                child: const Text('Open reporter'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();

    expect(result?.opened, isFalse);
    expect(result?.message, contains('not mounted'));
  });

  testWidgets('availability reports when no navigator can show the sheet',
      (tester) async {
    late BuildContext reporterContext;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: HandrailBugReporter(
          config: _config,
          child: Builder(
            builder: (context) {
              reporterContext = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final availability =
        await HandrailBugReporter.availability(reporterContext);

    expect(availability.canOpen, isFalse);
    expect(availability.blocker, contains('no app navigator'));
  });

  testWidgets('openWithResult opens the reporter from a route context',
      (tester) async {
    HandrailBugReporterOpenResult? result;

    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: _config,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      result =
                          await HandrailBugReporter.openWithResult(context);
                    },
                    child: const Text('Open reporter'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(result?.message, isNull);
    expect(find.text('Report a bug?'), findsOneWidget);

    Navigator.of(tester.element(find.text('Report a bug?'))).pop();
    await tester.pumpAndSettle();

    expect(result?.opened, isTrue);
  });

  testWidgets('restores and reports the shake preference', (tester) async {
    final changes = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: _config,
          initialShakeReportingEnabled: false,
          onShakeReportingChanged: changes.add,
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(find.text('Toggle on to enable'), findsOneWidget);
    expect(find.text('Toggle off to disable'), findsNothing);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(changes, <bool>[true]);
    expect(find.text('Toggle off to disable'), findsOneWidget);
    expect(find.text('Toggle on to enable'), findsNothing);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('description field capitalizes sentences', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: _config,
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => HandrailBugReporter.open(context),
                    child: const Text('Open reporter'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    final descriptionField = tester.widget<EditableText>(
      find.byType(EditableText),
    );
    expect(
      descriptionField.textCapitalization,
      TextCapitalization.sentences,
    );
  });

  testWidgets(
      'notification opt-in appears for a Known User email without an email field',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: HandrailBugReporterConfig(
            projectId: 'project-123',
            environment: 'staging',
            appVersion: '1.2.3',
            buildNumber: '42',
            reportToken: 'report-token',
            policyDiscoveryTimeout: const Duration(milliseconds: 20),
          ),
          clientFactory: (config) => HandrailBugReportClient(
            apiBaseUrl: config.apiBaseUrl,
            endpointPath: config.endpointPath,
            reportToken: config.reportToken,
            httpClient: MockClient((request) async => http.Response(
                  jsonEncode(<String, Object?>{
                    'schema_version': 1,
                    'project_id': 'project-123',
                    'environment': 'staging',
                    'reporter': <String, Object?>{
                      'identity_verified': true,
                      'access_level': 'full_access',
                    },
                    'reporter_notifications': <String, Object?>{
                      'available': true,
                      'recipient_hint': 'a***@example.com',
                      'lifecycles': <String>['fixed'],
                    },
                    'ask_options': <Object?>[],
                  }),
                  200,
                )),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    final notificationLabel = find.text('Email me when this is fixed');
    expect(notificationLabel, findsOneWidget);
    expect(find.textContaining('a***@example.com'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email address'), findsNothing);
    await tester.ensureVisible(notificationLabel);
    await tester.tap(notificationLabel);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Email address'), findsNothing);
  });

  testWidgets(
      'notification opt-in is hidden when Known User email is unavailable',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: const HandrailBugReporterConfig(
            projectId: 'project-123',
            environment: 'staging',
            appVersion: '1.2.3',
            buildNumber: '42',
            reportToken: 'report-token',
            policyDiscoveryTimeout: Duration(milliseconds: 20),
          ),
          clientFactory: (config) => HandrailBugReportClient(
            apiBaseUrl: config.apiBaseUrl,
            endpointPath: config.endpointPath,
            reportToken: config.reportToken,
            httpClient: MockClient((request) async => http.Response(
                  jsonEncode(<String, Object?>{
                    'schema_version': 1,
                    'project_id': 'project-123',
                    'environment': 'staging',
                    'reporter': <String, Object?>{
                      'identity_verified': true,
                      'access_level': 'full_access',
                    },
                    'reporter_notifications': <String, Object?>{
                      'available': false,
                      'recipient_hint': null,
                      'lifecycles': <String>['fixed'],
                    },
                    'ask_options': <Object?>[],
                  }),
                  200,
                )),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    expect(find.text('Email me when this is fixed'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Email address'), findsNothing);
  });

  testWidgets('submitted reports include brightness and selected severity',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, Object?>? submittedPayload;
    http.Request? submittedRequest;
    var assertionProviderCalls = 0;
    var currentSessionIdentifier = 'session-before-open';
    var currentSessionVerifier = 'verifier-before-open';

    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
        home: HandrailBugReporter(
          config: HandrailBugReporterConfig(
            apiBaseUrl: '/api',
            endpointPath: '/mobile-bug-reports',
            projectSlug: 'handrail',
            environment: 'dev',
            appVersion: '1.3.225',
            buildNumber: '1',
            commitSha: ' widget-commit-sha ',
            reportToken: 'report-token',
            usernameProvider: () async => ' widget-user ',
            reporterAssertionProvider: () async {
              assertionProviderCalls += 1;
              return HandrailReporterAssertion.fresh(
                userIdentifier: 'stable-user-123',
                sessionIdentifier: currentSessionIdentifier,
                verifier: currentSessionVerifier,
              );
            },
          ),
          metadataProvider: _FakeMetadataProvider(),
          clientFactory: (config) {
            return HandrailBugReportClient(
              apiBaseUrl: config.apiBaseUrl,
              reportToken: config.reportToken,
              endpointPath: config.endpointPath,
              httpClient: MockClient((request) async {
                submittedRequest = request;
                submittedPayload =
                    jsonDecode(request.body) as Map<String, Object?>;
                return http.Response('{"ok":true}', 201);
              }),
            );
          },
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => HandrailBugReporter.open(context),
                    child: const Text('Open reporter'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();
    expect(find.text('Critical'), findsOneWidget);
    expect(find.text('Moderate'), findsOneWidget);
    expect(find.text('Medium'), findsNothing);
    await tester.tap(find.text('High'));
    await tester.pump();
    expect(
      find.text(
        'App 1.3.225 (1) · Bug reporter SDK ${HandrailBugReporterSdkMetadata.version}',
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byType(TextFormField),
      'The dark mode report sheet looks wrong.',
    );
    await tester.pump();
    currentSessionIdentifier = 'session-at-send';
    currentSessionVerifier = 'verifier-at-send';
    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(sendButton);
    for (var i = 0; i < 10 && submittedPayload == null; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(submittedRequest?.method, 'POST');
    expect(submittedRequest?.url.toString(), '/api/mobile-bug-reports');
    expect(submittedPayload?['app_brightness'], 'dark');
    expect(submittedPayload?['severity'], 'high');
    expect(submittedPayload?['app_version'], '1.3.225');
    expect(submittedPayload?['build_number'], '1');
    expect(submittedPayload?['commit_sha'], 'widget-commit-sha');
    expect(submittedPayload?['username'], 'widget-user');
    expect(assertionProviderCalls, 1);
    expect(
      submittedPayload?['reporter_assertion'],
      allOf(
        containsPair('version', 1),
        containsPair('user_identifier', 'stable-user-123'),
        containsPair('session_identifier', 'session-at-send'),
        containsPair('verifier', 'verifier-at-send'),
        contains('issued_at'),
        contains('nonce'),
      ),
    );
    expect(
      submittedPayload?['reporter_sdk_version'],
      HandrailBugReporterSdkMetadata.version,
    );
    expect(
      submittedPayload?['reporter_sdk_commit'],
      HandrailBugReporterSdkMetadata.commit,
    );
    expect(
      submittedPayload?['reporter_sdk_ref'],
      HandrailBugReporterSdkMetadata.ref,
    );
  });

  testWidgets(
      'role automation policy renders read-only and submission has no deploy controls',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, Object?>? submittedPayload;
    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: _config,
          metadataProvider: _FakeMetadataProvider(),
          clientFactory: (config) => HandrailBugReportClient(
            apiBaseUrl: config.apiBaseUrl,
            reportToken: config.reportToken,
            httpClient: MockClient((request) async {
              if (request.method == 'GET') {
                return http.Response(
                  jsonEncode(<String, Object?>{
                    'schema_version': 1,
                    'project_id': 'project-123',
                    'environment': 'staging',
                    'reporter': <String, Object?>{
                      'identity_verified': true,
                      'access_level': 'user',
                      'role': 'contributor',
                    },
                    'ask_options': const <Object?>[],
                    'automation_policy': <String, Object?>{
                      'schema_version': 3,
                      'automatic_fix_max_risk': 'moderate',
                      'production_max_risk_by_impact': <String, Object?>{
                        'critical': 'moderate',
                        'high': 'low',
                        'moderate': 'none',
                        'low': 'none',
                      },
                    },
                  }),
                  200,
                );
              }
              submittedPayload =
                  jsonDecode(request.body) as Map<String, Object?>;
              return http.Response('{"ok":true}', 201);
            }),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    expect(find.text('Automation policy'), findsOneWidget);
    expect(find.text('Contributor policy'), findsOneWidget);
    expect(find.textContaining('Automatic fix: up to moderate risk'),
        findsOneWidget);
    expect(find.text('Fix and deploy to staging'), findsNothing);
    expect(find.text('Fix and deploy to production'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField),
      'The staging app still shows the broken behavior.',
    );
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(sendButton);
    for (var i = 0; i < 10 && submittedPayload == null; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(submittedPayload?['environment'], 'staging');
    expect(submittedPayload, isNot(contains('automation_requests')));
  });

  testWidgets(
      'policy discovery retries when application identity is still hydrating',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var sessionProviderCalls = 0;
    var policyRequests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: HandrailBugReporterConfig(
            projectId: 'project-123',
            environment: 'staging',
            appVersion: '1.2.3',
            buildNumber: '42',
            reportToken: 'report-token',
            applicationSessionTokenProvider: () async {
              sessionProviderCalls += 1;
              return sessionProviderCalls == 1
                  ? null
                  : 'hydrated-session-token';
            },
          ),
          clientFactory: (config) => HandrailBugReportClient(
            apiBaseUrl: config.apiBaseUrl,
            reportToken: config.reportToken,
            httpClient: MockClient((request) async {
              policyRequests += 1;
              final verified =
                  request.headers['x-handrail-application-session-token'] ==
                      'hydrated-session-token';
              return http.Response(
                jsonEncode(<String, Object?>{
                  'schema_version': 1,
                  'project_id': 'project-123',
                  'environment': 'staging',
                  'reporter': <String, Object?>{
                    'identity_verified': verified,
                    'access_level': verified ? 'full_access' : 'default',
                    'role': verified ? 'maintainer' : null,
                  },
                  'ask_options': const <Object?>[],
                  if (verified)
                    'automation_policy': <String, Object?>{
                      'schema_version': 3,
                      'automatic_fix_max_risk': 'high',
                      'production_max_risk_by_impact': <String, Object?>{
                        'critical': 'moderate',
                        'high': 'low',
                        'moderate': 'none',
                        'low': 'none',
                      },
                    },
                }),
                200,
              );
            }),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    expect(sessionProviderCalls, 2);
    expect(policyRequests, 2);
    expect(find.text('Automation policy'), findsOneWidget);
    expect(find.text('Maintainer policy'), findsOneWidget);
    expect(find.text('Fix and deploy to production'), findsNothing);
  });

  testWidgets(
      'automation options stay hidden when policy has no deploy controls',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: const HandrailBugReporterConfig(
            projectSlug: 'handrail',
            environment: 'production',
            appVersion: '1.2.3',
            buildNumber: '42',
            reportToken: 'report-token',
          ),
          clientFactory: (config) => HandrailBugReportClient(
            apiBaseUrl: config.apiBaseUrl,
            reportToken: config.reportToken,
            httpClient: MockClient((request) async => http.Response(
                  jsonEncode(<String, Object?>{
                    'schema_version': 1,
                    'project_id': 'project-123',
                    'environment': 'production',
                    'reporter': <String, Object?>{
                      'identity_verified': false,
                      'access_level': 'default',
                    },
                    'ask_options': const <Object?>[
                      <String, Object?>{
                        'key': 'deploy_production',
                        'label': 'Fix and deploy to production',
                      },
                    ],
                  }),
                  200,
                )),
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    expect(
      find.text('Optional Handrail actions'),
      findsNothing,
    );
  });

  testWidgets(
      'stalled policy discovery does not leave optional actions loading',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: HandrailBugReporterConfig(
            projectId: 'project-123',
            environment: 'staging',
            appVersion: '1.2.3',
            buildNumber: '42',
            reportToken: 'report-token',
            policyDiscoveryTimeout: const Duration(milliseconds: 20),
            applicationSessionTokenProvider: () => Completer<String?>().future,
          ),
          child: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => HandrailBugReporter.open(context),
                child: const Text('Open reporter'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    expect(find.text('Loading automation policy…'), findsNothing);
    expect(find.text('Optional Handrail actions'), findsNothing);
    expect(find.text('What happened?'), findsOneWidget);
  });

  testWidgets(
      'web preview reports screenshot capture as intentionally unsupported',
      (tester) async {
    if (!kIsWeb) {
      return;
    }

    Map<String, Object?>? submittedPayload;

    await tester.pumpWidget(
      MaterialApp(
        home: HandrailBugReporter(
          config: _config,
          metadataProvider: _FakeMetadataProvider(),
          clientFactory: (config) {
            return HandrailBugReportClient(
              apiBaseUrl: config.apiBaseUrl,
              reportToken: config.reportToken,
              httpClient: MockClient((request) async {
                submittedPayload =
                    jsonDecode(request.body) as Map<String, Object?>;
                return http.Response('{"ok":true}', 201);
              }),
            );
          },
          child: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => HandrailBugReporter.open(context),
                    child: const Text('Open reporter'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open reporter'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report bug'));
    await tester.pumpAndSettle();

    expect(find.text('Screenshot unavailable'), findsOneWidget);
    expect(
      find.text('Screenshot capture is not supported in Flutter web preview.'),
      findsOneWidget,
    );
    expect(find.textContaining('LateError'), findsNothing);

    await tester.enterText(
      find.byType(TextFormField),
      'The preview report needs to submit without screenshot capture.',
    );
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(sendButton);
    for (var i = 0; i < 10 && submittedPayload == null; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(submittedPayload?['screenshot_base64'], isNull);
    expect(
      submittedPayload?['screenshot_capture_error'],
      'Screenshot capture is not supported in Flutter web preview.',
    );
  });
}

class _FakeMetadataProvider extends HandrailDeviceMetadataProvider {
  @override
  Future<HandrailDeviceMetadata> read() async {
    return const HandrailDeviceMetadata(
      platform: 'android',
      deviceModel: 'test-device',
      osVersion: 'test-os',
    );
  }
}
