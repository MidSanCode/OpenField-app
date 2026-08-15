import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openfield/data/models/post.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:openfield/widgets/attachment_view.dart';
import 'package:openfield/widgets/content_context_menu.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/post_reaction_bar.dart';
import 'package:openfield/widgets/verified_badge.dart';

class PostCard extends StatefulWidget {
  final Post post;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onTapReply;
  final VoidCallback? onTapAuthor;
  final bool showReplies;
  final ValueChanged<Post>? onPostChanged;
  final String? token;
  final VoidCallback? onUnauthenticated;

  const PostCard({
    super.key,
    required this.post,
    this.isMine = false,
    this.onEdit,
    this.onDelete,
    this.onTapReply,
    this.onTapAuthor,
    this.showReplies = true,
    this.onPostChanged,
    this.token,
    this.onUnauthenticated,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  static const int _truncateLength = 200;
  late bool _expanded;

  Post get post => widget.post;

  @override
  void initState() {
    super.initState();
    _expanded = post.content.length <= _truncateLength;
  }

  bool get _isTruncated => post.content.length > _truncateLength;

  String get _displayContent =>
      _expanded || !_isTruncated ? post.content : post.content.substring(0, _truncateLength);

  /// Opens the post context menu, either as a desktop right-click popup at
  /// [position] or as the mobile long-press bottom sheet.
  Future<void> _showContextMenu([Offset? position]) async {
    final items = buildContentMenuItems(
      isMine: widget.isMine,
      isFavorite: post.isFavorite,
    );
    final action = position != null
        ? await showContentMenuAt(context, position, items: items)
        : await showContentBottomSheet(context, items: items);
    if (action == null || !mounted) return;
    await _handleAction(action);
  }

  Future<void> _handleAction(String action) async {
    switch (action) {
      case ContentAction.copyLink:
        await Clipboard.setData(
          ClipboardData(text: postLink(post.id)),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('linkCopied'.tr())),
          );
        }
      case ContentAction.edit:
        widget.onEdit?.call();
      case ContentAction.delete:
        widget.onDelete?.call();
      case ContentAction.favorite:
      case ContentAction.unfavorite:
        await _toggleFavorite();
    }
  }

  Future<void> _toggleFavorite() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      widget.onUnauthenticated?.call();
      return;
    }
    try {
      final api = ApiService();
      final updated = post.isFavorite
          ? await api.unfavoritePost(post.id, token)
          : await api.favoritePost(post.id, token);
      if (!mounted) return;
      widget.onPostChanged?.call(updated);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onLongPress: () => _showContextMenu(),
      onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: widget.onTapAuthor,
                    borderRadius: BorderRadius.circular(24),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundImage: post.avatarUrl != null && post.avatarUrl!.isNotEmpty
                          ? NetworkImage(post.avatarUrl!)
                          : null,
                      child: post.avatarUrl == null || post.avatarUrl!.isEmpty
                          ? Text(post.authorName.substring(0, 1).toUpperCase())
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: widget.onTapAuthor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          VerifiedName(
                            name: post.authorName,
                            verified: post.authorVerified,
                            style: theme.textTheme.titleMedium,
                          ),
                          Text(
                            _formatDate(post.createdAt),
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') widget.onEdit?.call();
                      if (value == 'delete') widget.onDelete?.call();
                      if (value == 'favorite') _toggleFavorite();
                      if (value == 'copyLink') {
                        Clipboard.setData(
                          ClipboardData(text: postLink(post.id)),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('linkCopied'.tr())),
                        );
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'copyLink',
                        child: Text('copyPostLink'.tr()),
                      ),
                      PopupMenuItem(
                        value: 'favorite',
                        child: Text(
                          post.isFavorite ? 'removeFavorite'.tr() : 'addFavorite'.tr(),
                        ),
                      ),
                      if (widget.isMine)
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('edit'.tr()),
                        ),
                      if (widget.isMine)
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'delete'.tr(),
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              MarkdownContent(data: _displayContent),
              if (_isTruncated && !_expanded) ...[
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => setState(() => _expanded = true),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      'showMore'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
              if (post.attachments.isNotEmpty) ...[
                const SizedBox(height: 12),
                AttachmentView(attachments: post.attachments),
              ],
              if (widget.showReplies) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    InkWell(
                      onTap: widget.onTapReply,
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            Icon(
                              Icons.chat_bubble_outline,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              post.replyCount > 0 ? '${post.replyCount}' : 'reply'.tr(),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: PostReactionBar(
                        post: post,
                        token: widget.token,
                        onChanged: widget.onPostChanged ?? (_) {},
                        onUnauthenticated: widget.onUnauthenticated,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
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
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
