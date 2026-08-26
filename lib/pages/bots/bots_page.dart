import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/widgets/robot_badge.dart';

/// Bot account management for the signed-in human user: create bots, reveal
/// the one-time API token, regenerate or delete them.
///
/// Bots are ordinary accounts everywhere else — they chat and post like
/// humans — they just authenticate with a static ofb_ token instead of a
/// password and render a robot badge next to their name.
class BotsPage extends StatefulWidget {
  const BotsPage({super.key});

  @override
  State<BotsPage> createState() => _BotsPageState();
}

class _BotsPageState extends State<BotsPage> {
  List<BotAccount>? _bots;
  final int _limit = 10;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final token = context.read<AuthService>().accessToken;
    if (token == null) return;
    try {
      final bots = await ApiService().listBots(token);
      if (!mounted) return;
      setState(() {
        _bots = bots;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _createBot() async {
    final result = await showDialog<_BotCreationResult>(
      context: context,
      builder: (_) => const _CreateBotDialog(),
    );
    if (result == null || !mounted) return;
    final token = context.read<AuthService>().accessToken;
    if (token == null) return;

    try {
      final data =
          await ApiService().registerBot(token, result.username, result.nickname);
      if (!mounted) return;
      await _reload();
      final botUser = data['user'];
      final apiToken = data['token'];
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BotTokenDialog(
          botName: botUser is Map<String, dynamic>
              ? ((botUser['nickname'] as String?)?.isNotEmpty == true
                  ? botUser['nickname'] as String
                  : botUser['username'] as String? ?? '')
              : '',
          token: apiToken?.toString() ?? '',
          isNew: true,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack(e.toString());
    }
  }

  Future<void> _regenerate(BotAccount bot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('botRegenerateTitle'.tr()),
        content: Text('botRegenerateBody'.tr(args: [bot.displayName])),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr())),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('confirm'.tr())),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthService>().accessToken;
    if (token == null) return;
    try {
      final newToken = await ApiService().regenerateBotToken(token, bot.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _BotTokenDialog(
            botName: bot.displayName, token: newToken, isNew: false),
      );
      await _reload();
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack(e.toString());
    }
  }

  Future<void> _delete(BotAccount bot) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('botDeleteTitle'.tr()),
        content: Text('botDeleteBody'.tr(args: [bot.displayName])),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final token = context.read<AuthService>().accessToken;
    if (token == null) return;
    try {
      await ApiService().deleteBot(token, bot.id);
      if (mounted) _showSnack('botDeleted'.tr());
      await _reload();
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack(e.toString());
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('bots'.tr())),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_bots?.length ?? 0) >= _limit ? null : _createBot,
        icon: const Icon(Icons.smart_toy_outlined),
        label: Text('botCreate'.tr()),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: Builder(builder: (context) {
          if (_bots == null && _error != null) {
            return ListView(children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.cloud_off_outlined,
                      size: 44, color: theme.colorScheme.outline),
                  const SizedBox(height: 10),
                  Text(_error!, textAlign: TextAlign.center),
                ]),
              ),
            ]);
          }
          final bots = _bots;
          if (bots == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (bots.isEmpty) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 80),
                  child: Column(
                    children: [
                      Icon(Icons.smart_toy_outlined,
                          size: 48, color: theme.colorScheme.outline),
                      const SizedBox(height: 12),
                      Text('botEmpty'.tr()),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          'botEmptyHint'.tr(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView.separated(
            itemCount: bots.length,
            separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
            itemBuilder: (context, i) {
              final bot = bots[i];
              return ListTile(
                leading: bot.avatarUrl.isNotEmpty
                    ? CircleAvatar(
                        radius: 22,
                        backgroundImage: NetworkImage(bot.avatarUrl))
                    : CircleAvatar(
                        radius: 22,
                        backgroundColor: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.7),
                        child: Icon(Icons.smart_toy,
                            color: theme.colorScheme.onPrimaryContainer),
                      ),
                title: Row(children: [
                  Flexible(child: Text(bot.displayName,
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 5),
                  RobotBadge(size: 15),
                ]),
                subtitle: Text('@${bot.username}',
                    style: theme.textTheme.bodySmall),
                trailing: PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'token') {
                      showDialog<void>(
                        context: context,
                        builder: (_) => _BotApiHelpDialog(bot: bot),
                      );
                    } else if (value == 'regen') {
                      _regenerate(bot);
                    } else if (value == 'delete') {
                      _delete(bot);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'token',
                        child: Row(children: [
                          const Icon(Icons.api, size: 18),
                          const SizedBox(width: 10),
                          Text('botApiUsage'.tr()),
                        ])),
                    PopupMenuItem(
                        value: 'regen',
                        child: Row(children: [
                          const Icon(Icons.key_off_outlined, size: 18),
                          const SizedBox(width: 10),
                          Text('botRegenerate'.tr()),
                        ])),
                    PopupMenuItem(
                        value: 'delete',
                        child: Row(children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: theme.colorScheme.error),
                          const SizedBox(width: 10),
                          Text('delete'.tr(),
                              style:
                                  TextStyle(color: theme.colorScheme.error)),
                        ])),
                  ],
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

class _BotCreationResult {
  final String username;
  final String nickname;
  const _BotCreationResult(this.username, this.nickname);
}

class _CreateBotDialog extends StatefulWidget {
  const _CreateBotDialog();

  @override
  State<_CreateBotDialog> createState() => _CreateBotDialogState();
}

class _CreateBotDialogState extends State<_CreateBotDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();

  bool get _valid =>
      RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(_usernameCtrl.text.trim()) &&
      _nicknameCtrl.text.trim().isNotEmpty;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('botCreateTitle'.tr()),
      content: Form(
        key: _formKey,
        onChanged: () => setState(() {}),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: _usernameCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'botUsernameLabel'.tr(),
              hintText: 'my_helper_bot',
              helperText: 'botUsernameHint'.tr(),
            ),
            validator: (v) =>
                v != null && RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(v)
                    ? null
                    : 'botUsernameInvalid'.tr(),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _nicknameCtrl,
            decoration: InputDecoration(
                labelText: 'botNicknameLabel'.tr()),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('cancel'.tr())),
        FilledButton(
          onPressed: !_valid
              ? null
              : () => Navigator.of(context).pop(_BotCreationResult(
                  _usernameCtrl.text.trim(), _nicknameCtrl.text.trim())),
          child: Text('create'.tr()),
        ),
      ],
    );
  }
}

/// Shown exactly once after create/regenerate: the only chance to copy the
/// plaintext ofb_ token.
class _BotTokenDialog extends StatelessWidget {
  final String botName;
  final String token;
  final bool isNew;

  const _BotTokenDialog({
    required this.botName,
    required this.token,
    required this.isNew,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(isNew ? Icons.smart_toy : Icons.key,
          color: theme.colorScheme.primary),
      title: Text(isNew ? 'botCreatedTitle'.tr() : 'botRegeneratedTitle'.tr()),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment:
          CrossAxisAlignment.start, children: [
        Text(
          isNew
              ? 'botCreatedBody'.tr(args: [botName])
              : 'botRegeneratedBody'.tr(args: [botName]),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.maxFinite,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectionArea(
            child: Text(token,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontFamily: 'monospace')),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: Text('copy'.tr()),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: token));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('botTokenCopied'.tr())));
              }
            },
          ),
        ]),
        Text('botTokenOnceWarning'.tr(),
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error)),
      ]),
      actions: [
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('done'.tr())),
      ],
    );
  }
}

/// Static API usage help shown from the per-bot menu.
class _BotApiHelpDialog extends StatelessWidget {
  final BotAccount bot;

  const _BotApiHelpDialog({required this.bot});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final example = '''
# 以机器人身份发消息（curl 示例）
curl -X POST \\
  -H "Authorization: Bearer ofb_你的令牌" \\
  -H "Content-Type: application/json" \\
  -d '{"content":"hello"}' \\
  <服务器>/api/v1/conversations/<会话ID>/messages''';
    return AlertDialog(
      title: Text('botApiUsage'.tr()),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('botApiIntro'.tr(args: ['${bot.id}'])),
              const SizedBox(height: 10),
              Container(
                width: double.maxFinite,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectionArea(
                  child: Text(example,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontFamily: 'monospace')),
                ),
              ),
              const SizedBox(height: 10),
              Text('botApiScopeNote'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('close'.tr())),
      ],
    );
  }
}
