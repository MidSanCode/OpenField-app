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
  final int memberLevel;
  final bool memberActive;
  final String nameColor;
  final String nameColorTo;
  final bool nameDynamic;
  final String avatarFrame;
  final String? parentContent;
  final String? parentName;
  final List<Attachment> attachments;
  final int favoriteCount;
  final bool isFavorite;

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
    this.memberLevel = 0,
    this.memberActive = false,
    this.nameColor = '',
    this.nameColorTo = '',
    this.nameDynamic = false,
    this.avatarFrame = '',
    this.parentContent,
    this.parentName,
    this.attachments = const [],
    this.favoriteCount = 0,
    this.isFavorite = false,
  });

  bool get isDeleted => deletedAt != null;

  String get authorName => (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  factory PostReply.fromJson(Map<String, dynamic> json) {
    return PostReply(
      id: _asInt(json['id']),
      postId: _asInt(json['post_id']),
      userId: _asInt(json['user_id']),
      content: json['content'] as String? ?? '',
      parentId: json['parent_id'] is num
          ? (json['parent_id'] as num).toInt()
          : json['parent_id'] is String
              ? int.tryParse(json['parent_id'] as String)
              : null,
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _asDate(json['updated_at']) ?? DateTime.now(),
      deletedAt: _asDate(json['deleted_at']),
      username: json['username'] as String?,
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      isVerified: json['is_verified'] as bool? ?? false,
      memberLevel: _asInt(json['member_level']),
      memberActive: json['member_active'] as bool? ?? false,
      nameColor: json['name_color'] as String? ?? '',
      nameColorTo: json['name_color_to'] as String? ?? '',
      nameDynamic: json['name_dynamic'] as bool? ?? false,
      avatarFrame: json['avatar_frame'] as String? ?? '',
      parentContent: json['parent_content'] as String?,
      parentName: json['parent_name'] as String?,
      attachments: (json['attachments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((a) => Attachment.fromJson(a))
              .toList() ??
          const [],
      favoriteCount: _asInt(json['favorite_count']),
      isFavorite: json['is_favorite'] as bool? ?? false,
    );
  }

  /// Safely coerces an id field, tolerating strings and missing values so a
  /// schema change on the server never crashes the client.
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
