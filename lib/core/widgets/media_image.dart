import 'package:flutter/material.dart';
import 'package:logging/logging.dart';

final Logger _imageLog = Logger('image');

/// A [Image.network] that never renders a blank area.
///
/// While loading it shows a muted placeholder; when the fetch fails it shows a
/// placeholder carrying the HTTP status code (e.g. "HTTP 404") when the
/// platform exposes one, so missing/broken media is visibly explained instead
/// of silently disappearing.
class MediaImage extends StatelessWidget {
  const MediaImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.alignment = Alignment.center,
    this.dark = false,
  });

  final String url;
  final BoxFit fit;
  final int? cacheWidth;
  final Alignment alignment;

  /// Renders the placeholder in light-on-dark colours (e.g. the full-screen
  /// black media preview).
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = dark ? Colors.black : theme.colorScheme.surfaceContainerHighest;
    return Image.network(
      url,
      fit: fit,
      cacheWidth: cacheWidth,
      alignment: alignment,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: bg,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: dark ? Colors.white54 : theme.colorScheme.primary,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stack) {
        final status = error is NetworkImageLoadException
            ? 'HTTP ${error.statusCode}'
            : error.toString();
        _imageLog.warning('image load failed: $url ($status)');
        return _MediaErrorPlaceholder(
          statusCode: error is NetworkImageLoadException
              ? error.statusCode
              : null,
          dark: dark,
        );
      },
    );
  }
}

class _MediaErrorPlaceholder extends StatelessWidget {
  final int? statusCode;
  final bool dark;

  const _MediaErrorPlaceholder({this.statusCode, required this.dark});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = dark
        ? Colors.white60
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      color: dark ? Colors.black : theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image_outlined, color: fg, size: 28),
          if (statusCode != null) ...[
            const SizedBox(height: 4),
            Text(
              'HTTP $statusCode',
              style: theme.textTheme.labelSmall?.copyWith(color: fg),
            ),
          ],
        ],
      ),
    );
  }
}
