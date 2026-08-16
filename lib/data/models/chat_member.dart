class ChatMember {
  final int conversationId;
  final int userId;
  final String role; // owner | admin | member
  final String note;
  final String groupNickname;
  final String title;
  final String status; // pending | active | declined
  final int addedBy;
  final DateTime createdAt;
  final DateTime? mutedUntil;
  final String? username;
  final String? nickname;
  final String? avatarUrl;
  final bool isVerified;
  final int memberLevel;
  final bool memberActive;
  final String nameColor;
  final String nameColorTo;
  final bool nameDynamic;
  final List<String> nameColors;
  final String nameGradientDirection;
  final String avatarFrame;
  final String? e2eePublicKey;

  /// Per-conversation chat notification preference: 'all' (every message),
  /// 'mentions' (only when @-mentioned) or 'none'. Server default is 'all'.
  final String notifyLevel;

  const ChatMember({
    required this.conversationId,
    required this.userId,
    required this.role,
    required this.note,
    required this.groupNickname,
    required this.status,
    required this.addedBy,
    required this.createdAt,
    this.title = '',
    this.mutedUntil,
    this.username,
    this.nickname,
    this.avatarUrl,
    this.isVerified = false,
    this.memberLevel = 0,
    this.memberActive = false,
    this.nameColor = '',
    this.nameColorTo = '',
    this.nameDynamic = false,
    this.nameColors = const [],
    this.nameGradientDirection = '',
    this.avatarFrame = '',
    this.e2eePublicKey,
    this.notifyLevel = 'all',
  });

  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  bool get isMuted {
    final until = mutedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  ChatMember copyWith({
    String? role,
    String? note,
    String? groupNickname,
    String? title,
    DateTime? mutedUntil,
    String? notifyLevel,
  }) {
    return ChatMember(
      conversationId: conversationId,
      userId: userId,
      role: role ?? this.role,
      note: note ?? this.note,
      groupNickname: groupNickname ?? this.groupNickname,
      title: title ?? this.title,
      status: status,
      addedBy: addedBy,
      createdAt: createdAt,
      mutedUntil: mutedUntil ?? this.mutedUntil,
      username: username,
      nickname: nickname,
      avatarUrl: avatarUrl,
      isVerified: isVerified,
      memberLevel: memberLevel,
      memberActive: memberActive,
      nameColor: nameColor,
      nameColorTo: nameColorTo,
      nameDynamic: nameDynamic,
      nameColors: nameColors,
      nameGradientDirection: nameGradientDirection,
      avatarFrame: avatarFrame,
      e2eePublicKey: e2eePublicKey,
      notifyLevel: notifyLevel ?? this.notifyLevel,
    );
  }

  factory ChatMember.fromJson(Map<String, dynamic> json) {
    final muted = json['muted_until'];
    return ChatMember(
      conversationId: _asInt(json['conversation_id']),
      userId: _asInt(json['user_id']),
      role: json['role'] as String? ?? 'member',
      note: json['note'] as String? ?? '',
      groupNickname: json['group_nickname'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'active',
      addedBy: _asInt(json['added_by']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      mutedUntil: _asDate(muted),
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      memberLevel: _asInt(json['member_level']),
      memberActive: json['member_active'] as bool? ?? false,
      nameColor: json['name_color'] as String? ?? '',
      nameColorTo: json['name_color_to'] as String? ?? '',
      nameDynamic: json['name_dynamic'] as bool? ?? false,
      nameColors: _asStringList(json['name_colors']),
      nameGradientDirection: json['name_gradient_direction'] as String? ?? '',
      avatarFrame: json['avatar_frame'] as String? ?? '',
      e2eePublicKey: json['e2ee_public_key'] as String?,
      notifyLevel: json['notify_level'] as String? ?? 'all',
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

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }
}
