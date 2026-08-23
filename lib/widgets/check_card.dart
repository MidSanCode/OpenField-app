import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:openfield/core/widgets/pin_dialog.dart';
import 'package:openfield/data/models/check.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// Formats a cents amount as a compact coin figure (e.g. "12" or "12.5").
String formatCoins(int cents) {
  if (cents % 100 == 0) return '${cents ~/ 100}';
  return (cents / 100).toStringAsFixed(2);
}

/// A claimable red-packet card for one [checkId]. Loads the current state
/// from the server; tapping claims a share when possible. Used both inside
/// chat bubbles and attached to posts.
class CheckCard extends StatefulWidget {
  final int checkId;
  final String? token;

  const CheckCard({super.key, required this.checkId, this.token});

  @override
  State<CheckCard> createState() => _CheckCardState();
}

class _CheckCardState extends State<CheckCard> {
  final ApiService _apiService = ApiService();
  Check? _check;
  bool _loading = true;
  bool _claiming = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final check = await _apiService.getCheck(widget.checkId,
          token: widget.token ?? authService.accessToken);
      if (!mounted) return;
      setState(() {
        _check = check;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _claim() async {
    final token = widget.token ??
        Provider.of<AuthService>(context, listen: false).accessToken;
    if (token == null || _claiming) return;
    setState(() => _claiming = true);
    try {
      await _apiService.claimCheck(token, widget.checkId);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
      // Reload anyway: the error may be "already claimed" / "all taken".
      await _load();
    } finally {
      if (mounted) setState(() => _claiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_error != null || _check == null) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(Icons.redeem, color: theme.colorScheme.outline),
            const SizedBox(width: 8),
            Expanded(child: Text('checkUnavailable'.tr())),
          ],
        ),
      );
    }
    final check = _check!;
    final claimable = check.isActive &&
        !check.claimedByMe;

    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: claimable && !_claiming ? _claim : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(Icons.redeem_rounded,
                          size: 40, color: theme.colorScheme.primary),
                      if (_claiming)
                        const SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _statusText(check),
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'checkSummary'.tr(args: [
                            formatCoins(check.total),
                            '${check.shares}',
                            check.isRandom
                                ? 'checkModeRandom'.tr()
                                : 'checkModeAverage'.tr()
                          ]),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (claimable)
                    Icon(Icons.touch_app_outlined,
                        size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ),
          ),
          if (check.claims.isNotEmpty)
            Container(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${check.claims.length}/${check.shares} · ${formatCoins(check.claimedTotal)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...check.claims.take(5).map(
                        (cl) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Avatar(radius: 10, imageUrl: cl.userAvatar),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  cl.userName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                              Text(formatCoins(cl.amount),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusText(Check check) {
    if (check.claimedByMe) {
      return 'checkClaimedMine'.tr(args: [formatCoins(check.myAmount)]);
    }
    switch (check.status) {
      case 'settled':
        return 'checkAllClaimed'.tr();
      case 'refunded':
        return 'checkExpiredRefunded'.tr();
      default:
        if (!check.isActive) return 'checkExpired'.tr();
        if (check.remainingShares <= 0) return 'checkAllClaimed'.tr();
        return 'checkTapToClaim'.tr();
    }
  }
}

/// Opens the compose dialog (amount/shares/mode/expiry), then the payment PIN
/// prompt, and creates the check. Returns the new check id, or null when the
/// flow was cancelled or failed (failures surface as snackbars).
Future<int?> showCheckComposeDialog(BuildContext context) async {
  final form = await _showForm(context);
  if (form == null || !context.mounted) return null;

  final authService = Provider.of<AuthService>(context, listen: false);
  final api = ApiService();
  final token = authService.accessToken;
  if (token == null) return null;

  String pin;
  try {
    if (!(authService.user?.hasPin ?? false)) {
      pin = await showPinDialog(context, isSetting: true) ?? '';
      if (pin.isEmpty || !context.mounted) return null;
      await api.setPin(token, pin);
      await authService.fetchCurrentUser();
    } else {
      pin = await showPinDialog(context, isSetting: false) ?? '';
      if (pin.isEmpty || !context.mounted) return null;
    }
    final check = await api.createCheck(
      token,
      amountCoins: form.$1,
      shares: form.$2,
      mode: form.$3,
      expiresInHours: form.$4,
      pin: pin,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('checkCreated'.tr())),
      );
    }
    return check.id;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
    return null;
  }
}

typedef _CheckForm = (double amount, int shares, String mode, int hours);

Future<_CheckForm?> _showForm(BuildContext context) async {
  final amountController = TextEditingController();
  final sharesController = TextEditingController(text: '1');
  String mode = 'random';
  int hours = 24;

  return showDialog<_CheckForm>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text('checkComposeTitle'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: amountController,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'checkAmount'.tr()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sharesController,
                keyboardType: TextInputType.number,
                decoration:
                    InputDecoration(labelText: 'checkShares'.tr()),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'random',
                    icon: const Icon(Icons.casino_outlined, size: 18),
                    label: Text('checkModeRandom'.tr()),
                  ),
                  ButtonSegment(
                    value: 'average',
                    icon: const Icon(Icons.balance_outlined, size: 18),
                    label: Text('checkModeAverage'.tr()),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (s) => setState(() => mode = s.first),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final (h, key) in const [
                    (1, 'checkExpiry1h'),
                    (24, 'checkExpiry24h'),
                    (72, 'checkExpiry3d'),
                    (168, 'checkExpiry7d'),
                  ])
                    ChoiceChip(
                      label: Text(key.tr()),
                      selected: hours == h,
                      onSelected: (_) => setState(() => hours = h),
                    ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text.trim());
              final shares = int.tryParse(sharesController.text.trim());
              if (amount == null || amount <= 0 || shares == null ||
                  shares < 1 || shares > 500) {
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  SnackBar(content: Text('checkInvalidInput'.tr())),
                );
                return;
              }
              Navigator.of(dialogContext).pop((amount, shares, mode, hours));
            },
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    ),
  );
}
