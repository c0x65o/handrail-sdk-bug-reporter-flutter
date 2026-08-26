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

The reporter-policy discovery and optional automation controls are included in
`v0.1.50`. Apps should keep the dependency ref on `release/0.1`; the app
lockfile records the exact commit that was pulled. To intentionally pull future
approved `0.1.x` updates, run:

```sh
flutter pub upgrade handrail_bug_reporter
```

Submitted payloads include SDK diagnostics under explicit fields:

- `reporter_sdk_version`
- `reporter_sdk_commit`
- `reporter_sdk_ref`

The package version is owned by `pubspec.yaml`. Handrail's shared version-bump
operation regenerates the runtime SDK version through
`.handrail/version-mirrors.json`; do not edit the mirrored default directly.
Build systems may override `HANDRAIL_BUG_REPORTER_SDK_COMMIT`,
`HANDRAIL_BUG_REPORTER_SDK_REF`, or `HANDRAIL_BUG_REPORTER_SDK_VERSION` with
`--dart-define` when stamping immutable release builds; apps should not
hard-code these values in their reporter config.

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
  applicationSessionTokenProvider: () async =>
      appAuth.currentSession?.rawToken,
);
```

`username` and `usernameProvider` are optional. When a non-blank username is
available, the SDK includes it in manual and crash report payloads so Handrail
can display who submitted the report. Use `usernameProvider` when the signed-in
user can change while the app is running; a provider value takes precedence
over the fixed `username` value. These fields are display-only compatibility
metadata. A username, profile key, or public report token does not authenticate
the reporter and grants no workflow, repair, deployment, or policy authority.

### Authenticated reporter attribution

`applicationSessionTokenProvider` is an optional asynchronous callback that
returns the raw token for the application's current authenticated session. The
SDK resolves it immediately before every manual report, crash report, and
queued-crash retry and sends it only in the
`x-handrail-application-session-token` request header. It never puts the token
in the JSON payload or offline crash queue.

Handrail hashes the token, verifies it against the project/environment-scoped
Known Users session mapping, and derives the stable application user ID from
the session row. The client does not submit a trusted user ID. Missing,
expired, revoked, ambiguous, or invalid sessions leave attribution unverified.
Authentication selects the reporter's Default, User, or Full Access policy
column but does not grant repair or deployment authority by itself.

### Optional automation controls

When the report sheet opens, the SDK calls
`GET /api/mobile-bug-reports/policy` with the same report-token and current
application-session headers used for submission. Handrail resolves the current
reporter server-side and returns only that reporter's access tier and available
`Ask` controls; the SDK never downloads the Known Users directory.

The form renders returned controls such as Verify, Repair proposal, Fix, Deploy
to staging, and Deploy to production as optional checkboxes. It intentionally
does not display low/medium/high risk choices. Selected controls are submitted
under `automation_requests`; Handrail reclassifies the report and applies the
exact risk row plus the existing workflow and deployment safety gates.

Policy discovery is best-effort and falls back after five seconds by default.
If it is unavailable, stalls, or returns no `Ask` controls, ordinary bug
reporting remains available and no automation options are shown. Apps may set
`policyDiscoveryTimeout` to a different bounded duration; it does not affect
report submission. When an application-session provider is configured, the SDK
briefly re-resolves it after an unverified response so opening the sheet during
auth hydration does not permanently hide the authenticated controls.

Never copy the raw session token into static reporter config, browser storage,
preferences, local databases, files, logs, analytics, breadcrumbs, crash
metadata, or error evidence. For web applications whose session is held in an
HttpOnly cookie, forward the token from an authenticated same-origin server
handler; do not expose the cookie to browser JavaScript.

#### Migrating from username attribution

Existing integrations can keep `username` or `usernameProvider` for display.
Add `applicationSessionTokenProvider` after Config has a Known Users stable ID
and session mapping. Do not turn the public report token into an application
session token. If there is no current authenticated session, return `null`;
ordinary bug submission continues without verified attribution.

### Report update notifications

The manual report sheet now supports an unchecked, report-scoped opt-in for
Fixed and Deployed emails. Prefill the authenticated account address without
storing it in the bug payload:

```dart
HandrailBugReporterConfig(
  // existing report configuration...
  reporterEmailProvider: () async => authSession.currentUser?.email,
  applicationSessionTokenProvider: () async => authSession.rawToken,
  notificationsEnabled: true,
)
```

After Handrail accepts the report, the SDK posts the email and explicit consent
to `/api/mobile-bug-reports/bugs/:bugId/subscription`. Subscription failure is
shown separately and never changes the accepted report to an error. Every
message includes a report-scoped unsubscribe link. Existing apps remain source
compatible; the provider and feature flag are optional.

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
