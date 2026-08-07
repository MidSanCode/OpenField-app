import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/chat_member.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/chat_local_db.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/chat/start_chat_page.dart';
import 'package:openfield/widgets/attachment_view.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/verified_badge.dart';

class ConversationPage extends StatefulWidget {
  final int conversationId;

  /// When set, the page is embedded in a split view (landscape chat page) and
  /// this callback is invoked instead of popping the navigator.
  final VoidCallback? onBack;

  const ConversationPage({super.key, required this.conversationId, this.onBack});

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
  StreamSubscription<PushEvent>? _realtimeSub;
  final Map<int, Timer> _typingTimers = {};
  String? _typingUserId;
  Timer? _typingSendTimer;

  @override
  void initState() {
    super.initState();
    _myUserId = Provider.of<AuthService>(context, listen: false).user?.id ?? 0;
    _load();
    _realtimeSub = RealtimeService.instance.events.listen(_onRealtimeEvent);
    _scrollController.addListener(_onScroll);
  }

  /// Triggers loading of older messages when the user scrolls near the top.
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.offset <= 120) {
      _loadOlder();
    }
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _typingSendTimer?.cancel();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Handles realtime push events for this conversation.
  void _onRealtimeEvent(PushEvent event) {
    if (event.conversationId != widget.conversationId) return;
    if (!mounted) return;
    switch (event.type) {
      case 'chat.message.created':
        final msg = ChatMessage.fromJson(event.data);
        final exists = _messages.any((m) => m.id == msg.id || m.clientId == msg.clientId);
        if (exists) return;
        // Race guard: this is our own optimistic message echoed back over WS
        // before the HTTP response resolved it. Match by content + sender +
        // near-identical timestamp and resolve it in place.
        final pending = _messages
            .where((m) =>
                m.id <= 0 &&
                m.isPending &&
                m.senderId == msg.senderId &&
                m.content == msg.content &&
                m.createdAt.difference(msg.createdAt).abs().inSeconds <= 10)
            .firstOrNull;
        if (pending != null) {
          setState(() => _messages = _replaceByClientId(pending.clientId, msg));
          ChatLocalDb.instance.upsertMessage(msg);
          return;
        }
        setState(() => _messages = _sorted([..._messages, msg]));
        ChatLocalDb.instance.upsertMessage(msg);
        _scrollToBottom();
        break;
      case 'chat.message.updated':
        final msg = ChatMessage.fromJson(event.data);
        setState(() {
          _messages = _messages.map((m) => m.id == msg.id ? msg : m).toList();
        });
        ChatLocalDb.instance.upsertMessage(msg);
        break;
      case 'chat.message.deleted':
        final msg = ChatMessage.fromJson(event.data);
        ChatMessage? tombstone;
        setState(() {
          _messages = _messages.map((m) {
            if (m.id != msg.id) return m;
            final deleted = ChatMessage(
              id: m.id,
              conversationId: m.conversationId,
              senderId: m.senderId,
              content: m.content,
              replyToId: m.replyToId,
              replyToName: m.replyToName,
              replyToContent: m.replyToContent,
              editedAt: m.editedAt,
              deletedAt: msg.deletedAt ?? DateTime.now(),
              createdAt: m.createdAt,
              senderName: m.senderName,
              senderAvatar: m.senderAvatar,
              senderVerified: m.senderVerified,
              attachments: m.attachments,
              clientId: m.clientId,
              status: m.status,
            );
            tombstone = deleted;
            return deleted;
          }).toList();
        });
        final t = tombstone;
        if (t != null) {
          ChatLocalDb.instance.upsertMessage(t);
        }
        break;
      case 'chat.typing':
        final userId = event.userId;
        if (userId == null || userId == _myUserId) break;
        final existing = _typingTimers.remove(userId);
        existing?.cancel();
        setState(() => _typingUserId = userId.toString());
        _typingTimers[userId] = Timer(const Duration(seconds: 4), () {
          _typingTimers.remove(userId);
          if (mounted) setState(() => _typingUserId = null);
        });
        break;
    }
  }

  /// Debounced sender-side signal so we don't spam the server on every keystroke.
  void _onTypingChanged(String _) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    _typingSendTimer?.cancel();
    _typingSendTimer = Timer(const Duration(milliseconds: 800), () {
      _apiService.sendTyping(token, widget.conversationId).catchError((_) {});
    });
  }

  /// Resolves a typing user's display name from known members, falling back to
  /// the member id so the indicator stays useful even before members load.
  String _typingUserName(String userId) {
    final member = _members.where((m) => m.userId.toString() == userId).firstOrNull;
    if (member != null && member.displayName.isNotEmpty) {
      return member.displayName;
    }
    return 'typingSomeone'.tr();
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

    // Offline-first: render cached messages immediately if present.
    final cached = await ChatLocalDb.instance.loadMessages(widget.conversationId, limit: 200);
    // A message left in "sending" from a previous session can never complete;
    // surface it as failed so the user can retry.
    final restored = cached.map((m) {
      if (m.status == MessageStatus.sending && m.id <= 0) {
        return ChatMessage(
          id: m.id,
          conversationId: m.conversationId,
          senderId: m.senderId,
          content: m.content,
          replyToId: m.replyToId,
          editedAt: m.editedAt,
          deletedAt: m.deletedAt,
          createdAt: m.createdAt,
          senderName: m.senderName,
          senderAvatar: m.senderAvatar,
          senderVerified: m.senderVerified,
          clientId: m.clientId,
          status: MessageStatus.failed,
        );
      }
      return m;
    }).toList();
    if (restored.isNotEmpty && mounted) {
      setState(() {
        _messages = restored;
        _isLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }

    try {
      final detail = await _apiService.getConversation(token, widget.conversationId);
      final messages = await _apiService.listMessages(token, widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = detail.conversation;
        _members = detail.members;
        _myMembership = detail.myMembership;
        _messages = _mergeMessages(_messages, messages);
        _isLoading = false;
        _hasOlder = messages.length >= 50;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
      // Cache the merged result so the next open is instant.
      await ChatLocalDb.instance.replaceConversation(
          widget.conversationId, _messages);
      if (messages.isNotEmpty) {
        await _apiService.markConversationRead(
          token,
          widget.conversationId,
          messages.last.id,
        );
      }
    } catch (e) {
      // Network failed: keep showing cached messages; only surface the error
      // when there is nothing cached to show.
      if (cached.isEmpty && mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Merges cached and server messages by id, keeping them sorted oldest first.
  List<ChatMessage> _mergeMessages(List<ChatMessage> a, List<ChatMessage> b) {
    final byId = <int, ChatMessage>{};
    for (final m in [...a, ...b]) {
      if (m.id > 0) byId[m.id] = m;
    }
    final merged = byId.values.toList();
    // Preserve any local-only (pending/failed) messages from the UI list.
    final local = [...a, ...b].where((m) => m.id <= 0).toList();
    merged.addAll(local);
    return _sorted(merged);
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || !_hasOlder || _messages.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _loadingOlder = true);
    final before = _messages.first.id;

    // Local first: older messages already cached render without the network.
    final older = await ChatLocalDb.instance.loadMessages(
      widget.conversationId,
      beforeId: before,
      limit: 50,
    );
    if (older.length >= 50) {
      if (!mounted) return;
      setState(() {
        _hasOlder = true;
        _messages = [...older, ..._messages];
        _loadingOlder = false;
      });
      return;
    }

    try {
      final serverOlder =
          await _apiService.listMessages(token, widget.conversationId, before: before);
      if (!mounted) return;
      // Merge local + server so nothing cached is lost when the cache is small.
      final merged = _mergeMessages(older, serverOlder);
      setState(() {
        _hasOlder = serverOlder.length >= 50;
        _messages = [...merged, ..._messages];
        _loadingOlder = false;
      });
      await ChatLocalDb.instance.appendMessages(widget.conversationId, merged);
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

    // Optimistic send: render the message immediately with a local id +
    // timestamp, then resolve with the server-confirmed message.
    final local = ChatMessage(
      id: -DateTime.now().millisecondsSinceEpoch,
      conversationId: widget.conversationId,
      senderId: _myUserId,
      content: content,
      replyToId: replyToId,
      createdAt: DateTime.now(),
      senderName: authService.user?.nickname ?? authService.username,
      senderAvatar: authService.user?.avatarUrl ?? authService.avatarUrl,
      clientId: generateClientId(),
      status: MessageStatus.sending,
    );
    setState(() => _messages = _sorted([..._messages, local]));
    _scrollToBottom();
    _dispatchSend(local, token);
  }

  /// Sends (or resends) a message, updating the optimistic bubble in place.
  Future<void> _dispatchSend(ChatMessage local, String token) async {
    _markStatus(local.clientId, MessageStatus.sending);
    try {
      final msg = await _apiService.sendChatMessage(
        token,
        widget.conversationId,
        local.content,
        replyToId: local.replyToId,
      );
      if (!mounted) return;
      setState(() {
        _messages = _replaceByClientId(local.clientId, msg);
      });
      ChatLocalDb.instance.upsertMessage(msg);
      await _apiService.markConversationRead(token, widget.conversationId, msg.id);
    } catch (e) {
      if (!mounted) return;
      _markStatus(local.clientId, MessageStatus.failed);
      _scrollToBottom();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _markStatus(String clientId, MessageStatus status) {
    if (!mounted) return;
    setState(() {
      _messages = _messages.map((m) {
        if (m.clientId != clientId) return m;
        return ChatMessage(
          id: m.id,
          conversationId: m.conversationId,
          senderId: m.senderId,
          content: m.content,
          replyToId: m.replyToId,
          editedAt: m.editedAt,
          deletedAt: m.deletedAt,
          createdAt: m.createdAt,
          senderName: m.senderName,
          senderAvatar: m.senderAvatar,
          senderVerified: m.senderVerified,
          clientId: m.clientId,
          status: status,
        );
      }).toList();
    });
  }

  List<ChatMessage> _replaceByClientId(String clientId, ChatMessage replacement) {
    final resolved = _messages.where((m) => m.clientId != clientId).toList();
    return _sorted([...resolved, replacement]);
  }

  /// Sorts messages newest-first by timestamp, falling back to id for ties.
  List<ChatMessage> _sorted(List<ChatMessage> msgs) {
    final sorted = [...msgs]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted.reversed.toList();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickAndSendAttachment() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final result = await FilePicker.platform.pickFiles();
    final file = result?.files.single;
    if (file == null || file.path == null) return;
    final local = ChatMessage(
      id: -DateTime.now().millisecondsSinceEpoch,
      conversationId: widget.conversationId,
      senderId: _myUserId,
      content: '',
      createdAt: DateTime.now(),
      senderName: authService.user?.nickname ?? authService.username,
      senderAvatar: authService.user?.avatarUrl ?? authService.avatarUrl,
      clientId: generateClientId(),
      status: MessageStatus.sending,
    );
    setState(() => _messages = _sorted([..._messages, local]));
    _scrollToBottom();
    try {
      final attachment = await _apiService.uploadAttachmentSmart(file.path!, token);
      final msg = await _apiService.sendChatMessage(
        token,
        widget.conversationId,
        '',
        attachmentIds: [attachment.id],
      );
      if (!mounted) return;
      setState(() {
        _messages = _replaceByClientId(local.clientId, msg);
      });
      ChatLocalDb.instance.upsertMessage(msg);
      _scrollToBottom();
      await _apiService.markConversationRead(token, widget.conversationId, msg.id);
    } catch (e) {
      if (!mounted) return;
      _markStatus(local.clientId, MessageStatus.failed);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _onMessageLongPress(ChatMessage message) async {
    final isMine = message.senderId == _myUserId;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.isFailed && token != null) ...[
              ListTile(
                leading: Icon(Icons.refresh, color: Theme.of(ctx).colorScheme.primary),
                title: Text('chatResend'.tr()),
                onTap: () => Navigator.of(ctx).pop('resend'),
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.reply),
              title: Text('chatQuoteReply'.tr()),
              onTap: () => Navigator.of(ctx).pop('reply'),
            ),
            if (isMine && !message.isDeleted) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('edit'.tr()),
                onTap: () => Navigator.of(ctx).pop('edit'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
                title: Text('delete'.tr(), style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ],
          ],
        ),
      ),
    );
    if (action == null) return;
    switch (action) {
      case 'resend':
        if (token != null) {
          _dispatchSend(message, token);
        }
        break;
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: message.content);
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('edit'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 5000,
          decoration: InputDecoration(hintText: 'message'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('save'.tr()),
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
      ChatLocalDb.instance.upsertMessage(updated);
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
      final deleted = _messages.firstWhere(
        (m) => m.id == message.id,
        orElse: () => message,
      );
      ChatLocalDb.instance.upsertMessage(deleted);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _editNote() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: _myMembership?.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatNote'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: 'chatNote'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('save'.tr()),
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: _myMembership?.groupNickname ?? '');
    final nickname = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatGroupNickname'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: InputDecoration(hintText: 'chatGroupNickname'.tr()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('save'.tr()),
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
                        'chatGroupMembers'.tr(),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (canManage)
                        IconButton(
                          icon: const Icon(Icons.person_add_alt_outlined),
                          tooltip: 'chatGroupInvite'.tr(),
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
                        subtitle: Text(_roleLabel(m.role)),
                        trailing: canManage && m.role != 'owner'
                            ? IconButton(
                                icon: Icon(Icons.person_remove_outlined,
                                    color: Theme.of(context).colorScheme.error),
                                tooltip: 'delete'.tr(),
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

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'chatOwnerRole'.tr();
      case 'admin':
        return 'chatAdminRole'.tr();
      default:
        return 'normalUser'.tr();
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
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatGroupLeaveConfirm'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('confirm'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _apiService.leaveGroup(token, widget.conversationId);
      if (!mounted) return;
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteConversation() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final isGroup = _conversation?.isGroup ?? false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isGroup ? 'chatGroupDeleteConfirm'.tr() : 'chatDeleteConfirm'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('cancel'.tr())),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _apiService.deleteConversation(token, widget.conversationId);
      ChatLocalDb.instance.deleteConversation(widget.conversationId);
      if (!mounted) return;
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final conv = _conversation;
    final isGroup = conv?.isGroup ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'back'.tr(),
                onPressed: widget.onBack,
              )
            : null,
        title: Text(conv?.title ?? ''),
        actions: [
          if (isGroup)
            IconButton(
              icon: const Icon(Icons.group_outlined),
              tooltip: 'chatGroupMembers'.tr(),
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
                case 'delete':
                  _deleteConversation();
                  break;
              }
            },
            itemBuilder: (context) => [
              if (!isGroup)
                PopupMenuItem(value: 'note', child: Text('chatNote'.tr())),
              if (isGroup)
                PopupMenuItem(value: 'nickname', child: Text('chatGroupNickname'.tr())),
              if (isGroup && _myMembership?.role != 'owner')
                PopupMenuItem(
                  value: 'leave',
                  child: Text(
                    'chatGroupLeave'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              if (!isGroup || _myMembership?.role == 'owner')
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    isGroup ? 'chatGroupDelete'.tr() : 'chatDelete'.tr(),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
            ],
          ),
        ],
      ),
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

    final authToken =
        Provider.of<AuthService>(context, listen: false).accessToken;

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
                            child: Text('chatLoadEarlier'.tr()),
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
                onRetry: (message.isFailed && authToken != null)
                    ? () => _dispatchSend(message, authToken)
                    : null,
              );
            },
          ),
        ),
        if (_replyToId != null)
          _ReplyBar(
            message: _messages.where((m) => m.id == _replyToId).firstOrNull,
            onCancel: () => setState(() => _replyToId = null),
          ),
        if (_typingUserId != null)
          _TypingIndicator(
            name: _typingUserName(_typingUserId!),
            verified: _members
                    .where((m) => m.userId.toString() == _typingUserId)
                    .firstOrNull
                    ?.isVerified ??
                false,
          ),
        _buildInputBar(),
      ],
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: _pickAndSendAttachment,
              icon: const Icon(Icons.attach_file),
              tooltip: 'attachFile'.tr(),
            ),
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onChanged: _onTypingChanged,
                decoration: InputDecoration(
                  hintText: 'message'.tr(),
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
              tooltip: 'send'.tr(),
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
  final VoidCallback? onRetry;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.showSenderName,
    required this.onLongPress,
    this.senderAvatar,
    this.replyPreview,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyPreviewText = _replyPreviewText();

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
                        if (replyPreviewText != null) ...[
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surface.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              replyPreviewText,
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
                            'messageDeleted'.tr(),
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
                        if (message.attachments.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          AttachmentView(attachments: message.attachments),
                        ],
                        if (message.isEdited)
                          Text(
                            'chatEdited'.tr(),
                            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.createdAt),
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                        ),
                        if (isMine && !message.isDeleted) ...[
                          const SizedBox(width: 4),
                          _SendStatusIndicator(message: message, onRetry: onRetry),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 8),
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
          ],
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Quote preview: prefers the in-thread message (fresh edits/deletes), then
  /// falls back to the server-provided [ChatMessage.replyToName]/replyToContent
  /// so quotes still render when the referenced message isn't loaded.
  String? _replyPreviewText() {
    final rp = replyPreview;
    if (rp != null && !rp.isDeleted && rp.content.isNotEmpty) {
      return '${rp.displayName}: ${rp.content}';
    }
    if (message.replyToName != null && message.replyToName!.isNotEmpty) {
      final content = message.replyToContent ?? '';
      if (content.isEmpty) return null;
      return '${message.replyToName}: $content';
    }
    return null;
  }
}

/// Animated "someone is typing…" pill shown above the input bar.
class _TypingIndicator extends StatelessWidget {
  final String name;
  final bool verified;

  const _TypingIndicator({required this.name, this.verified = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingDots(),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (verified) ...[
            const SizedBox(width: 4),
            Icon(Icons.verified, size: 14, color: theme.colorScheme.primary),
          ],
          Text(
            'typing'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Three bouncing dots used by the typing indicator.
class _TypingDots extends StatefulWidget {
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return SizedBox(
      width: 22,
      height: 10,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (var i = 0; i < 3; i++)
                AnimatedOpacity(
                  opacity: 0.2 + (0.8 * ((_animation.value + (i * 0.33)) % 1.0)),
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Small inline indicator for local send state: a spinner while sending, a
/// retry button when the send failed.
class _SendStatusIndicator extends StatelessWidget {
  final ChatMessage message;
  final VoidCallback? onRetry;

  const _SendStatusIndicator({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (message.isPending) {
      return const SizedBox(
        width: 12,
        height: 12,
        child: CircularProgressIndicator(strokeWidth: 1.6),
      );
    }
    if (message.isFailed) {
      return Tooltip(
        message: 'chatResend'.tr(),
        child: InkWell(
          onTap: onRetry,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Icon(
              Icons.error_outline,
              size: 13,
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    return Icon(
      Icons.check,
      size: 13,
      color: theme.colorScheme.onSurfaceVariant,
    );
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
                  ? 'chatReplying'.tr()
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
