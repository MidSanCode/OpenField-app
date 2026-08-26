import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:openfield/core/widgets/media_image.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/data/services/encrypted_attachment_service.dart';
import 'package:openfield/pages/media/media_preview_page.dart';

class AttachmentView extends StatelessWidget {
  final List<Attachment> attachments;
  final bool interactive;
  final VoidCallback? onOpen;

  /// The conversation the attachments belong to. Required to decrypt E2EE
  /// attachments (the group key is scoped per conversation).
  final int? conversationId;

  const AttachmentView({
    super.key,
    required this.attachments,
    this.interactive = true,
    this.onOpen,
    this.conversationId,
  });

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) return const SizedBox.shrink();
    final encrypted = attachments.where((a) => a.isEncrypted);
    if (encrypted.isNotEmpty) {
      if (conversationId == null) {
        return const SizedBox.shrink();
      }
      return _EncryptedAttachmentsView(
        conversationId: conversationId!,
        attachments: attachments,
        interactive: interactive,
        onOpen: onOpen,
      );
    }
    return _PlainBody(
      attachments: attachments
          .map((a) => _ResolvedAtt(attachment: a, fromLocalFile: false))
          .toList(),
      interactive: interactive,
      onOpen: onOpen,
    );
  }
}

/// Renders attachments that must be decrypted locally before they can be shown.
/// Resolves every encrypted attachment to a temporary local file, then renders
/// the same grid/tile UI against the recovered files.
class _EncryptedAttachmentsView extends StatefulWidget {
  final int conversationId;
  final List<Attachment> attachments;
  final bool interactive;
  final VoidCallback? onOpen;

  const _EncryptedAttachmentsView({
    required this.conversationId,
    required this.attachments,
    required this.interactive,
    this.onOpen,
  });

  @override
  State<_EncryptedAttachmentsView> createState() => _EncryptedAttachmentsViewState();
}

class _EncryptedAttachmentsViewState extends State<_EncryptedAttachmentsView> {
  late Future<List<_ResolvedAtt>> _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve();
  }

  Future<List<_ResolvedAtt>> _resolve() async {
    final service = EncryptedAttachmentService.instance;
    final out = <_ResolvedAtt>[];
    for (final a in widget.attachments) {
      if (!a.isEncrypted) {
        out.add(_ResolvedAtt(attachment: a, fromLocalFile: false));
        continue;
      }
      final path = await service.decryptToFile(widget.conversationId, a);
      out.add(
        _ResolvedAtt(
          attachment: Attachment(
            id: a.id,
            originalName: a.originalName,
            mimeType: a.originalMime.isNotEmpty ? a.originalMime : a.mimeType,
            sizeBytes: a.sizeBytes,
            url: path,
            thumbUrl: '',
            visibility: a.visibility,
          ),
          fromLocalFile: true,
        ),
      );
    }
    return out;
  }

  void _retry() {
    setState(() => _future = _resolve());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<_ResolvedAtt>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: theme.colorScheme.primary),
              ),
            ),
          );
        }
        if (snapshot.hasError || snapshot.data == null) {
          return Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 18, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'attachmentDecryptFailed'.tr(),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(onPressed: _retry, child: const Text('Retry')),
              ],
            ),
          );
        }
        return _PlainBody(
          attachments: snapshot.data!,
          interactive: widget.interactive,
          onOpen: widget.onOpen,
        );
      },
    );
  }
}

/// A decrypted attachment (or a plain one passed through). When [fromLocalFile]
/// is true, [attachment.url] points at a local, decrypted copy of the file.
class _ResolvedAtt {
  final Attachment attachment;
  final bool fromLocalFile;
  const _ResolvedAtt({required this.attachment, required this.fromLocalFile});
}

class _PlainBody extends StatelessWidget {
  final List<_ResolvedAtt> attachments;
  final bool interactive;
  final VoidCallback? onOpen;

  const _PlainBody({required this.attachments, required this.interactive, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final images = attachments.where((a) => a.attachment.isImage).toList();
    final others = attachments.where((a) => !a.attachment.isImage).toList();

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
  final List<_ResolvedAtt> images;

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
  final _ResolvedAtt att;

  const _ImageCell({required this.att});

  @override
  Widget build(BuildContext context) {
    final attachment = att.attachment;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _openResolved(context, att),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (att.fromLocalFile)
              Image.file(
                File(attachment.url),
                fit: BoxFit.cover,
                cacheWidth: 720,
                errorBuilder: (_, _, _) => _imageError(context),
              )
            else
              MediaImage(
                url: attachment.previewUrl,
                fit: BoxFit.cover,
                // Cap the decoded image so preview grids never hold the full
                // original in memory.
                cacheWidth: 720,
              ),
            if (!attachment.isPublic)
              Positioned(
                top: 4,
                right: 4,
                child: _VisibilityBadge(visibility: attachment.visibility),
              ),
          ],
        ),
      ),
    );
  }

  Widget _imageError(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.image_not_supported_outlined,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _OthersList extends StatelessWidget {
  final List<_ResolvedAtt> attachments;
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
  final _ResolvedAtt attachment;
  final bool interactive;
  final VoidCallback? onOpen;

  const _AttachmentTile({required this.attachment, required this.interactive, this.onOpen});

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _rendering = false;

  /// Download state for "save to device": null = idle, otherwise fraction in
  /// [0, 1]. While downloading, the action slot shows the progress instead of
  /// the open button.
  double? _downloadProgress;
  bool _downloadFailed = false;

  _ResolvedAtt get resolved => widget.attachment;

  Attachment get attachment => resolved.attachment;

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
                    _openResolved(context, resolved);
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
                  if (_downloadProgress != null)
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value:
                                _downloadProgress! <= 0 ? null : _downloadProgress!,
                            strokeWidth: 2.2,
                          ),
                          Text(
                            '${(_downloadProgress! * 100).round()}',
                            style: const TextStyle(fontSize: 7),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    InkResponse(
                      radius: 18,
                      onTap: _downloadToDevice,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          _downloadFailed
                              ? Icons.error_outline
                              : Icons.download_outlined,
                          size: 18,
                          color: _downloadFailed
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
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

  /// Downloads the attachment to the device temp dir with a progress ring,
  /// then opens it with an external app. Encrypted attachments already live
  /// locally after decryption, so they skip the download.
  Future<void> _downloadToDevice() async {
    if (resolved.fromLocalFile || _localPathIfAny(attachment.url) != null) {
      _openResolved(context, resolved);
      return;
    }
    setState(() {
      _downloadProgress = 0;
      _downloadFailed = false;
    });
    try {
      final dir = await getTemporaryDirectory();
      final safeName = attachment.originalName.isNotEmpty
          ? attachment.originalName
          : 'attachment-${attachment.id}';
      final savePath =
          '${dir.path}${Platform.pathSeparator}of_dl_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await ApiService().downloadToFile(
        attachment.url,
        savePath,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _downloadProgress = total != null && total > 0 ? received / total : 0.5;
          });
        },
      );
      if (!mounted) return;
      setState(() => _downloadProgress = null);
      _openLocalFile(context, savePath);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadProgress = null;
        _downloadFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
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

void _openResolved(BuildContext context, _ResolvedAtt att) {
  if (att.fromLocalFile) {
    _openLocalFile(context, att.attachment.url);
    return;
  }
  _openAttachment(context, att.attachment);
}

void _openAttachment(BuildContext context, Attachment att) {
  final local = _localPathIfAny(att.url);
  if (local != null) {
    _openLocalFile(context, local);
    return;
  }
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

/// Returns [url] as a local file path when it points at an existing file on
/// this device (decrypted E2EE attachments live in the temp dir), else null.
String? _localPathIfAny(String url) {
  if (url.isEmpty) return null;
  String path;
  if (url.startsWith('file:')) {
    path = Uri.parse(url).toFilePath();
  } else {
    path = url;
  }
  try {
    final file = File(path).existsSync();
    if (file) return path;
  } catch (_) {
    return null;
  }
  return null;
}

Future<void> _openLocalFile(BuildContext context, String path) async {
  final uri = Uri.file(path);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    return;
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open attachment')),
    );
  }
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
