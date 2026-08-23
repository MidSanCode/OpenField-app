import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/chat_member.dart';
import 'package:openfield/data/models/chat_message.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/data/services/settings_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:openfield/core/format/chat_time.dart';

/// Chat history search inside one conversation. Supports filtering by content
/// keyword, time range, sender and attachments (presence or file name); all
/// criteria combine with AND. Tapping a result pops and returns the message so
/// the caller can jump to it.
class ChatSearchPage extends StatefulWidget {
  final int conversationId;

  /// Conversation members offered in the sender filter (already loaded by the
  /// caller; may be empty, which hides the sender picker entries).
  final List<ChatMember> members;

  /// Encrypted conversations store ciphertext server-side, so content /
  /// file-name keywords cannot match there; a hint explains this.
  final bool encrypted;

  const ChatSearchPage({
    super.key,
    required this.conversationId,
    this.members = const [],
    this.encrypted = false,
  });

  @override
  State<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends State<ChatSearchPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _queryController = TextEditingController();
  Timer? _debounce;

  ChatMember? _sender;
  DateTime? _from;
  DateTime? _to;
  bool _hasAttachments = false;
  String _fileName = '';

  List<ChatMessage> _results = [];
  bool _isLoading = false;
  bool _searched = false;
  String? _error;

  bool get _hasCriteria =>
      _queryController.text.trim().isNotEmpty ||
      _sender != null ||
      _from != null ||
      _to != null ||
      _hasAttachments ||
      _fileName.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _queryController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.removeListener(_onQueryChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (_hasCriteria) _search();
    });
  }

  Future<void> _search() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      // The end bound is date-only from the picker, so extend it to the last
      // second of that day to make the range inclusive.
      final to = _to != null
          ? DateTime(_to!.year, _to!.month, _to!.day, 23, 59, 59)
          : null;
      final msgs = await _apiService.searchMessages(
        token,
        widget.conversationId,
        query: _queryController.text,
        senderId: _sender?.userId,
        from: _from,
        to: to,
        hasAttachments: _hasAttachments,
        fileName: _fileName,
      );
      if (!mounted) return;
      setState(() {
        _results = msgs;
        _isLoading = false;
        _searched = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _searched = true;
      });
    }
  }

  Future<void> _pickSender() async {
    final active =
        widget.members.where((m) => m.status == 'active').toList();
    final picked = await showModalBottomSheet<ChatMember?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text('chatSearchAllSenders'.tr()),
              onTap: () => Navigator.of(ctx).pop(null),
            ),
            ...active.map(
              (m) => ListTile(
                leading: Avatar(radius: 18, imageUrl: m.avatarUrl ?? ''),
                title: Text(m.displayName),
                subtitle: m.title.isNotEmpty ? Text(m.title) : null,
                onTap: () => Navigator.of(ctx).pop(m),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || picked == null) return;
    setState(() => _sender = picked);
    if (_hasCriteria) _search();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? (_from ?? DateTime.now()) : (_to ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to != null && _to!.isBefore(picked)) _to = null;
      } else {
        _to = picked;
        if (_from != null && picked.isBefore(_from!)) _from = null;
      }
    });
    if (_hasCriteria) _search();
  }

  Future<void> _pickFileName() async {
    final controller = TextEditingController(text: _fileName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('chatSearchFileName'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration:
              InputDecoration(hintText: 'chatSearchFileNameHint'.tr()),
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
    if (!mounted || name == null) return;
    setState(() => _fileName = name);
    if (_hasCriteria) _search();
  }

  void _clearFilters() {
    setState(() {
      _queryController.clear();
      _sender = null;
      _from = null;
      _to = null;
      _hasAttachments = false;
      _fileName = '';
      _results = [];
      _searched = false;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryController,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          decoration: InputDecoration(
            hintText: 'chatSearchContentHint'.tr(),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'search'.tr(),
            onPressed: _hasCriteria ? _search : null,
          ),
          IconButton(
            icon: const Icon(Icons.filter_alt_off_outlined),
            tooltip: 'chatSearchClearFilters'.tr(),
            onPressed: (_hasCriteria || _searched) ? _clearFilters : null,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                InputChip(
                  avatar: Icon(
                    Icons.person_search_outlined,
                    size: 18,
                    color: _sender != null
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(_sender?.displayName ?? 'chatSearchBySender'.tr()),
                  onPressed: _pickSender,
                  onDeleted: _sender != null
                      ? () {
                          setState(() => _sender = null);
                          if (_hasCriteria) _search();
                        }
                      : null,
                ),
                InputChip(
                  avatar: Icon(
                    Icons.date_range_outlined,
                    size: 18,
                    color: (_from != null || _to != null)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(
                    _from != null || _to != null
                        ? '${_fmtDate(_from) ?? '?'} ~ ${_fmtDate(_to) ?? '?'}'
                        : 'chatSearchByTime'.tr(),
                  ),
                  onPressed: () => _pickDate(isFrom: true),
                  onDeleted: (_from != null || _to != null)
                      ? () {
                          setState(() {
                            _from = null;
                            _to = null;
                          });
                          if (_hasCriteria) _search();
                        }
                      : null,
                ),
                FilterChip(
                  avatar: const Icon(Icons.attach_file, size: 18),
                  label: Text('chatSearchHasAttachment'.tr()),
                  selected: _hasAttachments,
                  onSelected: (v) {
                    setState(() => _hasAttachments = v);
                    if (_hasCriteria) _search();
                  },
                ),
                InputChip(
                  avatar: Icon(
                    Icons.description_outlined,
                    size: 18,
                    color: _fileName.isNotEmpty
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  label: Text(_fileName.isEmpty
                      ? 'chatSearchFileName'.tr()
                      : _fileName),
                  onPressed: _pickFileName,
                  onDeleted: _fileName.isNotEmpty
                      ? () {
                          setState(() => _fileName = '');
                          if (_hasCriteria) _search();
                        }
                      : null,
                ),
              ],
            ),
          ),
          if (widget.encrypted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Icon(Icons.lock_outline,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'chatSearchEncryptedHint'.tr(),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 1),
          Expanded(child: _buildResults(theme)),
        ],
      ),
    );
  }

  String? _fmtDate(DateTime? d) =>
      d == null ? null : '${d.year}/${d.month}/${d.day}';

  Widget _buildResults(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text('loadFailed'.tr()));
    }
    if (!_hasCriteria && !_searched) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.manage_search,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 12),
            Text('chatSearchEmptyPrompt'.tr()),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(child: Text('chatSearchNoResults'.tr()));
    }
    final settings = Provider.of<SettingsService>(context);
    final keyword = _queryController.text.trim();
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) {
        final msg = _results[index];
        return _ResultTile(
          message: msg,
          keyword: keyword,
          timeText: formatChatTime(msg.createdAt, settings.displayTime,
              'timeYesterday'.tr()),
          onTap: () => Navigator.of(context).pop(msg),
        );
      },
    );
  }
}

class _ResultTile extends StatelessWidget {
  final ChatMessage message;
  final String keyword;
  final String timeText;
  final VoidCallback onTap;

  const _ResultTile({
    required this.message,
    required this.keyword,
    required this.timeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final atts = message.attachments;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Avatar(
              radius: 20,
              imageUrl: message.senderAvatar ?? '',
              fallbackIcon: Icons.person,
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
                          message.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(timeText,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontSize: 11)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  if (message.content.isNotEmpty)
                    _highlightedContent(theme, keyword),
                  if (atts.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        for (final a in atts.take(3))
                          Tooltip(
                            message: a.originalName,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    a.mimeType.startsWith('image/')
                                        ? Icons.image_outlined
                                        : Icons.insert_drive_file_outlined,
                                    size: 14,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 140),
                                    child: Text(
                                      a.originalName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        if (atts.length > 3)
                          Text('+${atts.length - 3}',
                              style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the message body with every case-insensitive occurrence of
  /// [keyword] emphasized, so users see why a hit matched.
  Widget _highlightedContent(ThemeData theme, String keyword) {
    final text = message.displayContent;
    if (keyword.isEmpty) {
      return Text(text, maxLines: 3, overflow: TextOverflow.ellipsis);
    }
    final lower = text.toLowerCase();
    final needle = keyword.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final i = lower.indexOf(needle, start);
      if (i < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (i > start) {
        spans.add(TextSpan(text: text.substring(start, i)));
      }
      spans.add(TextSpan(
        text: text.substring(i, i + needle.length),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ));
      start = i + needle.length;
    }
    return RichText(
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: theme.textTheme.bodyMedium,
        children: spans,
      ),
    );
  }
}
