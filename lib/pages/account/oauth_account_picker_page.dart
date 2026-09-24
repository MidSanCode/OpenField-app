import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:openfield/core/widgets/error_dialog.dart';
import 'package:openfield/data/models/user.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/pages/register/register_page.dart';

/// The multi-account picker shown right after an OIDC login when the identity
/// is already bound to one or more OpenField accounts. It lists the bound
/// accounts ("您想要登录哪个账号"), lets the user pick one to sign in as, or —
/// while the per-identity quota has room — add a brand-new account.
///
/// The page never signs in by itself: it holds a server-issued single-use
/// "pick ticket" from the OAuth callback. Selecting an account or creating a
/// new one consumes the ticket and returns a regular login token payload,
/// which is applied through [AuthService.applyLoginResult] exactly like a
/// normal login.
class OAuthAccountPickerPage extends StatefulWidget {
  /// The server-issued pick ticket from the OIDC callback.
  final String ticket;

  const OAuthAccountPickerPage({super.key, required this.ticket});

  @override
  State<OAuthAccountPickerPage> createState() => _OAuthAccountPickerPageState();
}

class _OAuthAccountPickerPageState extends State<OAuthAccountPickerPage> {
  final ApiService _apiService = ApiService();
  bool _loading = true;
  bool _working = false;
  String? _error;
  String _identityLabel = '';
  String _identityAvatar = '';
  int _maxAccounts = 5;
  List<User> _accounts = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _apiService.getOIDCPick(widget.ticket);
      if (!mounted) return;
      final raw = data['accounts'];
      final accounts = <User>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            accounts.add(User.fromJson(item));
          }
        }
      }
      setState(() {
        _identityLabel = (data['oauth2_username'] as String?) ?? '';
        _identityAvatar = (data['avatar_url'] as String?) ?? '';
        _maxAccounts = (data['max_accounts'] as num?)?.toInt() ?? 5;
        _accounts = accounts;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'pickTicketInvalid'.tr();
      });
    }
  }

  Future<void> _select(User account) async {
    setState(() => _working = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await _apiService.selectOIDCPick(widget.ticket, account.id);
      await authService.applyLoginResult(result);
      await _finishLogin(authService);
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _createNew() async {
    setState(() => _working = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final result = await _apiService.createOIDCPick(widget.ticket);
      await authService.applyLoginResult(result);
      await _finishLogin(authService);
    } catch (e) {
      if (mounted) await showApiErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Shared tail after applying the pick login result: refresh the full
  /// profile and open registration for accounts that still need it, else head
  /// to the account tab like a normal login.
  Future<void> _finishLogin(AuthService authService) async {
    if (!mounted) return;
    await authService.fetchCurrentUser();
    if (!mounted) return;
    final user = authService.user;
    if (user?.needsRegistration ?? false) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const RegisterPage()),
      );
    }
    if (mounted) context.go('/account');
  }

  bool get _canAdd => _accounts.length < _maxAccounts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('pickAccountTitle'.tr())),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 48, color: theme.colorScheme.error),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _load,
                child: Text('retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_identityLabel.isNotEmpty) ...[
          Row(
            children: [
              Avatar(
                imageUrl: _identityAvatar,
                radius: 20,
                initials: _identityLabel.isNotEmpty
                    ? _identityLabel.substring(0, 1).toUpperCase()
                    : '',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _identityLabel,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ] else
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              'pickAccountHint'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final account in _accounts)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: Avatar(
                imageUrl: account.avatarUrl,
                radius: 22,
                initials: _initials(account),
              ),
              title: Text(_displayName(account)),
              subtitle: account.username.isNotEmpty
                  ? Text('@${account.username}')
                  : null,
              trailing: const Icon(Icons.chevron_right),
              onTap: _working ? null : () => _select(account),
            ),
          ),
        const SizedBox(height: 8),
        if (_canAdd)
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                child: Icon(Icons.add, color: theme.colorScheme.primary),
              ),
              title: Text('addNewAccount'.tr()),
              onTap: _working ? null : _createNew,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'pickQuotaReached'.tr(namedArgs: {'max': '$_maxAccounts'}),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }

  String _displayName(User user) {
    final name = user.nickname.isNotEmpty ? user.nickname : user.username;
    return name.isNotEmpty ? name : 'Account';
  }

  String _initials(User user) {
    final name = _displayName(user);
    return name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '';
  }
}