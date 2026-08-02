import 'attachment.dart';

class PostReply {
  final int id;
  final int postId;
  final int userId;
  final String content;
  final int? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final String? username;
  final String? nickname;
  final String? avatarUrl;
  final bool isVerified;
  final String? parentContent;
  final String? parentName;
  final List<Attachment> attachments;

  const PostReply({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.deletedAt,
    this.username,
    this.nickname,
    this.avatarUrl,
    this.isVerified = false,
    this.parentContent,
    this.parentName,
    this.attachments = const [],
  });

  bool get isDeleted => deletedAt != null;

  String get authorName => (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  factory PostReply.fromJson(Map<String, dynamic> json) {
    return PostReply(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      userId: json['user_id'] as int,
      content: json['content'] as String? ?? '',
      parentId: json['parent_id'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      deletedAt: json['deleted_at'] != null ? DateTime.parse(json['deleted_at'] as String) : null,
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      parentContent: json['parent_content'] as String?,
      parentName: json['parent_name'] as String?,
      attachments: (json['attachments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((a) => Attachment.fromJson(a))
              .toList() ??
          const [],
    );
  }
}
