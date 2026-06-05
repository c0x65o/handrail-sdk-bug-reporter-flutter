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

  testWidgets('submitted reports include brightness and selected severity',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, Object?>? submittedPayload;

    await tester.pumpWidget(
      MaterialApp(
        themeMode: ThemeMode.dark,
        darkTheme: ThemeData.dark(),
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
    await tester.tap(find.text('High'));
    await tester.pump();
    await tester.enterText(
      find.byType(TextFormField),
      'The dark mode report sheet looks wrong.',
    );
    await tester.pump();
    final sendButton = find.widgetWithText(FilledButton, 'Send');
    await tester.ensureVisible(sendButton);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(sendButton);
    for (var i = 0; i < 10 && submittedPayload == null; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(submittedPayload?['app_brightness'], 'dark');
    expect(submittedPayload?['severity'], 'sev2');
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
