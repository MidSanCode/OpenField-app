import 'dart:ui' as ui;
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

/// Parses a "#RRGGBB" hex string into a [Color], or null when invalid/empty.
Color? nameColorFromHex(String hex, {double opacity = 1.0}) {
  final h = hex.replaceFirst('#', '').trim();
  if (h.length != 6) return null;
  final value = int.tryParse(h, radix: 16);
  if (value == null) return null;
  return Color((0xFF000000 | value) & 0xFFFFFFFF).withValues(alpha: opacity);
}

/// The display name of a membership tier (薄雾/篝火/明月/孤星), or empty for
/// non-members. Mirrors the server's catalog names.
String memberTierNameOf(int memberLevel) {
  switch (memberLevel) {
    case 1:
      return '薄雾';
    case 2:
      return '篝火';
    case 3:
      return '明月';
    case 4:
      return '孤星';
    default:
      return '';
  }
}

/// The accent color used for each membership tier badge.
Color memberTierColor(int memberLevel) {
  switch (memberLevel) {
    case 1:
      return const Color(0xFF9E9E9E); // 薄雾 mist grey
    case 2:
      return const Color(0xFFE64A19); // 篝火 fire orange
    case 3:
      return const Color(0xFF42A5F5); // 明月 moon blue
    case 4:
      return const Color(0xFF5B2C8E); // 孤星 lone star purple
    default:
      return const Color(0xFF9E9E9E);
  }
}

/// A pill showing the active membership tier name, rendered after the user's
/// display name and before the verification badge.
class MemberTierBadge extends StatelessWidget {
  final int memberLevel;
  final String tierName;
  final double textSize;

  const MemberTierBadge({
    super.key,
    required this.memberLevel,
    required this.tierName,
    this.textSize = 11,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = memberTierColor(memberLevel);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.55), width: 0.8),
      ),
      child: AnimatedDefaultTextStyle(
        duration: const Duration(milliseconds: 200),
        style: TextStyle(
          fontSize: textSize,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.brightness == Brightness.dark
              ? Color.alphaBlend(color.withValues(alpha: 0.35), theme.colorScheme.onSurface)
              : Color.alphaBlend(color, Colors.white),
        ),
        child: Text(tierName),
      ),
    );
  }
}

/// Inline row of a display name (optionally coloured / gradient / animated per
/// the user's membership name styling) followed by the membership tier badge
/// and the verified badge when enabled.
class VerifiedName extends StatefulWidget {
  final String name;
  final bool verified;
  final int memberLevel;
  final bool memberActive;
  final String memberTierName;
  final String nameColor;
  final String nameColorTo;
  final bool nameDynamic;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  const VerifiedName({
    super.key,
    required this.name,
    required this.verified,
    this.memberLevel = 0,
    this.memberActive = false,
    this.memberTierName = '',
    this.nameColor = '',
    this.nameColorTo = '',
    this.nameDynamic = false,
    this.style,
    this.maxLines,
    this.overflow,
  });

  /// Convenience constructor when only a plain verified name is needed.
  factory VerifiedName.simple({
    required String name,
    required bool verified,
    TextStyle? style,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    return VerifiedName(
      name: name,
      verified: verified,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  @override
  State<VerifiedName> createState() => _VerifiedNameState();
}

class _VerifiedNameState extends State<VerifiedName>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.nameDynamic && widget.memberActive) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant VerifiedName oldWidget) {
    super.didUpdateWidget(oldWidget);
    final animate = widget.nameDynamic && widget.memberActive;
    if (animate != _controller.isAnimating) {
      if (animate) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final dynamic = widget.nameDynamic && widget.memberActive;
    final color = nameColorFromHex(widget.nameColor);
    final colorTo = nameColorFromHex(widget.nameColorTo);
    final hasGradient =
        widget.memberActive && widget.nameColor.isNotEmpty && colorTo != null;

    Widget text = Text(
      widget.name,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.ellipsis,
      style: baseStyle.copyWith(color: color ?? baseStyle.color),
    );

    if (dynamic && color != null) {
      // Animated gradient name: the color sweep slides sideways in a seamless
      // loop while the membership is active.
      final end = colorTo ?? _shifted(color);
      text = AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [color, end, color, end, color],
              stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
              transform: _SlideGradient(-(_controller.value % 1.0) * bounds.width * 0.25),
            ).createShader(bounds),
            blendMode: BlendMode.srcATop,
            child: text,
          );
        },
      );
    } else if (hasGradient && color != null) {
      text = ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: [color, colorTo],
        ).createShader(bounds),
        blendMode: BlendMode.srcATop,
        child: text,
      );
    }

    final tierName = widget.memberActive && widget.memberLevel > 0
        ? (widget.memberTierName.isNotEmpty
            ? widget.memberTierName
            : memberTierNameOf(widget.memberLevel))
        : '';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: text),
        if (tierName.isNotEmpty) ...[
          const SizedBox(width: 5),
          MemberTierBadge(memberLevel: widget.memberLevel, tierName: tierName),
        ],
        if (widget.verified) ...[
          const SizedBox(width: 4),
          VerifiedBadge(),
        ],
      ],
    );
  }

  Color _shifted(Color base) {
    final brightness = Theme.of(context).colorScheme.brightness;
    return brightness == Brightness.dark
        ? Color.alphaBlend(base.withValues(alpha: 0.6), Colors.black)
        : Color.alphaBlend(base, Colors.white);
  }
}

/// A gradient transform that slides the pattern sideways by [dx] pixels so the
/// animated name's color sweep loops seamlessly.
class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.dx);

  final double dx;

  @override
  Matrix4? transform(Rect bounds, {ui.TextDirection? textDirection}) {
    return Matrix4.identity()..setTranslationRaw(dx, 0, 0);
  }
}