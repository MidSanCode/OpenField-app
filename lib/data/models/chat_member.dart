class ChatMember {
  final int conversationId;
  final int userId;
  final String role; // owner | admin | member
  final String note;
  final String groupNickname;
  final String status; // pending | active | declined
  final int addedBy;
  final DateTime createdAt;
  final String? username;
  final String? nickname;
  final String? avatarUrl;
  final bool isVerified;

  const ChatMember({
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.note,
    required this.groupNickname,
    required this.status,
    required this.addedBy,
    required this.createdAt,
    this.username,
    this.nickname,
    this.avatarUrl,
    this.isVerified = false,
  });

  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    return ChatMember(
      conversationId: json['conversation_id'] as int,
      userId: json['user_id'] as int,
      role: json['role'] as String? ?? 'member',
      note: json['note'] as String? ?? '',
      groupNickname: json['group_nickname'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      addedBy: json['added_by'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
    );
  }
}
