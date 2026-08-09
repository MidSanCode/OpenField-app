/// Central app metadata used by the "About" screen.
///
/// Bump [appVersion] when a new build is released so users can verify which
/// version they are running.
class AppConfig {
  const AppConfig._();

  /// Human-readable version shown in the About section.
  static const String appVersion = '1.1.0';

  /// Free-form build label (e.g. a build number or git short hash).
  static const String buildNumber = '';

  /// Combined version string: version + optional build label.
  static String get versionLabel =>
      buildNumber.isEmpty ? appVersion : '$appVersion ($buildNumber)';
}
