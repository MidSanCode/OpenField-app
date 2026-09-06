import 'attachment.dart';

/// A 贴吧-style camp community: a named space whose posts live in the camp
/// rather than the global feed.
class Camp {
  final int id;
  final String name;
  final String description;
  final int creatorId;
  final String creatorName;
  final bool isVisible;
  final bool directJoin;
  final int memberCount;
  final int postCount;
  final bool isMember;
  final DateTime createdAt;
  final DateTime updatedAt;

  Camp({
    required this.id,
    required this.name,
    this.description = '',
    required this.creatorId,
    this.creatorName = '',
    this.isVisible = true,
    this.directJoin = true,
    this.memberCount = 0,
    this.postCount = 0,
    this.isMember = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Camp.fromJson(Map<String, dynamic> json) {
    return Camp(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      creatorId: _asInt(json['creator_id']),
      creatorName: json['creator_name'] as String? ?? '',
      isVisible: json['is_visible'] as bool? ?? true,
      directJoin: json['direct_join'] as bool? ?? true,
      memberCount: _asInt(json['member_count']),
      postCount: _asInt(json['post_count']),
      isMember: json['is_member'] as bool? ?? false,
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
    );
  }

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

/// A manage-published notice shown to a conversation's members.
class GroupAnnouncement {
  final int id;
  final int conversationId;
  final int creatorId;
  final String creatorName;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;

  GroupAnnouncement({
    required this.id,
    required this.conversationId,
    required this.creatorId,
    this.creatorName = '',
    this.title = '',
    required this.content,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupAnnouncement.fromJson(Map<String, dynamic> json) {
    return GroupAnnouncement(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversation_id']),
      creatorId: _asInt(json['creator_id']),
      creatorName: json['creator_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
    );
  }
}

/// One entry of a conversation's shared checklist.
class GroupTodo {
  final int id;
  final int conversationId;
  final int creatorId;
  final String creatorName;
  final String title;
  final bool done;
  final int doneBy;
  final DateTime createdAt;
  final DateTime? completedAt;

  GroupTodo({
    required this.id,
    required this.conversationId,
    required this.creatorId,
    this.creatorName = '',
    required this.title,
    this.done = false,
    this.doneBy = 0,
    required this.createdAt,
    this.completedAt,
  });

  factory GroupTodo.fromJson(Map<String, dynamic> json) {
    return GroupTodo(
      id: _asInt(json['id']),
      conversationId: _asInt(json['conversation_id']),
      creatorId: _asInt(json['creator_id']),
      creatorName: json['creator_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      done: json['done'] as bool? ?? false,
      doneBy: _asInt(json['done_by']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      completedAt: _asDate(json['completed_at']),
    );
  }
}

/// One attachment shared into a conversation, surfaced in the group's
/// shared file list.
class GroupFile {
  final int messageId;
  final int senderId;
  final String senderName;
  final DateTime createdAt;
  final Attachment attachment;

  GroupFile({
    required this.messageId,
    required this.senderId,
    this.senderName = '',
    required this.createdAt,
    required this.attachment,
  });

  factory GroupFile.fromJson(Map<String, dynamic> json) {
    return GroupFile(
      messageId: _asInt(json['message_id']),
      senderId: _asInt(json['sender_id']),
      senderName: json['sender_name'] as String? ?? '',
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      attachment: Attachment.fromJson(json['attachment'] as Map<String, dynamic>),
    );
  }
}

/// A server-wide announcement surfaced by clients on startup.
class AppAnnouncement {
  final int id;
  final String title;
  final String content;
  final bool active;
  final DateTime createdAt;

  AppAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    this.active = true,
    required this.createdAt,
  });

  factory AppAnnouncement.fromJson(Map<String, dynamic> json) {
    return AppAnnouncement(
      id: _asInt(json['id']),
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
      active: json['active'] as bool? ?? true,
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return null;
  }
}
