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
  });

  bool get isDeleted => deletedAt != null;
  bool get isEdited => editedAt != null;

  String get displayName => senderName ?? 'Unknown';

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
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
    );
  }
}
