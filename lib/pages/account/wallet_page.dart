import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/core/widgets/pin_dialog.dart';
import 'package:openfield/data/models/transfer.dart';
import 'package:openfield/data/models/user.dart';
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

  List<Transfer> _incoming = const [];
  List<Transfer> _outgoing = const [];
  bool _transfersLoaded = false;

  int _tabIndex = 0;

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
      final token = authService.accessToken;
      final wallet = await _apiService.getWallet(token!);
      if (!mounted) return;
      setState(() {
        _wallet = wallet;
        _isLoading = false;
      });
      await _loadTransfers(authService);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadTransfers(AuthService authService) async {
    final token = authService.accessToken;
    if (token == null) return;
    try {
      final results = await Future.wait([
        _apiService.listTransfers(token, direction: 'incoming', limit: 50),
        _apiService.listTransfers(token, direction: 'outgoing', limit: 50),
      ]);
      if (!mounted) return;
      setState(() {
        _incoming = results[0];
        _outgoing = results[1];
        _transfersLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _transfersLoaded = true);
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
          const SizedBox(height: 16),
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text('walletTransactions'.tr())),
              ButtonSegment(value: 1, label: Text('transfers'.tr())),
            ],
            selected: {_tabIndex},
            onSelectionChanged: (selection) {
              setState(() => _tabIndex = selection.first);
            },
          ),
          const SizedBox(height: 16),
          if (_tabIndex == 0)
            _buildTransactionsSection(context, wallet)
          else
            _buildTransfersSection(context),
        ],
      ),
    );
  }

  Widget _buildTransactionsSection(BuildContext context, Wallet wallet) {
    if (wallet.transactions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Text('walletEmpty'.tr())),
      );
    }
    return Column(
      children: wallet.transactions.map((t) => _buildTransactionTile(context, t)).toList(),
    );
  }

  Widget _buildTransfersSection(BuildContext context) {
    final pending = _incoming.where((t) => t.isPending).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.tonalIcon(
          onPressed: () => _showSendTransferDialog(context),
          icon: const Icon(Icons.send),
          label: Text('transferSend'.tr()),
        ),
        const SizedBox(height: 16),
        if (pending.isNotEmpty) ...[
          Text('transferIncomingPending'.tr(), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ...pending.map((t) => _buildTransferTile(context, t)),
          const SizedBox(height: 16),
        ],
        if (_outgoing.isNotEmpty) ...[
          Text('transferOutgoing'.tr(), style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          ..._outgoing.take(20).map((t) => _buildTransferTile(context, t)),
        ],
        if (pending.isEmpty && _outgoing.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                _transfersLoaded ? 'transferEmpty'.tr() : 'loadFailed'.tr(),
              ),
            ),
          ),
      ],
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

  Widget _buildTransferTile(BuildContext context, Transfer t) {
    final theme = Theme.of(context);
    final isIncoming = t.recipientId == _currentUserId();
    final isPending = t.isPending;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    isIncoming
                        ? (t.senderName.isNotEmpty ? t.senderName : 'transferUser'.tr())
                        : (t.recipientName.isNotEmpty ? t.recipientName : 'transferUser'.tr()),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Text(
                  '${isIncoming ? '+' : '-'}${_formatAmount(t.amount)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isIncoming ? theme.colorScheme.primary : theme.colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (t.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(t.note, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 4),
            Row(
              children: [
                Text(_statusLabel(t), style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(_formatTime(t.createdAt), style: theme.textTheme.bodySmall),
              ],
            ),
            if (isPending && isIncoming) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => _declineTransfer(t),
                    child: Text('chatRequestDecline'.tr()),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => _acceptTransfer(t),
                    child: Text('chatRequestAccept'.tr()),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  int? _currentUserId() {
    final authService = Provider.of<AuthService>(context, listen: false);
    return authService.user?.id;
  }

  Future<void> _acceptTransfer(Transfer t) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await _apiService.acceptTransfer(authService.accessToken!, t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('transferAccepted'.tr())),
      );
      await _load();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _declineTransfer(Transfer t) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      await _apiService.declineTransfer(authService.accessToken!, t.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('transferDeclined'.tr())),
      );
      await _load();
    } catch (e) {
      if (mounted) _showError(context, e);
    }
  }

  Future<void> _showSendTransferDialog(BuildContext context) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;

    final recipient = await _pickRecipient(context, token);
    if (recipient == null || !context.mounted) return;

    final controller = TextEditingController();
    final noteController = TextEditingController();
    String? errorText;
    final messenger = ScaffoldMessenger.of(context);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('transferSendTo'.tr(args: [recipient.displayName])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'transferAmount'.tr(),
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'transferNote'.tr(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('cancel'.tr()),
            ),
            FilledButton(
              onPressed: () async {
                final amount = _parseAmount(controller.text);
                if (amount == null || amount <= 0) {
                  setState(() => errorText = 'transferAmountInvalid'.tr());
                  return;
                }
                final note = noteController.text.trim();
                // Close the transfer dialog before prompting for the PIN so the
                // PIN dialog stays on top of the page, not the dialog.
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                if (!context.mounted) return;
                try {
                  var pin = '';
                  if (!(authService.user?.hasPin ?? false)) {
                    // First payment: force the user to set a payment PIN.
                    pin = await showPinDialog(context, isSetting: true) ?? '';
                    if (pin.isEmpty || !context.mounted) return;
                    await _apiService.setPin(token, pin);
                    await authService.fetchCurrentUser();
                  } else {
                    pin = await showPinDialog(context, isSetting: false) ?? '';
                    if (pin.isEmpty || !context.mounted) return;
                  }
                  await _apiService.createTransfer(
                    token,
                    recipientId: recipient.id,
                    amount: amount,
                    note: note,
                    pin: pin,
                  );
                  if (context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('transferSent'.tr())),
                    );
                    await _load();
                  }
                } catch (e) {
                  if (context.mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(e.toString())),
                    );
                  }
                }
              },
              child: Text('send'.tr()),
            ),
          ],
        ),
      ),
    );
  }

  /// Shows a searchable list of users; returns the selected recipient.
  Future<User?> _pickRecipient(BuildContext context, String token) async {
    final selected = await showModalBottomSheet<User>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RecipientPicker(token: token),
    );
    return selected;
  }

  int? _parseAmount(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    final value = int.tryParse(trimmed);
    return value;
  }

  String _statusLabel(Transfer t) {
    switch (t.status) {
      case 'pending':
        return 'transferStatusPending'.tr();
      case 'accepted':
        return 'transferStatusAccepted'.tr();
      case 'declined':
        return 'transferStatusDeclined'.tr();
      case 'refunded':
        return 'transferStatusRefunded'.tr();
      default:
        return t.status;
    }
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
    return '$amount';
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

  void _showError(BuildContext context, Object e) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
  }
}

/// Searchable user picker used to choose a transfer recipient.
class _RecipientPicker extends StatefulWidget {
  final String token;

  const _RecipientPicker({required this.token});

  @override
  State<_RecipientPicker> createState() => _RecipientPickerState();
}

class _RecipientPickerState extends State<_RecipientPicker> {
  final ApiService _apiService = ApiService();
  final _controller = TextEditingController();
  List<User> _results = const [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final q = query.trim();
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final results = await _apiService.searchUsers(widget.token, q, limit: 15);
      if (!mounted) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (_) {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Icon(Icons.person_search_outlined, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('transferPickRecipient'.tr(), style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'chatSearchHint'.tr(),
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: _search,
              ),
            ),
            const Divider(height: 16),
            Expanded(
              child: _searching
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                      ? Center(child: Text('chatNoUsers'.tr()))
                      : ListView(
                          children: _results.map((u) => _buildResultTile(context, u)).toList(),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultTile(BuildContext context, User user) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primaryContainer,
        backgroundImage: user.avatarUrl.isNotEmpty ? NetworkImage(user.avatarUrl) : null,
        child: user.avatarUrl.isEmpty
            ? Text(user.displayName.isEmpty ? '?' : user.displayName[0].toUpperCase())
            : null,
      ),
      title: Text(user.displayName),
      subtitle: Text('@${user.username}'),
      onTap: () => Navigator.of(context).pop(user),
    );
  }
}