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
    );
  }

  bool get hasOAuthBinding => oauth2Provider.isNotEmpty;

  String get displayName => nickname.isNotEmpty ? nickname : username;
}
