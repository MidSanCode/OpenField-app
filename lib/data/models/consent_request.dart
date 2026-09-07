/// A consent flow item: another user asking permission to start a private
/// chat or to invite this user into a group.
class ConsentRequest {
  /// Server-assigned request id.
  final int id;
  /// What the requester wants: 'private_chat' or 'group_invite'.
  final String type; // private_chat | group_invite
  /// User who sent the request.
  final int requesterId;
  /// User whose approval is needed (the viewer, usually).
  final int targetUserId;
  /// Conversation for group invites; null for private-chat requests.
  final int? conversationId;
  /// Free-form message the requester attached ('' when none).
  final String message;
  /// Request state: 'pending' until accepted or declined.
  final String status;
  /// When the request was created (server timestamp).
  final DateTime createdAt;
  /// When the target responded; null while still pending.
  final DateTime? respondedAt;
  /// Requester's display name, when the payload includes it.
  final String? requesterName;
  /// Requester's avatar URL, when the payload includes it.
  final String? requesterAvatar;
  /// Group title for group invites, when the payload includes it.
  final String? groupTitle;

  /// Creates a consent request; see [fromJson] for payload defaults.
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

  /// True when this request invites the user into a group (vs. a private
  /// chat request).
  bool get isGroupInvite => type == 'group_invite';

  /// Requester's display name, or 'Unknown' when absent.
  String get requesterDisplay => requesterName ?? 'Unknown';

  /// Deserializes from the server's consent payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
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
