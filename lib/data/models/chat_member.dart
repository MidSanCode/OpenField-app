class ChatMember {
  final int conversationId;
  final int userId;
  final String role; // owner | admin | member
  final String note;
  final String groupNickname;
  final String status; // pending | active | declined
  final int addedBy;
  final DateTime createdAt;
  final DateTime? mutedUntil;
  final String? username;
  final String? nickname;
  final String? avatarUrl;
  final bool isVerified;
  final String? e2eePublicKey;

  const ChatMember({
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.note,
    required this.groupNickname,
    required this.status,
    required this.addedBy,
    required this.createdAt,
    this.mutedUntil,
    this.username,
    this.nickname,
    this.avatarUrl,
    this.isVerified = false,
    this.e2eePublicKey,
  });

  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  bool get isMuted {
    final until = mutedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    final muted = json['muted_until'];
    return ChatMember(
      conversationId: json['conversation_id'] as int,
      userId: json['user_id'] as int,
      role: json['role'] as String? ?? 'member',
      note: json['note'] as String? ?? '',
      groupNickname: json['group_nickname'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      addedBy: json['added_by'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      mutedUntil: muted != null ? DateTime.parse(muted as String) : null,
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      e2eePublicKey: json['e2ee_public_key'] as String?,
    );
  }
}
