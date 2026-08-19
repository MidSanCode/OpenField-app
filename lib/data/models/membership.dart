/// A purchaseable membership tier returned by the server's membership catalog.
class MembershipTier {
  final int level;
  final String name;
  final String description;
  final int price;
  final double expMultiplier;
  final int durationDays;
  final int storageBonusMb;
  final bool allowGradient;
  final bool allowDynamic;
  final List<String> presetColors;

  const MembershipTier({
    required this.level,
    required this.name,
    required this.description,
    required this.price,
    required this.expMultiplier,
    required this.durationDays,
    this.storageBonusMb = 0,
    this.allowGradient = false,
    this.allowDynamic = false,
    this.presetColors = const [],
  });

  factory MembershipTier.fromJson(Map<String, dynamic> json) {
    return MembershipTier(
      level: _asInt(json['level']),
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: _asInt(json['price']),
      expMultiplier: (json['exp_multiplier'] as num?)?.toDouble() ?? 1.0,
      durationDays: _asInt(json['duration_days']),
      storageBonusMb: _asInt(json['storage_bonus_mb']),
      allowGradient: json['allow_gradient'] as bool? ?? false,
      allowDynamic: json['allow_dynamic'] as bool? ?? false,
      presetColors: ((json['preset_colors'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList(),
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
  final bool autoRenew;
  final List<MembershipTier> tiers;

  const MembershipStatus({
    required this.level,
    required this.name,
    required this.active,
    required this.expiresAt,
    required this.multiplier,
    required this.memberDays,
    required this.memberPrice,
    this.autoRenew = false,
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
      autoRenew: json['auto_renew'] as bool? ?? false,
      tiers: ((json['tiers'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MembershipTier.fromJson)
          .toList(),
    );
  }
}

/// One recorded membership purchase/renewal/upgrade row, returned by
/// GET /membership/purchases.
class MembershipPurchase {
  final int id;
  final int level;
  final String tierName;
  final int priceCoins;
  final String kind; // purchase | renew | upgrade
  final DateTime createdAt;

  const MembershipPurchase({
    required this.id,
    required this.level,
    required this.tierName,
    required this.priceCoins,
    required this.kind,
    required this.createdAt,
  });

  factory MembershipPurchase.fromJson(Map<String, dynamic> json) {
    return MembershipPurchase(
      id: _asInt(json['id']),
      level: _asInt(json['level']),
      tierName: json['tier_name'] as String? ?? '',
      priceCoins: _asInt(json['price_coins']),
      kind: json['kind'] as String? ?? 'purchase',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '')?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
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