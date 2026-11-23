import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
import 'package:handrail_bug_reporter/src/handrail_bug_history.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final owner in [false, true]) {
    testWidgets('shared and owner history, owner=$owner', (tester) async {
      var posts = 0;
      final config = HandrailBugReporterConfig(
          projectId: 'fixture',
          environment: 'dev',
          appVersion: '1',
          buildNumber: '1',
          reportToken: 'test',
          applicationSessionTokenProvider: () async => 'alice');
      final client = HandrailBugReportClient(
          apiBaseUrl: 'https://fixture.invalid',
          reportToken: 'test',
          httpClient: MockClient((request) async {
            expect(request.headers['x-handrail-application-session-token'],
                'alice');
            if (request.url.path.endsWith('/policy'))
              return http.Response(
                  jsonEncode({
                    'reporter': {'identity_verified': true},
                    'history': {'all_users': true}
                  }),
                  200);
            if (request.method == 'POST') {
              expect(request.url.path,
                  endsWith('/bugs/b/information-requests/q/answer'));
              expect(jsonDecode(request.body), {'answer': 'Phone'});
              posts++;
              return http.Response('{"answered":true}', 200);
            }
            expect(request.url.queryParameters['audience'], 'all');
            return http.Response(
                jsonEncode({
                  'bugs': [
                    {
                      'id': 'b',
                      'title': 'Checkout',
                      'is_owner': owner,
                      'status_rollup': {
                        'label': posts > 0 ? 'Reviewing' : 'Needs clarification'
                      },
                      'information_requests': [
                        {
                          'id': 'other',
                          'question': 'Which browser?',
                          'options': ['Safari', 'Chrome'],
                          'response_allowed': false
                        },
                        {
                          'id': 'q',
                          'question': 'Which device?',
                          'options': [],
                          if (!owner) 'response_allowed': true,
                          if (posts > 0) 'answer': {'text': 'Phone'}
                        }
                      ]
                    }
                  ]
                }),
                200);
          }));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: HandrailBugHistory(config: config, client: client))));
      await tester.pumpAndSettle();
      expect(find.text('The reporter has been asked.'), findsOneWidget);
      expect(find.text('Safari'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.enterText(find.byType(TextField), 'Phone');
      await tester.pump();
      await tester.tap(find.text('Send answer'));
      await tester.pumpAndSettle();
      expect(posts, 1);
      expect(find.text('Reviewing'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });
  }
}
