import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openfield/core/widgets/media_image.dart';
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
    // A single image is shown at a capped, human-friendly size instead of
    // stretching to fill the whole card/screen width.
    if (images.length == 1) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: _ImageCell(att: images.first),
          ),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: images.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemBuilder: (context, index) => _ImageCell(att: images[index]),
    );
  }
}

class _ImageCell extends StatelessWidget {
  final Attachment att;

  const _ImageCell({required this.att});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openAttachment(context, att),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MediaImage(
              url: att.previewUrl,
              fit: BoxFit.cover,
              // Cap the decoded image so preview grids never hold the full
              // original in memory.
              cacheWidth: 720,
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

class _AttachmentTile extends StatefulWidget {
  final Attachment attachment;
  final bool interactive;
  final VoidCallback? onOpen;

  const _AttachmentTile({required this.attachment, required this.interactive, this.onOpen});

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _rendering = false;

  Attachment get attachment => widget.attachment;

  bool get _isMedia => attachment.isVideo || attachment.isAudio;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: widget.interactive
              ? () {
                  widget.onOpen?.call();
                  if (_isMedia) {
                    setState(() => _rendering = !_rendering);
                  } else {
                    _openAttachment(context, attachment);
                  }
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
                if (widget.interactive) ...[
                  if (_isMedia)
                    InkResponse(
                      radius: 18,
                      onTap: () => setState(() => _rendering = !_rendering),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _rendering ? Icons.close : Icons.play_circle_outline,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  InkResponse(
                    radius: 18,
                    onTap: () => _openAttachment(context, attachment),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_rendering) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: _InlineMediaPlayer(attachment: attachment),
          ),
        ],
      ],
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

/// Attempts to render video/audio inline in the bubble. Uses media_kit, so
/// failures (unsupported codec, network issue, ...) fall back to a compact
/// error tile with retry/external-open actions instead of breaking the chat.
class _InlineMediaPlayer extends StatefulWidget {
  final Attachment attachment;

  const _InlineMediaPlayer({required this.attachment});

  @override
  State<_InlineMediaPlayer> createState() => _InlineMediaPlayerState();
}

class _InlineMediaPlayerState extends State<_InlineMediaPlayer> {
  Player? _player;
  VideoController? _videoController;
  bool _loading = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final player = Player();
      if (widget.attachment.isVideo) {
        _videoController = VideoController(player);
      }
      await player.open(Media(widget.attachment.url));
      if (!mounted) {
        player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_failed) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Unable to play this media',
                style: theme.textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Retry')),
            TextButton(
              onPressed: () => _openAttachment(context, widget.attachment),
              child: const Text('Open'),
            ),
          ],
        ),
      );
    }

    if (_loading || _player == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final att = widget.attachment;
    if (att.isVideo && _videoController != null) {
      return SizedBox(
        height: 200,
        child: Video(
          controller: _videoController!,
          controls: AdaptiveVideoControls,
        ),
      );
    }

    return _compactAudio(context);
  }

  Widget _compactAudio(BuildContext context) {
    final player = _player!;
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                visualDensity: VisualDensity.compact,
                iconSize: 26,
                icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                onPressed: () => player.playOrPause(),
              );
            },
          ),
          Expanded(
            child: Text(
              widget.attachment.originalName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          StreamBuilder<Duration>(
            stream: player.stream.position,
            initialData: player.state.position,
            builder: (context, pos) {
              final position = pos.data ?? Duration.zero;
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                initialData: player.state.duration,
                builder: (context, dur) {
                  final duration = dur.data ?? Duration.zero;
                  return Text(
                    '${_fmtDuration(position)} / ${_fmtDuration(duration)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  String _fmtDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (d.inHours > 0) return '${d.inHours}:${two(m % 60)}:${two(s)}';
    return '${two(m)}:${two(s)}';
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
