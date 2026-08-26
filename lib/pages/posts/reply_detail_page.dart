import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/models/post_reply.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/widgets/reply_tile.dart';

/// A full thread view for a single reply: the target reply plus every nested
/// descendant, with a composer to reply into the thread.
class ReplyDetailPage extends StatefulWidget {
  final Post post;
  final PostReply reply;

  const ReplyDetailPage({super.key, required this.post, required this.reply});

  @override
  State<ReplyDetailPage> createState() => _ReplyDetailPageState();
}

class _ReplyDetailPageState extends State<ReplyDetailPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _replyController = TextEditingController();
  late PostReply _reply;
  List<PostReply> _replies = [];
  bool _isLoading = true;
  bool _isSending = false;
  double? _uploadProgress;
  String? _error;
  PostReply? _replyingTo;
  Attachment? _pendingAttachment;

  @override
  void initState() {
    super.initState();
    _reply = widget.reply;
    _load();
  }

  @override
  void dispose() {
    _replyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final replies = await _apiService.listReplies(widget.post.id, token: token);
      if (!mounted) return;
      setState(() {
        _replies = replies;
        // Prefer the freshest copy of the target reply from the list.
        for (final r in replies) {
          if (r.id == widget.reply.id) {
            _reply = r;
            break;
          }
        }
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

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles();
    final file = result?.files.single;
    if (file == null || file.path == null) return;
    if (!mounted) return;
    setState(() {
      _pendingAttachment = Attachment(
        id: 0,
        originalName: file.name,
        mimeType: '',
        sizeBytes: file.size,
        url: file.path!,
        visibility: 'public',
      );
    });
  }

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty && _pendingAttachment == null) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _isSending = true);
    try {
      int? attachmentId;
      if (_pendingAttachment != null) {
        final att = await _apiService.uploadAttachmentSmart(
          _pendingAttachment!.url,
          token,
          onProgress: (p) {
            if (mounted) setState(() => _uploadProgress = p);
          },
        );
        attachmentId = att.id;
      }
      final reply = await _apiService.createReply(
        widget.post.id,
        content,
        token,
        parentId: _replyingTo?.id ?? _reply.id,
        attachmentIds: attachmentId != null ? [attachmentId] : const [],
      );
      _replyController.clear();
      if (!mounted) return;
      setState(() {
        _replies = [..._replies, reply];
        _isSending = false;
        _uploadProgress = null;
        _replyingTo = null;
        _pendingAttachment = null;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSending = false;
        _uploadProgress = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  final _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  void _replyTo(PostReply reply) {
    setState(() => _replyingTo = reply);
  }

  Future<void> _editReply(PostReply reply, String token) async {
    final controller = TextEditingController(text: reply.content);
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('edit'.tr()),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 5000,
          decoration: InputDecoration(hintText: 'replyContent'.tr()),
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
      final updated = await _apiService.updateReply(
        widget.post.id,
        reply.id,
        content,
        token,
        attachmentIds: reply.attachments.map((a) => a.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _replies = _replies.map((r) => r.id == updated.id ? updated : r).toList();
        if (updated.id == _reply.id) _reply = updated;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteReply(PostReply reply, String token) async {
    try {
      await _apiService.deleteReply(widget.post.id, reply.id, token);
      if (!mounted) return;
      setState(() {
        _replies = _replies.where((r) => r.id != reply.id).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Collects the descendant thread of the target reply, in tree order.
  List<PostReply> _descendants() {
    final childrenOf = <int?, List<PostReply>>{};
    for (final r in _replies) {
      if (r.id == _reply.id) continue;
      childrenOf.putIfAbsent(r.parentId, () => []).add(r);
    }
    final result = <PostReply>[];
    void walk(int parentId, int depth) {
      for (final r in childrenOf[parentId] ?? []) {
        result.add(r);
        walk(r.id, depth + 1);
      }
    }

    walk(_reply.id, 0);
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('reply'.tr())),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        color: Theme.of(context).colorScheme.surfaceContainerLow,
                        child: _buildReplyTile(_reply, onTap: () => _openAuthorProfile(_reply.userId)),
                      ),
                      const Divider(),
                      if (_error != null && _replies.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                            child: TextButton(
                              onPressed: _load,
                              child: Text('retry'.tr()),
                            ),
                          ),
                        )
                      else
                        ..._descendants().map((r) => _buildReplyTile(
                              r,
                              onTap: () => _openReplyDetail(r),
                            )),
                      if (_descendants().isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(child: Text('replyEmpty'.tr())),
                        ),
                    ],
                  ),
                ),
                _buildReplyBar(),
              ],
            ),
    );
  }

  void _openAuthorProfile(int userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
    );
  }

  /// Builds a [ReplyTile] wired to the page-level reply/edit/delete/favorite
  /// handlers. Right-click and long-press open the shared context menu.
  Widget _buildReplyTile(PostReply reply, {required VoidCallback onTap}) {
    final authService = Provider.of<AuthService>(context);
    final currentUserId = authService.user?.id;
    return ReplyTile(
      reply: reply,
      onTap: onTap,
      onReply: () => _replyTo(reply),
      token: authService.accessToken,
      isMine: reply.userId == currentUserId,
      onEdit: () => _editReply(reply, authService.accessToken ?? ''),
      onDelete: () => _deleteReply(reply, authService.accessToken ?? ''),
      onReplyChanged: (updated) => setState(() {
        _replies = _replies.map((r) => r.id == updated.id ? updated : r).toList();
        if (updated.id == _reply.id) _reply = updated;
      }),
      onUnauthenticated: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('loginWithOIDC'.tr())),
        );
      },
      onTapAuthor: () => _openAuthorProfile(reply.userId),
    );
  }

  void _openReplyDetail(PostReply reply) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReplyDetailPage(post: widget.post, reply: reply),
      ),
    );
  }

  Widget _buildReplyBar() {
    final authService = Provider.of<AuthService>(context);
    if (!authService.isAuthenticated) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(child: Text('loginWithOIDC'.tr())),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.reply, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'replyingToHint'.tr(namedArgs: {'name': _replyingTo!.authorName}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _replyingTo = null),
                    ),
                  ],
                ),
              ),
            if (_pendingAttachment != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _pendingAttachment!.originalName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.close, size: 16),
                      onPressed: () => setState(() => _pendingAttachment = null),
                    ),
                  ],
                ),
              ),
            if (_isSending && _uploadProgress != null && _uploadProgress! < 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: _uploadProgress,
                          minHeight: 4,
                          backgroundColor:
                              Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${(_uploadProgress! * 100).round()}%',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: _isSending ? null : _pickAttachment,
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'replyAttachHint'.tr(),
                ),
                Expanded(
                  child: TextField(
                    controller: _replyController,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'replyContent'.tr(),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    onSubmitted: (_) => _sendReply(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _isSending ? null : _sendReply,
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  tooltip: 'send'.tr(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
