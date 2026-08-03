# handrail_flutter_bug_reporter

Reusable Flutter package for submitting Handrail mobile bug reports.

## Usage

```yaml
dependencies:
  handrail_bug_reporter:
    git:
      url: https://github.com/c0x65o/handrail_flutter_bug_reporter.git
      ref: release/0.1
```

The Dart package name remains `handrail_bug_reporter`, so app imports stay:

```dart
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
```

For local workspace development, apps can point to this repo with a path dependency and run `flutter pub get`.

Use `release/0.1` as the moving minor release channel for apps that should receive approved `0.1.x` SDK patches. Use immutable patch tags such as `v0.1.26` only when a build must stay fixed to one SDK patch release. Do not use `main` as the app dependency ref.

## Release note

The intended patch release for the severity label, same-origin Mobile Preview submission, and web screenshot fallback fixes is `v0.1.26` on `release/0.1`. Apps should keep the dependency ref on `release/0.1`; the app lockfile records the exact commit that was pulled. To intentionally pull future approved `0.1.x` updates, run:

```sh
flutter pub upgrade handrail_bug_reporter
```

Submitted payloads include SDK diagnostics under explicit fields:

- `reporter_sdk_version`
- `reporter_sdk_commit`
- `reporter_sdk_ref`

The package version is owned by `pubspec.yaml` and mirrored by the SDK metadata constants for runtime payloads. Build systems may override `HANDRAIL_BUG_REPORTER_SDK_COMMIT`, `HANDRAIL_BUG_REPORTER_SDK_REF`, or `HANDRAIL_BUG_REPORTER_SDK_VERSION` with `--dart-define` when stamping immutable release builds; apps should not hard-code these values in their reporter config.

The SDK treats reporting and production submission as enabled by default once
the public Handrail config and report token are present. Pass
`enabled: false` or `allowProductionReporting: false` only for projects that
intentionally opt out or require profile-gated production reports.

Configure the reporter with Handrail's immutable project ID. The SDK submits
that value as `project_id`; slug-based lookup is retained only as a deprecated
compatibility path for apps built with an older integration:

```dart
HandrailBugReporterConfig(
  projectId: const String.fromEnvironment('HANDRAIL_BUG_REPORT_PROJECT'),
  environment: const String.fromEnvironment('HANDRAIL_BUG_REPORT_ENV'),
  appVersion: appVersion,
  buildNumber: buildNumber,
  reportToken: const String.fromEnvironment('HANDRAIL_BUG_REPORT_TOKEN'),
  usernameProvider: () async => appAuth.currentUser?.displayName,
  reporterAssertionProvider: () async {
    // Read the current user and session from the app's authenticated context.
    // Do not cache this result in the reporter configuration.
    final session = await appAuth.currentSessionForBugReporting();
    if (session == null || !session.isAuthenticated) return null;

    return HandrailReporterAssertion.fresh(
      userIdentifier: session.stableUserId,
      sessionIdentifier: session.sessionId,
      verifier: session.verifier,
    );
  },
);
```

`username` and `usernameProvider` are optional. When a non-blank username is
available, the SDK includes it in manual and crash report payloads so Handrail
can display who submitted the report. Use `usernameProvider` when the signed-in
user can change while the app is running; a provider value takes precedence
over the fixed `username` value. These fields are display-only compatibility
metadata. A username, profile key, or public report token does not authenticate
the reporter and grants no workflow, repair, deployment, or policy authority.

### Authenticated reporter assertions

`reporterAssertionProvider` is an optional asynchronous callback for apps that
bind a Handrail reporter profile to an authenticated application user. Resolve
the stable application user ID, current session ID, and verifier through the
application's existing authenticated session layer. The verifier is an
application session proof accepted by the identity source configured in
Handrail; it is not a Handrail administrator, API, or deployment secret.

Return `null` when the app has no authenticated session. Otherwise, construct a
new version-1 assertion with `HandrailReporterAssertion.fresh`. It creates a
current UTC `issued_at` value and a cryptographically random base64url `nonce`:

```dart
reporterAssertionProvider: () async {
  final session = await appAuth.currentSessionForBugReporting();
  if (session == null || !session.isAuthenticated) return null;

  return HandrailReporterAssertion.fresh(
    userIdentifier: session.stableUserId, // Never a display name or email.
    sessionIdentifier: session.sessionId,
    verifier: session.verifier,
  );
},
```

The SDK calls the provider immediately before each manual submission, crash
submission, and queued-crash retry. Do not memoize assertions: every transport
attempt needs current user/session data, a fresh `issued_at`, and a fresh nonce.
This also means a sign-out, account switch, session rotation, expiration, or
revocation is reflected on the next attempt. Unsupported or incomplete
assertions are omitted, leaving the report on the vanilla, non-authoritative
path.

Assertion and verifier material is transport-only. Never write it to secure or
plain preferences, local databases, files, offline queues, logs, analytics,
breadcrumbs, crash metadata, or error evidence. The SDK deliberately removes
`reporter_assertion` before storing a failed crash report and invokes the
provider again only when retry transport is attempted. The application's
authentication layer remains the sole owner of the current session credential;
the reporter integration must not copy the verifier into any additional
storage.

For web integrations backed by an HttpOnly cookie, keep the cookie and session
secret out of browser JavaScript. Have the browser call an authenticated
same-origin server route; derive the assertion from that route's verified
request or signed-session context, generate fresh proof fields there, and send
it only on that single Handrail intake request. Do not put the assertion into
browser storage, client retry queues, logs, analytics, or captured errors.

#### Migrating from username attribution

Existing integrations can keep `username` or `usernameProvider` for display.
Add `reporterAssertionProvider` alongside it after Handrail has a matching
identity source and reporter-profile binding. Do not copy the username into
`userIdentifier`, and do not turn the public report token into a verifier. If
the authenticated context cannot produce all three stable session values,
return `null`; ordinary bug submission continues, but Handrail will not treat
the reporter as verified.

## Crash capture

When `HandrailBugReporter` is mounted with a complete submission config, the
SDK also installs bounded crash capture. It forwards `FlutterError.onError`,
`PlatformDispatcher.instance.onError`, and recent `debugPrint` output into the
same `/api/mobile-bug-reports` intake with `source: handrail_flutter_sdk`.

Apps can add breadcrumbs to the crash payload without coupling to a separate
logging sink:

```dart
HandrailCrashReporter.recordLog(
  'Remote deploy screen opened',
  category: 'navigation',
  context: <String, Object?>{'route': '/deployments'},
);
```

Crash submissions include the app route, version/build, commit SHA, device/OS,
exception type, stack trace, recent logs, reporter SDK metadata, and structured
crash metadata. Existing error handlers still run after the Handrail reporter,
so Sentry or app-local handlers keep their current behavior.
