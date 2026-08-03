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
import 'package:openfield/pages/posts/reply_detail_page.dart';
import 'package:openfield/widgets/post_card.dart';
import 'package:openfield/widgets/reply_tile.dart';

class PostDetailPage extends StatefulWidget {
  final Post post;

  const PostDetailPage({super.key, required this.post});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> {
  final ApiService _apiService = ApiService();
  final TextEditingController _replyController = TextEditingController();
  late Post _post;
  List<PostReply> _replies = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _error;
  PostReply? _replyingTo;
  Attachment? _pendingAttachment;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
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
      final post = token != null ? await _apiService.getPost(_post.id, token) : _post;
      final replies = await _apiService.listReplies(_post.id, token: token);
      if (!mounted) return;
      setState(() {
        _post = post;
        _replies = replies;
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

  void _openAuthorProfile(int userId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProfilePage(userId: userId)),
    );
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
        final att = await _apiService.uploadAttachmentSmart(_pendingAttachment!.url, token);
        attachmentId = att.id;
      }
      final reply = await _apiService.createReply(
        _post.id,
        content,
        token,
        parentId: _replyingTo?.id,
        attachmentIds: attachmentId != null ? [attachmentId] : const [],
      );
      _replyController.clear();
      if (!mounted) return;
      setState(() {
        _replies = [..._replies, reply];
        _isSending = false;
        _replyingTo = null;
        _pendingAttachment = null;
        _post = Post(
          id: _post.id,
          userId: _post.userId,
          content: _post.content,
          createdAt: _post.createdAt,
          updatedAt: _post.updatedAt,
          username: _post.username,
          nickname: _post.nickname,
          avatarUrl: _post.avatarUrl,
          attachments: _post.attachments,
          replyCount: _post.replyCount + 1,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  void _replyTo(PostReply reply) {
    setState(() {
      _replyingTo = reply;
    });
  }

  Future<void> _onReplyLongPress(PostReply reply) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final isMine = reply.userId == authService.user?.id;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.reply_outlined),
              title: Text('reply'.tr()),
              onTap: () => Navigator.of(ctx).pop('reply'),
            ),
            if (isMine) ...[
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
    if (action == 'reply') {
      _replyTo(reply);
    } else if (action == 'edit') {
      await _editReply(reply);
    } else if (action == 'delete') {
      await _deleteReply(reply);
    }
  }

  Future<void> _editReply(PostReply reply) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
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
        _post.id,
        reply.id,
        content,
        token,
        attachmentIds: reply.attachments.map((a) => a.id).toList(),
      );
      if (!mounted) return;
      setState(() {
        _replies = _replies.map((r) => r.id == updated.id ? updated : r).toList();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _deleteReply(PostReply reply) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    try {
      await _apiService.deleteReply(_post.id, reply.id, token);
      if (!mounted) return;
      setState(() {
        _replies = _replies.where((r) => r.id != reply.id).toList();
        _post = Post(
          id: _post.id,
          userId: _post.userId,
          content: _post.content,
          createdAt: _post.createdAt,
          updatedAt: _post.updatedAt,
          username: _post.username,
          nickname: _post.nickname,
          avatarUrl: _post.avatarUrl,
          attachments: _post.attachments,
          replyCount: (_post.replyCount - 1).clamp(0, 1 << 30),
        );
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  /// Builds a reply tree: top-level replies followed by their nested children.
  List<Widget> _buildReplyTree(List<PostReply> replies) {
    final childrenOf = <int?, List<PostReply>>{};
    for (final r in replies) {
      childrenOf.putIfAbsent(r.parentId, () => []).add(r);
    }
    final result = <Widget>[];
    void addChildren(int? parentId) {
      for (final r in childrenOf[parentId] ?? []) {
        final depth = r.parentId == null ? 0 : 1;
        result.add(_buildReplyItem(r, depth));
        addChildren(r.id);
      }
    }

    addChildren(null);
    return result;
  }

  Widget _buildReplyItem(PostReply reply, int depth) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16),
      child: ReplyTile(
        reply: reply,
        onTap: () => _openReplyDetail(reply),
        onLongPress: () => _onReplyLongPress(reply),
        onTapAuthor: () => _openAuthorProfile(reply.userId),
      ),
    );
  }

  void _openReplyDetail(PostReply reply) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReplyDetailPage(post: _post, reply: reply),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUserId = authService.user?.id;

    return Scaffold(
      appBar: AppBar(title: Text('replies'.tr())),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _replies.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('loadFailed'.tr()),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _load, child: Text('retry'.tr())),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.only(bottom: 8),
                        children: [
                          PostCard(
                            post: _post,
                            isMine: _post.userId == currentUserId,
                            onTapAuthor: () => _openAuthorProfile(_post.userId),
                            onTapReply: () {},
                            showReplies: false,
                            token: Provider.of<AuthService>(context).accessToken,
                            onPostChanged: (updated) => setState(() => _post = updated),
                          ),
                          const Divider(),
                          if (_replies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(child: Text('replyEmpty'.tr())),
                            )
                          else
                            ..._buildReplyTree(_replies),
                        ],
                      ),
                    ),
                    _buildReplyBar(),
                  ],
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

