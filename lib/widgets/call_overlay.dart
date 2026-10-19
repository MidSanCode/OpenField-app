import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:openfield/data/services/call_service.dart';

/// Full-screen surface for an ongoing call.
///
/// The overlay is mounted from `MaterialApp.router`'s builder rather than a
/// route, because a call must survive navigation: pushing a page would be lost
/// the moment the user backs out or another page is pushed on top.
class CallOverlay extends StatelessWidget {
  /// Creates the overlay; it renders nothing while no call is visible.
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallService>(
      builder: (context, call, _) {
        if (!call.isVisible) return const SizedBox.shrink();
        return _CallSurface(call: call);
      },
    );
  }
}

/// The visible call screen: peer identity, status line and the control row.
class _CallSurface extends StatelessWidget {
  const _CallSurface({required this.call});

  final CallService call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incoming = call.isRinging;

    return Material(
      color: Colors.black.withValues(alpha: 0.92),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 32),
            Text(
              call.isVideo ? 'callVideoCall'.tr() : 'callAudioCall'.tr(),
              style: theme.textTheme.labelLarge?.copyWith(
                color: Colors.white70,
                letterSpacing: 1.2,
              ),
            ),
            const Spacer(),
            _PeerAvatar(call: call),
            const SizedBox(height: 20),
            Text(
              call.peerName.isNotEmpty ? call.peerName : 'callIncoming'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _statusText(call),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white70),
            ),
            if (call.error != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  call.error!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
            ],
            const Spacer(),
            _ControlRow(call: call, incoming: incoming),
            const SizedBox(height: 36),
          ],
        ),
      ),
    );
  }

  static String _statusText(CallService call) {
    switch (call.phase) {
      case CallPhase.dialing:
        return 'callDialing'.tr();
      case CallPhase.ringing:
        return 'callIncoming'.tr();
      case CallPhase.connecting:
        return 'callConnecting'.tr();
      case CallPhase.active:
        return _formatElapsed(call.elapsed);
      case CallPhase.ended:
        switch (call.endReason) {
          case 'declined':
            return 'callDeclined'.tr();
          case 'timeout':
            return 'callNoAnswer'.tr();
          case 'failed':
          case 'connection_failed':
            return 'callFailed'.tr();
          default:
            return call.isCaller && call.session?.isRinging == true
                ? 'callNoAnswer'.tr()
                : 'callEnded'.tr();
        }
      case CallPhase.idle:
        return '';
    }
  }

  /// Renders a call duration as `mm:ss` (hours are folded into minutes, since a
  /// call this app supports will not plausibly run past an hour).
  static String _formatElapsed(Duration elapsed) {
    final minutes = elapsed.inMinutes;
    final seconds = elapsed.inSeconds % 60;
    final buffer = StringBuffer()
      ..write(minutes.toString().padLeft(2, '0'))
      ..write(':')
      ..write(seconds.toString().padLeft(2, '0'));
    return buffer.toString();
  }
}

/// Peer avatar with a soft ring, falling back to an icon when no picture is
/// known (incoming calls carry no profile until the lookup lands).
class _PeerAvatar extends StatelessWidget {
  const _PeerAvatar({required this.call});

  final CallService call;

  @override
  Widget build(BuildContext context) {
    final url = call.peerAvatar;
    return Container(
      width: 132,
      height: 132,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.08),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url.isNotEmpty
          ? Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const _AvatarFallback(),
            )
          : const _AvatarFallback(),
    );
  }
}

/// Placeholder shown while the peer's picture is unknown.
class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Icon(Icons.person, size: 64, color: Colors.white38),
    );
  }
}

/// Accept/decline while ringing, otherwise mute, speaker and hang up.
class _ControlRow extends StatelessWidget {
  const _ControlRow({required this.call, required this.incoming});

  final CallService call;
  final bool incoming;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (incoming || call.phase == CallPhase.ended) {
      if (call.phase == CallPhase.ended) {
        return _RoundButton(
          icon: Icons.close,
          label: 'callClose'.tr(),
          color: theme.colorScheme.surfaceContainerHighest,
          foreground: Colors.white,
          onPressed: call.hangup,
        );
      }
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end,
            label: 'callDecline'.tr(),
            color: theme.colorScheme.error,
            foreground: Colors.white,
            onPressed: call.decline,
          ),
          _RoundButton(
            icon: Icons.call,
            label: 'callAnswer'.tr(),
            color: Colors.green.shade600,
            foreground: Colors.white,
            onPressed: call.accept,
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: call.isMuted ? Icons.mic_off : Icons.mic,
          label: call.isMuted ? 'callUnmute'.tr() : 'callMute'.tr(),
          color: call.isMuted
              ? Colors.white
              : Colors.white.withValues(alpha: 0.12),
          foreground: call.isMuted ? Colors.black : Colors.white,
          onPressed: call.toggleMute,
        ),
        _RoundButton(
          icon: call.isSpeakerOn ? Icons.volume_up : Icons.volume_down,
          label: 'callSpeaker'.tr(),
          color: call.isSpeakerOn
              ? Colors.white
              : Colors.white.withValues(alpha: 0.12),
          foreground: call.isSpeakerOn ? Colors.black : Colors.white,
          onPressed: call.toggleSpeaker,
        ),
        _RoundButton(
          icon: Icons.call_end,
          label: 'callHangUp'.tr(),
          color: Theme.of(context).colorScheme.error,
          foreground: Colors.white,
          onPressed: call.hangup,
        ),
      ],
    );
  }
}

/// One large circular control with a caption underneath.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 72,
          height: 72,
          child: Material(
            color: color,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: Icon(icon, size: 32, color: foreground),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}
