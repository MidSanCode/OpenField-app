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
  final int viewCount;
  final int uniqueViews;
  final Map<String, int> reactions;
  final String myReaction;

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
    this.viewCount = 0,
    this.uniqueViews = 0,
    this.reactions = const {},
    this.myReaction = '',
  });

  String get authorName => (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  bool get authorVerified => isVerified ?? false;

  int get reactionCount => reactions.values.fold(0, (sum, count) => sum + count);

  factory Post.fromJson(Map<String, dynamic> json) {
    final rawAttachments = json['attachments'];
    List<Attachment> attachments = const [];
    if (rawAttachments is List) {
      attachments = rawAttachments
          .whereType<Map<String, dynamic>>()
          .map((a) => Attachment.fromJson(a))
          .toList();
    }
    final rawReactions = json['reactions'];
    final reactions = <String, int>{};
    if (rawReactions is Map) {
      rawReactions.forEach((key, value) {
        reactions[key.toString()] = (value as num?)?.toInt() ?? 0;
      });
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
      viewCount: json['view_count'] as int? ?? 0,
      uniqueViews: json['unique_views'] as int? ?? 0,
      reactions: reactions,
      myReaction: json['my_reaction'] as String? ?? '',
    );
  }
}
