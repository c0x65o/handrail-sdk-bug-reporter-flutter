import 'package:flutter_test/flutter_test.dart';
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';

void main() {
  test('all-users discovery requires verified identity and literal opt-in', () {
    for (final verified in [true, false, null, 'true']) {
      for (final allowed in [true, false, null, 'true', 1]) {
        final policy = HandrailBugAutomationPolicy.fromJson({
          'schema_version': 1,
          'project_id': 'fixture',
          'environment': 'dev',
          'reporter': {'identity_verified': verified},
          'history': {'all_users': allowed},
        });
        expect(policy.allUsersHistory, verified == true && allowed == true);
      }
    }
    for (final history in [null, false, 'true', <String, Object?>{}]) {
      expect(HandrailBugAutomationPolicy.fromJson({
        'reporter': {'identity_verified': true},
        'history': history,
      }).allUsersHistory, isFalse);
    }
  });
}
