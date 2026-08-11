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
  final String oauth2Provider;
  final String oauth2Username;
  final String bio;
  final bool isVerified;
  final String verifiedNote;
  final String verifiedBy;
  final int followerCount;
  final int followingCount;
  final bool isFollowing;
  final int exp;
  final DateTime? lastDailyBonusAt;

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
    this.oauth2Provider = '',
    this.oauth2Username = '',
    this.bio = '',
    this.isVerified = false,
    this.verifiedNote = '',
    this.verifiedBy = '',
    this.followerCount = 0,
    this.followingCount = 0,
    this.isFollowing = false,
    this.exp = 0,
    this.lastDailyBonusAt,
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
      oauth2Provider: json['oauth2_provider'] as String? ?? '',
      oauth2Username: json['oauth2_username'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      verifiedNote: json['verified_note'] as String? ?? '',
      verifiedBy: json['verified_by'] as String? ?? '',
      followerCount: (json['follower_count'] as num?)?.toInt() ?? 0,
      followingCount: (json['following_count'] as num?)?.toInt() ?? 0,
      isFollowing: json['is_following'] as bool? ?? false,
      exp: (json['exp'] as num?)?.toInt() ?? 0,
      lastDailyBonusAt: _asDate(json['last_daily_bonus_at']),
    );
  }

  bool get hasOAuthBinding => oauth2Provider.isNotEmpty;

  String get displayName => nickname.isNotEmpty ? nickname : username;

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

  /// Fraction (0..1) of progress toward the next level.
  double get levelProgress {
    final lvl = level;
    if (lvl >= _maxLevel) return 1;
    final current = _thresholds[lvl - 1];
    final next = _thresholds[lvl];
    final span = next - current;
    if (span <= 0) return 1;
    final into = exp - current;
    if (into <= 0) return 0;
    if (into >= span) return 1;
    return into / span;
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
    String? oauth2Provider,
    String? oauth2Username,
    String? bio,
    bool? isVerified,
    String? verifiedNote,
    String? verifiedBy,
    int? followerCount,
    int? followingCount,
    bool? isFollowing,
    int? exp,
    DateTime? lastDailyBonusAt,
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
      oauth2Provider: oauth2Provider ?? this.oauth2Provider,
      oauth2Username: oauth2Username ?? this.oauth2Username,
      bio: bio ?? this.bio,
      isVerified: isVerified ?? this.isVerified,
      verifiedNote: verifiedNote ?? this.verifiedNote,
      verifiedBy: verifiedBy ?? this.verifiedBy,
      followerCount: followerCount ?? this.followerCount,
      followingCount: followingCount ?? this.followingCount,
      isFollowing: isFollowing ?? this.isFollowing,
      exp: exp ?? this.exp,
      lastDailyBonusAt: lastDailyBonusAt ?? this.lastDailyBonusAt,
    );
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
