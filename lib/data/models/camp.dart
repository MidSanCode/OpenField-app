import 'attachment.dart';

/// A 贴吧-style camp community: a named space whose posts live in the camp
/// rather than the global feed.
class Camp {
  /// Server-assigned camp id.
  final int id;
  /// Camp display name.
  final String name;
  /// Short description ('' when the camp has none).
  final String description;
  /// User id of the camp's creator.
  final int creatorId;
  /// Creator's display name ('' when the payload omits it).
  final String creatorName;
  /// Whether the camp shows up in public listings.
  final bool isVisible;
  /// Whether users can join without an approval step.
  final bool directJoin;
  /// Whether plain members may publish posts into the camp (admins/owner
  /// always may). Defaults to true.
  final bool memberPost;
  /// Whether plain members may pin their own posts within the camp
  /// (admins/owner always may). Defaults to false.
  final bool memberPin;
  /// Short notice shown inside the camp; only owner/admins may change it.
  /// Empty string = no announcement.
  final String announcement;
  /// Current member count.
  final int memberCount;
  /// Total posts published in the camp.
  final int postCount;
  /// Whether the current viewer is a member.
  final bool isMember;
  /// The viewer's role in this camp: "owner", "admin", "member" or '' for
  /// non-members.
  final String myRole;
  /// When the camp was created (server timestamp).
  final DateTime createdAt;
  /// When the camp was last updated (server timestamp).
  final DateTime updatedAt;

  /// Creates a camp; see [fromJson] for payload defaults.
  Camp({
    required this.id,
    required this.name,
    this.description = '',
    required this.creatorId,
    this.creatorName = '',
    this.isVisible = true,
    this.directJoin = true,
    this.memberPost = true,
    this.memberPin = false,
    this.announcement = '',
    this.memberCount = 0,
    this.postCount = 0,
    this.isMember = false,
    this.myRole = '',
    required this.createdAt,
    required this.updatedAt,
  });

  /// Deserializes from the server's camp payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
  factory Camp.fromJson(Map<String, dynamic> json) {
    return Camp(
      id: _asInt(json['id']),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      creatorId: _asInt(json['creator_id']),
      creatorName: json['creator_name'] as String? ?? '',
      isVisible: json['is_visible'] as bool? ?? true,
      directJoin: json['direct_join'] as bool? ?? true,
      memberPost: json['member_post'] as bool? ?? true,
      memberPin: json['member_pin'] as bool? ?? false,
      announcement: json['announcement'] as String? ?? '',
      memberCount: _asInt(json['member_count']),
      postCount: _asInt(json['post_count']),
      isMember: json['is_member'] as bool? ?? false,
      myRole: json['my_role'] as String? ?? '',
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  /// The viewer may manage members/camp basics (owner or admin).
  bool get canManage => myRole == 'owner' || myRole == 'admin';
  /// The viewer may change the camp's permission switches (owner only).
  bool get canEditPermissions => myRole == 'owner';

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

/// One row of a camp's roster: the member's identity plus their camp role
/// ("owner", "admin" or "member") and join time.
class CampMember {
  /// Camp the member belongs to.
  final int campId;
  /// User id of the member.
  final int userId;
  /// Camp role: "owner", "admin" or "member".
  final String role;
  /// Login name ('' when the payload omits it).
  final String username;
  /// Display name ('' when the payload omits it).
  final String nickname;
  /// Avatar URL ('' when unset).
  final String avatarUrl;
  /// Whether the member is verified.
  final bool isVerified;
  /// When the member joined (server timestamp).
  final DateTime joinedAt;

  /// Creates a camp member; see [fromJson] for payload defaults.
  CampMember({
    required this.campId,
    required this.userId,
    this.role = 'member',
    this.username = '',
    this.nickname = '',
    this.avatarUrl = '',
    this.isVerified = false,
    required this.joinedAt,
  });

  /// Display name preference: nickname falls back to username.
  String get displayName => nickname.isNotEmpty ? nickname : (username.isNotEmpty ? username : '#$userId');

  /// Deserializes from the server's camp-member payload, tolerating missing
  /// or mistyped fields (defaults apply per field).
  factory CampMember.fromJson(Map<String, dynamic> json) {
    return CampMember(
      campId: _asInt(json['camp_id']),
      userId: _asInt(json['user_id']),
      role: json['role'] as String? ?? 'member',
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      joinedAt: _asDate(json['joined_at']) ?? DateTime.now(),
    );
  }
}

/// A manage-published notice shown to a conversation's members.
class GroupAnnouncement {
  /// Server-assigned announcement id.
  final int id;
  /// Conversation the announcement belongs to.
  final int conversationId;
  /// User id of the publisher.
  final int creatorId;
  /// Publisher's display name ('' when the payload omits it).
  final String creatorName;
  /// Announcement title ('' when none).
  final String title;
  /// Announcement body text.
  final String content;
  /// When the announcement was published (server timestamp).
  final DateTime createdAt;
  /// When the announcement was last updated (server timestamp).
  final DateTime updatedAt;

  /// Creates an announcement; see [fromJson] for payload defaults.
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

  /// Deserializes from the server's announcement payload, tolerating missing
  /// or mistyped fields (defaults apply per field).
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
  /// Server-assigned todo id.
  final int id;
  /// Conversation the todo belongs to.
  final int conversationId;
  /// User id of the todo's creator.
  final int creatorId;
  /// Creator's display name ('' when the payload omits it).
  final String creatorName;
  /// What needs to be done.
  final String title;
  /// Whether the todo has been checked off.
  final bool done;
  /// User id that checked it off (0 while still open).
  final int doneBy;
  /// When the todo was created (server timestamp).
  final DateTime createdAt;
  /// When the todo was checked off; null while [done] is false.
  final DateTime? completedAt;

  /// Creates a todo; see [fromJson] for payload defaults.
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

  /// Deserializes from the server's todo payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
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
  /// Id of the chat message the file was attached to.
  final int messageId;
  /// User id of the member who shared the file.
  final int senderId;
  /// Sender's display name ('' when the payload omits it).
  final String senderName;
  /// When the file was shared (message timestamp, server time).
  final DateTime createdAt;
  /// The attachment itself (URL, type, size, E2EE metadata, ...).
  final Attachment attachment;

  /// Creates a shared-file entry; see [fromJson] for payload defaults.
  GroupFile({
    required this.messageId,
    required this.senderId,
    this.senderName = '',
    required this.createdAt,
    required this.attachment,
  });

  /// Deserializes from the server's shared-file payload; throws when the
  /// `attachment` object is missing or malformed.
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
  /// Server-assigned announcement id.
  final int id;
  /// Announcement title.
  final String title;
  /// Announcement body text.
  final String content;
  /// Whether the announcement is currently shown to users.
  final bool active;
  /// When the announcement was published (server timestamp).
  final DateTime createdAt;

  /// Creates an app announcement; see [fromJson] for payload defaults.
  AppAnnouncement({
    required this.id,
    required this.title,
    required this.content,
    this.active = true,
    required this.createdAt,
  });

  /// Deserializes from the server's announcement payload, tolerating missing
  /// or mistyped fields (defaults apply per field).
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
