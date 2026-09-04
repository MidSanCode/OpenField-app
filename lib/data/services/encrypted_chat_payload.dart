// Sealing/serialisation shared by the encrypted chat cache implementations
// (IO and web). Rows keep only the id / conversation / timestamp in clear;
// everything sensitive is sealed in the payload blob.

import 'dart:convert';
import 'dart:typed_data';

import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/services/e2ee_crypto.dart';

/// Serialises the message's sensitive fields into a JSON map (attachments
/// inlined).
Map<String, dynamic> encryptedPayloadJson(ChatMessage m) => {
      'sender_id': m.senderId,
      'content': m.content,
      'kind': m.kind,
      'reply_to_id': m.replyToId,
      'reply_to_name': m.replyToName,
      'reply_to_content': m.replyToContent,
      'edited_at': m.editedAt?.toIso8601String(),
      'deleted_at': m.deletedAt?.toIso8601String(),
      'sender_name': m.senderName,
      'sender_avatar': m.senderAvatar,
      'sender_verified': m.senderVerified,
      'client_id': m.clientId,
      'status': m.status.index,
      'decrypted_content': m.decryptedContent,
      'mentions': m.mentions,
      'attachments': m.attachments.map((a) => a.toJson()).toList(),
    };

/// Seals the message payload with AES-256-GCM. Returns `nonce || ciphertext`,
/// or null when encryption fails (callers skip the row rather than store
/// plaintext).
Uint8List? sealMessagePayload(ChatMessage m, Uint8List key) {
  final plaintext = utf8.encode(jsonEncode(encryptedPayloadJson(m)));
  final nonce = randomBytes(12);
  try {
    final cipher = aes256GcmEncrypt(
      key: key,
      nonce: nonce,
      plaintext: Uint8List.fromList(plaintext),
    );
    final builder = BytesBuilder()..add(nonce)..add(cipher);
    return builder.takeBytes();
  } catch (_) {
    return null;
  }
}

/// Decrypts a payload blob back into a [ChatMessage]. Rows that fail to
/// authenticate (key mismatch, tampering) return an empty placeholder so the
/// conversation view never crashes on stale cache.
ChatMessage openMessagePayload(
  Object? raw,
  Uint8List key,
  int id,
  int conversationId,
  DateTime createdAt,
) {
  Uint8List? bytes;
  if (raw is Uint8List) {
    bytes = raw;
  } else if (raw is List<int>) {
    bytes = Uint8List.fromList(raw);
  }
  if (bytes != null && bytes.length > 12) {
    final nonce = bytes.sublist(0, 12);
    final cipher = bytes.sublist(12);
    final plain = aes256GcmDecrypt(key: key, nonce: nonce, ciphertext: cipher);
    if (plain != null) {
      try {
        final decoded = jsonDecode(utf8.decode(plain));
        if (decoded is Map<String, dynamic>) {
          return _messageFromJson(decoded, id, conversationId, createdAt);
        }
      } catch (_) {}
    }
  }
  return ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: 0,
    content: '',
    createdAt: createdAt,
    kind: 'text',
  );
}

ChatMessage _messageFromJson(
  Map<String, dynamic> j,
  int id,
  int conversationId,
  DateTime createdAt,
) {
  final attachments = <Attachment>[];
  final rawAtts = j['attachments'];
  if (rawAtts is List) {
    for (final a in rawAtts) {
      if (a is Map<String, dynamic>) {
        try {
          attachments.add(Attachment.fromJson(a));
        } catch (_) {}
      }
    }
  }
  final statusRaw = j['status'] as int? ?? MessageStatus.sent.index;
  final status = MessageStatus.values.length > statusRaw
      ? MessageStatus.values[statusRaw]
      : MessageStatus.sent;
  final rawMentions = j['mentions'];
  final mentions = rawMentions is List
      ? rawMentions.whereType<int>().toList()
      : const <int>[];
  return ChatMessage(
    id: id,
    conversationId: conversationId,
    senderId: j['sender_id'] as int? ?? 0,
    content: j['content'] as String? ?? '',
    kind: j['kind'] as String? ?? 'text',
    replyToId: j['reply_to_id'] as int?,
    replyToName: j['reply_to_name'] as String?,
    replyToContent: j['reply_to_content'] as String?,
    editedAt: _asDate(j['edited_at']),
    deletedAt: _asDate(j['deleted_at']),
    createdAt: createdAt,
    senderName: j['sender_name'] as String?,
    senderAvatar: j['sender_avatar'] as String?,
    senderVerified: j['sender_verified'] as bool? ?? false,
    clientId: j['client_id'] as String? ?? '',
    status: status,
    decryptedContent: j['decrypted_content'] as String?,
    mentions: mentions,
    attachments: attachments,
  );
}

DateTime? _asDate(Object? value) {
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}
