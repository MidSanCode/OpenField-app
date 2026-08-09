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
      id: _asInt(json['id']),
      type: json['type'] as String? ?? 'private_chat',
      requesterId: _asInt(json['requester_id']),
      targetUserId: _asInt(json['target_user_id']),
      conversationId: json['conversation_id'] is num
          ? (json['conversation_id'] as num).toInt()
          : json['conversation_id'] is String
              ? int.tryParse(json['conversation_id'] as String)
              : null,
      message: json['message'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      respondedAt: _asDate(json['responded_at']),
      requesterName: json['requester_name'] as String?,
      requesterAvatar: json['requester_avatar'] as String?,
      groupTitle: json['group_title'] as String?,
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
}
