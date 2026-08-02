import 'package:flutter/material.dart';
import 'package:openfield/data/models/post_reply.dart';
import 'package:openfield/widgets/attachment_view.dart';
import 'package:openfield/widgets/markdown_content.dart';
import 'package:openfield/widgets/verified_badge.dart';

/// A single reply row used in post detail and reply detail pages.
class ReplyTile extends StatelessWidget {
  final PostReply reply;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback? onTapAuthor;

  const ReplyTile({
    super.key,
    required this.reply,
    required this.onTap,
    required this.onLongPress,
    this.onTapAuthor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
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
                  Row(
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
                  MarkdownContent(data: reply.content),
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
