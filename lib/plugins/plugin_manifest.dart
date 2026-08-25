import 'plugin_permissions.dart';

/// Where a plugin came from. Store plugins were reviewed and uploaded by an
/// admin (verified badge); imported ones are sideloaded by the user.
enum PluginSource { store, imported }

/// Parsed + validated `manifest.json` of a plugin bundle.
///
/// A bundle is a zip containing at minimum:
/// ```
/// manifest.json
/// main.js
/// ```
class PluginManifest {
  /// Stable identifier, e.g. `com.example.demo`. Lowercase letters, digits,
  /// dots, dashes; 3-64 chars. Doubles as the on-disk directory name.
  final String id;

  final String name;
  final String version;
  final String author;
  final String description;

  /// Entry script file name inside the bundle (plain `.js` file).
  final String entry;

  /// Permission keys the plugin requests. Every key must exist in the client
  /// catalog or the bundle fails validation — unknown capabilities are
  /// rejected rather than silently ignored.
  final List<String> permissions;

  /// Hosts `of.http.fetch` may contact when `http.fetch` is granted
  /// (exact host names, no wildcards). Empty list = no network access even
  /// with the permission granted.
  final List<String> allowedHosts;

  /// Oldest app version this plugin supports (informational for now).
  final String minAppVersion;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    this.author = '',
    this.description = '',
    this.entry = 'main.js',
    this.permissions = const [],
    this.allowedHosts = const [],
    this.minAppVersion = '',
  });

  static final RegExp _idRe = RegExp(r'^[a-z0-9][a-z0-9._-]{2,63}$');
  static final RegExp _versionRe =
      RegExp(r'^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$');
  // ignore: unused_field
  static final RegExp _entryRe = RegExp(r'^[A-Za-z0-9._-]+\.js$');

  /// Parses and validates a raw JSON map. Throws [FormatException] with a
  /// human-readable message when anything is off — callers surface it in the
  /// install/import error dialog.
  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    if (!_idRe.hasMatch(id)) {
      throw const FormatException('无效插件 id / Invalid plugin id');
    }
    final name = (json['name'] ?? '').toString().trim();
    if (name.isEmpty || name.length > 100) {
      throw const FormatException('无效插件名称 / Invalid plugin name');
    }
    final version = (json['version'] ?? '').toString().trim();
    if (!_versionRe.hasMatch(version)) {
      throw const FormatException('无效版本号 / Invalid version');
    }
    var entry = (json['entry'] ?? 'main.js').toString().trim();
    if (entry.isEmpty) entry = 'main.js';
    if (entry.contains('/') ||
        entry.contains('\\') ||
        entry.contains('..') ||
        !entry.toLowerCase().endsWith('.js')) {
      throw const FormatException('无效入口脚本 / Invalid entry script');
    }

    final permsRaw = json['permissions'];
    final perms = <String>[];
    if (permsRaw is List) {
      for (final p in permsRaw) {
        final key = p.toString();
        if (permissionDefOf(key) == null) {
          throw FormatException('未知权限 / Unknown permission: $key');
        }
        if (!perms.contains(key)) perms.add(key);
      }
    } else if (permsRaw != null) {
      throw const FormatException('permissions 必须是数组 / permissions must be a list');
    }

    final hostsRaw = json['allowed_hosts'] ?? json['allowedHosts'];
    final hosts = <String>[];
    if (hostsRaw is List) {
      for (final h in hostsRaw) {
        final host = h.toString().trim().toLowerCase();
        if (host.isEmpty) continue;
        if (host.contains('/') ||
            host.contains('*') ||
            host.contains(' ') ||
            !host.contains('.')) {
          throw FormatException('无效 allowed_hosts 主机 / Invalid host: $host');
        }
        hosts.add(host);
      }
    }

    return PluginManifest(
      id: id,
      name: name,
      version: version,
      author: (json['author'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      entry: entry,
      permissions: List.unmodifiable(perms),
      allowedHosts: List.unmodifiable(hosts),
      minAppVersion: (json['min_app_version'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'author': author,
        'description': description,
        'entry': entry,
        'permissions': permissions,
        'allowed_hosts': allowedHosts,
        'min_app_version': minAppVersion,
      };

  @override
  String toString() => 'PluginManifest($id@$version)';
}
