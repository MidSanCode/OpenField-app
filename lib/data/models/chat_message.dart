import 'dart:convert';
import 'dart:math';
import 'attachment.dart';

/// How a message relates to the server. [sent] is confirmed; [sending] and
/// [failed] are local-only states for optimistic UI.
enum MessageStatus { sending, sent, failed }

class ChatMessage {
  final int id;
  final int conversationId;
  final int senderId;
  final String content;

  /// Server-side message kind: 'text' or system kinds such as
  /// 'system.join' / 'system.leave' / 'system.mute' / 'system.unmute' /
  /// 'system.mute.all' / 'system.unmute.all'.
  final String kind;
  final int? replyToId;
  final String? replyToName;
  final String? replyToContent;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime createdAt;
  final String? senderName;
  final String? senderAvatar;
  final bool senderVerified;
  final List<Attachment> attachments;

  /// Local, client-generated identity used to track a message before the
  /// server assigns an [id] (optimistic sends) and to keep ordering stable.
  final String clientId;

  /// Local send state. Only meaningful for the current user's own messages.
  final MessageStatus status;

  /// The decrypted plaintext of an end-to-end-encrypted message, populated
  /// locally after a successful decrypt. When null, [content] holds the
  /// ciphertext envelope (for encrypted conversations).
  final String? decryptedContent;

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.kind = 'text',
    required this.createdAt,
    this.replyToId,
    this.replyToName,
    this.replyToContent,
    this.editedAt,
    this.deletedAt,
    this.senderName,
    this.senderAvatar,
    this.senderVerified = false,
    this.attachments = const [],
    String? clientId,
    this.status = MessageStatus.sent,
    this.decryptedContent,
  }) : clientId = clientId ?? '';

  /// The text to display: the decrypted plaintext for E2EE messages, otherwise
  /// the raw content. Undecryptable E2EE envelopes are masked so the raw
  /// ciphertext never leaks into the UI.
  String get displayContent {
    if (decryptedContent != null) return decryptedContent!;
    return isEnvelope ? '' : content;
  }

  /// True when [content] looks like an E2EE envelope (a JSON object carrying
  /// the version/sender/index/nonce/cipher fields). Used to avoid rendering
  /// ciphertext when a message could not be decrypted.
  bool get isEnvelope {
    final t = content.trimLeft();
    if (!t.startsWith('{')) return false;
    final decoded = _tryDecodeJson(t);
    return decoded is Map<String, dynamic> &&
        decoded.containsKey('v') &&
        decoded.containsKey('c');
  }

  /// True when this is a text message from an encrypted conversation that has
  /// not been decrypted yet.
  bool get needsDecryption => decryptedContent == null && !isSystem;

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
  bool get isSystem => kind.startsWith('system.');
  bool get isJoin => kind == 'system.join';
  bool get isLeave => kind == 'system.leave';
  bool get isLocal => id <= 0;
  bool get isPending => status == MessageStatus.sending;
  bool get isFailed => status == MessageStatus.failed;

  String get displayName => senderName ?? 'Unknown';

  /// Stable ordering key: newest timestamp wins; ties broken by id so locally
  /// created messages sort by creation time, not by insertion.
  int compareForOrder(ChatMessage other) {
    final c = other.createdAt.compareTo(createdAt);
    if (c != 0) return c;
    return other.id.compareTo(id);
  }

  /// Copy with a new status / server fields (used when an optimistic send
  /// resolves).
  ChatMessage resolve({int? serverId, MessageStatus? status}) {
    return ChatMessage(
      id: serverId ?? id,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      kind: kind,
      replyToId: replyToId,
      replyToName: replyToName,
      replyToContent: replyToContent,
      editedAt: editedAt,
      deletedAt: deletedAt,
      createdAt: createdAt,
      senderName: senderName,
      senderAvatar: senderAvatar,
      senderVerified: senderVerified,
      attachments: attachments,
      clientId: clientId,
      status: status ?? MessageStatus.sent,
      decryptedContent: decryptedContent,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    List<Attachment> attachments = const [];
    if (rawAttachments is List) {
      attachments = rawAttachments
          .whereType<Map<String, dynamic>>()
          .map((a) => Attachment.fromJson(a))
          .toList();
    }
    return ChatMessage(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversation_id']),
      senderId: _asInt(json['sender_id']),
      content: json['content'] as String? ?? '',
      kind: json['kind'] as String? ?? 'text',
      replyToId: json['reply_to_id'] is num ? (json['reply_to_id'] as num).toInt() : null,
      replyToName: json['reply_to_name'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      editedAt: _asDate(json['edited_at']),
      deletedAt: _asDate(json['deleted_at']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      senderName: json['sender_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
      senderVerified: json['sender_verified'] as bool? ?? false,
      attachments: attachments,
    );
  }

  /// Safely coerces an id field, tolerating strings and missing values so a
  /// schema change on the server never crashes the client.
  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  static DateTime? _asDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    try {
      return DateTime.parse(value.toString());
    } catch (_) {
      return null;
    }
  }

  static Object? _tryDecodeJson(String input) {
    try {
      return jsonDecode(input);
    } catch (_) {
      return null;
    }
  }
}

/// Generates a unique client-side message id. Uses a timestamp + random suffix
/// so it is monotonic within a session and unique across devices.
String generateClientId() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '$ts-$rand';
}
