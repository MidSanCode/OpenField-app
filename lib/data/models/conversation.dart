import 'chat_message.dart';
import 'chat_member.dart';

/// A chat conversation: a 1:1 private thread or a group, with denormalized
/// viewer state (membership, unread count, last message).
class Conversation {
  /// Server-assigned conversation id.
  final int id;
  /// Conversation kind: 'private' or 'group'.
  final String type; // private | group
  /// Display title ('' when the server does not set one).
  final String title;
  /// Conversation avatar URL ('' when unset).
  final String avatarUrl;
  /// User id of the group owner (0 when unknown / not a group).
  final int ownerId;
  /// When the conversation was created (server timestamp).
  final DateTime createdAt;
  /// When the conversation was last updated (server timestamp).
  final DateTime updatedAt;
  /// Whether the group is publicly listed/discoverable.
  final bool isPublic;
  /// Whether users can join without an approval step.
  final bool allowJoin;
  /// Until when the whole group is muted; null = not muted.
  final DateTime? muteAllUntil;
  /// Whether messages in this conversation are end-to-end encrypted.
  final bool encrypted;
  /// Current member count.
  final int memberCount;
  /// Whether the current viewer is a member.
  final bool isMember;
  /// Most recent message, for list previews; null when empty.
  final ChatMessage? lastMessage;
  /// Messages the current viewer has not read yet.
  final int unread;

  /// Creates a conversation; see [fromJson] for payload defaults.
  const Conversation({
    required this.id,
    required this.type,
    required this.title,
    required this.avatarUrl,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.isPublic = false,
    this.allowJoin = false,
    this.muteAllUntil,
    this.encrypted = false,
    this.memberCount = 0,
    this.isMember = false,
    this.lastMessage,
    this.unread = 0,
  });

  /// True for group conversations.
  bool get isGroup => type == 'group';

  /// True when the viewer can join right away: a public group with direct
  /// joins enabled.
  bool get canJoinDirectly => isGroup && isPublic && allowJoin;

  /// True while the group-wide mute deadline is in the future (checked
  /// against the current wall clock at call time).
  bool get isGroupMuted {
    final until = muteAllUntil;
    return until != null && until.isAfter(DateTime.now());
  }

  /// Deserializes from the server's conversation payload, tolerating missing
  /// or mistyped fields (defaults apply per field).
  factory Conversation.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    final muteAll = json['mute_all_until'];
    return Conversation(
      id: _asInt(json['id']),
      type: json['type'] as String? ?? 'private',
      title: json['title'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      ownerId: _asInt(json['owner_id']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
      isPublic: json['is_public'] as bool? ?? false,
      allowJoin: json['allow_join'] as bool? ?? false,
      muteAllUntil: _asDate(muteAll),
      encrypted: json['encrypted'] as bool? ?? false,
      memberCount: _asInt(json['member_count']),
      isMember: json['is_member'] as bool? ?? false,
      lastMessage: last is Map<String, dynamic> ? ChatMessage.fromJson(last) : null,
      unread: _asInt(json['unread']),
    );
  }

  /// Safely coerces an id/count field, tolerating strings and missing values so
  /// a schema change on the server never crashes the client.
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

/// The full payload behind a conversation page: the conversation plus its
/// member list and the viewer's own membership row.
class ConversationDetail {
  /// The conversation itself.
  final Conversation conversation;
  /// All members of the conversation.
  final List<ChatMember> members;
  /// The viewer's own membership; null when they are not a member.
  final ChatMember? myMembership;

  /// Creates a conversation detail; see [fromJson] for payload defaults.
  const ConversationDetail({
    required this.conversation,
    required this.members,
    this.myMembership,
  });

  /// Deserializes from the server's detail payload. Accepts either a nested
  /// `conversation` object or a flat conversation shape at the top level;
  /// missing member lists become empty.
  factory ConversationDetail.fromJson(Map<String, dynamic> json) {
    final conv = json['conversation'];
    final members = json['members'];
    final mine = json['my_membership'];
    return ConversationDetail(
      conversation: conv is Map<String, dynamic>
          ? Conversation.fromJson(conv)
          : Conversation.fromJson(json),
      members: members is List
          ? members
              .whereType<Map<String, dynamic>>()
              .map((m) => ChatMember.fromJson(m))
              .toList()
          : const [],
      myMembership: mine is Map<String, dynamic> ? ChatMember.fromJson(mine) : null,
    );
  }
}
