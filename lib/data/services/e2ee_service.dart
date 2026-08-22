import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/e2ee_crypto.dart';
import 'package:openfield/data/services/secure_kv.dart';

/// Thrown when a synchronous E2EE operation cannot run because the service has
/// not been initialised or the conversation has no usable group key.
class E2eeException implements Exception {
  final String message;
  E2eeException(this.message);
  @override
  String toString() => message;
}

/// Tracks the chain state for one (conversation, sender, key version).
class _ChainRec {
  final int version;
  final int nextIndex;
  final Uint8List nextKey;
  const _ChainRec(this.version, this.nextIndex, this.nextKey);
}

/// OpenField's pragmatic end-to-end encryption layer.
///
/// - Each user has a stable X25519 identity keypair; the public half is
///   published on the account so other members can seal group keys to us.
/// - Each encrypted conversation has a random 32-byte group key. When
///   encryption is enabled or a member joins, a fresh group key is generated
///   and delivered to every member as an AES-256-GCM envelope sealed with an
///   ephemeral X25519 key (so the server only ever stores ciphertext).
/// - Messages are encrypted with a per-sender hash chain derived from the
///   group key. The chain ratchets forward on every send/decrypt and old chain
///   values are never kept, which provides forward secrecy: a leaked current
///   group key cannot decrypt messages encrypted under an earlier chain state,
///   and a removed member (who no longer receives new group keys) cannot
///   decrypt new messages.
///
/// The server never sees plaintext group keys or messages.
class E2eeService {
  E2eeService._();

  static final E2eeService instance = E2eeService._();

  static const _keyIdentityPrivate = 'e2ee_identity_private';
  static const _keyIdentityPublic = 'e2ee_identity_public';
  static const _keyGroupKeysPrefix = 'e2ee_group_keys_';

  static final Uint8List _chainInfoPrefix = utf8.encode('openfield:e2ee:chain.');
  static final Uint8List _ratchetInfo = utf8.encode('openfield:e2ee:ratchet');
  static final Uint8List _msgInfo = utf8.encode('openfield:e2ee:msg');
  static final Uint8List _attInfo = utf8.encode('openfield:e2ee:att');
  static final Uint8List _envelopeInfo = utf8.encode('openfield:e2ee:envelope');
  static final Uint8List _chatDbInfo = utf8.encode('openfield:e2ee:chatdb');

  bool _initialized = false;
  Uint8List? _identityPrivate;
  String? _identityPublic;
  final Map<int, Map<int, Uint8List>> _groupKeys = {};
  final Map<String, _ChainRec> _chainCache = {};

  /// The base64url-encoded identity public key, or null before [ensureIdentity].
  String? get identityPublicKey => _identityPublic;

  Future<void> _init() async {
    if (_initialized) return;
    await SecureKV.migrate();
    // Load all cached group keys into memory: `e2ee_group_keys_<convId>`
    // stores a JSON object mapping key-version -> base64 group key.
    final stored = await SecureKV.readAll();
    _identityPrivate = _tryDecode(stored[_keyIdentityPrivate]);
    _identityPublic = stored[_keyIdentityPublic];
    for (final entry in stored.entries) {
      if (!entry.key.startsWith(_keyGroupKeysPrefix)) continue;
      final convId = int.tryParse(entry.key.substring(_keyGroupKeysPrefix.length));
      if (convId == null) continue;
      try {
        final decoded = jsonDecode(entry.value);
        if (decoded is Map<String, dynamic>) {
          final versions = <int, Uint8List>{};
          for (final e in decoded.entries) {
            final v = int.tryParse(e.key);
            final gk = _tryDecode(e.value as String?);
            if (v != null && gk != null) versions[v] = gk;
          }
          if (versions.isNotEmpty) _groupKeys[convId] = versions;
        }
      } catch (_) {}
    }
    _initialized = true;
  }

  Uint8List? _tryDecode(String? b64) {
    if (b64 == null || b64.isEmpty) return null;
    try {
      return base64Url.decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Derives the key that seals the local encrypted-chat cache
  /// ([EncryptedChatDb]) from the user's E2EE identity private key via
  /// HKDF-SHA256. Returns null when no identity exists yet (a fresh device has
  /// an empty encrypted cache until [ensureIdentity] creates one).
  Future<Uint8List?> storageKey() async {
    await _init();
    final priv = _identityPrivate;
    if (priv == null) return null;
    return hkdfSha256(priv, info: _chatDbInfo, length: 32);
  }

  /// Loads the identity keypair (creating and publishing one on first run) and
  /// warms the in-memory group-key cache. Call once after login, before using
  /// the synchronous [encryptMessage]/[decryptMessage] methods.
  Future<void> ensureIdentity(ApiService api, String accessToken) async {
    await _init();
    if (_identityPrivate == null) {
      final (priv, pub) = generateX25519Keypair();
      _identityPrivate = priv;
      _identityPublic = base64Url.encode(pub);
      await SecureKV.write(_keyIdentityPrivate, base64Url.encode(priv));
      await SecureKV.write(_keyIdentityPublic, _identityPublic!);
    } else if (_identityPublic == null) {
      final pub = x25519PublicKey(_identityPrivate!);
      if (pub != null) {
        _identityPublic = base64Url.encode(pub);
        await SecureKV.write(_keyIdentityPublic, _identityPublic!);
      }
    }
    if (_identityPublic != null) {
      await _publishIdentity(api, accessToken, _identityPublic!);
    }
  }

  Future<void> _publishIdentity(ApiService api, String token, String pub) async {
    try {
      await api.updateE2EEKey(token, pub);
    } catch (_) {
      // Publishing is best-effort: a later conversation open will re-publish.
    }
  }

  /// The highest group-key version cached locally for [conversationId], or null
  /// when no key is available yet.
  int? currentVersion(int conversationId) {
    final versions = _groupKeys[conversationId];
    if (versions == null || versions.isEmpty) return null;
    var maxV = 0;
    for (final v in versions.keys) {
      if (v > maxV) maxV = v;
    }
    return maxV;
  }

  Uint8List? _groupKeyFor(int conversationId, int version) =>
      _groupKeys[conversationId]?[version];

  bool hasGroupKey(int conversationId) => currentVersion(conversationId) != null;

  /// Fetches the conversation's key envelopes from the server and decrypts the
  /// ones addressed to us, caching every newly available group key version.
  /// Returns the number of new versions stored (0 when nothing changed).
  Future<int> syncGroupKeys(
    ApiService api,
    String token,
    int conversationId,
    int myUserId,
  ) async {
    await _init();
    final data = await api.getE2EEKeys(token, conversationId);
    final envelopes = data['envelopes'];
    if (envelopes is! List) return 0;

    var added = 0;
    for (final e in envelopes) {
      if (e is! Map<String, dynamic>) continue;
      final version = e['version'] as int?;
      final target = e['target_user_id'] as int?;
      final cipher = e['ciphertext'] as String?;
      if (version == null ||
          target != myUserId ||
          cipher == null ||
          cipher.isEmpty) {
        continue;
      }
      if (_groupKeyFor(conversationId, version) != null) continue;
      final gk = _decryptEnvelope(cipher);
      if (gk == null) continue;
      _storeGroupKey(conversationId, version, gk);
      added++;
    }
    return added;
  }

  /// Rotates the conversation to a fresh group key: generates a new key, seals
  /// it to every member's published identity key (skipping members without
  /// one), uploads the envelopes and caches our own copy. Returns the new key
  /// version.
  Future<int> rotateGroupKey(
    ApiService api,
    String token,
    int conversationId,
    List<({int userId, String publicKey})> members,
  ) async {
    await _init();
    final gk = randomBytes(32);
    final envelopes = <int, String>{};
    for (final m in members) {
      final pub = _tryDecode(m.publicKey);
      if (pub == null || pub.length != 32) continue;
      final sealed = _encryptEnvelope(gk, pub);
      envelopes[m.userId] = sealed;
    }
    if (envelopes.isEmpty) {
      throw E2eeException('No member has a published encryption key');
    }
    final version = await api.putE2EEKeys(token, conversationId, envelopes);
    _storeGroupKey(conversationId, version, gk);
    // Drop any chain state for the old key versions so the new epoch starts
    // fresh for the sender's own ratchet.
    _chainCache.removeWhere((key, _) => key.startsWith('$conversationId:'));
    return version;
  }

  Uint8List? _decryptEnvelope(String b64) {
    final blob = _tryDecode(b64);
    if (blob == null || blob.length < 32 + 12 + 16) return null;
    if (_identityPrivate == null) return null;
    final ephemeral = blob.sublist(0, 32);
    final nonce = blob.sublist(32, 44);
    final cipher = blob.sublist(44);
    final shared = x25519(_identityPrivate!, ephemeral);
    if (shared == null) return null;
    final key = hkdfSha256(shared, info: _envelopeInfo, length: 32);
    return aes256GcmDecrypt(key: key, nonce: nonce, ciphertext: cipher);
  }

  String _encryptEnvelope(Uint8List groupKey, Uint8List memberPublic) {
    final (ephPriv, ephPub) = generateX25519Keypair();
    final shared = x25519(ephPriv, memberPublic);
    if (shared == null) throw E2eeException('Failed to derive shared secret');
    final key = hkdfSha256(shared, info: _envelopeInfo, length: 32);
    final nonce = randomBytes(12);
    final cipher = aes256GcmEncrypt(key: key, nonce: nonce, plaintext: groupKey);
    final blob = BytesBuilder()..add(ephPub)..add(nonce)..add(cipher);
    return base64Url.encode(blob.toBytes());
  }

  void _storeGroupKey(int conversationId, int version, Uint8List gk) {
    _groupKeys.putIfAbsent(conversationId, () => {})[version] = gk;
    final raw = _groupKeys[conversationId]!
        .map((v, key) => MapEntry('$v', base64Url.encode(key)));
    unawaited(SecureKV.write('$_keyGroupKeysPrefix$conversationId', jsonEncode(raw)));
  }

  Uint8List _chainRoot(Uint8List gk, int senderId) =>
      hkdfSha256(gk, info: _concat(_chainInfoPrefix, utf8.encode('$senderId')), length: 32);

  Uint8List _chainAdvance(Uint8List c) => hmacSha256(c, _ratchetInfo);

  Uint8List _messageKey(Uint8List c) => hkdfSha256(c, info: _msgInfo, length: 32);

  Uint8List _aad(int conversationId, int senderId, int version, int index) =>
      utf8.encode('openfield:e2ee:v1:$conversationId:$senderId:$version:$index');

  static Uint8List _concat(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length + b.length);
    out.setRange(0, a.length, a);
    out.setRange(a.length, a.length + b.length, b);
    return out;
  }

  String _chainCacheKey(int conversationId, int senderId, int version) =>
      '$conversationId:$senderId:$version';

  /// Encrypts [plaintext] for an encrypted conversation and returns the JSON
  /// envelope to be stored in the message's `content` field. Throws
  /// [E2eeException] when the conversation has no usable group key.
  String encryptMessage(int conversationId, int senderId, String plaintext) {
    final version = currentVersion(conversationId);
    if (version == null) {
      throw E2eeException('No encryption key available for this conversation');
    }
    final gk = _groupKeyFor(conversationId, version)!;
    final key = _chainCacheKey(conversationId, senderId, version);
    final rec = _chainCache[key];
    final index = rec?.nextIndex ?? 0;
    final c = rec != null ? rec.nextKey : _chainRoot(gk, senderId);
    final mk = _messageKey(c);
    final nonce = randomBytes(12);
    final cipher = aes256GcmEncrypt(
      key: mk,
      nonce: nonce,
      plaintext: utf8.encode(plaintext),
      aad: _aad(conversationId, senderId, version, index),
    );
    _chainCache[key] = _ChainRec(version, index + 1, _chainAdvance(c));
    return jsonEncode({
      'v': version,
      's': senderId,
      'i': index,
      'n': base64Url.encode(nonce),
      'c': base64Url.encode(cipher),
    });
  }

  /// Decrypts a message envelope. Returns the plaintext, or null when the
  /// message cannot be decrypted (missing group key for its version, wrong
  /// key, or tampered data).
  String? decryptMessage(int conversationId, int senderId, String envelopeJson) {
    Map<String, dynamic> env;
    try {
      final decoded = jsonDecode(envelopeJson);
      if (decoded is! Map<String, dynamic>) return null;
      env = decoded;
    } catch (_) {
      return null;
    }
    final version = env['v'] as int?;
    final sender = env['s'] as int?;
    final index = env['i'] as int?;
    final nonceB64 = env['n'] as String?;
    final cipherB64 = env['c'] as String?;
    if (version == null ||
        sender == null ||
        index == null ||
        nonceB64 == null ||
        cipherB64 == null) {
      return null;
    }
    final gk = _groupKeyFor(conversationId, version);
    if (gk == null) return null;

    final key = _chainCacheKey(conversationId, sender, version);
    final rec = _chainCache[key];
    Uint8List c;
    if (rec != null && rec.nextIndex <= index) {
      c = rec.nextKey;
      for (var n = 0; n < index - rec.nextIndex; n++) {
        c = _chainAdvance(c);
      }
    } else {
      var root = _chainRoot(gk, sender);
      for (var n = 0; n < index; n++) {
        root = _chainAdvance(root);
      }
      c = root;
    }

    final mk = _messageKey(c);
    final nonce = _tryDecode(nonceB64);
    final cipher = _tryDecode(cipherB64);
    if (nonce == null || cipher == null) return null;

    final plain = aes256GcmDecrypt(
      key: mk,
      nonce: nonce,
      ciphertext: cipher,
      aad: _aad(conversationId, sender, version, index),
    );
    if (plain == null) return null;

    if (rec == null || index + 1 > rec.nextIndex) {
      _chainCache[key] = _ChainRec(version, index + 1, _chainAdvance(c));
    }
    try {
      return utf8.decode(plain);
    } catch (_) {
      return null;
    }
  }

  /// Encrypts attachment [bytes] (the raw file) for [conversationId] under the
  /// conversation's current group key. Returns the group-key version the file
  /// was sealed under, the base64url-encoded GCM nonce, and the ciphertext —
  /// the latter is what gets uploaded to the server. Returns null when no
  /// group key is cached yet.
  ({int version, String nonceB64, Uint8List cipher})? encryptAttachment(
    int conversationId,
    Uint8List bytes,
  ) {
    final version = currentVersion(conversationId);
    if (version == null) return null;
    final gk = _groupKeyFor(conversationId, version)!;
    final key = hkdfSha256(gk, info: _attInfo, length: 32);
    final nonce = randomBytes(12);
    final cipher = aes256GcmEncrypt(key: key, nonce: nonce, plaintext: bytes);
    return (version: version, nonceB64: base64Url.encode(nonce), cipher: cipher);
  }

  /// Decrypts attachment ciphertext sealed under [version] with the nonce
  /// returned by [encryptAttachment]. Returns null when the matching group key
  /// is missing or the data does not authenticate.
  Uint8List? decryptAttachment(
    int conversationId,
    int version,
    String nonceB64,
    Uint8List cipher,
  ) {
    final gk = _groupKeyFor(conversationId, version);
    if (gk == null) return null;
    final key = hkdfSha256(gk, info: _attInfo, length: 32);
    final nonce = _tryDecode(nonceB64);
    if (nonce == null || nonce.length != 12) return null;
    return aes256GcmDecrypt(key: key, nonce: nonce, ciphertext: cipher);
  }
}
