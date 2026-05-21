# handrail_flutter_bug_reporter

Reusable Flutter package for submitting Handrail mobile bug reports.

## Usage

```yaml
dependencies:
  handrail_bug_reporter:
    git:
      url: https://github.com/c0x65o/handrail_flutter_bug_reporter.git
      ref: main
```

The Dart package name remains `handrail_bug_reporter`, so app imports stay:

```dart
import 'package:handrail_bug_reporter/handrail_bug_reporter.dart';
```

For local workspace development, apps can point to this repo with a path dependency and run `flutter pub get`.
