import 'package:openfield/data/services/api_service.dart';

/// Per-server scoping for the local chat caches.
///
/// Message and conversation ids are only unique **within one server**, so a
/// single shared cache would silently mix conversations from different
/// servers (id collisions overwrite each other's rows, and switching servers
/// shows the wrong history). Every cache database is therefore named after
/// the host it was fetched from, and the stores re-resolve their database on
/// every access so a runtime host switch lands in the right shard.
///
/// Legacy single-file caches (before scoping) keep working unchanged: their
/// un-suffixed name is the shard of the default production host, so data
/// fetched from the default host is never lost.
class ChatDbScope {
  ChatDbScope._();

  /// The default host is special-cased: it keeps the original, un-suffixed
  /// database names (`openfield_chat` / `openfield_e2ee`) so existing
  /// installations do not lose their cache across the upgrade.
  static const String _defaultHost = ApiService.defaultServerHost;

  /// Cache of the last resolved suffix per host — avoids re-hashing on every
  /// DB access without changing behavior when the host switches.
  static final Map<String, String> _suffixCache = {};

  /// Returns the database-name suffix for the currently active server host
  /// (an empty string for the default host).
  static String suffix() => suffixFor(ApiService.serverHost);

  /// The suffix for a specific host. Uses a short hash for long hosts so the
  /// database names stay reasonable on every platform (Windows MAX_PATH,
  /// IndexedDB name limits are generous but SQLite file names are not).
  static String suffixFor(String host) {
    final cached = _suffixCache[host];
    if (cached != null) return cached;
    final normalized = _normalize(host);
    final suffix = normalized == _normalize(_defaultHost)
        ? ''
        : _hash(normalized);
    _suffixCache[host] = suffix;
    return suffix;
  }

  /// The shard-aware database file name (IO platforms).
  static String fileName(String base) {
    final s = suffix();
    return s.isEmpty ? '$base.db' : '$base.$s.db';
  }

  /// The shard-aware database name (web IndexedDB).
  static String dbName(String base) {
    final s = suffix();
    return s.isEmpty ? base : '${base}_$s';
  }

  /// Lowercase host without a trailing slash; port and scheme are kept so
  /// `http://localhost:8080` and `https://localhost` never collide.
  static String _normalize(String host) =>
      host.trim().toLowerCase().replaceAll(RegExp(r'/+$'), '');

  /// FNV-1a 32-bit, hex — short, dependency-free and stable across restarts.
  static String _hash(String input) {
    var hash = 0x811c9dc5;
    for (final code in input.codeUnits) {
      hash ^= code & 0xff;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
      hash ^= code >> 8;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
