import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';

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
    await tester.pumpAndSettle();

    expect(find.text('Report a bug?'), findsOneWidget);

    Navigator.of(tester.element(find.text('Report a bug?'))).pop();
    await tester.pumpAndSettle();

    expect(result?.opened, isTrue);
  });
}
