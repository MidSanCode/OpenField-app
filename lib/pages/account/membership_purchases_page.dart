import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/membership.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// The authenticated user's membership purchase / renewal / upgrade history,
/// newest first. Each row shows the tier, how much was charged (补差价 for
/// upgrades) and when it happened.
class MembershipPurchasesPage extends StatefulWidget {
  const MembershipPurchasesPage({super.key});

  @override
  State<MembershipPurchasesPage> createState() =>
      _MembershipPurchasesPageState();
}

class _MembershipPurchasesPageState extends State<MembershipPurchasesPage> {
  final ApiService _apiService = ApiService();
  List<MembershipPurchase> _purchases = const [];
  bool _isLoading = true;
  String? _error;

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
      final purchases = await _apiService.getMembershipPurchases(token, limit: 100);
      if (!mounted) return;
      setState(() {
        _purchases = purchases;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('memberPurchasesTitle'.tr())),
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
    if (_purchases.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text('memberPurchasesEmpty'.tr()),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _purchases.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final p = _purchases[index];
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_kindIcon(p.kind), color: Theme.of(context).colorScheme.primary),
            title: Text('${_kindLabel(p.kind)} · ${_tierName(p.level, p.tierName)}'),
            subtitle: Text(_formatTime(p.createdAt)),
            trailing: Text(
              '-${p.priceCoins}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          );
        },
      ),
    );
  }

  IconData _kindIcon(String kind) {
    switch (kind) {
      case 'renew':
        return Icons.refresh;
      case 'upgrade':
        return Icons.arrow_upward;
      case 'purchase':
      default:
        return Icons.add_circle_outline;
    }
  }

  String _kindLabel(String kind) {
    switch (kind) {
      case 'renew':
        return 'memberPurchaseKindRenew'.tr();
      case 'upgrade':
        return 'memberPurchaseKindUpgrade'.tr();
      case 'purchase':
      default:
        return 'memberPurchaseKindPurchase'.tr();
    }
  }

  String _tierName(int level, String fallback) {
    final key = 'memberTier$level';
    return key.tr() == key ? fallback : key.tr();
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
