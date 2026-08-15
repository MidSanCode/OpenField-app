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
  final int favoriteCount;
  final String visibility;
  final bool isFavorite;
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
    this.favoriteCount = 0,
    this.visibility = 'public',
    this.isFavorite = false,
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
      id: _asInt(json['id']),
      userId: _asInt(json['user_id']),
      content: json['content'] as String? ?? '',
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool?,
      attachments: attachments,
      replyCount: _asInt(json['reply_count']),
      viewCount: _asInt(json['view_count']),
      uniqueViews: _asInt(json['unique_views']),
      favoriteCount: _asInt(json['favorite_count']),
      visibility: json['visibility'] as String? ?? 'public',
      isFavorite: json['is_favorite'] as bool? ?? false,
      reactions: reactions,
      myReaction: json['my_reaction'] as String? ?? '',
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

  Post copyWith({
    int? id,
    int? userId,
    String? content,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? username,
    String? nickname,
    String? avatarUrl,
    bool? isVerified,
    List<Attachment>? attachments,
    int? replyCount,
    int? viewCount,
    int? uniqueViews,
    int? favoriteCount,
    String? visibility,
    bool? isFavorite,
    Map<String, int>? reactions,
    String? myReaction,
  }) {
    return Post(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      content: content ?? this.content,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      isVerified: isVerified ?? this.isVerified,
      attachments: attachments ?? this.attachments,
      replyCount: replyCount ?? this.replyCount,
      viewCount: viewCount ?? this.viewCount,
      uniqueViews: uniqueViews ?? this.uniqueViews,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      visibility: visibility ?? this.visibility,
      isFavorite: isFavorite ?? this.isFavorite,
      reactions: reactions ?? this.reactions,
      myReaction: myReaction ?? this.myReaction,
    );
  }
}
