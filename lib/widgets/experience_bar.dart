import 'package:flutter/material.dart';
import 'package:openfield/data/models/user.dart';

/// Level + tier name + a colour-coded experience bar. The bar takes the colour
/// (or gradient) of the user's current tier so progress is tinted per tier.
class ExperienceBar extends StatelessWidget {
  const ExperienceBar({super.key, required this.user});

  final User user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tierColor = user.tierColor;
    final gradient = user.tierGradient;
    final progress = user.levelProgress.clamp(0.0, 1.0);

    return Column(
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
              '${user.expIntoLevel} / ${user.expForNextLevel}',
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
                Container(color: theme.colorScheme.surfaceContainerHighest),
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
  }
}
