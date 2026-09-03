import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _log = Logger('PluginPrefsBox');

/// Tiny synchronous key-value store backing `of.storage`. Reads come from an
/// in-memory map seeded from SharedPreferences at boot; writes update memory
/// immediately and persist asynchronously. All plugin namespaces share one
/// serialized JSON blob under a single preference key — plugin storage is
/// small by design and this keeps it atomic and simple.
class PluginPrefsBox {
  PluginPrefsBox._();
  static final PluginPrefsBox instance = PluginPrefsBox._();

  static const _blobKey = 'of_plugin_storage';

  final Map<String, Object?> _mem = {};
  Future<void>? _loading;

  /// Must be awaited once before any engine starts.
  Future<void> ensureLoaded() {
    if (_mem.isNotEmpty) return Future.value();
    return (_loading ??= _load());
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_blobKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) _mem.addAll(decoded);
      }
    } catch (e) {
      _log.warning('failed to load plugin storage: $e');
    }
  }

  Object? get(String key) => _mem[key];

  void set(String key, Object? value) {
    _mem[key] = value;
    _persist();
  }

  void remove(String key) {
    _mem.remove(key);
    _persist();
  }

  /// Removes every namespaced key of one plugin (used on uninstall).
  void removeNamespace(String namespacePrefix) {
    _mem.removeWhere((k, _) => k.startsWith(namespacePrefix));
    _persist();
  }

  void _persist() {
    SharedPreferences.getInstance().then((sp) {
      sp.setString(_blobKey, jsonEncode(_mem));
    }).catchError((e) {
      _log.warning('failed to persist plugin storage: $e');
    });
  }
}
