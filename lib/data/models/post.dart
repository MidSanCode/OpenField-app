import 'attachment.dart';

class Post {
  final int id;
  final int userId;
  final String content;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? username;
  final String? nickname;
  final String? avatarUrl;
  final bool? isVerified;
  final List<Attachment> attachments;
  final int replyCount;

  Post({
    required this.id,
    required this.userId,
    required this.content,
    required this.createdAt,
    required this.updatedAt,
    this.username,
    this.nickname,
    this.avatarUrl,
    this.isVerified,
    this.attachments = const [],
    this.replyCount = 0,
  });

  String get authorName => (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  bool get authorVerified => isVerified ?? false;

  factory Post.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    List<Attachment> attachments = const [];
    if (rawAttachments is List) {
      attachments = rawAttachments
          .whereType<Map<String, dynamic>>()
          .map((a) => Attachment.fromJson(a))
          .toList();
    }
    return Post(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool?,
      attachments: attachments,
      replyCount: json['reply_count'] as int? ?? 0,
    );
  }
}
