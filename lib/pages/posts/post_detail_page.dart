import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/models/post_reply.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/auth_service.dart';
import 'package:openfield/l10n/app_localizations.dart';
import 'package:openfield/pages/account/profile_page.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/post_card.dart';
import 'package:openfield/widgets/verified_badge.dart';

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

  Future<void> _sendReply() async {
    final content = _replyController.text.trim();
    if (content.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    setState(() => _isSending = true);
    try {
      final reply = await _apiService.createReply(_post.id, content, token);
      _replyController.clear();
      if (!mounted) return;
      setState(() {
        _replies = [..._replies, reply];
        _isSending = false;
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

  Future<void> _onReplyLongPress(PostReply reply) async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null || reply.userId != authService.user?.id) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
        ),
      ),
    );
    if (action == null) return;
    if (action == 'edit') {
      await _editReply(reply);
    } else if (action == 'delete') {
      await _deleteReply(reply);
    }
  }

  Future<void> _editReply(PostReply reply) async {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context, listen: false);
    final token = authService.accessToken;
    if (token == null) return;
    final controller = TextEditingController(text: reply.content);
    final content = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.edit),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: 5000,
          decoration: InputDecoration(hintText: l10n.replyContent),
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
      final updated = await _apiService.updateReply(_post.id, reply.id, content, token);
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final authService = Provider.of<AuthService>(context);
    final currentUserId = authService.user?.id;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.replies)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _replies.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(l10n.loadFailed),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _load, child: Text(l10n.retry)),
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
                          ),
                          const Divider(),
                          if (_replies.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(32),
                              child: Center(child: Text(l10n.replyEmpty)),
                            )
                          else
                            ..._replies.map(
                              (r) => _ReplyTile(
                                reply: r,
                                isMine: r.userId == currentUserId,
                                onLongPress: () => _onReplyLongPress(r),
                                onTapAuthor: () => _openAuthorProfile(r.userId),
                              ),
                            ),
                        ],
                      ),
                    ),
                    _buildReplyBar(l10n),
                  ],
                ),
    );
  }

  Widget _buildReplyBar(AppLocalizations l10n) {
    final authService = Provider.of<AuthService>(context);
    if (!authService.isAuthenticated) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Center(child: Text(l10n.loginWithOIDC)),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _replyController,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: l10n.replyContent,
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
              tooltip: l10n.send,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReplyTile extends StatelessWidget {
  final PostReply reply;
  final bool isMine;
  final VoidCallback onLongPress;
  final VoidCallback? onTapAuthor;

  const _ReplyTile({
    required this.reply,
    required this.isMine,
    required this.onLongPress,
    this.onTapAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onLongPress: isMine ? onLongPress : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: onTapAuthor,
              borderRadius: BorderRadius.circular(16),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: (reply.avatarUrl != null && reply.avatarUrl!.isNotEmpty)
                    ? NetworkImage(reply.avatarUrl!)
                    : null,
                child: (reply.avatarUrl == null || reply.avatarUrl!.isEmpty)
                    ? Text(reply.authorName.substring(0, 1).toUpperCase())
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InkWell(
                    onTap: onTapAuthor,
                    child: VerifiedName(
                      name: reply.authorName,
                      verified: reply.isVerified,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  MarkdownContent(data: reply.content),
                  const SizedBox(height: 2),
                  Text(
                    _formatDate(reply.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
