/// A purchaseable membership tier returned by the server's membership catalog.
class MembershipTier {
  final int level;
  final String name;
  final String description;
  final int price;
  final double expMultiplier;
  final int durationDays;

  const MembershipTier({
    required this.level,
    required this.name,
    required this.description,
    required this.price,
    required this.expMultiplier,
    required this.durationDays,
  });

  factory MembershipTier.fromJson(Map<String, dynamic> json) {
    return MembershipTier(
      level: _asInt(json['level']),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: _asInt(json['price']),
      expMultiplier: (json['exp_multiplier'] as num?)?.toDouble() ?? 1.0,
      durationDays: _asInt(json['duration_days']),
    );
  }
}

/// The authenticated user's membership state plus the purchase catalog,
/// returned by GET /membership.
class MembershipStatus {
  final int level;
  final String name;
  final bool active;
  final DateTime? expiresAt;
  final double multiplier;
  final int memberDays;
  final int memberPrice;
  final List<MembershipTier> tiers;

  const MembershipStatus({
    required this.level,
    required this.name,
    required this.active,
    required this.expiresAt,
    required this.multiplier,
    required this.memberDays,
    required this.memberPrice,
    required this.tiers,
  });

  factory MembershipStatus.fromJson(Map<String, dynamic> json) {
    return MembershipStatus(
      level: _asInt(json['level']),
      name: json['name'] as String? ?? '',
      active: json['active'] as bool? ?? false,
      expiresAt: _asDate(json['expires_at']),
      multiplier: (json['exp_multiplier'] as num?)?.toDouble() ?? 1.0,
      memberDays: _asInt(json['member_days']),
      memberPrice: _asInt(json['member_price']),
      tiers: ((json['tiers'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MembershipTier.fromJson)
          .toList(),
    );
  }
}

int _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _asDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}