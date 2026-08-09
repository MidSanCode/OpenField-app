import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/chat/conversation_page.dart';
import 'package:openfield/pages/chat/consent_requests_page.dart';
import 'package:openfield/pages/chat/discover_groups_page.dart';
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
  StreamSubscription<PushEvent>? _realtimeSub;
  int? _selectedConversationId;

  /// Wide (landscape / tablet) layouts show the conversation list and the open
  /// conversation side by side instead of pushing a separate route.
  bool get _isWide =>
      MediaQuery.of(context).orientation == Orientation.landscape ||
      MediaQuery.sizeOf(context).width >= 640;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeSub = RealtimeService.instance.events.listen(_onRealtimeEvent);
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  /// Refresh the conversation list in place when a realtime chat event arrives,
  /// so new messages/edits appear without leaving the page.
  void _onRealtimeEvent(PushEvent event) {
    switch (event.type) {
      case 'chat.message.created':
      case 'chat.message.updated':
      case 'chat.message.deleted':
      case 'chat.conversation.updated':
      case 'chat.consent.requested':
        _reloadSilently();
        break;
    }
  }

  /// Same as [_load] but without toggling the full-screen spinner, so realtime
  /// refreshes don't flicker the UI.
  Future<void> _reloadSilently() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      final conversations = await _apiService.listConversations(token);
      final requests = await _apiService.listConsentRequests(token);
      if (!mounted) return;
      setState(() {
        _conversations = conversations;
        _requests = requests;
      });
    } catch (_) {
      // Ignore transient failures on background refreshes.
    }
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
    if (_isWide) {
      setState(() => _selectedConversationId = conv.id);
      return;
    }
    // Push on the root navigator so the chat room covers the shell entirely,
    // including the bottom navigation bar on narrow (portrait) screens.
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ConversationPage(conversationId: conv.id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openStartChat() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const StartChatPage()),
    );
    if (mounted) _load();
  }

  Future<void> _openRequests() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const ConsentRequestsPage()),
    );
    if (mounted) _load();
  }

  Future<void> _openDiscover() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const DiscoverGroupsPage()),
    );
    if (mounted) _load();
  }

  /// FAB action: start a new private chat or create a group from one button.
  Future<void> _showCreateMenu() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text('chatStartPrivate'.tr()),
              onTap: () => Navigator.of(ctx).pop('private'),
            ),
            ListTile(
              leading: const Icon(Icons.group_outlined),
              title: Text('chatNewGroup'.tr()),
              onTap: () => Navigator.of(ctx).pop('group'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'private') {
      await _openStartChat();
    } else if (choice == 'group') {
      await _createGroup();
    }
  }

  Future<void> _createGroup() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController();
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatGroupCreate'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(
            labelText: 'groupTitle'.tr(),
            hintText: 'groupTitleHint'.tr(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    try {
      final conv = await _apiService.createGroup(token, title);
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).push(
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
    return Scaffold(
      appBar: AppBar(title: Text('chat'.tr())),
      body: _isWide ? _buildSplitBody() : _buildBody(),
    );
  }

  /// Wide (landscape) layout: conversation list on the left, the open
  /// conversation on the right.
  Widget _buildSplitBody() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 340,
          child: _buildBody(),
        ),
        VerticalDivider(width: 1, thickness: 1),
        Expanded(
          child: _selectedConversationId == null
              ? _buildEmptyPane()
              : ConversationPage(
                  key: ValueKey(_selectedConversationId),
                  conversationId: _selectedConversationId!,
                  onBack: () {
                    setState(() => _selectedConversationId = null);
                    _reloadSilently();
                  },
                ),
        ),
      ],
    );
  }

  /// Placeholder shown in the detail pane before a conversation is selected.
  Widget _buildEmptyPane() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text('chatSelectConversation'.tr()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    // The conversation list (selection area) is wrapped in a Stack so the
    // "new chat / group" button floats at its bottom-right while the accept
    // invitations and discover actions sit above the list.
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              if (!_isLoading && _error == null) _buildQuickActions(),
              Expanded(child: _buildListArea()),
            ],
          ),
        ),
        if (!_isLoading && _error == null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              heroTag: 'chatNewFab',
              onPressed: _showCreateMenu,
              tooltip: 'chatNew'.tr(),
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }

  /// Accept invitations + discover groups, placed above the conversation list.
  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openRequests,
              icon: const Icon(Icons.person_add_alt_outlined, size: 18),
              label: Stack(
                clipBehavior: Clip.none,
                children: [
                  Text('chatRequests'.tr()),
                  if (_requests.isNotEmpty)
                    Positioned(
                      right: -10,
                      top: -8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.error,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                        child: Text(
                          '${_requests.length}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _openDiscover,
              icon: const Icon(Icons.explore_outlined, size: 18),
              label: Text('chatGroupDiscover'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListArea() {
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
    if (_conversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text('chatEmpty'.tr()),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: _openStartChat,
              icon: const Icon(Icons.add),
              label: Text('chatStartPrivate'.tr()),
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
    final last = conversation.lastMessage;
    final time = last != null ? _formatTime(last.createdAt) : '';
    final preview = _buildPreview(context, last);

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

  Widget _buildPreview(BuildContext context, ChatMessage? last) {
    final theme = Theme.of(context);
    if (last == null) return const SizedBox.shrink();
    String text;
    if (last.isDeleted) {
      text = 'messageDeleted'.tr();
    } else if (last.isSystem) {
      final name = last.displayName.isEmpty
          ? 'chatGroupSomeone'.tr()
          : last.displayName;
      switch (last.kind) {
        case 'system.join':
          text = 'chatGroupJoinedGroup'.tr(args: [name]);
          break;
        case 'system.leave':
          text = 'chatGroupLeftGroup'.tr(args: [name]);
          break;
        case 'system.mute':
          text = 'chatGroupMemberMuted'.tr(args: [name]);
          break;
        case 'system.unmute':
          text = 'chatGroupMemberUnmuted'.tr(args: [name]);
          break;
        case 'system.mute.all':
          text = 'chatGroupMutedAll'.tr();
          break;
        case 'system.unmute.all':
          text = 'chatGroupUnmutedAll'.tr();
          break;
        default:
          text = last.displayContent;
      }
    } else if (conversation.isGroup && last.displayName.isNotEmpty) {
      text = '${last.displayName}: ${last.displayContent}';
    } else {
      text = last.displayContent;
    }
    if (text.isEmpty && conversation.encrypted) {
      text = 'e2eeUndecryptable'.tr();
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
