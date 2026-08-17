import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

import 'cached_network_image.dart';

final Logger _imageLog = Logger('image');

/// A circular avatar backed by a remote image. Unlike [CircleAvatar] with a
/// raw [NetworkImage], a failed fetch (refused connection, HTTP error, broken
/// image) never throws an uncaught `FlutterError`: it logs a single warning
/// line — `image load failed: <url>: <error>` (carrying the HTTP status when
/// the platform exposes one) — and renders a placeholder carrying the HTTP
/// status code (e.g. "HTTP 404") or, when the URL was empty, the caller's
/// initials / fallback icon.
///
/// Use this everywhere a user / group / conversation / reply avatar is shown so
/// broken media is visibly explained instead of either disappearing or filling
/// the console with a full stack trace.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    this.imageUrl = '',
    this.radius = 22,
    this.initials = '',
    this.fallbackIcon = Icons.person,
    this.backgroundColor,
    this.foregroundColor,
  });

  /// Remote avatar URL. An empty value renders the initials / fallback icon.
  final String imageUrl;

  /// Circle radius in logical pixels.
  final double radius;

  /// Short string (typically a single capitalised letter) shown when the URL
  /// is empty. Takes precedence over [fallbackIcon] when non-empty.
  final String initials;

  /// Icon shown when the URL is empty and [initials] is empty.
  final IconData fallbackIcon;

  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = backgroundColor ?? theme.colorScheme.primaryContainer;
    final fg = foregroundColor ?? theme.colorScheme.onPrimaryContainer;
    final size = radius * 2;

    if (imageUrl.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: bg,
        foregroundColor: fg,
        child: initials.isNotEmpty
            ? Text(
                initials,
                style: TextStyle(fontSize: radius * 0.95),
              )
            : Icon(fallbackIcon, color: fg, size: radius),
      );
    }

    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: Image(
          image: CachedNetworkImageProvider(imageUrl),
          fit: BoxFit.cover,
          gaplessPlayback: true,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Container(
              color: bg,
              alignment: Alignment.center,
              child: SizedBox(
                width: radius,
                height: radius,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                  color: fg,
                ),
              ),
            );
          },
          errorBuilder: (context, error, stack) {
            final status = error is NetworkImageLoadException
                ? 'HTTP ${error.statusCode}'
                : error.toString();
            _imageLog.warning('image load failed: $imageUrl ($status)');
            return _AvatarError(
              message: status,
              bg: bg,
              fg: fg,
            );
          },
        ),
      ),
    );
  }
}

class _AvatarError extends StatelessWidget {
  final String message;
  final Color bg;
  final Color fg;

  const _AvatarError({
    required this.message,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final short = message.length > 12 ? message.substring(0, 12) : message;
    return Container(
      color: bg,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: fg, size: 18),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              short,
              maxLines: 1,
              style: TextStyle(
                color: fg,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
