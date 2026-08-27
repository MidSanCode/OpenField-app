import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';

/// Lists the devices the current user is signed in on and lets them revoke
/// any session (including the one on this device, which signs them out).
class SessionsPage extends StatefulWidget {
  const SessionsPage({super.key});

  @override
  State<SessionsPage> createState() => _SessionsPageState();
}

class _SessionsPageState extends State<SessionsPage> {
  final ApiService _api = ApiService();
  List<SessionDevice> _sessions = [];
  bool _loading = true;
  int? _currentSessionId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    try {
      final sessions = await _api.listSessions(token);
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
        _loading = false;
        // The first session the server returns for the requesting device is
        // "this" device; we flag it so the UI can label it.
        _currentSessionId = sessions.isNotEmpty ? sessions.first.id : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _revoke(SessionDevice device) async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final token = auth.accessToken;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('sessionRevokeConfirm'.tr()),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('cancel'.tr())),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('sessionRevoke'.tr())),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.deleteSession(token, device.id);
      final isCurrent = device.id == _currentSessionId;
      await _load();
      if (!mounted) return;
      if (isCurrent) {
        await auth.clearTokens();
        if (mounted) Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  String _formatWhen(DateTime? t) {
    if (t == null) return '';
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return 'online'.tr();
    if (diff.inHours < 1) return '${diff.inMinutes}m';
    if (diff.inDays < 1) return '${diff.inHours}h';
    if (diff.inDays < 30) return '${diff.inDays}d';
    return '${t.year}-${t.month}-${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('sessionsTitle'.tr())),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(child: Text('sessionsEmpty'.tr()))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = _sessions[index];
                    final isCurrent = device.id == _currentSessionId;
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.phone_android_outlined),
                      title: Row(
                        children: [
                          Expanded(child: Text(device.deviceLabel)),
                          if (isCurrent)
                            Chip(
                              label: Text('sessionThisDevice'.tr()),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${'sessionIp'.tr().replaceFirst('{ip}', device.lastIp)} · ${'sessionLastUsed'.tr().replaceFirst('{time}', _formatWhen(device.lastUsedAt))}',
                        style: theme.textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.logout),
                        tooltip: 'sessionRevoke'.tr(),
                        onPressed: () => _revoke(device),
                      ),
                    );
                  },
                ),
    );
  }
}
