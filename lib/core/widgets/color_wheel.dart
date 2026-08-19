import 'dart:math' as math;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A circular HSV color wheel: dragging around the disc picks hue (angle) and
/// saturation (radius from the white centre); a value slider below controls
/// brightness. Self-contained with no third-party dependencies, used by the
/// app theme color picker and the member display-name color editor.
class ColorWheel extends StatefulWidget {
  final Color initialColor;
  final double size;
  final ValueChanged<Color>? onChanged;

  const ColorWheel({
    super.key,
    required this.initialColor,
    this.size = 220,
    this.onChanged,
  });

  @override
  State<ColorWheel> createState() => _ColorWheelState();
}

class _ColorWheelState extends State<ColorWheel> {
  late HSVColor _hsv;
  double _value = 1.0;
  double _sat = 0;

  @override
  void initState() {
    super.initState();
    _applyInitial(widget.initialColor);
  }

  @override
  void didUpdateWidget(ColorWheel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialColor != widget.initialColor) {
      _applyInitial(widget.initialColor);
    }
  }

  void _applyInitial(Color color) {
    _hsv = HSVColor.fromColor(color);
    _value = _hsv.value;
    _sat = _hsv.saturation;
  }

  void _updateFromPosition(Offset local, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final delta = local - center;
    final distance = delta.distance;
    final maxR = size.shortestSide / 2;
    final hue = (math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360;
    final sat = (distance / maxR).clamp(0.0, 1.0);
    setState(() {
      _sat = sat;
      _hsv = HSVColor.fromAHSV(1, hue, sat, _value);
    });
    widget.onChanged?.call(_hsv.toColor());
  }

  Offset _markerOffset(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final angleRads = _hsv.hue * math.pi / 180;
    final r = _hsv.saturation * size.shortestSide / 2;
    return center + Offset(math.cos(angleRads) * r, math.sin(angleRads) * r);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wheelSize = Size.square(widget.size);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onPanDown: (d) => _updateFromPosition(d.localPosition, wheelSize),
          onPanUpdate: (d) => _updateFromPosition(d.localPosition, wheelSize),
          child: SizedBox.fromSize(
            size: wheelSize,
            child: Stack(
              children: [
                CustomPaint(
                  painter: _WheelPainter(value: _value),
                  size: wheelSize,
                ),
                // Value dimming: multiplying the bright disc by black.
                IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 1 - _value),
                    ),
                  ),
                ),
                Builder(builder: (context) {
                  final offset = _markerOffset(wheelSize);
                  return Positioned(
                    left: offset.dx - 9,
                    top: offset.dy - 9,
                    child: IgnorePointer(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.transparent,
                          border: Border.all(
                            color: theme.colorScheme.onSurface,
                            width: 3,
                          ),
                          boxShadow: const [
                            BoxShadow(color: Colors.white70, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const Icon(Icons.brightness_low_outlined, size: 18),
            Expanded(
              child: Slider(
                value: _value,
                onChanged: (v) {
                  setState(() {
                    _value = v;
                    _hsv = HSVColor.fromAHSV(1, _hsv.hue, _sat, v);
                  });
                  widget.onChanged?.call(_hsv.toColor());
                },
              ),
            ),
            const Icon(Icons.brightness_high_outlined, size: 18),
          ],
        ),
      ],
    );
  }
}

/// Paints the hue×saturation disc at a fixed [value]: a full saturation sweep
/// of hues faded to white at the centre (so the middle is white / S=0).
class _WheelPainter extends CustomPainter {
  final double value;

  _WheelPainter({required this.value});

  static const List<Color> _hueStops = [
    Color(0xFFFF0000), // red
    Color(0xFFFFFF00), // yellow
    Color(0xFF00FF00), // green
    Color(0xFF00FFFF), // cyan
    Color(0xFF0000FF), // blue
    Color(0xFFFF00FF), // magenta
    Color(0xFFFF0000), // red
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final sweep = Paint()
      ..shader = const SweepGradient(
        colors: _hueStops,
        startAngle: 0,
        endAngle: math.pi * 2,
      ).createShader(rect);
    canvas.drawCircle(center, radius, sweep);

    // Fade toward white at the centre: saturation drops to 0 in the middle.
    final whiteFade = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawCircle(center, radius, whiteFade);

    // Soft edge shadow for depth.
    final edge = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.black.withValues(alpha: 0.0),
          Colors.black.withValues(alpha: 0.18),
        ],
        stops: const [0.82, 1.0],
      ).createShader(rect);
    canvas.drawCircle(center, radius, edge);
  }

  @override
  bool shouldRepaint(covariant _WheelPainter oldDelegate) =>
      oldDelegate.value != value;
}

/// Opens a dialog hosting a [ColorWheel] with a confirmation footer. Returns
/// the picked color, or null when cancelled.
Future<Color?> showColorWheelDialog({
  required BuildContext context,
  required Color initialColor,
  String? title,
}) async {
  Color? picked = initialColor;
  return showDialog<Color>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title ?? 'colorWheelTitle'.tr()),
      content: StatefulBuilder(
        builder: (context, setState) {
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ColorWheel(
                  initialColor: picked ?? initialColor,
                  onChanged: (c) => setState(() => picked = c),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: picked ?? initialColor,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _hexOf(picked ?? initialColor),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text('cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(picked ?? initialColor),
          child: Text('confirm'.tr()),
        ),
      ],
    ),
  );
}

/// Formats a [Color] as an uppercase "#RRGGBB" string.
String _hexOf(Color color) {
  return '#${(color.r * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(color.g * 255).round().toRadixString(16).padLeft(2, '0')}'
      '${(color.b * 255).round().toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}