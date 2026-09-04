import 'dart:async';
import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:openfield/core/log/log_overlay.dart' show appNavigatorKey;
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/plugins/plugin_engine.dart';
import 'package:openfield/plugins/plugin_fs.dart';
import 'package:openfield/plugins/plugin_gate.dart';
import 'package:openfield/plugins/plugin_manifest.dart';
import 'package:openfield/plugins/plugin_prefs_box.dart';

final _log = Logger('PluginManager');

/// Platform file layer (dart:io on native; a clear-error stub on web).
final PluginFileSystem _fs = getPluginFileSystem();

/// Where one installed plugin came from.
enum PluginOrigin { store, imported }

/// One plugin installed on this device.
class InstalledPlugin {
  final PluginManifest manifest;

  /// Absolute directory containing manifest.json / entry script / meta.
  final String dir;

  final PluginOrigin origin;

  /// True only for bundles published through the admin-reviewed store.
  final bool verifiedFromStore;

  InstalledPlugin({
    required this.manifest,
    required this.dir,
    required this.origin,
    required this.verifiedFromStore,
  });
}

/// Installs, enables/disables and boots plugins. All JS execution flows
/// through [PluginEngine]; nothing runs unless [PluginGate] reports an
/// online session ("secure boot").
class PluginManager extends ChangeNotifier {
  PluginManager._();

  static final PluginManager instance = PluginManager._();

  final Map<String, InstalledPlugin> _installed = {};
  final Map<String, PluginEngine> _engines = {};
  final Set<String> _enabled = {};
  final Map<String, Set<String>> _grants = {};

  String? _pluginsDir;
  bool _initialized = false;
  bool _gateHooked = false;
  VoidCallback? _gateListener;
  static AuthService? Function()? _authProvider;

  List<InstalledPlugin> get plugins => List.unmodifiable(_installed.values);

  InstalledPlugin? plugin(String id) => _installed[id];

  bool isEnabled(String id) => _enabled.contains(id);

  bool isGranted(String id, String permId) =>
      (_grants[id] ?? const {}).contains(permId);

  /// True when every requested permission has been accepted by the user.
  bool isGrantedAll(String id, List<String> perms) {
    final granted = _grants[id] ?? const {};
    return perms.every(granted.contains);
  }

  Set<String> grantsOf(String id) => _grants[id] ?? const {};

  bool isRunning(String id) => _engines[id]?.running ?? false;

  /// Number of currently running engines (for status chips).
  int get runningCount => _engines.values.where((e) => e.running).length;

  // ------------------------------------------------------------------
  // Init
  // ------------------------------------------------------------------

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    _pluginsDir = await _fs.rootDir();
    await PluginPrefsBox.instance.ensureLoaded();

    await _scanInstalled();
    await _loadPrefs();

    _hookGate();
  }

  void _hookGate() {
    if (_gateHooked) return;
    _gateHooked = true;
    _gateListener = () => _onGateChanged();
    PluginGate.instance.addListener(_gateListener!);
    PluginGate.instance.start();
    // Boot immediately if the gate already came up online.
    if (PluginGate.instance.allowsPlugins) {
      scheduleMicrotask(_bootAllEnabled);
    }
  }

  void _onGateChanged() {
    if (PluginGate.instance.allowsPlugins) {
      _bootAllEnabled();
    } else {
      // Secure boot: no verified online session → everything stops now.
      _stopAll();
    }
    notifyListeners();
  }

  /// Registers how to reach the signed-in auth service; called once from
  /// main() after the provider tree exists.
  static void attachAuthProvider(AuthService? Function() provider) {
    _authProvider = provider;
  }

  AuthService? _authAccessor() {
    try {
      return _authProvider?.call();
    } catch (_) {
      return null;
    }
  }

  Future<void> _scanInstalled() async {
    for (final entity in _fs.listDirs(_pluginsDir!)) {
      try {
        final raw = _fs.readText('${entity.path}/manifest.json');
        if (raw == null) continue;
        final manifest =
            PluginManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        var origin = PluginOrigin.imported;
        var verified = false;
        final metaRaw = _fs.readText('${entity.path}/.ofmeta.json');
        if (metaRaw != null) {
          try {
            final meta = jsonDecode(metaRaw) as Map<String, dynamic>;
            origin = meta['origin'] == 'store'
                ? PluginOrigin.store
                : PluginOrigin.imported;
            verified = meta['verified'] == true;
          } catch (_) {}
        }
        _installed[manifest.id] = InstalledPlugin(
          manifest: manifest,
          dir: entity.path,
          origin: origin,
          verifiedFromStore: verified,
        );
      } catch (e) {
        _log.warning('skipping broken plugin dir ${entity.path}: $e');
      }
    }
  }

  Future<void> _loadPrefs() async {
    final sp = await SharedPreferences.getInstance();
    _enabled.addAll(sp.getStringList(_kEnabled) ?? const []);
    final grantsRaw = sp.getString(_kGrants);
    if (grantsRaw != null && grantsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(grantsRaw) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is List) _grants[k] = v.map((e) => e.toString()).toSet();
        });
      } catch (_) {}
    }
  }

  static const _kEnabled = 'of_plugins_enabled';
  static const _kGrants = 'of_plugins_grants';

  Future<void> _persistPrefs() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setStringList(_kEnabled, _enabled.toList());
    await sp.setString(
      _kGrants,
      jsonEncode(_grants.map((k, v) => MapEntry(k, v.toList()))),
    );
  }

  // ------------------------------------------------------------------
  // Install / uninstall
  // ------------------------------------------------------------------

  /// Extracts a plugin bundle ([zipBytes]) into the plugins directory,
  /// validates its manifest and registers it. Returns the installed plugin
  /// so callers can run the permission-consent flow. An existing install of
  /// the same id is replaced (upgrade path).
  Future<InstalledPlugin> installBundle(
    List<int> zipBytes, {
    required PluginOrigin origin,
    bool verified = false,
  }) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    PluginManifest? manifest;
    final files = <String, List<int>>{};
    for (final f in archive) {
      if (!f.isFile) continue;
      final name = f.name.replaceAll('\\', '/');
      if (name.startsWith('..') || name.contains('../')) {
        throw const FormatException('插件包含非法路径 / illegal path in bundle');
      }
      final bytes = f.content as List<int>;
      final lower = name.toLowerCase();
      if (lower == 'manifest.json') {
        final raw = utf8.decode(bytes, allowMalformed: false);
        manifest =
            PluginManifest.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      } else if (lower.endsWith('.js')) {
        if (bytes.length > 512 * 1024) {
          throw const FormatException('脚本过大 / script too large');
        }
        files.putIfAbsent(lower, () => bytes);
      }
    }
    if (manifest == null) {
      throw const FormatException('缺少 manifest.json / manifest.json missing');
    }
    if (!files.containsKey(manifest.entry.toLowerCase())) {
      throw FormatException('缺少入口脚本 ${manifest.entry}');
    }

    final target = '$_pluginsDir/${manifest.id}';
    _fs.deleteRecursive(target);
    for (final entry in files.entries) {
      _fs.writeBytes('$target/${entry.key}', entry.value);
    }
    _fs.writeText('$target/manifest.json',
        const JsonEncoder.withIndent('  ').convert(manifest.toJson()));
    _fs.writeText('$target/.ofmeta.json', jsonEncode({
      'origin': origin.name,
      'verified': verified,
    }));

    final installed = InstalledPlugin(
      manifest: manifest,
      dir: target,
      origin: origin,
      verifiedFromStore: verified,
    );
    _installed[manifest.id] = installed;
    notifyListeners();
    return installed;
  }

  /// Stops, unregisters and deletes a plugin together with its storage.
  Future<void> uninstall(String id) async {
    await _engines[id]?.stop();
    _engines.remove(id);
    final installed = _installed.remove(id);
    _enabled.remove(id);
    _grants.remove(id);
    if (installed != null) {
      PluginPrefsBox.instance.removeNamespace('plugin_${installed.manifest.id}_');
      try {
        _fs.deleteRecursive(installed.dir);
      } catch (_) {}
    }
    await _persistPrefs();
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Enable / disable / grants
  // ------------------------------------------------------------------

  Future<void> enable(String id) async {
    _enabled.add(id);
    await _persistPrefs();
    if (PluginGate.instance.allowsPlugins) {
      unawaited(_bootOne(id));
    }
    notifyListeners();
  }

  Future<void> disable(String id) async {
    _enabled.remove(id);
    await _persistPrefs();
    unawaited(_engines[id]?.stop());
    notifyListeners();
  }

  Future<void> setGrants(String id, Set<String> grants) async {
    _grants[id] = Set.unmodifiable(grants);
    await _persistPrefs();
    // Restart a running engine so permission changes take effect at once.
    if (isRunning(id)) {
      await _engines[id]?.stop();
      if (_enabled.contains(id) && PluginGate.instance.allowsPlugins) {
        unawaited(_bootOne(id));
      }
    }
    notifyListeners();
  }

  // ------------------------------------------------------------------
  // Booting
  // ------------------------------------------------------------------

  Future<void> _bootAllEnabled() async {
    for (final id in _installed.keys.toList(growable: false)) {
      if (_enabled.contains(id)) await _bootOne(id);
    }
    notifyListeners();
  }

  Future<void> _bootOne(String id) async {
    final installed = _installed[id];
    if (installed == null || !PluginGate.instance.allowsPlugins) return;
    // Tear down any previous instance first (upgrade / grant change).
    await _engines[id]?.stop();

    final engine = PluginEngineImpl(
      manifest: installed.manifest,
      pluginDir: installed.dir,
    )
      ..authAccessor = _authAccessor
      ..toastSink = _showToast;
    engine.grants = Set.of(_grants[id] ?? const {});
    _engines[id] = engine;
    try {
      await engine.start(permissionCheck: (permId) async {
        if (!engine.grants.contains(permId)) return false;
        if (!PluginGate.instance.allowsPlugins) return false;
        return true;
      });
    } catch (e) {
      _log.warning('plugin $id failed to boot: $e');
      _engines.remove(id);
    }
    notifyListeners();
  }

  void _showToast(String message) {
    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    try {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      // No scaffold mounted yet — drop the toast.
    }
  }

  Future<void> _stopAll() async {
    for (final engine in _engines.values) {
      try {
        await engine.stop();
      } catch (_) {}
    }
    notifyListeners();
  }

  @override
  void dispose() {
    if (_gateListener != null) {
      PluginGate.instance.removeListener(_gateListener!);
    }
    super.dispose();
  }
}
