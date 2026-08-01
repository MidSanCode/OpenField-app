import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/chat_member.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/chat/start_chat_page.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/verified_badge.dart';

class ConversationPage extends StatefulWidget {
  final int conversationId;

  const ConversationPage({super.key, required this.conversationId});

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Conversation? _conversation;
  List<ChatMessage> _messages = [];
  List<ChatMember> _members = [];
  ChatMember? _myMembership;
  bool _isLoading = true;
  bool _loadingOlder = false;
  bool _hasOlder = true;
  String? _error;
  int? _replyToId;
  int _myUserId = 0;

  @override
  void initState() {
    super.initState();
    _myUserId = Provider.of<AuthService>(context, listen: false).user?.id ?? 0;
    _load();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail = await _apiService.getConversation(token, widget.conversationId);
      final messages = await _apiService.listMessages(token, widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = detail.conversation;
        _members = detail.members;
        _myMembership = detail.myMembership;
        _messages = messages;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
      if (messages.isNotEmpty) {
        await _apiService.markConversationRead(
          token,
          widget.conversationId,
          messages.last.id,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _loadingOlder = true);
    try {
      final before = _messages.first.id;
      final older = await _apiService.listMessages(token, widget.conversationId, before: before);
      if (!mounted) return;
      setState(() {
        _hasOlder = older.length >= 50;
        _messages = [...older, ..._messages];
        _loadingOlder = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  Future<void> _send() async {
    final content = _inputController.text.trim();
    if (content.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;

    final replyToId = _replyToId;
    setState(() {
      _inputController.clear();
      _replyToId = null;
    });
    try {
      final msg = await _apiService.sendChatMessage(
        token,
        widget.conversationId,
        content,
        replyToId: replyToId,
      );
      if (!mounted) return;
      setState(() => _messages = [..._messages, msg]);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
      await _apiService.markConversationRead(token, widget.conversationId, msg.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _onMessageLongPress(ChatMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    final isMine = message.senderId == _myUserId;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text(l10n.chatQuoteReply),
              onTap: () => Navigator.of(ctx).pop('reply'),
            ),
            if (isMine && !message.isDeleted) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(l10n.edit),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text(l10n.delete, style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'reply':
        setState(() => _replyToId = message.id);
        break;
      case 'edit':
        await _editMessage(message);
        break;
      case 'delete':
        await _deleteMessage(message);
        break;
    }
  }

  Future<void> _editMessage(ChatMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: message.content);
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.edit),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 5000,
          decoration: InputDecoration(hintText: l10n.message),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (content == null || content.isEmpty) return;
    try {
      final updated = await _apiService.editChatMessage(
        token,
        widget.conversationId,
        message.id,
        content,
      );
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((m) => m.id == updated.id ? updated : m).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.deleteChatMessage(token, widget.conversationId, message.id);
      if (!mounted) return;
      setState(() {
        _messages = _messages.map((m) {
          if (m.id != message.id) return m;
          return ChatMessage(
            id: m.id,
            conversationId: m.conversationId,
            senderId: m.senderId,
            content: '',
            createdAt: m.createdAt,
            deletedAt: DateTime.now(),
            replyToId: m.replyToId,
            editedAt: m.editedAt,
            senderName: m.senderName,
            senderAvatar: m.senderAvatar,
          );
        }).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _editNote() async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: _myMembership?.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatNote),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: l10n.chatNote),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (note == null) return;
    try {
      await _apiService.updateNote(token, widget.conversationId, note);
      if (!mounted) return;
      setState(() {
        _myMembership = _myMembership == null
            ? null
            : ChatMember(
                conversationId: _myMembership!.conversationId,
                userId: _myMembership!.userId,
                role: _myMembership!.role,
                note: note,
                groupNickname: _myMembership!.groupNickname,
                status: _myMembership!.status,
                addedBy: _myMembership!.addedBy,
                createdAt: _myMembership!.createdAt,
                username: _myMembership!.username,
                nickname: _myMembership!.nickname,
                avatarUrl: _myMembership!.avatarUrl,
              );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _editGroupNickname() async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: _myMembership?.groupNickname ?? '');
    final nickname = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatGroupNickname),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: l10n.chatGroupNickname),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (nickname == null) return;
    try {
      await _apiService.updateGroupNickname(token, widget.conversationId, nickname);
      if (!mounted) return;
      setState(() {
        _myMembership = _myMembership == null
            ? null
            : ChatMember(
                conversationId: _myMembership!.conversationId,
                userId: _myMembership!.userId,
                role: _myMembership!.role,
                note: _myMembership!.note,
                groupNickname: nickname,
                status: _myMembership!.status,
                addedBy: _myMembership!.addedBy,
                createdAt: _myMembership!.createdAt,
                username: _myMembership!.username,
                nickname: _myMembership!.nickname,
                avatarUrl: _myMembership!.avatarUrl,
              );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _showMembers() async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final canManage = _myMembership?.role == 'owner' || _myMembership?.role == 'admin';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final members = _members.where((m) => m.userId != _myUserId).toList();
        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            builder: (context, scrollController) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Text(
                        l10n.chatGroupMembers,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (canManage)
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_outlined),
                          tooltip: l10n.chatGroupInvite,
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    StartChatPage(inviteToGroup: widget.conversationId),
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final m = members[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          backgroundImage: (m.avatarUrl != null && m.avatarUrl!.isNotEmpty)
                              ? NetworkImage(m.avatarUrl!)
                              : null,
                          child: (m.avatarUrl == null || m.avatarUrl!.isEmpty)
                              ? Text(m.displayName.substring(0, 1).toUpperCase())
                              : null,
                        ),
                        title: Text(m.displayName),
                        subtitle: Text(_roleLabel(l10n, m.role)),
                        trailing: canManage && m.role != 'owner'
                            ? IconButton(
                                icon: Icon(Icons.person_remove_outlined,
                                    color: Theme.of(context).colorScheme.error),
                                tooltip: l10n.delete,
                                onPressed: () async {
                                  await _removeMember(m.userId);
                                },
                              )
                            : null,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _roleLabel(AppLocalizations l10n, String role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return l10n.normalUser;
    }
  }

  Future<void> _removeMember(int userId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.removeGroupMember(token, widget.conversationId, userId);
      if (!mounted) return;
      setState(() {
        _members = _members.where((m) => m.userId != userId).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _leaveGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatGroupLeaveConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _apiService.leaveGroup(token, widget.conversationId);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final conv = _conversation;
    final isGroup = conv?.isGroup ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(conv?.title ?? ''),
        actions: [
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: l10n.chatGroupMembers,
              onPressed: _showMembers,
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'note':
                  _editNote();
                  break;
                case 'nickname':
                  _editGroupNickname();
                  break;
                case 'leave':
                  _leaveGroup();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (!isGroup)
                PopupMenuItem(value: 'note', child: Text(l10n.chatNote)),
              if (isGroup)
                PopupMenuItem(value: 'nickname', child: Text(l10n.chatGroupNickname)),
              if (isGroup)
                PopupMenuItem(
                  value: 'leave',
                  child: Text(
                    l10n.chatGroupLeave,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.loadFailed),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: _messages.length + (_hasOlder ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == 0 && _hasOlder) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: _loadingOlder
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : TextButton(
                            onPressed: _loadOlder,
                            child: const Text('Load earlier'),
                          ),
                  ),
                );
              }
              final msgIndex = index - (_hasOlder ? 1 : 0);
              final message = _messages[msgIndex];
              final replyTo = message.replyToId != null
                  ? _messages.where((m) => m.id == message.replyToId).firstOrNull
                  : null;
              return _MessageBubble(
                message: message,
                isMine: message.senderId == _myUserId,
                showSenderName: (_conversation?.isGroup ?? false) && !message.isDeleted,
                senderAvatar: message.senderAvatar,
                replyPreview: replyTo,
                onLongPress: () => _onMessageLongPress(message),
              );
            },
          ),
        ),
        if (_replyToId != null)
          _ReplyBar(
            message: _messages.where((m) => m.id == _replyToId).firstOrNull,
            onCancel: () => setState(() => _replyToId = null),
          ),
        _buildInputBar(l10n),
      ],
    );
  }

  Widget _buildInputBar(AppLocalizations l10n) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.message,
                  isDense: true,
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _send,
              icon: const Icon(Icons.send),
              tooltip: l10n.send,
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool showSenderName;
  final String? senderAvatar;
  final ChatMessage? replyPreview;
  final VoidCallback onLongPress;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    required this.onLongPress,
    this.senderAvatar,
    this.replyPreview,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: (senderAvatar != null && senderAvatar!.isNotEmpty)
                  ? NetworkImage(senderAvatar!)
                  : null,
              child: (senderAvatar == null || senderAvatar!.isEmpty)
                  ? Text(message.displayName.isEmpty
                      ? '?'
                      : message.displayName.substring(0, 1).toUpperCase())
                  : null,
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Column(
                crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (showSenderName && message.displayName.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      child: VerifiedName(
                        name: message.displayName,
                        verified: message.senderVerified,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.68,
                    ),
                    decoration: BoxDecoration(
                      color: isMine
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(isMine ? 14 : 4),
                        topRight: Radius.circular(isMine ? 4 : 14),
                        bottomLeft: const Radius.circular(14),
                        bottomRight: const Radius.circular(14),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (replyPreview != null && !replyPreview!.isDeleted) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${replyPreview!.displayName}: ${replyPreview!.content}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                        if (message.isDeleted)
                          Text(
                            l10n.messageDeleted,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          MarkdownContent(
                            data: message.content,
                            padding: EdgeInsets.zero,
                          ),
                        if (message.isEdited)
                          Text(
                            l10n.chatEdited,
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Text(
                      _formatTime(message.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMine) const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

class _ReplyBar extends StatelessWidget {
  final ChatMessage? message;
  final VoidCallback onCancel;

  const _ReplyBar({required this.message, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message == null
                  ? 'Replying...'
                  : '${message!.displayName}: ${message!.content}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
