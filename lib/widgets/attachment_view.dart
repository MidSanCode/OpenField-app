import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/pages/media/media_preview_page.dart';

class AttachmentView extends StatelessWidget {
  final List<Attachment> attachments;
  final bool interactive;
  final VoidCallback? onOpen;

  const AttachmentView({
    super.key,
    required this.attachments,
    this.interactive = true,
    this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final images = attachments.where((a) => a.isImage).toList();
    final others = attachments.where((a) => !a.isImage).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (images.isNotEmpty) _ImageGrid(images: images),
        if (others.isNotEmpty) ...[
          const SizedBox(height: 8),
          _OthersList(attachments: others, interactive: interactive, onOpen: onOpen),
        ],
      ],
    );
  }
}

class _ImageGrid extends StatelessWidget {
  final List<Attachment> images;

  const _ImageGrid({required this.images});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: images.length == 1 ? 1 : 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) {
        final att = images[index];
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: () => _openAttachment(context, att),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  att.url,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(color: Theme.of(context).colorScheme.surfaceContainerHighest);
                  },
                  errorBuilder: (context, error, stack) => Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
                if (!att.isPublic)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: _VisibilityBadge(visibility: att.visibility),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OthersList extends StatelessWidget {
  final List<Attachment> attachments;
  final bool interactive;
  final VoidCallback? onOpen;

  const _OthersList({required this.attachments, required this.interactive, this.onOpen});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final att in attachments) ...[
          _AttachmentTile(attachment: att, interactive: interactive, onOpen: onOpen),
          if (att != attachments.last) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  final Attachment attachment;
  final bool interactive;
  final VoidCallback? onOpen;

  const _AttachmentTile({required this.attachment, required this.interactive, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: interactive
          ? () {
              onOpen?.call();
              _openAttachment(context, attachment);
            }
          : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              _iconFor(attachment),
              size: 28,
              color: theme.colorScheme.primary,
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
                          attachment.originalName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      if (!attachment.isPublic) ...[
                        const SizedBox(width: 6),
                        _VisibilityBadge(visibility: attachment.visibility),
                      ],
                    ],
                  ),
                  Text(
                    '${_typeLabel(context)} · ${formatBytes(attachment.sizeBytes)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (interactive)
              Icon(
                Icons.open_in_new,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }

  String _typeLabel(BuildContext context) {
    if (attachment.isAudio) return 'audio';
    if (attachment.isVideo) return 'video';
    if (attachment.isText) return 'text';
    return 'file';
  }

  IconData _iconFor(Attachment att) {
    if (att.isAudio) return Icons.audio_file_outlined;
    if (att.isVideo) return Icons.video_file_outlined;
    if (att.isText) return Icons.description_outlined;
    return Icons.insert_drive_file_outlined;
  }
}

class _VisibilityBadge extends StatelessWidget {
  final String visibility;

  const _VisibilityBadge({required this.visibility});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    switch (visibility) {
      case 'private':
        return Icon(Icons.lock, size: 14, color: theme.colorScheme.error);
      case 'restricted':
        return Icon(Icons.group, size: 14, color: theme.colorScheme.primary);
      default:
        return const SizedBox.shrink();
    }
  }
}

Future<void> _openUrl(BuildContext context, String url) async {
  await openAttachmentUrl(context, url);
}

void _openAttachment(BuildContext context, Attachment att) {
  if (att.isImage || att.isVideo || att.isAudio) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaPreviewPage(attachment: att),
      ),
    );
    return;
  }
  _openUrl(context, att.url);
}

Future<void> openAttachmentUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } else {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open attachment')),
      );
    }
  }
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
