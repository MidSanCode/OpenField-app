import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:openfield/data/models/attachment.dart';
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

  bool get _isPlayable => widget.attachment.isVideo || widget.attachment.isAudio;

  @override
  void initState() {
    super.initState();
    if (_isPlayable) {
      _initPlayer();
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
                child: Image.network(
                  att.url,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    );
                  },
                  errorBuilder: (context, error, stack) => const Icon(
                    Icons.broken_image_outlined,
                    size: 48,
                    color: Colors.white,
                  ),
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
