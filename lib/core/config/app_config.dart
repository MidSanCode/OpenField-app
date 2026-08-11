import 'package:package_info_plus/package_info_plus.dart';

/// Central app metadata used by the "About" screen.
///
/// The display version is read at runtime from the built app (pubspec.yaml's
/// `version: <version>+<build>`, e.g. `1.0.0+1`), so it never drifts from the
/// value Gradle/AGB and the stores actually see. Call [load] once from `main`
/// before building the widget tree.
class AppConfig {
  const AppConfig._();

  static PackageInfo? _info;

  /// Loads the runtime version info. Safe to call repeatedly; the first
  /// success is kept.
  static Future<void> load() async {
    if (_info != null) return;
    try {
      _info = await PackageInfo.fromPlatform();
    } catch (_) {
      _info = null;
    }
  }

  /// Human-readable version shown in the About section (e.g. "1.0.0").
  static String get appVersion => _info?.version ?? '';

  /// The build label from pubspec (the number after '+', e.g. "1").
  static String get buildNumber => _info?.buildNumber ?? '';

  /// Combined version string: version + optional build label.
  static String get versionLabel {
    if (_info == null) return '';
    final build = buildNumber;
    return build.isEmpty ? appVersion : '$appVersion ($build)';
  }
}