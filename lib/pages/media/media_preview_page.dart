import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:openfield/core/widgets/media_image.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/api_service.dart';
import 'package:openfield/widgets/attachment_view.dart';

/// Full-screen in-app preview for an attachment: images are zoomable and
/// rotatable (desktop buttons + mobile gestures), videos and audio play
/// through media_kit with progress/pause/fullscreen controls and streaming.
class MediaPreviewPage extends StatefulWidget {
  final Attachment attachment;

  const MediaPreviewPage({super.key, required this.attachment});

  @override
  State<MediaPreviewPage> createState() => _MediaPreviewPageState();
}

class _MediaPreviewPageState extends State<MediaPreviewPage> {
  Player? _player;
  VideoController? _videoController;
  bool _openFailed = false;

  // Image view state.
  final TransformationController _transformController = TransformationController();
  int _rotation = 0; // multiples of 90 degrees
  double _zoom = 1.0;

  /// Decoded pixel dimensions of the image (null until loaded).
  int? _imageWidth;
  int? _imageHeight;

  // Save-to-device state.
  double? _saveProgress;
  bool _saveFailed = false;

  bool get _isPlayable => widget.attachment.isVideo || widget.attachment.isAudio;

  @override
  void initState() {
    super.initState();
    if (widget.attachment.isImage) {
      _decodeDimensions();
    }
    if (_isPlayable) {
      _initPlayer();
    }
  }

  /// Reads the pixel dimensions of the displayed image from the already
  /// resolved image cache (network or local file), for the metadata sheet.
  Future<void> _decodeDimensions() async {
    final att = widget.attachment;
    if (att.url.isEmpty || att.mimeType.contains('svg')) return;
    final ImageProvider provider;
    final uri = Uri.tryParse(att.url);
    if (uri != null && uri.scheme.startsWith('http')) {
      provider = NetworkImage(att.url);
    } else {
      if (!File(att.url).existsSync()) return;
      provider = FileImage(File(att.url));
    }
    try {
      final stream = provider.resolve(ImageConfiguration.empty);
      final completer = Completer<ImageInfo>();
      late ImageStreamListener listener;
      listener = ImageStreamListener(
        (info, _) {
          if (!completer.isCompleted) completer.complete(info);
          stream.removeListener(listener);
        },
        onError: (_, _) {
          if (!completer.isCompleted) completer.completeError('load failed');
          stream.removeListener(listener);
        },
      );
      stream.addListener(listener);
      final info =
          await completer.future.timeout(const Duration(seconds: 15));
      info.image.dispose();
      if (!mounted) return;
      setState(() {
        _imageWidth = info.image.width;
        _imageHeight = info.image.height;
      });
    } catch (_) {
      // Dimensions stay unknown; the metadata sheet shows a dash.
    }
  }

  @override
  void dispose() {
    _player?.dispose();
    _transformController.dispose();
    super.dispose();
  }

  Future<void> _initPlayer() async {
    try {
      final player = Player();
      if (widget.attachment.isVideo) {
        _videoController = VideoController(player);
      }
      await player.open(Media(widget.attachment.url), play: true);
      if (!mounted) {
        player.dispose();
        return;
      }
      setState(() {
        _player = player;
        _openFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => _openFailed = true);
    }
  }

  void _rotate(int steps) {
    setState(() => _rotation = (_rotation + steps) % 4);
  }

  void _zoomBy(double factor) {
    final next = (_zoom * factor).clamp(1.0, 8.0);
    setState(() => _zoom = next);
    _transformController.value = Matrix4.diagonal3Values(next, next, 1);
  }

  void _resetView() {
    setState(() {
      _zoom = 1.0;
      _rotation = 0;
    });
    _transformController.value = Matrix4.identity();
  }

  /// Bottom sheet listing the attachment's metadata: name, type, size, pixel
  /// dimensions (images), upload time, visibility and E2EE state.
  void _showMetadataSheet() {
    final att = widget.attachment;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(label,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Text(value, style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            );
        final mime = att.isEncrypted && att.originalMime.isNotEmpty
            ? '${att.originalMime} (E2EE)'
            : att.mimeType;
        final visibility = switch (att.visibility) {
          'private' => 'visibilityPrivate'.tr(),
          'restricted' => 'visibilityFriends'.tr(),
          _ => 'visibilityPublic'.tr(),
        };
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('metadataTitle'.tr(),
                        style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                row('metaName'.tr(), att.originalName),
                row('metaType'.tr(), mime.isEmpty ? '-' : mime),
                row('metaSize'.tr(), formatBytes(att.sizeBytes)),
                if (att.isImage)
                  row('metaDimensions'.tr(),
                      _imageWidth != null ? '$_imageWidth × $_imageHeight' : '-'),
                if (att.createdAt != null)
                  row('metaUploadedAt'.tr(),
                      MaterialLocalizations.of(sheetContext)
                          .formatFullDate(att.createdAt!)),
                row('metaVisibility'.tr(), visibility),
                row('metaId'.tr(), '#${att.id}'),
                if (att.bucket.isNotEmpty) row('metaBucket'.tr(), att.bucket),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Downloads the attachment to the device temp dir with progress feedback
  /// on the app-bar button, then opens it externally.
  Future<void> _saveToDevice() async {
    final att = widget.attachment;
    try {
      setState(() {
        _saveProgress = 0;
        _saveFailed = false;
      });
      final dir = await getTemporaryDirectory();
      final safeName = att.originalName.isNotEmpty
          ? att.originalName
          : 'attachment-${att.id}';
      final savePath =
          '${dir.path}${Platform.pathSeparator}of_dl_${DateTime.now().millisecondsSinceEpoch}_$safeName';
      await ApiService().downloadToFile(att.url, savePath,
          onProgress: (received, total) {
        if (!mounted) return;
        setState(() {
          _saveProgress =
              total != null && total > 0 ? received / total : 0.5;
        });
      });
      if (!mounted) return;
      setState(() => _saveProgress = null);
      openAttachmentUrl(context, Uri.file(savePath).toString());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saveProgress = null;
        _saveFailed = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final att = widget.attachment;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          att.originalName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          if (att.isImage) ...[
            IconButton(
              icon: const Icon(Icons.rotate_left),
              tooltip: 'Rotate left',
              onPressed: () => _rotate(-1),
            ),
            IconButton(
              icon: const Icon(Icons.rotate_right),
              tooltip: 'Rotate right',
              onPressed: () => _rotate(1),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_in),
              tooltip: 'Zoom in',
              onPressed: () => _zoomBy(1.5),
            ),
            IconButton(
              icon: const Icon(Icons.zoom_out),
              tooltip: 'Zoom out',
              onPressed: () => _zoomBy(1 / 1.5),
            ),
            IconButton(
              icon: const Icon(Icons.fit_screen_outlined),
              tooltip: 'Reset',
              onPressed: _resetView,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'metadataTitle'.tr(),
            onPressed: _showMetadataSheet,
          ),
          IconButton(
            icon: _saveProgress != null
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    _saveFailed ? Icons.error_outline : Icons.download_outlined,
                  ),
            tooltip: 'attachmentDownload'.tr(),
            onPressed: _saveProgress == null ? _saveToDevice : null,
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open externally',
            onPressed: () => openAttachmentUrl(context, att.url),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: att.isImage
              ? _buildImage(att)
              : _buildPlayable(att),
        ),
      ),
    );
  }

  Widget _buildImage(Attachment att) {
    // Rotation is applied outside so InteractiveViewer gestures keep working.
    final angle = _rotation * math.pi / 2;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: InteractiveViewer(
            transformationController: _transformController,
            maxScale: 8,
            minScale: 0.5,
            child: Transform.rotate(
              angle: angle,
              child: Center(
                child: MediaImage(
                  url: att.url,
                  fit: BoxFit.contain,
                  dark: true,
                ),
              ),
            ),
          ),
        ),
        // Mobile gesture hint.
        Positioned(
          left: 0,
          right: 0,
          bottom: 16,
          child: IgnorePointer(
            child: Center(
              child: Text(
                'Pinch to zoom · drag to pan',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlayable(Attachment att) {
    if (_openFailed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
            'Unable to play this file',
            style: TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              setState(() => _openFailed = false);
              _initPlayer();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    if (_player == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (widget.attachment.isVideo && _videoController != null) {
      // Video() ships with adaptive controls (play/pause, progress bar,
      // volume, fullscreen) and streams from the URL.
      return Video(
        controller: _videoController!,
        controls: AdaptiveVideoControls,
        onEnterFullscreen: () async {
          // Optional: keep the screen awake while watching fullscreen.
        },
      );
    }

    return _buildAudioPlayer(att);
  }

  Widget _buildAudioPlayer(Attachment att) {
    final player = _player!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.audio_file, color: Colors.white, size: 72),
          const SizedBox(height: 12),
          Text(
            att.originalName,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 24),
          StreamBuilder<bool>(
            stream: player.stream.playing,
            initialData: player.state.playing,
            builder: (context, snapshot) {
              final playing = snapshot.data ?? false;
              return IconButton(
                iconSize: 64,
                color: Colors.white,
                icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                onPressed: () => player.playOrPause(),
              );
            },
          ),
          const SizedBox(height: 8),
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
                  final max = duration.inMilliseconds > 0
                      ? duration.inMilliseconds.toDouble()
                      : 1.0;
                  final value = position.inMilliseconds
                      .clamp(0, duration.inMilliseconds)
                      .toDouble();
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(
                        value: value,
                        max: max,
                        activeColor: Colors.white,
                        inactiveColor: Colors.white30,
                        onChanged: (v) {
                          player.seek(Duration(milliseconds: v.round()));
                        },
                      ),
                      Text(
                        '${_fmt(position)} / ${_fmt(duration)}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}
