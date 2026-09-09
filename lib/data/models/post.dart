import 'attachment.dart';
import 'check.dart';

/// A feed post: body content plus denormalized author profile/styling,
/// engagement counters, and an optional quote/repost of another post.
class Post {
  /// Server-assigned post id; 0 when the payload omits it.
  final int id;
  /// Author's user id.
  final int userId;
  /// Post body text; empty for pure reposts (see [isPureRepost]).
  final String content;
  /// When the post was created (server timestamp).
  final DateTime createdAt;
  /// When the post was last edited (server timestamp).
  final DateTime updatedAt;
  /// Author's @username, when the payload includes it.
  final String? username;
  /// Author's display nickname, when the payload includes it.
  final String? nickname;
  /// Author's avatar URL, when the payload includes it.
  final String? avatarUrl;
  /// Whether the author carries a verification badge; null when unknown
  /// (see [authorVerified] for the effective value).
  final bool? isVerified;
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
  /// Media attached to the post; empty when text-only.
  final List<Attachment> attachments;
  /// Denormalized reply count from the server.
  final int replyCount;
  /// Denormalized total view count from the server.
  final int viewCount;
  /// Denormalized distinct-viewer count from the server.
  final int uniqueViews;
  /// Number of users who favorited this post.
  final int favoriteCount;
  /// [tipTotal] is the sum of non-refunded net tips on this post, in cents
  /// (95% of each tip). The server's tip_total column feeds this field.
  final int tipTotal;
  /// Who can see the post; server-controlled value, 'public' by default.
  final String visibility;
  /// Whether the current viewer favorited this post.
  final bool isFavorite;
  /// Reaction emoji to count map, as reported by the server.
  final Map<String, int> reactions;
  /// The current viewer's own reaction emoji ('' = none).
  final String myReaction;
  /// Free-form tags attached to the post by the author. Empty list means the
  /// post is untagged.
  final List<String> tags;

  /// The check attached to this post, when present (null otherwise).
  final Check? check;

  /// The post this post quotes or reposts (null when not a quote). When
  /// [quotedPostId] is set but this is null, the quoted post was deleted or
  /// is not visible to the viewer — clients render a placeholder.
  final int quotedPostId;
  /// The resolved [quotedPostId] target (null when absent/deleted/invisible).
  final Post? quotedPost;

  /// True when the author pinned this post (floats to the top of their
  /// profile; the feed renders a badge).
  final bool pinned;

  /// The camp (贴吧-style community) this post belongs to; 0 = global feed.
  final int campId;

  /// True when camp admins pinned this post to the top of its camp feed
  /// (only meaningful when [campId] > 0).
  final bool campPinned;

  /// True when this post carries no commentary of its own and only embeds
  /// the quoted post (a pure repost).
  bool get isPureRepost => quotedPostId > 0 && content.trim().isEmpty;

  /// Creates a post; every styling/counter field has a neutral default so
  /// local optimistic instances only need the core fields.
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
    this.isBot = false,
    this.memberLevel = 0,
    this.memberActive = false,
    this.nameColor = '',
    this.nameColorTo = '',
    this.nameDynamic = false,
    this.nameColors = const [],
    this.nameGradientDirection = '',
    this.avatarFrame = '',
    this.attachments = const [],
    this.replyCount = 0,
    this.viewCount = 0,
    this.uniqueViews = 0,
    this.favoriteCount = 0,
    this.tipTotal = 0,
    this.visibility = 'public',
    this.isFavorite = false,
    this.reactions = const {},
    this.myReaction = '',
    this.check,
    this.tags = const [],
    this.quotedPostId = 0,
    this.quotedPost,
    this.pinned = false,
    this.campId = 0,
    this.campPinned = false,
  });

  /// The author's display name: nickname when non-empty, else username,
  /// else 'Unknown'.
  String get authorName => (nickname != null && nickname!.isNotEmpty) ? nickname! : (username ?? 'Unknown');

  /// Whether the author carries a verification badge; false when unknown.
  bool get authorVerified => isVerified ?? false;

  /// Total number of reactions across all emoji.
  int get reactionCount => reactions.values.fold(0, (sum, count) => sum + count);

  /// Deserializes from the server's post payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
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
      isBot: json['is_bot'] as bool? ?? false,
      memberLevel: _asInt(json['member_level']),
      memberActive: json['member_active'] as bool? ?? false,
      nameColor: json['name_color'] as String? ?? '',
      nameColorTo: json['name_color_to'] as String? ?? '',
      nameDynamic: json['name_dynamic'] as bool? ?? false,
      nameColors: _asStringList(json['name_colors']),
      nameGradientDirection: json['name_gradient_direction'] as String? ?? '',
      avatarFrame: json['avatar_frame'] as String? ?? '',
      attachments: attachments,
      replyCount: _asInt(json['reply_count']),
      viewCount: _asInt(json['view_count']),
      uniqueViews: _asInt(json['unique_views']),
      favoriteCount: _asInt(json['favorite_count']),
      tipTotal: _asInt(json['tip_total']),
      visibility: json['visibility'] as String? ?? 'public',
      isFavorite: _firstBool(json, const ['is_favorite', 'favorited']),
      tags: ((json['tags'] as List?) ?? const []).cast<String>(),
      reactions: reactions,
      myReaction: json['my_reaction'] as String? ?? '',
      check: json['check'] is Map<String, dynamic>
          ? Check.fromJson(json['check'] as Map<String, dynamic>)
          : null,
      quotedPostId: _asInt(json['quoted_post_id']),
      quotedPost: json['quoted_post'] is Map<String, dynamic>
          ? Post.fromJson(json['quoted_post'] as Map<String, dynamic>)
          : null,
      pinned: json['pinned'] as bool? ?? false,
      campId: _asInt(json['camp_id']),
      campPinned: json['camp_pinned'] as bool? ?? false,
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

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return const [];
  }

  /// Returns a copy with the given fields replaced (null keeps the current
  /// value).
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
    bool? isBot,
    int? memberLevel,
    bool? memberActive,
    String? nameColor,
    String? nameColorTo,
    bool? nameDynamic,
    List<String>? nameColors,
    String? nameGradientDirection,
    String? avatarFrame,
    List<Attachment>? attachments,
    int? replyCount,
    int? viewCount,
    int? uniqueViews,
    int? favoriteCount,
    int? tipTotal,
    String? visibility,
    bool? isFavorite,
    Map<String, int>? reactions,
    String? myReaction,
    Check? check,
    List<String>? tags,
    int? quotedPostId,
    Post? quotedPost,
    bool? pinned,
    int? campId,
    bool? campPinned,
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
      isBot: isBot ?? this.isBot,
      memberLevel: memberLevel ?? this.memberLevel,
      memberActive: memberActive ?? this.memberActive,
      nameColor: nameColor ?? this.nameColor,
      nameColorTo: nameColorTo ?? this.nameColorTo,
      nameDynamic: nameDynamic ?? this.nameDynamic,
      nameColors: nameColors ?? this.nameColors,
      nameGradientDirection: nameGradientDirection ?? this.nameGradientDirection,
      avatarFrame: avatarFrame ?? this.avatarFrame,
      attachments: attachments ?? this.attachments,
      replyCount: replyCount ?? this.replyCount,
      viewCount: viewCount ?? this.viewCount,
      uniqueViews: uniqueViews ?? this.uniqueViews,
      favoriteCount: favoriteCount ?? this.favoriteCount,
      tipTotal: tipTotal ?? this.tipTotal,
      visibility: visibility ?? this.visibility,
      isFavorite: isFavorite ?? this.isFavorite,
      reactions: reactions ?? this.reactions,
      myReaction: myReaction ?? this.myReaction,
      check: check ?? this.check,
      tags: tags ?? this.tags,
      quotedPostId: quotedPostId ?? this.quotedPostId,
      quotedPost: quotedPost ?? this.quotedPost,
      pinned: pinned ?? this.pinned,
      campId: campId ?? this.campId,
      campPinned: campPinned ?? this.campPinned,
    );
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
