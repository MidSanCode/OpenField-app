/// A red-packet style check: money escrowed by the creator and claimable by
/// other users until it expires. Mirrors the server's `checks` table.
class Check {
  final int id;
  final int creatorId;

  /// Escrowed total, in cents.
  final int total;

  /// How many users may claim a share.
  final int shares;
  final String mode; // random | average
  final String status; // active | settled | refunded
  final int? postId;
  final DateTime expiresAt;
  final DateTime? refundedAt;
  final DateTime createdAt;

  // Denormalized for display.
  final String creatorName;
  final String creatorAvatar;
  final List<CheckClaim> claims;

  /// Sum of claimed amounts, in cents.
  final int claimedTotal;
  final bool claimedByMe;

  /// The viewer's own payout in cents, when [claimedByMe].
  final int myAmount;

  const Check({
    required this.id,
    required this.creatorId,
    required this.total,
    required this.shares,
    required this.mode,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
    this.postId,
    this.refundedAt,
    this.creatorName = '',
    this.creatorAvatar = '',
    this.claims = const [],
    this.claimedTotal = 0,
    this.claimedByMe = false,
    this.myAmount = 0,
  });

  bool get isRandom => mode == 'random';
  bool get isActive => status == 'active' && expiresAt.isAfter(DateTime.now());
  bool get isSettled => status == 'settled';
  bool get isRefunded => status == 'refunded';
  int get remainingShares => shares - claims.length;

  factory Check.fromJson(Map<String, dynamic> json) {
    final rawClaims = json['claims'];
    List<CheckClaim> claims = const [];
    if (rawClaims is List) {
      claims = rawClaims
          .whereType<Map<String, dynamic>>()
          .map((c) => CheckClaim.fromJson(c))
          .toList();
    }
    return Check(
      id: _asInt(json['id']),
      creatorId: _asInt(json['creator_id']),
      total: _asCents(json['total']),
      shares: _asInt(json['shares']),
      mode: json['mode'] as String? ?? 'random',
      status: json['status'] as String? ?? 'active',
      postId: json['post_id'] is num ? (json['post_id'] as num).toInt() : null,
      expiresAt:
          _asDate(json['expires_at']) ?? DateTime.now().add(const Duration(days: 1)),
      refundedAt: _asDate(json['refunded_at']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      creatorName: json['creator_name'] as String? ?? '',
      creatorAvatar: json['creator_avatar'] as String? ?? '',
      claims: claims,
      claimedTotal: _asCents(json['claimed_total']),
      claimedByMe: json['claimed_by_me'] as bool? ?? false,
      myAmount: _asCents(json['my_amount']),
    );
  }
}

/// One user's payout from a check.
class CheckClaim {
  final int id;
  final int checkId;
  final int userId;

  /// Payout in cents.
  final int amount;
  final DateTime createdAt;
  final String userName;
  final String userAvatar;

  const CheckClaim({
    required this.id,
    required this.checkId,
    required this.userId,
    required this.amount,
    required this.createdAt,
    this.userName = '',
    this.userAvatar = '',
  });

  factory CheckClaim.fromJson(Map<String, dynamic> json) {
    return CheckClaim(
      id: _asInt(json['id']),
      checkId: _asInt(json['check_id']),
      userId: _asInt(json['user_id']),
      amount: _asCents(json['amount']),
      createdAt: _asDate(json['created_at']) ?? DateTime.now(),
      userName: json['user_name'] as String? ?? '',
      userAvatar: json['user_avatar'] as String? ?? '',
    );
  }
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// Money arrives as a decimal coin number (e.g. 10.5); keep cents exactly.
int _asCents(Object? value) {
  if (value is int) return value;
  if (value is num) return (value * 100).round();
  if (value is String) {
    final d = double.tryParse(value);
    if (d != null) return (d * 100).round();
  }
  return 0;
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  try {
    return DateTime.parse(value.toString());
  } catch (_) {
    return null;
  }
}
