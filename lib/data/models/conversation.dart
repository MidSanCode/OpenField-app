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
      id: json['id'] as int,
      type: json['type'] as String? ?? 'private',
      title: json['title'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      ownerId: json['owner_id'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      isPublic: json['is_public'] as bool? ?? false,
      allowJoin: json['allow_join'] as bool? ?? false,
      muteAllUntil: muteAll != null ? DateTime.parse(muteAll as String) : null,
      memberCount: json['member_count'] as int? ?? 0,
      isMember: json['is_member'] as bool? ?? false,
      lastMessage: last is Map<String, dynamic> ? ChatMessage.fromJson(last) : null,
      unread: json['unread'] as int? ?? 0,
    );
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
