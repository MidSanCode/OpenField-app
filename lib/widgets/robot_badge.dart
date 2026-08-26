import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The small robot glyph rendered after a bot account's display name.
///
/// Bots are ordinary accounts in every other respect; this badge is the only
/// visual difference, so it stays subtle: a filled rounded chip with a robot
/// icon that scales with the surrounding text.
class RobotBadge extends StatelessWidget {
  /// Height of the badge in logical pixels; defaults relative to ambient text.
  final double size;

  /// Explicit color override (defaults derive from the theme).
  final Color? color;

  const RobotBadge({super.key, this.size = 14, this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor =
        color ?? theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85);
    return Tooltip(
      message: 'botBadgeTooltip'.tr(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        padding: EdgeInsets.all(size * 0.16),
        child: Icon(
          Icons.smart_toy_outlined,
          size: size * 0.68,
          color: effectiveColor,
        ),
      ),
    );
  }
}
