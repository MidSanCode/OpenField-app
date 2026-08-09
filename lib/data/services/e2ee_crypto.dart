/// Low-level primitives for OpenField's pragmatic E2EE layer.
///
/// Key exchange uses X25519 (RFC 7748, implemented here because the available
/// pointycastle release does not ship Curve25519), group key envelopes are
/// sealed with AES-256-GCM, and key material is derived with HKDF-SHA256.
/// Everything is deterministic and library-only, so the same code runs on
/// mobile, desktop and web.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

final BigInt _p25519 = (BigInt.one << 255) - BigInt.from(19);
final BigInt _a24 = BigInt.from(121665);

/// Cryptographically secure random bytes.
Uint8List randomBytes(int length) {
  final rand = Random.secure();
  final out = Uint8List(length);
  for (var i = 0; i < length; i++) {
    out[i] = rand.nextInt(256);
  }
  return out;
}

BigInt _decodeLittleEndian(Uint8List b) {
  var v = BigInt.zero;
  for (var i = b.length - 1; i >= 0; i--) {
    v = (v << 8) | BigInt.from(b[i]);
  }
  return v;
}

Uint8List _encodeLittleEndian(BigInt v) {
  final out = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}

Uint8List _clampScalar(Uint8List k) {
  final out = Uint8List.fromList(k);
  out[0] &= 248;
  out[31] &= 127;
  out[31] |= 64;
  return out;
}

/// Performs an X25519 Diffie-Hellman exchange between [privateKey] and
/// [publicKey]. Returns null when the shared secret would be all zeroes (a
/// low-order point, which must never be used as a key).
Uint8List? x25519(Uint8List privateKey, Uint8List publicKey) {
  if (privateKey.length != 32 || publicKey.length != 32) return null;

  final scalar = _decodeLittleEndian(_clampScalar(privateKey));
  final x1 = _decodeLittleEndian(publicKey) & ((BigInt.one << 255) - BigInt.one);

  var x2 = BigInt.one;
  var z2 = BigInt.zero;
  var x3 = x1;
  var z3 = BigInt.one;
  var swap = false;

  for (var t = 254; t >= 0; t--) {
    final kt = (scalar >> t) & BigInt.one;
    final shouldSwap = swap != (kt == BigInt.one);
    if (shouldSwap) {
      var tmp = x2;
      x2 = x3;
      x3 = tmp;
      tmp = z2;
      z2 = z3;
      z3 = tmp;
    }
    swap = kt == BigInt.one;

    final a = (x2 + z2) % _p25519;
    final aa = (a * a) % _p25519;
    final b = (x2 - z2) % _p25519;
    final bb = (b * b) % _p25519;
    final e = (aa - bb) % _p25519;
    final c = (x3 + z3) % _p25519;
    final d = (x3 - z3) % _p25519;
    final da = (d * a) % _p25519;
    final cb = (c * b) % _p25519;
    x3 = (da + cb) * (da + cb) % _p25519;
    z3 = (x1 * ((da - cb) * (da - cb) % _p25519)) % _p25519;
    x2 = (aa * bb) % _p25519;
    z2 = (e * ((aa + (_a24 * e) % _p25519) % _p25519)) % _p25519;
  }

  if (swap) {
    var tmp = x2;
    x2 = x3;
    x3 = tmp;
    tmp = z2;
    z2 = z3;
    z3 = tmp;
  }

  final zInv = z2.modPow(_p25519 - BigInt.from(2), _p25519);
  final result = (x2 * zInv) % _p25519;
  if (result == BigInt.zero) return null;
  return _encodeLittleEndian(result);
}

/// The X25519 base point (u = 9).
final Uint8List _x25519BasePoint = () {
  final b = Uint8List(32);
  b[0] = 9;
  return b;
}();

/// Derives the X25519 public key for a 32-byte private key.
Uint8List? x25519PublicKey(Uint8List privateKey) =>
    x25519(privateKey, _x25519BasePoint);

/// Generates a fresh X25519 keypair. The returned record holds the raw 32-byte
/// private key and its public key.
(Uint8List privateKey, Uint8List publicKey) generateX25519Keypair() {
  final private = randomBytes(32);
  final public = x25519PublicKey(private)!;
  return (private, public);
}

/// HKDF-SHA256 (RFC 5869). When [salt] is empty a zero-filled salt of the hash
/// length is used. [length] is the number of output bytes.
Uint8List hkdfSha256(
  Uint8List ikm, {
  Uint8List? salt,
  required Uint8List info,
  required int length,
}) {
  final effectiveSalt = (salt == null || salt.isEmpty) ? Uint8List(32) : salt;
  final prk = Uint8List.fromList(Hmac(sha256, effectiveSalt).convert(ikm).bytes);

  final out = Uint8List(length);
  var t = Uint8List(0);
  var offset = 0;
  var counter = 1;
  while (offset < length) {
    final builder = BytesBuilder()..add(t)..add(info)..addByte(counter);
    t = Uint8List.fromList(Hmac(sha256, prk).convert(builder.takeBytes()).bytes);
    final n = min(t.length, length - offset);
    out.setRange(offset, offset + n, t, 0);
    offset += n;
    counter++;
  }
  return out;
}

/// HMAC-SHA256 helper.
Uint8List hmacSha256(Uint8List key, Uint8List data) =>
    Uint8List.fromList(Hmac(sha256, key).convert(data).bytes);

/// Encrypts [plaintext] with AES-256-GCM. Returns the concatenation of the
/// ciphertext and the 16-byte authentication tag.
Uint8List aes256GcmEncrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List plaintext,
  Uint8List? aad,
}) {
  if (key.length != 32) throw ArgumentError('AES-256 key must be 32 bytes');
  if (nonce.length != 12) throw ArgumentError('GCM nonce must be 12 bytes');
  final cipher = GCMBlockCipher(AESEngine());
  cipher.init(
    true,
    AEADParameters(KeyParameter(key), 128, nonce, aad ?? Uint8List(0)),
  );
  return cipher.process(plaintext);
}

/// Decrypts the output of [aes256GcmEncrypt]. Returns null when the tag does
/// not authenticate (wrong key, nonce or tampered data).
Uint8List? aes256GcmDecrypt({
  required Uint8List key,
  required Uint8List nonce,
  required Uint8List ciphertext,
  Uint8List? aad,
}) {
  if (key.length != 32) return null;
  if (nonce.length != 12) return null;
  try {
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
      false,
      AEADParameters(KeyParameter(key), 128, nonce, aad ?? Uint8List(0)),
    );
    return cipher.process(ciphertext);
  } catch (_) {
    return null;
  }
}
