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
  final int? replyToId;
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

  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    required this.createdAt,
    this.replyToId,
    this.editedAt,
    this.deletedAt,
    this.senderName,
    this.senderAvatar,
    this.senderVerified = false,
    this.attachments = const [],
    String? clientId,
    this.status = MessageStatus.sent,
  }) : clientId = clientId ?? '';

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;
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
      replyToId: replyToId,
      editedAt: editedAt,
      deletedAt: deletedAt,
      createdAt: createdAt,
      senderName: senderName,
      senderAvatar: senderAvatar,
      senderVerified: senderVerified,
      attachments: attachments,
      clientId: clientId,
      status: status ?? MessageStatus.sent,
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
      id: json['id'] as int,
      conversationId: json['conversation_id'] as int,
      senderId: json['sender_id'] as int,
      content: json['content'] as String? ?? '',
      replyToId: json['reply_to_id'] as int?,
      editedAt: json['edited_at'] != null ? DateTime.parse(json['edited_at'] as String) : null,
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderName: json['sender_name'] as String?,
      senderAvatar: json['sender_avatar'] as String?,
      senderVerified: json['sender_verified'] as bool? ?? false,
      attachments: attachments,
    );
  }
}

/// Generates a unique client-side message id. Uses a timestamp + random suffix
/// so it is monotonic within a session and unique across devices.
String generateClientId() {
  final ts = DateTime.now().microsecondsSinceEpoch;
  final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
  return '$ts-$rand';
}
