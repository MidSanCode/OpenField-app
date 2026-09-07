/// A purchaseable membership tier returned by the server's membership catalog.
class MembershipTier {
  /// Tier level this purchase grants (0 = the implicit non-member tier).
  final int level;
  /// Tier display name.
  final String name;
  /// Human-readable summary of the tier's perks.
  final String description;
  /// Purchase price in coins.
  final int price;
  /// Experience multiplier while the tier is active (e.g. 2.0).
  final double expMultiplier;
  /// Length of the granted membership, in days.
  final int durationDays;
  /// Extra storage granted while active, in megabytes (0 when none).
  final int storageBonusMb;
  /// Whether the tier unlocks gradient name colours.
  final bool allowGradient;
  /// Whether the tier unlocks animated (dynamic) name colours.
  final bool allowDynamic;
  /// Name-colour presets unlocked by the tier.
  final List<String> presetColors;

  /// Creates a tier; see [fromJson] for payload defaults.
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

  /// Deserializes from the server's tier payload, tolerating missing or
  /// mistyped fields (defaults apply per field).
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
  /// Current membership tier (0 = none).
  final int level;
  /// Current tier's display name.
  final String name;
  /// Whether the membership is currently active.
  final bool active;
  /// When the active membership expires; null when inactive or unknown.
  final DateTime? expiresAt;
  /// Experience multiplier granted by the active tier (1.0 when none).
  final double multiplier;
  /// Remaining membership duration, in days (0 when inactive).
  final int memberDays;
  /// Price already paid for the current membership, in coins (used to
  /// compute upgrade price differences).
  final int memberPrice;
  /// Whether the membership renews automatically at expiry.
  final bool autoRenew;
  /// Purchaseable tiers from the server's catalog.
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

  /// Deserializes from GET /membership, tolerating missing or mistyped
  /// fields (defaults apply per field).
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
  /// Server-assigned purchase record id.
  final int id;
  /// Tier level this purchase applied to.
  final int level;
  /// Tier display name at purchase time.
  final String tierName;
  /// Amount charged, in coins.
  final int priceCoins;
  /// What kind of transaction it was: 'purchase', 'renew' or 'upgrade'.
  final String kind; // purchase | renew | upgrade
  /// When the purchase happened (localized timestamp).
  final DateTime createdAt;

  /// Creates a purchase record; see [fromJson] for payload defaults.
  const MembershipPurchase({
    required this.id,
    required this.level,
    required this.tierName,
    required this.priceCoins,
    required this.kind,
    required this.createdAt,
  });

  /// Deserializes from the server's purchase payload; unparseable dates fall
  /// back to the Unix epoch.
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