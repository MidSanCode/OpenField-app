import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

/// A small blue verified badge shown next to verified usernames.
class VerifiedBadge extends StatelessWidget {
  final double size;

  const VerifiedBadge({super.key, this.size = 16});

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.verified, size: size, color: Colors.lightBlue);
    return Tooltip(
      message: 'verifiedAccount'.tr(),
      child: icon,
    );
  }
}

/// Inline row of a display name followed by a verified badge when enabled.
class VerifiedName extends StatelessWidget {
  final String name;
  final bool verified;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const VerifiedName({
    super.key,
    required this.name,
    required this.verified,
    this.style,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            name,
            style: style,
            maxLines: maxLines,
            overflow: overflow ?? TextOverflow.ellipsis,
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(),
        ],
      ],
    );
  }
}
