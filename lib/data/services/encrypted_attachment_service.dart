import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/e2ee_service.dart';
import 'package:openfield/data/services/media_cache.dart';

/// Decrypts E2EE-encrypted attachments to local files so they can be previewed
/// and opened.
///
/// Attachments shared in an encrypted conversation are uploaded as AES-GCM
/// ciphertext (the server never sees the plaintext file). [decryptToFile]
/// downloads the ciphertext blob, decrypts it with the conversation's group key
/// and writes the recovered file to the temporary directory. Results are cached
/// by attachment id for the lifetime of the process; concurrent requests for
/// the same attachment share a single download/decrypt.
class EncryptedAttachmentService {
  EncryptedAttachmentService._();

  static final EncryptedAttachmentService instance =
      EncryptedAttachmentService._();

  final Map<int, String> _localFiles = {};
  final Map<int, Future<String>> _inFlight = {};

  /// Decrypts [att] for [conversationId] and returns the path of the recovered
  /// local file. Throws on download/decrypt failure.
  Future<String> decryptToFile(int conversationId, Attachment att) async {
    final cached = _localFiles[att.id];
    if (cached != null && File(cached).existsSync()) return cached;

    final existing = _inFlight[att.id];
    if (existing != null) return existing;

    final future = _doDecrypt(conversationId, att);
    _inFlight[att.id] = future;
    try {
      final path = await future;
      _localFiles[att.id] = path;
      return path;
    } finally {
      _inFlight.remove(att.id);
    }
  }

  Future<String> _doDecrypt(int conversationId, Attachment att) async {
    final version = att.cryptoVersion;
    final nonce = att.cryptoNonce;
    if (version == null || nonce.isEmpty) {
      throw StateError('Attachment ${att.id} is not encrypted');
    }
    final cipher = await MediaCache.instance.loadBytes(att.url);
    final plain = E2eeService.instance
        .decryptAttachment(conversationId, version, nonce, cipher);
    if (plain == null) {
      throw StateError('Failed to decrypt attachment ${att.id}');
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}e2ee_${att.id}_${DateTime.now().microsecondsSinceEpoch}${_extensionFor(att)}',
    );
    await file.writeAsBytes(plain, flush: true);
    return file.path;
  }

  static const Map<String, String> _extByMime = {
    'image/jpeg': '.jpg',
    'image/png': '.png',
    'image/gif': '.gif',
    'image/webp': '.webp',
    'image/heic': '.heic',
    'image/bmp': '.bmp',
    'image/svg+xml': '.svg',
    'video/mp4': '.mp4',
    'video/webm': '.webm',
    'video/quicktime': '.mov',
    'video/x-matroska': '.mkv',
    'audio/mpeg': '.mp3',
    'audio/mp3': '.mp3',
    'audio/wav': '.wav',
    'audio/x-wav': '.wav',
    'audio/ogg': '.ogg',
    'audio/opus': '.opus',
    'audio/aac': '.aac',
    'audio/x-m4a': '.m4a',
    'audio/flac': '.flac',
    'text/plain': '.txt',
    'text/markdown': '.md',
    'text/csv': '.csv',
    'application/pdf': '.pdf',
    'application/json': '.json',
  };

  String _extensionFor(Attachment att) {
    final byMime = _extByMime[att.originalMime];
    if (byMime != null) return byMime;
    if (att.originalName.contains('.')) {
      final dot = att.originalName.lastIndexOf('.');
      final ext = att.originalName.substring(dot);
      return ext.length > 1 && ext.length <= 6 ? ext : '';
    }
    return '';
  }
}
