import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/task.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// The user's experience award history, newest first. Reached by tapping the
/// experience bar on the account page.
class ExpHistoryPage extends StatefulWidget {
  const ExpHistoryPage({super.key});

  @override
  State<ExpHistoryPage> createState() => _ExpHistoryPageState();
}

class _ExpHistoryPageState extends State<ExpHistoryPage> {
  final ApiService _apiService = ApiService();
  List<ExpEntry> _entries = const [];
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
      final entries = await _apiService.listExpHistory(token, limit: 100);
      if (!mounted) return;
      setState(() {
        _entries = entries;
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
      appBar: AppBar(title: Text('expHistoryTitle'.tr())),
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
    if (_entries.isEmpty) {
      return Center(child: Text('expHistoryEmpty'.tr()));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _entries.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) => _buildEntry(context, _entries[index]),
      ),
    );
  }

  Widget _buildEntry(BuildContext context, ExpEntry entry) {
    final theme = Theme.of(context);
    final positive = entry.amount > 0;
    return ListTile(
      leading: Icon(
        positive ? Icons.add_circle_outline : Icons.remove_circle_outline,
        color: positive ? theme.colorScheme.primary : theme.colorScheme.error,
      ),
      title: Text(
        entry.description.isEmpty ? _reasonLabel(entry.reason) : entry.description,
      ),
      subtitle: Text(
        '${_reasonLabel(entry.reason)} · ${_formatTime(entry.createdAt)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Text(
        '${positive ? '+' : ''}${entry.amount}',
        style: theme.textTheme.titleMedium?.copyWith(
          color: positive ? theme.colorScheme.primary : theme.colorScheme.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _reasonLabel(String reason) {
    switch (reason) {
      case 'daily_bonus':
        return 'expReasonDailyBonus'.tr();
      case 'makeup':
        return 'expReasonMakeup'.tr();
      case 'task':
        return 'expReasonTask'.tr();
      case 'adjust':
        return 'expReasonAdjust'.tr();
      default:
        return reason;
    }
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} $hh:$mm';
  }
}