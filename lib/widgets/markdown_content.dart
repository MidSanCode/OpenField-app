import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

/// Renders markdown content with a consistent style. Falls back gracefully to
/// plain text rendering for malformed input.
class MarkdownContent extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final EdgeInsetsGeometry padding;
  final bool selectable;

  const MarkdownContent({
    super.key,
    required this.data,
    this.style,
    this.padding = EdgeInsets.zero,
    this.selectable = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = style ?? theme.textTheme.bodyMedium;
    return Padding(
      padding: padding,
      child: MarkdownBody(
        data: data,
        selectable: selectable,
        styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
          p: baseStyle,
          blockquoteDecoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        ),
      ),
    );
  }
}
