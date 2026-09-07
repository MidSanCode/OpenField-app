/// One user's membership in a conversation: role, moderation state and
/// denormalized profile/styling of that user.
class ChatMember {
  /// Conversation this membership belongs to.
  final int conversationId;
  /// The member's user id.
  final int userId;
  /// Role within the conversation.
  final String role; // owner | admin | member
  /// Operator-set note about this member (only visible to operators).
  final String note;
  /// Member's nickname inside this conversation ('' = use their global name).
  final String groupNickname;
  /// Member title granted in this conversation ('' = none).
  final String title;
  /// Join request state for pending memberships.
  final String status; // pending | active | declined
  /// User id of the member who added this user (0 when they joined directly).
  final int addedBy;
  /// When the membership was created (server timestamp).
  final DateTime createdAt;
  /// When this member's mute expires; null = not muted.
  final DateTime? mutedUntil;
  /// Member's @username, when the payload includes it.
  final String? username;
  /// Member's global nickname, when the payload includes it.
  final String? nickname;
  /// Member's avatar URL, when the payload includes it.
  final String? avatarUrl;
  /// Whether the member carries a verification badge.
  final bool isVerified;
  /// Whether the member is a bot account.
  final bool isBot;
  /// Member's membership tier (0 = none).
  final int memberLevel;
  /// Whether the member's membership is currently active.
  final bool memberActive;
  /// Member's name colour as a hex string ('' = default rendering).
  final String nameColor;
  /// Second name colour for gradients ('' = none).
  final String nameColorTo;
  /// Whether the name colour animates over time.
  final bool nameDynamic;
  /// Palette for dynamic names; empty = use [nameColor]/[nameColorTo].
  final List<String> nameColors;
  /// Gradient direction hint for the name colours ('' = default).
  final String nameGradientDirection;
  /// Avatar frame asset key ('' = no frame).
  final String avatarFrame;
  /// The member's E2EE identity public key, when published; null otherwise.
  final String? e2eePublicKey;

  /// Per-conversation chat notification preference: 'all' (every message),
  /// 'mentions' (only when @-mentioned) or 'none'. Server default is 'all'.
  final String notifyLevel;

  /// Creates a member; see [fromJson] for payload defaults.
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
    this.isBot = false,
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

  /// The member's display name: nickname when non-empty, else username,
  /// else 'Unknown'.
  String get displayName =>
      (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  /// True while the member's mute deadline is in the future (checked against
  /// the current wall clock at call time).
  bool get isMuted {
    final until = mutedUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Returns a copy with only the listed fields replaced (role, note, group
  /// nickname, title, mute and notify level); every other field, including
  /// identity and profile data, is preserved as-is, and a null argument
  /// keeps the current value.
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

  /// Deserializes from the server's member payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
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
      isBot: json['is_bot'] as bool? ?? false,
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
