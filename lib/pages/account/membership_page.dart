import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/core/widgets/pin_dialog.dart';
import 'package:openfield/data/models/membership.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/account/name_style_page.dart';

/// Membership hub: shows the user's current tier, expiry and exp multiplier
/// plus the purchaseable catalog. Purchases are paid with wallet coins and
/// authorized by the payment PIN (same flow as transfers).
class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  final ApiService _apiService = ApiService();
  MembershipStatus? _status;
  bool _isLoading = true;
  String? _error;
  int? _buyingLevel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final status = await _apiService.getMembership(token);
      if (!mounted) return;
      setState(() {
        _status = status;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _purchase(MembershipTier tier) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null || _buyingLevel != null) return;

    setState(() => _buyingLevel = tier.level);
    try {
      // Payment PIN authorizes the purchase: first-time payers must set one.
      var pin = '';
      if (!(authService.user?.hasPin ?? false)) {
        pin = await showPinDialog(context, isSetting: true) ?? '';
        if (pin.isEmpty || !mounted) return;
        await _apiService.setPin(token, pin);
        await authService.fetchCurrentUser();
      } else {
        pin = await showPinDialog(context, isSetting: false) ?? '';
        if (pin.isEmpty || !mounted) return;
      }
      await _apiService.purchaseMembership(token, tier.level, pin);
      await authService.fetchCurrentUser();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('memberPurchased'.tr(args: [tier.name]))),
      );
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _buyingLevel = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('memberTitle'.tr())),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('loadFailed'.tr()),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text('retry'.tr())),
          ],
        ),
      );
    }
    final status = _status!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(context, status),
          const SizedBox(height: 8),
          Text(
            'memberTiers'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...status.tiers.map((t) => _buildTierCard(context, t)),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context, MembershipStatus status) {
    final theme = Theme.of(context);
    final active = status.active;
    final label = active
        ? (status.name.isNotEmpty
            ? _tierName(status.level, status.name)
            : 'memberLv'.tr(namedArgs: {'level': '${status.level}'}))
        : 'memberNone'.tr();

    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  active ? Icons.workspace_premium : Icons.workspace_premium_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              active
                  ? 'memberActiveHint'.tr(
                      namedArgs: {
                        'level': '${status.level}',
                        'multiplier': _formatMultiplier(status.multiplier),
                      },
                    )
                  : 'memberInactiveHint'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              active && status.expiresAt != null
                  ? 'memberExpiresAt'.tr(
                      namedArgs: {'date': _formatDate(status.expiresAt!.toLocal())},
                    )
                  : 'memberDurationHint'.tr(
                      namedArgs: {'days': '${status.memberDays}'},
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NameStylePage()),
                );
              },
              icon: const Icon(Icons.palette_outlined, size: 18),
              label: Text('nameStyleTitle'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierCard(BuildContext context, MembershipTier tier) {
    final theme = Theme.of(context);
    final status = _status;
    final isCurrent = status != null && status.active && status.level >= tier.level;
    final buying = _buyingLevel == tier.level;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.workspace_premium_outlined, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Lv.${tier.level} ${_tierName(tier.level, tier.name)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'memberOwned'.tr(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              tier.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (tier.storageBonusMb > 0)
                  _perkChip(
                    theme,
                    Icons.storage_outlined,
                    'memberStorageBonus'.tr(namedArgs: {'mb': '${tier.storageBonusMb}'}),
                  ),
                _perkChip(theme, Icons.palette_outlined, 'memberNameColorPerk'.tr()),
                if (tier.allowGradient)
                  _perkChip(theme, Icons.gradient, 'memberNameGradientPerk'.tr()),
                if (tier.allowDynamic)
                  _perkChip(theme, Icons.auto_awesome, 'memberNameDynamicPerk'.tr()),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'memberPrice'.tr(namedArgs: {'price': '${tier.price}'}),
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'memberExpMultiplier'.tr(
                          namedArgs: {'multiplier': _formatMultiplier(tier.expMultiplier)},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton(
                  onPressed: isCurrent || buying ? null : () => _purchase(tier),
                  child: buying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(isCurrent ? 'memberOwned'.tr() : 'memberBuy'.tr()),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _perkChip(ThemeData theme, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  /// Localized tier names; falls back to the server-provided name so new tiers
  /// still render even if this client build lacks a translation.
  String _tierName(int level, String fallback) {
    final key = 'memberTier$level';
    return key.tr() == key ? fallback : key.tr();
  }

  String _formatMultiplier(double value) {
    return value == value.roundToDouble()
        ? '${value.toInt()}'
        : '$value';
  }

  String _formatDate(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
  }
}