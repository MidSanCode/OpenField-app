import 'attachment.dart';

/// A reply to a feed post (or to another reply, via [parentId]), with
/// denormalized author profile/styling and the parent-reply preview fields.
class PostReply {
  /// Server-assigned reply id.
  final int id;
  /// Post being replied to.
  final int postId;
  /// Author's user id.
  final int userId;
  /// Reply body text.
  final String content;
  /// Parent reply id for nested replies; null for top-level replies.
  final int? parentId;
  /// When the reply was created (server timestamp).
  final DateTime createdAt;
  /// When the reply was last edited (server timestamp).
  final DateTime updatedAt;
  /// When the reply was soft-deleted; null while it still exists.
  final DateTime? deletedAt;
  /// Author's @username, when the payload includes it.
  final String? username;
  /// Author's display nickname, when the payload includes it.
  final String? nickname;
  /// Author's avatar URL, when the payload includes it.
  final String? avatarUrl;
  /// Whether the author carries a verification badge.
  final bool isVerified;
  /// Whether the author is a bot account.
  final bool isBot;
  /// Author's membership tier (0 = none).
  final int memberLevel;
  /// Whether the author's membership is currently active.
  final bool memberActive;
  /// Author's name colour as a hex string ('' = default rendering).
  final String nameColor;
  /// Second name colour for gradients ('' = none).
  final String nameColorTo;
  /// Whether the name colour animates over time.
  final bool nameDynamic;
  /// Palette for dynamic names; empty = use [nameColor]/[nameColorTo].
  final List<String> nameColors;
  /// Gradient direction hint for the name colours ('' = default).
  final String nameGradientDirection;
  /// Avatar frame asset key ('' = no frame).
  final String avatarFrame;
  /// Content snippet of the parent reply, for nested-reply previews; null
  /// for top-level replies.
  final String? parentContent;
  /// Author name of the parent reply, for nested-reply previews; null for
  /// top-level replies.
  final String? parentName;
  /// Media attached to the reply; empty for text-only replies.
  final List<Attachment> attachments;
  /// Number of users who favorited this reply.
  final int favoriteCount;
  /// Whether the current viewer favorited this reply.
  final bool isFavorite;

  /// Creates a reply; see [fromJson] for payload defaults.
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
    this.isBot = false,
    this.memberLevel = 0,
    this.memberActive = false,
    this.nameColor = '',
    this.nameColorTo = '',
    this.nameDynamic = false,
    this.nameColors = const [],
    this.nameGradientDirection = '',
    this.avatarFrame = '',
    this.parentContent,
    this.parentName,
    this.attachments = const [],
    this.favoriteCount = 0,
    this.isFavorite = false,
  });

  /// True when this reply was soft-deleted ([deletedAt] set).
  bool get isDeleted => deletedAt != null;

  /// The author's display name: nickname when non-empty, else username,
  /// else 'Unknown'.
  String get authorName => (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  /// Deserializes from the server's reply payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
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
      isBot: json['is_bot'] as bool? ?? false,
      memberLevel: _asInt(json['member_level']),
      memberActive: json['member_active'] as bool? ?? false,
      nameColor: json['name_color'] as String? ?? '',
      nameColorTo: json['name_color_to'] as String? ?? '',
      nameDynamic: json['name_dynamic'] as bool? ?? false,
      nameColors: _asStringList(json['name_colors']),
      nameGradientDirection: json['name_gradient_direction'] as String? ?? '',
      avatarFrame: json['avatar_frame'] as String? ?? '',
      parentContent: json['parent_content'] as String?,
      parentName: json['parent_name'] as String?,
      attachments: (json['attachments'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((a) => Attachment.fromJson(a))
              .toList() ??
          const [],
      favoriteCount: _asInt(json['favorite_count']),
      isFavorite: _firstBool(json, const ['is_favorite', 'favorited']),
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

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Reads the first non-null boolean from a list of JSON keys. The server
  /// historically used `favorited` and a few stale payloads still ship the
  /// `is_favorite` key; either is fine, missing means false.
  static bool _firstBool(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is bool) return value;
    }
    return false;
  }
}
