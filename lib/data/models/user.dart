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
    );
  }

  bool get hasOAuthBinding => oauth2Provider.isNotEmpty;

  String get displayName => nickname.isNotEmpty ? nickname : username;

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
    );
  }
}
