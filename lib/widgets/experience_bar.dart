import 'package:flutter/material.dart';
import 'package:openfield/data/models/user.dart';

/// Level + tier name + a colour-coded experience bar. The bar takes the colour
/// (or gradient) of the user's current tier so progress is tinted per tier.
class ExperienceBar extends StatelessWidget {
  const ExperienceBar({super.key, required this.user, this.onTap});

  final User user;

  /// Optional tap handler (e.g. opens the exp history page). When null the bar
  /// renders as before without any hit area.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierColor = user.tierColor;
    final gradient = user.tierGradient;
    // Progress is the ratio of the user's total exp to the total exp required
    // to reach the next level (cumulative, so earned exp is never lost between
    // levels). A minimal sliver keeps the bar visibly filled even at small exp.
    final progress = user.levelProgress.clamp(0.02, 1.0);
    final expTotal = '${user.exp}';
    final expNext = '${user.totalExpForNextLevel}';

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Lv.${user.level}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if (user.tierName.isNotEmpty) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  user.tierName,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: tierColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              '$expTotal / $expNext',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                // The whole track takes the tier colour (softly tinted) so the
                // entire bar changes colour as the user climbs tiers, not just
                // the filled portion.
                Container(color: tierColor.withValues(alpha: 0.18)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: gradient.isNotEmpty
                      ? DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: gradient,
                            ),
                          ),
                        )
                      : ColoredBox(color: tierColor),
                ),
              ],
            ),
          ),
        ),
      ],
    );

    final onTap = this.onTap;
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: content,
      ),
    );
  }
}
