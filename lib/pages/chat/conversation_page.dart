import 'dart:async';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/chat_member.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/models/conversation.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/chat_cache_store.dart';
import 'package:openfield/data/services/chat_local_db.dart';
import 'package:openfield/data/services/e2ee_service.dart';
import 'package:openfield/data/services/encrypted_chat_db.dart';
import 'package:openfield/data/services/realtime_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/chat/group_settings_page.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/widgets/attachment_view.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/verified_badge.dart';

class ConversationPage extends StatefulWidget {
  final int conversationId;

  /// Known encryption state of the conversation, passed by the caller so the
  /// page can load the cache from the correct store before the detail fetch
  /// returns. When null it is resolved after the first load.
  final bool? encrypted;

  /// When set, the page is embedded in a split view (landscape chat page) and
  /// this callback is invoked instead of popping the navigator.
  final VoidCallback? onBack;

  const ConversationPage({
    super.key,
    required this.conversationId,
    this.encrypted,
    this.onBack,
  });

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
  bool _e2eeKeysReady = false;

  /// Confirmed encryption state of this conversation (resolved from the server
  /// detail). Drives which cache store messages are read from and written to.
  bool _isEncryptedConv = false;

  /// The cache store for a conversation with the given encryption state:
  /// MLS-encrypted conversations are kept in the dedicated encrypted database,
  /// everything else in the plaintext database.
  ChatCacheStore _storeFor(bool encrypted) =>
      encrypted ? EncryptedChatDb.instance : ChatLocalDb.instance;

  /// The cache store for this conversation.
  ChatCacheStore get _store => _storeFor(_isEncryptedConv);

  /// Mention autocomplete state. When the caret trails a bare `@token`, the
  /// matching members are listed above the input bar so the user can pick one
  /// (or @everyone, when privileged) to insert a mention.
  List<ChatMember> _mentionCandidates = [];
  bool _mentionShowEveryone = false;
  int _mentionTokenStart = 0;

  @override
  void initState() {
    super.initState();
    _isEncryptedConv = widget.encrypted ?? false;
    _myUserId = Provider.of<AuthService>(context, listen: false).user?.id ?? 0;
    if (_myUserId == 0) {
      _loadMyUserId();
    }
    _load();
    _realtimeSub = RealtimeService.instance.events.listen(_onRealtimeEvent);
    _scrollController.addListener(_onScroll);
  }

  /// After a page refresh the current profile may not be loaded yet, leaving
  /// [_myUserId] at 0 (which would mis-align every bubble to the left). Fetch
  /// the profile so own messages render on the right.
  Future<void> _loadMyUserId() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final user = await auth.fetchCurrentUser();
    if (mounted && user != null) {
      setState(() => _myUserId = user.id);
    }
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
        final msg = _decryptMessage(ChatMessage.fromJson(event.data));
        // Dedupe by server id only. clientId is only ever set on locally
        // generated optimistic messages (never on server-pushed payloads), so
        // comparing against it would match every cached server message whose
        // clientId defaulted to '' and silently swallow the new event.
        final exists = _messages.any((m) => m.id == msg.id);
        if (exists) return;
        // Race guard: this is our own optimistic message echoed back over WS
        // before the HTTP response resolved it. Match by sender + near-identical
        // timestamp + (for encrypted conversations) decrypted plaintext.
        final pending = _messages
            .where((m) =>
                m.id <= 0 &&
                m.isPending &&
                m.senderId == msg.senderId &&
                _contentMatches(m, msg) &&
                m.createdAt.difference(msg.createdAt).abs().inSeconds <= 10)
            .firstOrNull;
        if (pending != null) {
          setState(() => _messages = _replaceByClientId(pending.clientId, msg));
          _store.upsertMessage(msg);
          return;
        }
        setState(() => _messages = _sorted([..._messages, msg]));
        _store.upsertMessage(msg);
        _scrollToBottom();
        // If the new push arrived as an undecrypted envelope, our cached group
        // key for this version may be stale (e.g. the sender rotated keys
        // while we were offline). Pull the latest envelopes and re-decrypt
        // everything so the bubble renders instead of staying blank.
        if (_isUndecryptedEnvelope(msg)) {
          unawaited(_syncE2EEAndRedecrypt());
        }
        break;
      case 'chat.message.updated':
        final msg = _decryptMessage(ChatMessage.fromJson(event.data));
        setState(() {
          _messages = _messages.map((m) => m.id == msg.id ? msg : m).toList();
        });
        _store.upsertMessage(msg);
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
              decryptedContent: m.decryptedContent,
              kind: m.kind,
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
          _store.upsertMessage(t);
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
      case 'chat.conversation.updated':
        _refreshConversation();
        break;
      case 'chat.e2ee.keys.updated':
        _syncE2EEAndRedecrypt();
        break;
    }
  }

  /// Debounced sender-side signal so we don't spam the server on every keystroke.
  void _onTypingChanged(String text) {
    _updateMentionSuggestions(text);
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    _typingSendTimer?.cancel();
    _typingSendTimer = Timer(const Duration(milliseconds: 800), () {
      _apiService.sendTyping(token, widget.conversationId).catchError((_) {});
    });
  }

  /// Shows member suggestions while the caret trails a bare `@token`.
  void _updateMentionSuggestions(String text) {
    final sel = _inputController.selection;
    if (!sel.isValid || sel.baseOffset != sel.extentOffset) {
      _setMentionCandidates(const [], showEveryone: false);
      return;
    }
    final caret = sel.baseOffset;
    if (caret <= 0 || text.length < caret) {
      _setMentionCandidates(const [], showEveryone: false);
      return;
    }
    final before = text.substring(0, caret);
    if (before.contains('\n')) {
      _setMentionCandidates(const [], showEveryone: false);
      return;
    }
    final lastSpace = before.lastIndexOf(' ');
    final tokenStart = lastSpace < 0 ? 0 : lastSpace + 1;
    final token = before.substring(tokenStart);
    if (!token.startsWith('@') || token.length > 32) {
      _setMentionCandidates(const [], showEveryone: false);
      return;
    }
    final query = token.substring(1).toLowerCase();
    final canEveryone = _myMembership?.role == 'owner' ||
        _myMembership?.role == 'admin';
    final matches = _members
        .where((m) {
          if (m.userId == _myUserId) return false;
          final name =
              m.groupNickname.isNotEmpty ? m.groupNickname : m.displayName;
          return name.toLowerCase().contains(query) ||
              (m.username ?? '').toLowerCase().contains(query);
        })
        .take(8)
        .toList();
    if (mounted) {
      setState(() {
        _mentionTokenStart = tokenStart;
        _mentionCandidates = matches;
        _mentionShowEveryone =
            canEveryone && 'everyone'.contains(query);
      });
    }
  }

  void _setMentionCandidates(List<ChatMember> c, {bool showEveryone = false}) {
    if (!mounted) return;
    if (c.isEmpty &&
        showEveryone == false &&
        _mentionCandidates.isEmpty &&
        !_mentionShowEveryone) {
      return;
    }
    setState(() {
      _mentionCandidates = c;
      _mentionShowEveryone = showEveryone;
    });
  }

  void _insertMention(ChatMember member) {
    final name =
        member.groupNickname.isNotEmpty ? member.groupNickname : member.displayName;
    _replaceMentionToken('@$name ');
  }

  void _insertEveryoneMention() {
    _replaceMentionToken('@everyone ');
  }

  /// Replaces the currently-open `@token` (from [_mentionTokenStart] to the
  /// caret) with the chosen mention, then closes the suggestion list.
  void _replaceMentionToken(String replacement) {
    final text = _inputController.text;
    final sel = _inputController.selection;
    if (sel.isValid && sel.baseOffset >= _mentionTokenStart) {
      final end = sel.baseOffset > text.length ? text.length : sel.baseOffset;
      final newText = text.replaceRange(_mentionTokenStart, end, replacement);
      _inputController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: (_mentionTokenStart + replacement.length).clamp(0, newText.length)),
      );
    } else {
      _inputController.text = '$text$replacement';
      _inputController.selection =
          TextSelection.collapsed(offset: _inputController.text.length);
    }
    setState(() {
      _mentionCandidates = [];
      _mentionShowEveryone = false;
    });
    _scrollToBottom();
  }

  /// Collects the user ids referenced by `@name` tokens in the outgoing text.
  /// `@everyone` maps to the sentinel [ChatMessage.everyoneSentinel]; the
  /// server strips it again when the sender lacks owner/admin privileges.
  List<int> _extractMentions(String text) {
    final ids = <int>{};
    final canEveryone = _myMembership?.role == 'owner' ||
        _myMembership?.role == 'admin';
    for (final token in text.split(RegExp(r'\s+'))) {
      if (!token.startsWith('@') || token.length < 2) continue;
      final name = token.substring(1);
      if (canEveryone && name.toLowerCase() == 'everyone') {
        ids.add(ChatMessage.everyoneSentinel);
        continue;
      }
      ChatMember? matched;
      for (final m in _members) {
        final dn = m.groupNickname.isNotEmpty ? m.groupNickname : m.displayName;
        if (dn == name || m.username == name) {
          matched = m;
          break;
        }
      }
      if (matched != null && matched.userId != _myUserId) {
        ids.add(matched.userId);
      }
    }
    return ids.toList();
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

    // Offline-first: render cached messages immediately if present. MLS-
    // encrypted conversations are read from the dedicated encrypted store, so
    // decrypted plaintext never touches the plaintext cache.
    final cached =
        await _storeFor(_isEncryptedConv).loadMessages(widget.conversationId, limit: 200);
    // A message left in "sending" from a previous session can never complete;
    // surface it as failed so the user can retry.
    final restored = cached.map((m) {
      if (m.status == MessageStatus.sending && m.id <= 0) {
        return m.resolve(status: MessageStatus.failed);
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
      // The membership record is the server-authoritative identity of the
      // current user in this conversation; prefer it over the local profile.
      if (detail.myMembership != null) {
        _myUserId = detail.myMembership!.userId;
      }
      final encrypted = detail.conversation.encrypted;
      if (encrypted != _isEncryptedConv) {
        // Caller did not know the encryption state up front; load the cache
        // from the correct store now (keeps the offline-first render honest).
        _isEncryptedConv = encrypted;
        final correctCache =
            await _storeFor(encrypted).loadMessages(widget.conversationId, limit: 200);
        setState(() {
          _messages = correctCache
              .map((m) => m.status == MessageStatus.sending && m.id <= 0
                  ? m.resolve(status: MessageStatus.failed)
                  : m)
              .toList();
        });
      }
      if (encrypted) {
        // Writes must never land in the plaintext cache; scrub any legacy copy
        // left by a pre-encryption build so plaintext does not linger on disk.
        _isEncryptedConv = true;
        unawaited(ChatLocalDb.instance.deleteConversation(widget.conversationId));
      }
      var display = _mergeMessages(_messages, messages);
      if (encrypted) {
        await _ensureE2EE();
        display = _decryptBatch(display);
      }
      if (!mounted) return;
      setState(() {
        _conversation = detail.conversation;
        _members = detail.members;
        _myMembership = detail.myMembership;
        _messages = display;
        _isLoading = false;
        _hasOlder = messages.length >= 50;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
      // Cache the merged result so the next open is instant.
      await _storeFor(encrypted)
          .replaceConversation(widget.conversationId, _messages);
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
    final older = await _store.loadMessages(
      widget.conversationId,
      beforeId: before,
      limit: 50,
    );
    if (older.length >= 50) {
      if (!mounted) return;
      setState(() {
        _hasOlder = true;
        _messages = [..._decryptBatch(older), ..._messages];
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
        _messages = [..._decryptBatch(merged), ..._messages];
        _loadingOlder = false;
      });
      await _store.appendMessages(widget.conversationId, merged);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingOlder = false);
    }
  }

  /// Whether the current user is blocked from sending because of a personal
  /// mute or an active group-wide mute (owner/admin are exempt from the latter).
  bool get _isMuted {
    final membership = _myMembership;
    if (membership == null) return false;
    if (membership.isMuted) return true;
    final conv = _conversation;
    if (conv != null &&
        conv.isGroupMuted &&
        membership.role != 'owner' &&
        membership.role != 'admin') {
      return true;
    }
    return false;
  }

  DateTime? get _muteUntil {
    final membership = _myMembership;
    if (membership != null && membership.isMuted) return membership.mutedUntil;
    final conv = _conversation;
    if (conv != null && conv.isGroupMuted) return conv.muteAllUntil;
    return null;
  }

  bool get _canSend => _myMembership != null && !_isMuted;

  String _muteBannerText() {
    final until = _muteUntil;
    if (until == null) return 'chatYouAreMuted'.tr();
    final t = until.toLocal();
    final formatted = '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return 'chatYouAreMutedUntil'.tr(args: [formatted]);
  }

  void _showMutedSnackBar() {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(_muteBannerText())));
  }

  /// Re-fetches the conversation detail (settings + members + my membership)
  /// without disturbing the loaded messages. Used after settings/role/mute
  /// changes and on 'conversation.updated' push events.
  Future<void> _refreshConversation() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      final detail = await _apiService.getConversation(token, widget.conversationId);
      if (!mounted) return;
      if (detail.myMembership != null) {
        _myUserId = detail.myMembership!.userId;
      }
      setState(() {
        _conversation = detail.conversation;
        _members = detail.members;
        _myMembership = detail.myMembership;
      });
      if (detail.conversation.encrypted) {
        await _ensureE2EE();
      }
    } catch (_) {}
  }

  bool get _isEncrypted => _conversation?.encrypted ?? false;

  /// Whether the input bar should block sending until the group key has been
  /// synced for an encrypted conversation.
  bool get _e2eeBlocked => _isEncrypted && !_e2eeKeysReady && _myMembership != null;

  /// Loads the identity keypair and, for encrypted conversations, fetches and
  /// decrypts any new group-key envelopes addressed to us.
  Future<void> _ensureE2EE() {
    final inFlight = _e2eeFuture;
    if (inFlight != null) return inFlight;
    final future = _ensureE2EEInternal();
    _e2eeFuture = future;
    future.whenComplete(() => _e2eeFuture = null);
    return future;
  }

  Future<void>? _e2eeFuture;

  Future<void> _ensureE2EEInternal() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await E2eeService.instance.ensureIdentity(_apiService, token);
      if (_isEncrypted && _myUserId != 0) {
        try {
          await E2eeService.instance.syncGroupKeys(
              _apiService, token, widget.conversationId, _myUserId);
        } catch (_) {
          // Offline or a transient error: cached group keys still work.
        }
      }
    } catch (_) {
      // Identity setup failed; keys are unusable.
    }
    if (mounted) {
      setState(() =>
          _e2eeKeysReady = E2eeService.instance.hasGroupKey(widget.conversationId));
    }
  }

  ChatMessage _copyWithDecrypted(ChatMessage m, String plain) {
    return ChatMessage(
      id: m.id,
      conversationId: m.conversationId,
      senderId: m.senderId,
      content: m.content,
      kind: m.kind,
      replyToId: m.replyToId,
      replyToName: m.replyToName,
      replyToContent: m.replyToContent,
      editedAt: m.editedAt,
      deletedAt: m.deletedAt,
      createdAt: m.createdAt,
      senderName: m.senderName,
      senderAvatar: m.senderAvatar,
      senderVerified: m.senderVerified,
      attachments: m.attachments,
      clientId: m.clientId,
      status: m.status,
      decryptedContent: plain,
    );
  }

  /// Decrypts a single message when the conversation is encrypted. System
  /// messages and already-decrypted messages pass through unchanged.
  ChatMessage _decryptMessage(ChatMessage m) {
    if (!_isEncrypted || m.isSystem || m.decryptedContent != null) return m;
    final plain =
        E2eeService.instance.decryptMessage(widget.conversationId, m.senderId, m.content);
    if (plain == null) return m;
    return _copyWithDecrypted(m, plain);
  }

  /// Returns true when [m] looks like an E2EE envelope that could not be
  /// decrypted because the matching group key (or chain state) is missing.
  bool _isUndecryptedEnvelope(ChatMessage m) {
    if (!_isEncrypted) return false;
    if (m.isSystem) return false;
    if (m.decryptedContent != null) return false;
    return m.isEnvelope;
  }

  List<ChatMessage> _decryptBatch(List<ChatMessage> msgs) =>
      msgs.map(_decryptMessage).toList();

  /// Re-syncs group keys and re-decrypts every message (used after a key
  /// rotation event or a failed decrypt caused by a missed key sync).
  Future<void> _syncE2EEAndRedecrypt() async {
    await _ensureE2EE();
    if (!mounted) return;
    setState(() {
      _messages = _decryptBatch(_messages);
    });
  }

  /// Whether a pending local message and an echoed server message refer to the
  /// same logical message. For encrypted conversations the content differs
  /// (fresh ciphertext per send), so compare the decrypted plaintext instead.
  bool _contentMatches(ChatMessage pending, ChatMessage echo) {
    if (pending.content == echo.content) return true;
    if (!_isEncrypted) return false;
    final decrypted = E2eeService.instance
        .decryptMessage(widget.conversationId, echo.senderId, echo.content);
    return decrypted != null && decrypted == pending.decryptedContent;
  }

  /// Encrypts outgoing content for encrypted conversations.
  String _encryptOutgoing(String plaintext) {
    if (!_isEncrypted) return plaintext;
    return E2eeService.instance.encryptMessage(widget.conversationId, _myUserId, plaintext);
  }

  Future<void> _joinGroup() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      final conv = await _apiService.joinGroup(token, widget.conversationId);
      if (!mounted) return;
      setState(() {
        _conversation = conv;
        _myMembership = ChatMember(
          conversationId: conv.id,
          userId: _myUserId,
          role: 'member',
          note: '',
          groupNickname: '',
          status: 'active',
          addedBy: conv.ownerId,
          createdAt: DateTime.now(),
        );
      });
      _refreshConversation();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _send() async {
    if (!_canSend) {
      _showMutedSnackBar();
      return;
    }
    final content = _inputController.text.trim();
    if (content.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;

    // For encrypted conversations the group key must be available before we
    // can encrypt; try a sync first and fall back to a hint when it is not.
    if (_isEncrypted && !_e2eeKeysReady) {
      await _ensureE2EE();
      if (!mounted) return;
      if (!_e2eeKeysReady) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('e2eeKeysPending'.tr())));
        return;
      }
    }

    final replyToId = _replyToId;
    final mentions = _extractMentions(content);
    final cipher = _isEncrypted ? _encryptOutgoing(content) : content;
    setState(() {
      _inputController.clear();
      _replyToId = null;
      _mentionCandidates = [];
      _mentionShowEveryone = false;
    });

    // Optimistic send: render the message immediately with a local id +
    // timestamp, then resolve with the server-confirmed message. For encrypted
    // conversations the bubble shows the plaintext while [content] carries the
    // ciphertext envelope that will be sent.
    final local = ChatMessage(
      id: -DateTime.now().millisecondsSinceEpoch,
      conversationId: widget.conversationId,
      senderId: _myUserId,
      content: cipher,
      decryptedContent: _isEncrypted ? content : null,
      replyToId: replyToId,
      createdAt: DateTime.now(),
      senderName: authService.user?.nickname ?? authService.username,
      senderAvatar: authService.user?.avatarUrl ?? authService.avatarUrl,
      clientId: generateClientId(),
      status: MessageStatus.sending,
      mentions: mentions,
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
        mentions: local.mentions,
      );
      if (!mounted) return;
      setState(() {
        _messages = _replaceByClientId(local.clientId, msg);
      });
      _store.upsertMessage(msg);
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
          kind: m.kind,
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
    if (!_canSend) {
      _showMutedSnackBar();
      return;
    }
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
      _store.upsertMessage(msg);
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
    final controller = TextEditingController(text: message.displayContent);
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
      final payload = _isEncrypted ? _encryptOutgoing(content) : content;
      final updated = await _apiService.editChatMessage(
        token,
        widget.conversationId,
        message.id,
        payload,
      );
      if (!mounted) return;
      final resolved = _isEncrypted ? _decryptMessage(updated) : updated;
      setState(() {
        _messages = _messages.map((m) => m.id == resolved.id ? resolved : m).toList();
      });
      _store.upsertMessage(resolved);
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
            kind: m.kind,
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
      _store.upsertMessage(deleted);
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
                mutedUntil: _myMembership!.mutedUntil,
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
                mutedUntil: _myMembership!.mutedUntil,
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

  Future<void> _openGroupSettings() async {
    final conv = _conversation;
    if (conv == null) return;
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => GroupSettingsPage(conversation: conv),
      ),
    );
    if (mounted) _refreshConversation();
  }

  /// Lets the user pick their per-conversation chat notification preference
  /// ('all' | 'mentions' | 'none'). Server defaults to 'all'.
  Future<void> _changeNotifyLevel() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final current = _myMembership?.notifyLevel ?? 'all';
    final entries = [
      ('all', 'chatNotifyAll'.tr()),
      ('mentions', 'chatNotifyMentions'.tr()),
      ('none', 'chatNotifyNone'.tr()),
    ];
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                'chatNotifyLevel'.tr(),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            for (final entry in entries)
              ListTile(
                leading: Icon(
                  current == entry.$1
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: current == entry.$1
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(entry.$2),
                onTap: () => Navigator.of(ctx).pop(entry.$1),
              ),
          ],
        ),
      ),
    );
    if (choice == null || choice == current || !mounted) return;
    try {
      await _apiService.setNotifyLevel(token, widget.conversationId, choice);
      if (!mounted) return;
      setState(() {
        _myMembership = _myMembership?.copyWith(notifyLevel: choice);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('chatNotifyLevelSaved'.tr())),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
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
      _store.deleteConversation(widget.conversationId);
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
          PopupMenuButton<String>(
            onSelected: (value) {
              switch (value) {
                case 'note':
                  _editNote();
                  break;
                case 'nickname':
                  _editGroupNickname();
                  break;
                case 'settings':
                  _openGroupSettings();
                  break;
                case 'notify':
                  _changeNotifyLevel();
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
              if (isGroup)
                PopupMenuItem(value: 'settings', child: Text('chatGroupSettings'.tr())),
              PopupMenuItem(value: 'notify', child: Text('chatNotifyLevel'.tr())),
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
              if (message.isSystem) {
                return _SystemMessage(message: message);
              }
              final replyTo = message.replyToId != null
                  ? _messages.where((m) => m.id == message.replyToId).firstOrNull
                  : null;
              return _MessageBubble(
                message: message,
                isMine: message.senderId == _myUserId,
                isEncrypted: _isEncrypted,
                isMentioned: message.mentionsMe(_myUserId),
                showSenderName: (_conversation?.isGroup ?? false) && !message.isDeleted,
                senderAvatar: message.senderAvatar,
                senderTitle: _members
                    .where((m) => m.userId == message.senderId)
                    .firstOrNull
                    ?.title ??
                    '',
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
        if (_mentionCandidates.isNotEmpty || _mentionShowEveryone)
          _buildMentionSuggestions(),
        _buildInputArea(),
      ],
    );
  }

  /// Member autocomplete list shown above the input bar while the caret trails
  /// a bare `@token`. Tapping inserts the mention and closes the list.
  Widget _buildMentionSuggestions() {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        children: [
          if (_mentionShowEveryone)
            ListTile(
              dense: true,
              leading: const Icon(Icons.record_voice_over_outlined),
              title: Text(
                '@everyone',
                style: TextStyle(color: theme.colorScheme.primary),
              ),
              subtitle: Text('chatMentionEveryone'.tr()),
              onTap: _insertEveryoneMention,
            ),
          if (_mentionShowEveryone && _mentionCandidates.isNotEmpty)
            const Divider(height: 1),
          for (final member in _mentionCandidates)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 14,
                backgroundImage: (member.avatarUrl != null &&
                        member.avatarUrl!.isNotEmpty)
                    ? NetworkImage(member.avatarUrl!)
                    : null,
                child: (member.avatarUrl == null || member.avatarUrl!.isEmpty)
                    ? Text(member.displayName.isEmpty
                        ? '?'
                        : member.displayName.substring(0, 1).toUpperCase())
                    : null,
              ),
              title: Text(member.groupNickname.isNotEmpty
                  ? member.groupNickname
                  : member.displayName),
              subtitle: member.groupNickname.isNotEmpty
                  ? Text(member.username ?? '')
                  : null,
              onTap: () => _insertMention(member),
            ),
        ],
      ),
    );
  }

  /// Bottom bar: input when the user is an active (unmuted) member, a mute
  /// notice when muted, a join button when the group is open to self-joining,
  /// or a plain notice when the user has no way to participate.
  Widget _buildInputArea() {
    final theme = Theme.of(context);
    final membership = _myMembership;
    if (membership == null) {
      final conv = _conversation;
      if (conv != null && conv.canJoinDirectly) {
        return SafeArea(
          top: false,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _joinGroup,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text('chatJoinGroup'.tr()),
            ),
          ),
        );
      }
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(
            'chatNotMember'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    if (_isMuted) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
          child: Row(
            children: [
              Icon(Icons.block, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _muteBannerText(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_e2eeBlocked) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'e2eeKeysPending'.tr(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _syncE2EEAndRedecrypt(),
                child: Text('retry'.tr()),
              ),
            ],
          ),
        ),
      );
    }
    return _buildInputBar();
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

/// Centered grey pill rendered for server-generated system messages such as
/// "joined the chat", "left the chat", "muted" and group-wide mute notices.
class _SystemMessage extends StatelessWidget {
  final ChatMessage message;

  const _SystemMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _label(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  String _label() {
    final name = message.displayName.isEmpty ? 'chatSomeone'.tr() : message.displayName;
    switch (message.kind) {
      case 'system.join':
        return 'chatJoinedGroup'.tr(args: [name]);
      case 'system.leave':
        return 'chatLeftGroup'.tr(args: [name]);
      case 'system.mute':
        return 'chatMemberMuted'.tr(args: [name]);
      case 'system.unmute':
        return 'chatMemberUnmuted'.tr(args: [name]);
      case 'system.mute.all':
        return 'chatGroupMutedAll'.tr();
      case 'system.unmute.all':
        return 'chatGroupUnmutedAll'.tr();
      default:
        return message.displayContent;
    }
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMine;
  final bool isEncrypted;

  /// True when this message @-mentions the current user (or @everyone). Renders
  /// a subtle highlight so mentions are easy to spot.
  final bool isMentioned;
  final bool showSenderName;
  final String? senderAvatar;
  final String senderTitle;
  final ChatMessage? replyPreview;
  final VoidCallback onLongPress;
  final VoidCallback? onRetry;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isEncrypted,
    required this.isMentioned,
    required this.showSenderName,
    required this.onLongPress,
    this.senderAvatar,
    this.senderTitle = '',
    this.replyPreview,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final replyPreviewText = _replyPreviewText();
    final settings = Provider.of<SettingsService>(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProfilePage(userId: message.senderId),
                ),
              ),
              child: CircleAvatar(
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
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          VerifiedName(
                            name: message.displayName,
                            verified: message.senderVerified,
                            memberLevel: message.senderMemberLevel,
                            memberActive: message.senderMemberActive,
                            nameColor: message.senderNameColor,
                            nameColorTo: message.senderNameColorTo,
                            nameColors: message.senderNameColors,
                            nameGradientDirection: message.senderNameGradientDirection,
                            nameDynamic: message.senderNameDynamic,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                          if (senderTitle.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                senderTitle,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ],
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
                      border: isMentioned
                          ? Border.all(
                              color: theme.colorScheme.tertiary,
                              width: 1.2,
                            )
                          : null,
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
                        else if (isEncrypted)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 4, right: 6),
                                child: Icon(
                                  message.decryptedContent == null
                                      ? Icons.lock_outline
                                      : Icons.lock,
                                  size: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              Flexible(
                                child: message.decryptedContent == null
                                    ? Text(
                                        'e2eeUndecryptable'.tr(),
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          fontStyle: FontStyle.italic,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                    : MarkdownContent(
                                        data: message.displayContent,
                                        padding: EdgeInsets.zero,
                                      ),
                              ),
                            ],
                          )
                        else
                          MarkdownContent(
                            data: message.displayContent,
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
                          _formatTime(settings, message.createdAt),
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

  String _formatTime(SettingsService settings, DateTime time) {
    // Server timestamps are UTC; render in the client-selected timezone (or the
    // device's own zone by default).
    final local = settings.displayTime(time);
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// Quote preview: prefers the in-thread message (fresh edits/deletes), then
  /// falls back to the server-provided [ChatMessage.replyToName]/replyToContent
  /// so quotes still render when the referenced message isn't loaded.
  String? _replyPreviewText() {
    final rp = replyPreview;
    if (rp != null && !rp.isDeleted && rp.displayContent.isNotEmpty) {
      return '${rp.displayName}: ${rp.displayContent}';
    }
    if (message.replyToName != null && message.replyToName!.isNotEmpty) {
      final content = message.replyToContent ?? '';
      if (content.isEmpty) return null;
      // For encrypted conversations the server-stored replyToContent is an
      // envelope (not plaintext), so only fall back when it is readable.
      if (message.replyToName != null && message.replyToContent?.startsWith('{') == true) {
        return '${message.replyToName}: ${'chatEncryptedQuote'.tr()}';
      }
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
                  : '${message!.displayName}: ${message!.displayContent}',
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
