import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/widgets/attachment_view.dart';

/// Full-screen in-app preview for an attachment: images are zoomable,
/// videos and audio play through media_kit.
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

  bool get _isPlayable => widget.attachment.isVideo || widget.attachment.isAudio;

  @override
  void initState() {
    super.initState();
    if (_isPlayable) {
      _initPlayer();
    }
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

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
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
    return InteractiveViewer(
      maxScale: 6,
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
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Video(controller: _videoController!),
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
