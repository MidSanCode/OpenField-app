import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:openfield/data/models/attachment.dart';
import 'package:openfield/data/services/encrypted_attachment_service.dart';

/// A voice-message bubble for one audio [attachment]: play/pause, duration and
/// a seekable progress bar. Plain attachments stream from their URL; E2EE
/// attachments are decrypted to a local temp file first (the group key is
/// scoped per conversation).
class VoiceMessageBubble extends StatefulWidget {
  final Attachment attachment;
  final int? conversationId;

  const VoiceMessageBubble({
    super.key,
    required this.attachment,
    this.conversationId,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  Player? _player;
  String? _resolvedSource;
  bool _loading = true;
  bool _failed = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;

  Attachment get attachment => widget.attachment;

  @override
  void initState() {
    super.initState();
    _resolveAndPrepare();
  }

  Future<void> _resolveAndPrepare() async {
    try {
      if (attachment.isEncrypted) {
        final conv = widget.conversationId;
        if (conv == null) throw Exception('missing conversation');
        final path = await EncryptedAttachmentService.instance
            .decryptToFile(conv, attachment);
        _resolvedSource = path;
      } else {
        _resolvedSource = attachment.url;
      }

      // Prepare the player paused so the real duration is known before the
      // first play.
      final player = Player();
      await player.open(Media(_resolvedSource!), play: false);
      if (!mounted) {
        await player.dispose();
        return;
      }
      _player = player;
      _duration = player.state.duration;
      _subscribe(player);
      setState(() {
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

  void _subscribe(Player player) {
    _posSub = player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _durSub = player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playingSub = player.stream.playing.listen((v) {
      if (mounted) setState(() => _playing = v);
    });
    _completedSub = player.stream.completed.listen((done) {
      if (done && mounted) setState(() => _position = Duration.zero);
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(maxWidth: 280),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(10),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_failed || _player == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 18, color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text('voiceUnavailable'.tr())),
            TextButton(
              onPressed: () {
                setState(() {
                  _failed = false;
                  _loading = true;
                });
                _resolveAndPrepare();
              },
              child: Text('retry'.tr()),
            ),
          ],
        ),
      );
    }

    final totalMs = _duration.inMilliseconds.clamp(1, 1 << 40);
    final sliderValue = _position.inMilliseconds.clamp(0, totalMs).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              iconSize: 28,
              icon: Icon(
                _playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                color: theme.colorScheme.primary,
              ),
              tooltip: _playing ? 'pause'.tr() : 'play'.tr(),
              onPressed: () => _player!.playOrPause(),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 10),
                  padding: EdgeInsets.zero,
                ),
                child: Slider(
                  value: sliderValue,
                  max: totalMs.toDouble(),
                  onChanged: (v) {
                    _player!.seek(Duration(milliseconds: v.round()));
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                _fmt(_playing || sliderValue > 0 ? _position : _duration),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _fmt(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${two(s)}';
  }
}
