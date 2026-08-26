import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:openfield/data/models/post_reply.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/widgets/attachment_view.dart';
import 'package:openfield/widgets/content_context_menu.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/verified_badge.dart';
import 'package:openfield/core/widgets/avatar.dart';
import 'package:easy_localization/easy_localization.dart';

/// A single reply row used in post detail and reply detail pages.
class ReplyTile extends StatefulWidget {
  final PostReply reply;
  final VoidCallback onTap;
  final VoidCallback? onTapAuthor;
  final VoidCallback? onReply;
  final String? token;
  final bool isMine;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final ValueChanged<PostReply>? onReplyChanged;
  final VoidCallback? onUnauthenticated;

  const ReplyTile({
    super.key,
    required this.reply,
    required this.onTap,
    this.onTapAuthor,
    this.onReply,
    this.token,
    this.isMine = false,
    this.onEdit,
    this.onDelete,
    this.onReplyChanged,
    this.onUnauthenticated,
  });

  @override
  State<ReplyTile> createState() => _ReplyTileState();
}

class _ReplyTileState extends State<ReplyTile> {
  PostReply get reply => widget.reply;

  Future<void> _showContextMenu([Offset? position]) async {
    final items = buildContentMenuItems(
      isMine: widget.isMine,
      isFavorite: reply.isFavorite,
      includeReply: true,
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
          ClipboardData(text: replyLink(reply.postId, reply.id)),
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('linkCopied'.tr())),
          );
        }
      case ContentAction.reply:
        widget.onReply?.call();
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
      final updated = reply.isFavorite
          ? await api.unfavoriteReply(reply.postId, reply.id, token)
          : await api.favoriteReply(reply.postId, reply.id, token);
      if (!mounted) return;
      widget.onReplyChanged?.call(updated);
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
      onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: () => _showContextMenu(),
        child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: widget.onTapAuthor,
              borderRadius: BorderRadius.circular(16),
              child: Avatar(
                radius: 16,
                imageUrl: reply.avatarUrl ?? '',
                initials: reply.authorName.isNotEmpty
                    ? reply.authorName.substring(0, 1).toUpperCase()
                    : '',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      InkWell(
                        onTap: widget.onTapAuthor,
                        child: VerifiedName(
                            name: reply.authorName,
                            verified: reply.isVerified,
                            bot: reply.isBot,
                            memberLevel: reply.memberLevel,
                            memberActive: reply.memberActive,
                            nameColor: reply.nameColor,
                            nameColorTo: reply.nameColorTo,
                            nameColors: reply.nameColors,
                            nameGradientDirection: reply.nameGradientDirection,
                            nameDynamic: reply.nameDynamic,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ),
                      const SizedBox(width: 8),
                      if (reply.parentName != null && reply.parentName!.isNotEmpty)
                        Flexible(
                          child: Text(
                            '→ ${reply.parentName}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (reply.parentContent != null && reply.parentContent!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        reply.parentContent!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  MarkdownContent(data: reply.content, selectable: false),
                  if (reply.attachments.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    AttachmentView(attachments: reply.attachments),
                  ],
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
