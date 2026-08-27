import 'dart:convert';
import 'dart:ui' show Color;

/// Level-system constants mirrored from the server so the app can derive a
/// user's level and tier without a round trip. The server stays authoritative;
/// these only drive the badge shown in the UI.
const double _levelGrowth = 1.05;
const int _expPerLevel = 100;
const int _maxLevel = 200;

/// A named, colour-coded band of levels. Every ten levels the account moves to
/// a new tier whose name and colour drive the experience bar.
class LevelTier {
  final int minLevel;
  final int maxLevel;
  final String name;

  /// The solid colour of the experience bar for this tier.
  final Color color;

  /// Optional gradient colours. When non-empty the experience bar renders as a
  /// gradient instead of the solid [color] (used by the final "source" tier).
  final List<Color> gradientColors;

  const LevelTier(
    this.minLevel,
    this.maxLevel,
    this.name,
    this.color, {
    this.gradientColors = const [],
  });
}

/// The twenty level bands. Level ranges are inclusive.
const List<LevelTier> kTiers = [
  LevelTier(1, 10, '出发', Color(0xFF9E9E9E)),
  LevelTier(11, 20, '徒步', Color(0xFF7CB342)),
  LevelTier(21, 30, '听风', Color(0xFF42A5F5)),
  LevelTier(31, 40, '赤足', Color(0xFFB7611A)),
  LevelTier(41, 50, '燃火', Color(0xFFE64A19)),
  LevelTier(51, 60, '共行', Color(0xFFFFB300)),
  LevelTier(61, 70, '迷途', Color(0xFF9575CD)),
  LevelTier(71, 80, '自鸣', Color(0xFFEC6B8F)),
  LevelTier(81, 90, '越岭', Color(0xFF757575)),
  LevelTier(91, 100, '高原', Color(0xFF2C3E70)),
  LevelTier(101, 110, '观星', Color(0xFF5B2C8E)),
  LevelTier(111, 120, '入画', Color(0xFFA1672C)),
  LevelTier(121, 130, '风蚀', Color(0xFFD4B86A)),
  LevelTier(131, 140, '绿洲', Color(0xFF2E8B57)),
  LevelTier(141, 150, '如石', Color(0xFF37474F)),
  LevelTier(151, 160, '俯瞰', Color(0xFF4A90D9)),
  LevelTier(161, 170, '合一', Color(0xFF00C48C)),
  LevelTier(171, 180, '回响', Color(0xFFD9A13E)),
  LevelTier(181, 190, '无名', Color(0xFF1F1F1F)),
  LevelTier(
    191,
    200,
    '源起',
    Color(0xFF4A90D9),
    gradientColors: [
      Color(0xFFFF6B6B),
      Color(0xFFFFC53D),
      Color(0xFF46E0A5),
      Color(0xFF4D9FFF),
      Color(0xFFA06BFF),
      Color(0xFFFF6BD6),
    ],
  ),
];

class User {
  final int id;
  final String username;
  final String nickname;
  final String email;
  final String avatarUrl;
  final String bannerUrl;
  final String role;
  final bool needsRegistration;
  final int storageQuota;
  final int storageUsed;
  final String storageBucket;
  final String oauth2Provider;
  final String oauth2Username;
  final String bio;
  final bool isVerified;
  final String verifiedNote;
  final String verifiedBy;
  final int followerCount;
  final int followingCount;
  final int friendCount;
  final bool isFollowing;
  final bool isFriend;
  final bool hideFollowLists;
  final int exp;
  final DateTime? lastDailyBonusAt;
  final int memberLevel;
  final DateTime? memberExpiresAt;
  final String nameColor;
  final String nameColorTo;
  final bool nameDynamic;
  final List<String> nameColors;
  final String nameGradientDirection;
  final String avatarFrame;
  final bool hasPin;
  final bool isBot;
  final DateTime? createdAt;
  /// Presence: true when the user pinged a heartbeat within the last few
  /// minutes. [lastSeenAt] powers the "last seen" fallback when offline.
  final bool online;
  final DateTime? lastSeenAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.avatarUrl,
    this.nickname = '',
    this.bannerUrl = '',
    this.role = 'user',
    this.needsRegistration = false,
    this.storageQuota = 0,
    this.storageUsed = 0,
    this.storageBucket = 'default',
    this.oauth2Provider = '',
    this.oauth2Username = '',
    this.bio = '',
    this.isVerified = false,
    this.verifiedNote = '',
    this.verifiedBy = '',
    this.followerCount = 0,
    this.followingCount = 0,
    this.friendCount = 0,
    this.isFollowing = false,
    this.isFriend = false,
    this.hideFollowLists = false,
    this.exp = 0,
    this.lastDailyBonusAt,
    this.memberLevel = 0,
    this.memberExpiresAt,
    this.nameColor = '',
    this.nameColorTo = '',
    this.nameDynamic = false,
    this.nameColors = const [],
    this.nameGradientDirection = '',
    this.avatarFrame = '',
    this.hasPin = false,
    this.isBot = false,
    this.createdAt,
    this.online = false,
    this.lastSeenAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: (json['id'] as num?)?.toInt() ?? 0,
      username: json['username'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      bannerUrl: json['banner_url'] as String? ?? '',
      role: json['role'] as String? ?? 'user',
      needsRegistration: json['needs_registration'] as bool? ?? false,
      storageQuota: (json['storage_quota'] as num?)?.toInt() ?? 0,
      storageUsed: (json['storage_used'] as num?)?.toInt() ?? 0,
      storageBucket: json['storage_bucket'] as String? ?? 'default',
      oauth2Provider: json['oauth2_provider'] as String? ?? '',
      oauth2Username: json['oauth2_username'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      verifiedNote: json['verified_note'] as String? ?? '',
      verifiedBy: json['verified_by'] as String? ?? '',
      followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      friendCount: (json['friend_count'] as num?)?.toInt() ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
      isFriend: json['is_friend'] as bool? ?? false,
      hideFollowLists: json['hide_follow_lists'] as bool? ?? false,
      exp: (json['exp'] as num?)?.toInt() ?? 0,
      lastDailyBonusAt: _asDate(json['last_daily_bonus_at']),
      memberLevel: (json['member_level'] as num?)?.toInt() ?? 0,
      memberExpiresAt: _asDate(json['member_expires_at']),
      nameColor: json['name_color'] as String? ?? '',
      nameColorTo: json['name_color_to'] as String? ?? '',
      nameDynamic: json['name_dynamic'] as bool? ?? false,
      nameColors: _asStringList(json['name_colors']),
      nameGradientDirection: json['name_gradient_direction'] as String? ?? '',
      avatarFrame: json['avatar_frame'] as String? ?? '',
      hasPin: json['has_pin'] as bool? ?? false,
      isBot: json['is_bot'] as bool? ?? false,
      createdAt: _asDate(json['created_at']),
      online: json['online'] as bool? ?? false,
      lastSeenAt: _asDate(json['last_seen_at']),
    );
  }

  bool get hasOAuthBinding => oauth2Provider.isNotEmpty;

  String get displayName => nickname.isNotEmpty ? nickname : username;

  /// Whether the user currently holds an active membership (a tier above 0
  /// whose expiry is still in the future).
  bool get hasActiveMembership {
    final expires = memberExpiresAt;
    return memberLevel > 0 && expires != null && expires.isAfter(DateTime.now());
  }

  /// The experience multiplier granted by the user's active membership tier
  /// (2, 2.5, 3, 3.5), or 1 when not a member.
  double get memberExpMultiplier {
    final target = hasActiveMembership ? memberLevel : 0;
    switch (target) {
      case 1:
        return 2.0;
      case 2:
        return 2.5;
      case 3:
        return 3.0;
      case 4:
        return 3.5;
      default:
        return 1.0;
    }
  }

  /// The display name of the active membership tier (薄雾/篝火/明月/孤星), or
  /// empty when the user is not currently a member.
  String get memberTierName {
    switch (hasActiveMembership ? memberLevel : 0) {
      case 1:
        return '薄雾';
      case 2:
        return '篝火';
      case 3:
        return '明月';
      case 4:
        return '孤星';
      default:
        return '';
    }
  }

  /// The storage-space bonus (bytes) granted by an active membership tier:
  /// Lv.1 +100MB, Lv.2 +200MB, Lv.3 +400MB, Lv.4 +800MB, else 0.
  int get memberStorageBonusBytes {
    switch (hasActiveMembership ? memberLevel : 0) {
      case 1:
        return 100 * 1024 * 1024;
      case 2:
        return 200 * 1024 * 1024;
      case 3:
        return 400 * 1024 * 1024;
      case 4:
        return 800 * 1024 * 1024;
      default:
        return 0;
    }
  }

  /// The effective storage quota while the membership is active and the user is
  /// on the default storage bucket (base quota plus the tier bonus). On
  /// non-default buckets the bonus does not apply, matching the server's
  /// enforcement. After expiry the bonus reverts to 0.
  int get effectiveStorageQuota =>
      storageQuota + (storageBucket.isEmpty || storageBucket == 'default' ? memberStorageBonusBytes : 0);

  /// Experience-based level, derived with the same cumulative formula as the
  /// server. Total exp must reach the cumulative threshold of level 2 (=100)
  /// to advance from level 1; every level costs 5% more than the previous,
  /// rounded to the nearest integer.
  int get level {
    final e = exp;
    if (e <= 0) return 1;
    var lo = 1, hi = _maxLevel;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_thresholds[mid - 1] <= e) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return hi;
  }

  /// The tier (level band with a name and colour) for the current level, or
  /// null before level 1.
  LevelTier? get tier {
    final lvl = level;
    if (lvl <= 0) return null;
    for (final t in kTiers) {
      if (lvl >= t.minLevel && lvl <= t.maxLevel) return t;
    }
    return null;
  }

  /// The display tier name for the current level.
  String get tierName => tier?.name ?? '';

  /// The colour of the experience bar for the current tier. Falls back to a
  /// neutral grey below level 1.
  Color get tierColor => tier?.color ?? const Color(0xFFB0BEC5);

  /// Gradient colours for tiers that render with a shifting gradient instead of
  /// a solid colour (e.g. the final "source" tier). Empty for solid tiers.
  List<Color> get tierGradient => tier?.gradientColors ?? const [];

  /// Fraction (0..1) of progress toward the next level, computed against the
  /// current level's own span so the bar fills from empty to full within each
  /// level (never looks blank at level 1).
  double get levelProgressWithin {
    final span = expForNextLevel;
    if (span <= 0) return 1;
    final into = expIntoLevel;
    return (into / span).clamp(0.0, 1.0);
  }

  /// Fraction (0..1) of progress toward the next level.
  double get levelProgress {
    final total = totalExpForNextLevel;
    if (total <= 0) return 1;
    final into = exp / total;
    return into.clamp(0.0, 1.0);
  }

  /// Exp accumulated since the current level began.
  int get expIntoLevel {
    final lvl = level;
    final into = exp - _thresholds[lvl - 1];
    if (into <= 0) return 0;
    final span = _thresholds[lvl] - _thresholds[lvl - 1];
    return into > span ? span : into;
  }

  /// Exp still required to advance to the next level.
  int get expForNextLevel => _thresholds[level] - _thresholds[level - 1];

  /// Lifetime-total experience required to *reach* the level after the current
  /// one. Unlike [expForNextLevel] (the incremental span), this value is
  /// cumulative: it only grows as the user levels up, so the exp bar keeps
  /// adding on top of earned exp instead of resetting to zero at each level.
  int get totalExpForNextLevel {
    final lvl = level;
    if (lvl >= _maxLevel) return _thresholds[_maxLevel];
    return _thresholds[lvl];
  }

  /// Whether the once-per-server-day bonus can be claimed right now. The
  /// server remains authoritative; this is only an optimistic hint.
  bool get canClaimDailyBonus {
    final last = lastDailyBonusAt;
    if (last == null) return true;
    final now = DateTime.now();
    return !DateTime(last.year, last.month, last.day)
        .isAtSameMomentAs(DateTime(now.year, now.month, now.day));
  }

  /// Cumulative exp required to *reach* each level, precomputed once.
  ///
  /// [_thresholds]`[i]` is the total exp needed to be at level `i+1`
  /// (level 1 costs 0). Level 2 costs [_expPerLevel]; each later level costs
  /// 5% more than the previous, rounded to the nearest integer, so reaching
  /// level 3 needs 100 + 105 = 205 total exp.
  static final List<int> _thresholds = _buildThresholds();

  static List<int> _buildThresholds() {
    final thresholds = List<int>.filled(_maxLevel + 1, 0);
    var cost = _expPerLevel;
    for (var level = 1; level <= _maxLevel; level++) {
      thresholds[level] = thresholds[level - 1] + cost;
      cost = (cost * _levelGrowth).round();
    }
    return thresholds;
  }

  User copyWith({
    int? id,
    String? username,
    String? nickname,
    String? email,
    String? avatarUrl,
    String? bannerUrl,
    String? role,
    bool? needsRegistration,
    int? storageQuota,
    int? storageUsed,
    String? storageBucket,
    String? oauth2Provider,
    String? oauth2Username,
    String? bio,
    bool? isVerified,
    String? verifiedNote,
    String? verifiedBy,
    int? followerCount,
    int? followingCount,
    int? friendCount,
    bool? isFollowing,
    bool? isFriend,
    bool? hideFollowLists,
    int? exp,
    DateTime? lastDailyBonusAt,
    int? memberLevel,
    DateTime? memberExpiresAt,
    String? nameColor,
    String? nameColorTo,
    bool? nameDynamic,
    List<String>? nameColors,
    String? nameGradientDirection,
    String? avatarFrame,
    bool? hasPin,
    bool? isBot,
    DateTime? createdAt,
    bool? online,
    DateTime? lastSeenAt,
  }) {
    return User(
      id: id ?? this.id,
      username: username ?? this.username,
      nickname: nickname ?? this.nickname,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bannerUrl: bannerUrl ?? this.bannerUrl,
      role: role ?? this.role,
      needsRegistration: needsRegistration ?? this.needsRegistration,
      storageQuota: storageQuota ?? this.storageQuota,
      storageUsed: storageUsed ?? this.storageUsed,
      storageBucket: storageBucket ?? this.storageBucket,
      oauth2Provider: oauth2Provider ?? this.oauth2Provider,
      oauth2Username: oauth2Username ?? this.oauth2Username,
      bio: bio ?? this.bio,
      isVerified: isVerified ?? this.isVerified,
      verifiedNote: verifiedNote ?? this.verifiedNote,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      friendCount: friendCount ?? this.friendCount,
      isFollowing: isFollowing ?? this.isFollowing,
      isFriend: isFriend ?? this.isFriend,
      hideFollowLists: hideFollowLists ?? this.hideFollowLists,
      exp: exp ?? this.exp,
      lastDailyBonusAt: lastDailyBonusAt ?? this.lastDailyBonusAt,
      memberLevel: memberLevel ?? this.memberLevel,
      memberExpiresAt: memberExpiresAt ?? this.memberExpiresAt,
      nameColor: nameColor ?? this.nameColor,
      nameColorTo: nameColorTo ?? this.nameColorTo,
      nameDynamic: nameDynamic ?? this.nameDynamic,
      nameColors: nameColors ?? this.nameColors,
      nameGradientDirection: nameGradientDirection ?? this.nameGradientDirection,
      avatarFrame: avatarFrame ?? this.avatarFrame,
      hasPin: hasPin ?? this.hasPin,
      isBot: isBot ?? this.isBot,
      createdAt: createdAt ?? this.createdAt,
      online: online ?? this.online,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  static List<String> _asStringList(Object? value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    if (value is String && value.isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is List) {
          return decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    }
    return const [];
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
