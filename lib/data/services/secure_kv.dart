import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Encrypted key-value store for secrets (session tokens, E2EE keys).
///
/// Backed by flutter_secure_storage, which uses the platform credential store
/// (Android Keystore, iOS/macOS Keychain, Windows Credential Manager,
/// libsecret on Linux; on the web it falls back to browser storage). Values
/// written by older app versions into SharedPreferences — plaintext on disk —
/// are migrated once at startup and then removed from there.
class SecureKV {
  SecureKV._();

  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Prefixes of legacy SharedPreferences keys that hold sensitive values
  /// (tokens, key material, per-host session blobs) and must be moved into
  /// secure storage.
  static const List<String> _legacySensitivePrefixes = [
    'access_token',
    'refresh_token',
    'access_expires_at',
    'e2ee_identity_private',
    'e2ee_identity_public',
    'e2ee_group_keys_',
    'session.',
  ];

  static Future<void>? _migration;

  /// Moves legacy plaintext secrets from SharedPreferences into the platform
  /// credential store. Idempotent: values already present in secure storage
  /// are not overwritten and their plaintext copies are dropped either way.
  static Future<void> migrate() {
    return _migration ??= _doMigrate();
  }

  static Future<void> _doMigrate() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().toList()) {
      if (!_legacySensitivePrefixes.any(key.startsWith)) continue;
      final value = prefs.get(key);
      if (value is! String && value is! int) continue;
      final asString = value.toString();
      try {
        final existing = await _storage.read(key: key);
        if ((existing == null || existing.isEmpty) && asString.isNotEmpty) {
          await _storage.write(key: key, value: asString);
        }
        await prefs.remove(key);
      } catch (_) {
        // Secure storage unavailable: leave the value where it is rather than
        // destroying a working session.
        break;
      }
    }
  }

  static Future<String?> read(String key) => _storage.read(key: key);

  /// Returns every key-value pair currently in secure storage.
  static Future<Map<String, String>> readAll() => _storage.readAll();

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);
}
