/// Platform dispatch for the plugin engine.
///
/// flutter_js's QuickJS runtime is built on dart:ffi, which does not compile
/// for web. This barrel selects the real engine on IO platforms and a stub
/// on web, so the rest of the app keeps importing `plugin_engine.dart` and
/// web builds never see the ffi imports.
library;

import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/plugins/plugin_manifest.dart';

export 'plugin_engine_stub.dart'
    if (dart.library.io) 'plugin_engine_io.dart';

/// Contract both platform implementations keep, so plugin_manager.dart stays
/// platform-agnostic. The concrete [PluginEngineImpl] comes from the
/// branch-selected export above; each branch defines it with the same name
/// (mirroring plugin_fs.dart's getPluginFileSystem pattern).
abstract class PluginEngine {
  /// The plugin's parsed manifest.json.
  PluginManifest get manifest;

  /// Absolute directory holding manifest.json + the entry script.
  String get pluginDir;

  /// Grants currently in effect (mirrors PluginManager's persisted set).
  Set<String> get grants;
  set grants(Set<String> value);

  /// Provides the signed-in auth service, or null when logged out. Injected
  /// at start so the engine has no Provider dependency.
  AuthService? Function()? get authAccessor;
  set authAccessor(AuthService? Function()? value);

  /// Local toast sink for `of.ui.toast`.
  void Function(String message)? get toastSink;
  set toastSink(void Function(String message)? value);

  /// Whether the JS runtime is alive and the entry script has run.
  bool get running;

  /// Evaluates the entry script (subject to [permissionCheck]).
  Future<void> start({
    required Future<bool> Function(String permId) permissionCheck,
  });

  /// Stops background timers/JS work; keeps the engine reusable.
  Future<void> stop();

  /// Releases all native resources. The engine is unusable afterwards.
  void dispose();

  /// Evaluates a JS expression and returns its JSON value.
  Future<dynamic> evalExpression(String expression);
}
