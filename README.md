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

Use `release/0.1` as the moving minor release channel for apps that should receive approved `0.1.x` SDK patches. Use immutable patch tags such as `v0.1.23` only when a build must stay fixed to one SDK patch release. Do not use `main` as the app dependency ref.

## Release note

The intended patch release for the Flutter web screenshot fallback fix is `v0.1.23` on `release/0.1`. Apps should keep the dependency ref on `release/0.1`; the app lockfile records the exact commit that was pulled. To intentionally pull future approved `0.1.x` updates, run:

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
