class ConsentRequest {
  final int id;
  final String type; // private_chat | group_invite
  final int requesterId;
  final int targetUserId;
  final int? conversationId;
  final String message;
  final String status;
  final DateTime createdAt;
  final DateTime? respondedAt;
  final String? requesterName;
  final String? requesterAvatar;
  final String? groupTitle;

  const ConsentRequest({
    required this.id,
    required this.type,
    required this.requesterId,
    required this.targetUserId,
    required this.message,
    required this.status,
    required this.createdAt,
    this.conversationId,
    this.respondedAt,
    this.requesterName,
    this.requesterAvatar,
    this.groupTitle,
  });

  bool get isGroupInvite => type == 'group_invite';

  String get requesterDisplay => requesterName ?? 'Unknown';

  factory ConsentRequest.fromJson(Map<String, dynamic> json) {
    return ConsentRequest(
      id: json['id'] as int,
      type: json['type'] as String? ?? 'private_chat',
      requesterId: json['requester_id'] as int,
      targetUserId: json['target_user_id'] as int,
      conversationId: json['conversation_id'] as int?,
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      respondedAt: json['responded_at'] != null ? DateTime.parse(json['responded_at'] as String) : null,
      requesterName: json['requester_name'] as String?,
      requesterAvatar: json['requester_avatar'] as String?,
      groupTitle: json['group_title'] as String?,
    );
  }
}
