import 'package:logging/logging.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/plugins/plugin_engine.dart';
import 'package:openfield/plugins/plugin_manifest.dart';

final _log = Logger('PluginEngine');

/// Web placeholder engine. flutter_js ships a QuickJS runtime via dart:ffi,
/// which has no web implementation, so plugins cannot execute in the browser.
/// The class keeps the exact surface of the IO engine so plugin_manager.dart
/// stays platform-agnostic; starting a plugin surfaces a clear error instead
/// of a compile failure.
class PluginEngineImpl implements PluginEngine {
  PluginEngineImpl({required this.manifest, required this.pluginDir});

  @override
  final PluginManifest manifest;

  /// Absolute directory holding manifest.json + the entry script.
  @override
  final String pluginDir;

  /// Grants currently in effect (mirrors PluginManager's persisted set).
  @override
  Set<String> grants = {};

  /// Provides the signed-in auth service, or null when logged out. Injected
  /// at start so the engine has no Provider dependency.
  @override
  AuthService? Function()? authAccessor;

  /// Local toast sink for `of.ui.toast`.
  @override
  void Function(String message)? toastSink;

  @override
  bool get running => false;

  /// Always fails: there is no JavaScript runtime on web.
  @override
  Future<void> start({
    required Future<bool> Function(String permId) permissionCheck,
  }) async {
    _log.warning(
        'plugin ${manifest.id} cannot start: the plugin runtime requires a '
        'native platform (no QuickJS engine on web)');
    throw UnsupportedError(
        'plugin runtime is not supported on web (no JS engine)');
  }

  @override
  Future<void> stop() async {}

  @override
  void dispose() {}

  @override
  Future<dynamic> evalExpression(String expression) async => null;
}
