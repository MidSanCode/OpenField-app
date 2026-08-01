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
    this.lastMessage,
    this.unread = 0,
  });

  bool get isGroup => type == 'group';

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final last = json['last_message'];
    return Conversation(
      id: json['id'] as int,
      type: json['type'] as String? ?? 'private',
      title: json['title'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      ownerId: json['owner_id'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
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
