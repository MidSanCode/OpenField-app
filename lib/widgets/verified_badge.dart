import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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

/// Maps a gradient direction key (as stored by the server) to a begin/end
/// alignment pair. Unknown or empty values default to left→right.
(Alignment, Alignment) gradientDirectionOf(String direction) {
  switch (direction) {
    case 'right_left':
      return (Alignment.centerRight, Alignment.centerLeft);
    case 'top_bottom':
      return (Alignment.topCenter, Alignment.bottomCenter);
    case 'bottom_top':
      return (Alignment.bottomCenter, Alignment.topCenter);
    case 'top_left_bottom_right':
      return (Alignment.topLeft, Alignment.bottomRight);
    case 'bottom_left_top_right':
      return (Alignment.bottomLeft, Alignment.topRight);
    case 'left_right':
    default:
      return (Alignment.centerLeft, Alignment.centerRight);
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
  final List<String> nameColors;
  final String nameGradientDirection;
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
    this.nameColors = const [],
    this.nameGradientDirection = '',
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

class _VerifiedNameState extends State<VerifiedName> {
  bool get _shouldAnimate => widget.nameDynamic && widget.memberActive;

  @override
  void initState() {
    super.initState();
    if (_shouldAnimate) _NameGradientClock.instance.acquire();
  }

  @override
  void didUpdateWidget(covariant VerifiedName oldWidget) {
    super.didUpdateWidget(oldWidget);
    final wasAnimating = oldWidget.nameDynamic && oldWidget.memberActive;
    if (_shouldAnimate != wasAnimating) {
      if (_shouldAnimate) {
        _NameGradientClock.instance.acquire();
      } else {
        _NameGradientClock.instance.release();
      }
    }
  }

  @override
  void dispose() {
    if (_shouldAnimate) _NameGradientClock.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseStyle = widget.style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    final dynamic = widget.nameDynamic && widget.memberActive;
    final color = nameColorFromHex(widget.nameColor);
    final colorTo = nameColorFromHex(widget.nameColorTo);

    // The effective gradient color list: the server-side multi-color array wins
    // (Lv.3+ gradient), otherwise fall back to the legacy color/color_to pair.
    List<Color> gradientColors = [];
    if (widget.memberActive && widget.nameColors.isNotEmpty) {
      gradientColors = widget.nameColors
          .map(nameColorFromHex)
          .whereType<Color>()
          .toList();
    } else if (color != null) {
      gradientColors = [color, ?colorTo];
    }
    final hasGradient = widget.memberActive && gradientColors.length >= 2;
    final beginEnd = gradientDirectionOf(widget.nameGradientDirection);

    Widget text = Text(
      widget.name,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.ellipsis,
      style: baseStyle.copyWith(color: color ?? baseStyle.color),
    );

    if (dynamic && gradientColors.isNotEmpty) {
      // Animated gradient name: the color sweep slides sideways in a seamless
      // loop while the membership is active. All animated names share the
      // single app-wide [_NameGradientClock] ticker (instead of one
      // AnimationController + ShaderMask rebuild per name, which freezes feeds
      // full of member names); the gradient config is constant so it is built
      // once, and the animation is wrapped in a RepaintBoundary so only the
      // name repaints each tick rather than its whole list row.
      final colors = [...gradientColors, ...gradientColors];
      final stops = [
        for (var i = 0; i < gradientColors.length; i++)
          i / gradientColors.length / 2,
        for (var i = 0; i < gradientColors.length; i++)
          i / gradientColors.length / 2 + 0.5,
      ];
      text = RepaintBoundary(
        child: AnimatedBuilder(
          animation: _NameGradientClock.instance,
          builder: (context, _) {
            return ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: colors,
                stops: stops,
                begin: beginEnd.$1,
                end: beginEnd.$2,
                transform: _SlideGradient(
                  -(_NameGradientClock.instance.t % 1.0) * bounds.width * 0.5,
                ),
              ).createShader(bounds),
              blendMode: BlendMode.srcATop,
              child: text,
            );
          },
        ),
      );
    } else if (hasGradient) {
      text = ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: gradientColors,
          begin: beginEnd.$1,
          end: beginEnd.$2,
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

/// A single app-wide animation clock for animated gradient names.
///
/// Previously every animated [VerifiedName] created its own
/// `AnimationController` at 60fps, each rebuilding a `ShaderMask` on every
/// frame. With many member names on screen at once (feed cards, chat, member
/// lists) that saturated the engine and visibly froze the app. Instead all
/// animated names subscribe to one lazy ticker: the clock runs only while at
/// least one animated name is mounted, and every name sweeps in lockstep off
/// the shared 0..1 progress value.
class _NameGradientClock extends ChangeNotifier implements TickerProvider {
  _NameGradientClock._();

  static final _NameGradientClock _instance = _NameGradientClock._();

  /// The shared app-wide clock.
  static _NameGradientClock get instance => _instance;

  static const Duration period = Duration(seconds: 3);

  Ticker? _ticker;
  int _users = 0;
  double _t = 0;

  /// The current 0..1 animation progress.
  double get t => _t;

  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);

  /// Called when an animated name is mounted: starts the shared ticker.
  void acquire() {
    _users++;
    _ticker ??= createTicker(_onTick)..start();
  }

  /// Called when an animated name is disposed: stops the ticker when the last
  /// one goes away so the app does not keep a per-frame ticker running idle.
  void release() {
    if (_users > 0) _users--;
    if (_users == 0 && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
  }

  void _onTick(Duration elapsed) {
    _t = (elapsed.inMilliseconds % period.inMilliseconds) /
        period.inMilliseconds;
    notifyListeners();
  }
}