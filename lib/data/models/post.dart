import 'attachment.dart';
import 'check.dart';

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
  final bool isBot;
  final int memberLevel;
  final bool memberActive;
  final String nameColor;
  final String nameColorTo;
  final bool nameDynamic;
  final List<String> nameColors;
  final String nameGradientDirection;
  final String avatarFrame;
  final List<Attachment> attachments;
  final int replyCount;
  final int viewCount;
  final int uniqueViews;
  final int favoriteCount;
  /// [tipTotal] is the sum of non-refunded net tips on this post, in cents
  /// (95% of each tip). The server's tip_total column feeds this field.
  final int tipTotal;
  final String visibility;
  final bool isFavorite;
  final Map<String, int> reactions;
  final String myReaction;
  /// Free-form tags attached to the post by the author. Empty list means the
  /// post is untagged.
  final List<String> tags;

  /// The check attached to this post, when present (null otherwise).
  final Check? check;

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
