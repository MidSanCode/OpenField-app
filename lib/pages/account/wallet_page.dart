import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/wallet.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final ApiService _apiService = ApiService();
  Wallet? _wallet;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final wallet = await _apiService.getWallet(authService.accessToken!);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
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
      appBar: AppBar(title: Text('wallet'.tr())),
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
    final wallet = _wallet!;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildBalanceCard(context, wallet.balance),
          const SizedBox(height: 24),
          Text(
            'walletTransactions'.tr(),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (wallet.transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(child: Text('walletEmpty'.tr())),
            )
          else
            ...wallet.transactions.map((t) => _buildTransactionTile(context, t)),
        ],
      ),
    );
  }

  Widget _buildBalanceCard(BuildContext context, int balance) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'walletBalance'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _formatAmount(balance),
              style: theme.textTheme.displaySmall?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionTile(BuildContext context, WalletTransaction txn) {
    final theme = Theme.of(context);
    final credit = txn.isCredit;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        credit ? Icons.add_circle_outline : Icons.remove_circle_outline,
        color: credit ? theme.colorScheme.primary : theme.colorScheme.error,
      ),
      title: Text(txn.description.isEmpty ? _typeLabel(txn.type) : txn.description),
      subtitle: Text(_formatTime(txn.createdAt)),
      trailing: Text(
        '${credit ? '+' : ''}${_formatAmount(txn.amount)}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: credit ? theme.colorScheme.primary : theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'recharge':
        return 'walletTypeRecharge'.tr();
      case 'deduct':
        return 'walletTypeDeduct'.tr();
      default:
        return type;
    }
  }

  String _formatAmount(int amount) {
    return (amount / 100).toStringAsFixed(2);
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    if (day == today) return '$hh:$mm';
    final yesterday = today.subtract(const Duration(days: 1));
    if (day == yesterday) return 'walletYesterday'.tr();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}
