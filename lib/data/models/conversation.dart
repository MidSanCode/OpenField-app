import 'chat_message.dart';
import 'chat_member.dart';

class Conversation {
  final int id;
  final String type; // private | group
  final String title;
  final String avatarUrl;
  final int ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isPublic;
  final bool allowJoin;
  final DateTime? muteAllUntil;
  final bool encrypted;
  final int memberCount;
  final bool isMember;
  final ChatMessage? lastMessage;
  final int unread;

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

  bool get isGroup => type == 'group';

  bool get canJoinDirectly => isGroup && isPublic && allowJoin;

  bool get isGroupMuted {
    final until = muteAllUntil;
    return until != null && until.isAfter(DateTime.now());
  }

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

class ConversationDetail {
  final Conversation conversation;
  final List<ChatMember> members;
  final ChatMember? myMembership;

  const ConversationDetail({
    required this.conversation,
    required this.members,
    this.myMembership,
  });

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
