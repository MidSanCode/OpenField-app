import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/chat/conversation_page.dart';
import 'package:openfield/pages/chat/consent_requests_page.dart';
import 'package:openfield/pages/chat/start_chat_page.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final ApiService _apiService = ApiService();
  List<Conversation> _conversations = [];
  List<dynamic> _requests = [];
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
    if (token == null) {
      setState(() {
        _isLoading = false;
        _conversations = [];
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final conversations = await _apiService.listConversations(token);
      final requests = await _apiService.listConsentRequests(token);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _requests = requests;
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

  Future<void> _openConversation(Conversation conv) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConversationPage(conversationId: conv.id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openStartChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StartChatPage()),
    );
    if (mounted) _load();
  }

  Future<void> _openRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConsentRequestsPage()),
    );
    if (mounted) _load();
  }

  Future<void> _createGroup() async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatGroupCreate),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: l10n.groupTitle,
            hintText: l10n.groupTitleHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.confirm),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      final conv = await _apiService.createGroup(token, title);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => StartChatPage(inviteToGroup: conv.id),
        ),
      );
      if (mounted) _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chat),
        actions: [
          IconButton(
            onPressed: _openRequests,
            tooltip: l10n.chatRequests,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.person_add_alt_outlined),
                if (_requests.isNotEmpty)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        '${_requests.length}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: _openStartChat,
            tooltip: l10n.chatStartPrivate,
            icon: const Icon(Icons.chat_bubble_outline),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'group') _createGroup();
              if (value == 'private') _openStartChat();
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'private', child: Text(l10n.chatStartPrivate)),
              PopupMenuItem(value: 'group', child: Text(l10n.chatNewGroup)),
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
    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(l10n.chatEmpty),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _openStartChat,
              icon: const Icon(Icons.add),
              label: Text(l10n.chatStartPrivate),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        itemCount: _conversations.length,
        separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
        itemBuilder: (context, index) {
          final conv = _conversations[index];
          return _ConversationTile(
            conversation: conv,
            onTap: () => _openConversation(conv),
          );
        },
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const _ConversationTile({required this.conversation, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final last = conversation.lastMessage;
    final time = last != null ? _formatTime(last.createdAt) : '';
    final preview = _buildPreview(context, l10n, last);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: theme.colorScheme.primaryContainer,
              backgroundImage: conversation.avatarUrl.isNotEmpty
                  ? NetworkImage(conversation.avatarUrl)
                  : null,
              child: conversation.avatarUrl.isEmpty
                  ? Icon(
                      conversation.isGroup ? Icons.group : Icons.person,
                      color: theme.colorScheme.onPrimaryContainer,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conversation.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (time.isNotEmpty)
                        Text(time, style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: preview,
                      ),
                      if (conversation.unread > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            conversation.unread > 99 ? '99+' : '${conversation.unread}',
                            style: TextStyle(
                              color: theme.colorScheme.onError,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, AppLocalizations l10n, ChatMessage? last) {
    final theme = Theme.of(context);
    if (last == null) return const SizedBox.shrink();
    String text;
    if (last.isDeleted) {
      text = l10n.messageDeleted;
    } else if (conversation.isGroup && last.displayName.isNotEmpty) {
      text = '${last.displayName}: ${last.content}';
    } else {
      text = last.content;
    }
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(time.year, time.month, time.day);
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    if (that == today) return '$h:$m';
    if (now.difference(that).inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[time.weekday - 1];
    }
    return '${time.month}-${time.day}';
  }
}
