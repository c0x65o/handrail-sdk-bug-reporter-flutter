class HandrailBugReporterSdkMetadata {
  const HandrailBugReporterSdkMetadata._();

  static const String packageName = 'handrail_bug_reporter';

  static const String version = String.fromEnvironment(
    'HANDRAIL_BUG_REPORTER_SDK_VERSION',
    defaultValue: '0.1.58',
  );

  static const String commit = String.fromEnvironment(
    'HANDRAIL_BUG_REPORTER_SDK_COMMIT',
    defaultValue: 'unknown',
  );

  static const String ref = String.fromEnvironment(
    'HANDRAIL_BUG_REPORTER_SDK_REF',
    defaultValue: 'release/0.1',
  );
}
