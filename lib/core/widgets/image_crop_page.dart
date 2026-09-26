import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

/// Arguments for the isolate that performs the actual pixel crop. Every field
/// is isolate-sendable (no closures, no Flutter objects).
class _CropRequest {
  const _CropRequest({
    required this.bytes,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.maxOutputWidth,
    required this.preferPng,
  });

  final Uint8List bytes;
  final int x;
  final int y;
  final int width;
  final int height;
  final int maxOutputWidth;
  final bool preferPng;
}

/// Base (scale 1) displayed size: [imageSize] cover-fitted into [frame], so the
/// image always fills the crop frame at minimum zoom.
@visibleForTesting
Size cropBaseSize(Size imageSize, Rect frame) {
  final imageAspect = imageSize.width / imageSize.height;
  final frameAspect = frame.width / frame.height;
  if (imageAspect > frameAspect) {
    // Wider than the frame: match the height, overflow horizontally.
    return Size(frame.height * imageAspect, frame.height);
  }
  return Size(frame.width, frame.width / imageAspect);
}

/// Source-image rectangle currently visible inside [frame], given the viewer's
/// [offset] (displayed centre relative to the frame centre) and [scale].
///
/// This is the single source of truth for the viewport → pixel mapping; the
/// on-screen preview and the exported crop both derive from it.
@visibleForTesting
Rect cropSourceRect({
  required Rect frame,
  required Offset offset,
  required double scale,
  required Size imageSize,
}) {
  final base = cropBaseSize(imageSize, frame);
  final displayed = Size(base.width * scale, base.height * scale);
  final displayedLeft = frame.center.dx + offset.dx - displayed.width / 2;
  final displayedTop = frame.center.dy + offset.dy - displayed.height / 2;

  final scaleX = imageSize.width / displayed.width;
  final scaleY = imageSize.height / displayed.height;
  return Rect.fromLTWH(
    (frame.left - displayedLeft) * scaleX,
    (frame.top - displayedTop) * scaleY,
    frame.width * scaleX,
    frame.height * scaleY,
  );
}

/// Clamps [offset] so an image displayed at [displayed] always covers [frame].
@visibleForTesting
Offset cropClampOffset(Offset offset, Rect frame, Size displayed) {
  final maxDx = math.max(0.0, (displayed.width - frame.width) / 2);
  final maxDy = math.max(0.0, (displayed.height - frame.height) / 2);
  return Offset(
    offset.dx.clamp(-maxDx, maxDx),
    offset.dy.clamp(-maxDy, maxDy),
  );
}

/// Crops [req] with the pure-Dart `image` package and returns the encoded
/// result. Runs off the UI isolate (on web it degrades to the main isolate,
/// which is still correct, just not concurrent).
///
/// Throws [StateError] when the payload cannot be decoded. The `image` package
/// both returns null and throws [RangeError] on malformed input, so both are
/// normalised into the one error type callers handle.
Uint8List _cropInIsolate(_CropRequest req) {
  image.Image? decoded;
  try {
    decoded = image.decodeImage(req.bytes);
  } catch (_) {
    throw StateError('decode failed');
  }
  if (decoded == null) {
    throw StateError('decode failed');
  }

  // Clamp the rectangle to the image so rounding can never push it outside.
  // (int.clamp is typed as num, hence the explicit toInt().)
  final x = req.x.clamp(0, math.max(0, decoded.width - 1)).toInt();
  final y = req.y.clamp(0, math.max(0, decoded.height - 1)).toInt();
  final w = req.width.clamp(1, decoded.width - x).toInt();
  final h = req.height.clamp(1, decoded.height - y).toInt();

  var out = image.copyCrop(decoded, x: x, y: y, width: w, height: h);
  if (req.maxOutputWidth > 0 && out.width > req.maxOutputWidth) {
    out = image.copyResize(out, width: req.maxOutputWidth);
  }

  // PNG keeps transparency (icons, logos); JPEG keeps photos small.
  if (req.preferPng) {
    return Uint8List.fromList(image.encodePng(out));
  }
  return Uint8List.fromList(image.encodeJpg(out, quality: 92));
}

/// Builds the isolate payload from a crop rectangle in source-image pixels.
_CropRequest _cropRequest({
  required Uint8List bytes,
  required Rect source,
  required int maxOutputWidth,
  required bool preferPng,
}) {
  return _CropRequest(
    bytes: bytes,
    x: source.left.round(),
    y: source.top.round(),
    width: source.width.round(),
    height: source.height.round(),
    maxOutputWidth: maxOutputWidth,
    preferPng: preferPng,
  );
}

/// Crops [bytes] to [source] (source-image pixels, as produced by
/// [cropSourceRect]) and returns the encoded result synchronously.
///
/// The widget uses the same routine through `compute`; this entry point exists
/// so the pixel chain can be exercised without a widget tree.
Uint8List cropImageBytes({
  required Uint8List bytes,
  required Rect source,
  int maxOutputWidth = 1024,
  bool preferPng = false,
}) {
  return _cropInIsolate(_cropRequest(
    bytes: bytes,
    source: source,
    maxOutputWidth: maxOutputWidth,
    preferPng: preferPng,
  ));
}

/// Key for the gesture surface, so tests can measure the actual crop area
/// (which excludes the controls below it).
const Key cropAreaKey = ValueKey('image-crop-area');

/// A full-screen image cropper: the picked image sits under a fixed crop frame
/// with the requested aspect ratio; the user pans and pinches to choose the
/// visible region, and the result is returned as encoded bytes.
///
/// The pixel work runs through the pure-Dart `image` package rather than a
/// native cropper plugin, so the same code path works on Windows, Linux, macOS,
/// iOS, Android and Web. Pops with `Uint8List?` — the cropped image, or null
/// when the user cancels.
class ImageCropPage extends StatefulWidget {
  /// Creates a cropper for [bytes].
  const ImageCropPage({
    super.key,
    required this.bytes,
    this.aspectRatio = 1,
    this.title = '',
    this.maxOutputWidth = 1024,
    this.preferPng = false,
  });

  /// Source image bytes (already read from the picker, so this works on web).
  final Uint8List bytes;

  /// Width / height of the crop frame. `1` = square (avatars, icons).
  final double aspectRatio;

  /// App-bar title; empty falls back to a generic "crop image" label.
  final String title;

  /// Upper bound for the exported width, so a 12 MP photo does not become a
  /// multi-megabyte avatar. Height follows the crop aspect ratio.
  final int maxOutputWidth;

  /// Encode the result as PNG (keeps transparency) instead of JPEG.
  final bool preferPng;

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  /// Decoded source dimensions, resolved through the platform codec (cheap)
  /// rather than the `image` package (which we only pay for on confirm).
  int _imageWidth = 0;
  int _imageHeight = 0;
  bool _ready = false;
  bool _failed = false;
  bool _busy = false;

  /// Zoom relative to the cover-fit base size; never below 1 so the frame is
  /// always fully covered.
  double _scale = 1;
  /// Translation of the displayed image centre from the crop-frame centre, in
  /// viewport logical pixels.
  Offset _offset = Offset.zero;

  double _scaleAtGestureStart = 1;
  Offset _offsetAtGestureStart = Offset.zero;
  Offset _focalAtGestureStart = Offset.zero;

  /// Largest zoom the user may reach.
  static const double _maxScale = 6;

  /// Size of the gesture surface, recorded during layout. The confirm button
  /// lives outside that area, so it cannot receive the crop frame as a build
  /// argument and derives it from this instead.
  Size _cropViewport = Size.zero;

  @override
  void initState() {
    super.initState();
    _resolveSize();
  }

  Future<void> _resolveSize() async {
    try {
      final decoded = await decodeImageFromList(widget.bytes);
      final w = decoded.width;
      final h = decoded.height;
      decoded.dispose();
      if (!mounted) return;
      setState(() {
        _imageWidth = w;
        _imageHeight = h;
        _ready = w > 0 && h > 0;
        _failed = !_ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _failed = true;
      });
    }
  }

  /// The centred crop frame for a viewport of [viewport].
  Rect _cropRect(Size viewport) => cropRectFor(viewport, widget.aspectRatio);

  /// Base (scale 1) displayed size: the image cover-fitted into [frame], so it
  /// always fills the crop frame.
  Size _baseSize(Rect frame) =>
      cropBaseSize(Size(_imageWidth.toDouble(), _imageHeight.toDouble()), frame);

  /// Clamps [offset] so the displayed image always covers [frame].
  Offset _clampOffset(Offset offset, Rect frame, Size displayed) =>
      cropClampOffset(offset, frame, displayed);

  void _onScaleStart(ScaleStartDetails details) {
    _scaleAtGestureStart = _scale;
    _offsetAtGestureStart = _offset;
    _focalAtGestureStart = details.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Rect frame) {
    final base = _baseSize(frame);
    final newScale = (_scaleAtGestureStart * details.scale).clamp(1.0, _maxScale);
    final center = frame.center;

    // Keep the image point that started under the fingers pinned to them.
    // basePoint is expressed in unscaled display coordinates.
    final basePoint = (_focalAtGestureStart - center - _offsetAtGestureStart) /
        _scaleAtGestureStart;
    final target = details.localFocalPoint - center - basePoint * newScale;

    final displayed = Size(base.width * newScale, base.height * newScale);
    setState(() {
      _scale = newScale;
      _offset = _clampOffset(target, frame, displayed);
    });
  }

  void _reset() {
    setState(() {
      _scale = 1;
      _offset = Offset.zero;
    });
  }

  Future<void> _confirm() async {
    if (!_ready || _busy) return;
    final frame = _cropRect(_cropViewport);
    setState(() => _busy = true);
    try {
      final imageSize = Size(_imageWidth.toDouble(), _imageHeight.toDouble());
      final source = cropSourceRect(
        frame: frame,
        offset: _offset,
        scale: _scale,
        imageSize: imageSize,
      );

      final result = await compute(
        _cropInIsolate,
        _cropRequest(
          bytes: widget.bytes,
          source: source,
          maxOutputWidth: widget.maxOutputWidth,
          preferPng: widget.preferPng,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('cropFailed'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title.isEmpty ? 'cropImage'.tr() : widget.title),
        actions: [
          if (_ready)
            IconButton(
              icon: const Icon(Icons.restart_alt),
              tooltip: 'cropReset'.tr(),
              onPressed: _busy ? null : _reset,
            ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_failed) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text('cropFailed'.tr(), style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('cancel'.tr()),
            ),
          ],
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // The crop frame must be laid out against the gesture area alone, not
        // the whole body: the controls below it consume height, and centring
        // the frame in the larger box would push it out of the image.
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final viewport = Size(constraints.maxWidth, constraints.maxHeight);
              // Read back by the confirm button; assigning here (rather than
              // setState) is safe because the button only reads it after layout.
              _cropViewport = viewport;
              return _buildCropArea(theme, _cropRect(viewport));
            },
          ),
        ),
        _buildControls(theme),
      ],
    );
  }

  /// The gesture surface: the panned/zoomed image with the fixed crop frame on
  /// top, plus the scrim dimming everything outside the frame.
  Widget _buildCropArea(ThemeData theme, Rect frame) {
    final base = _baseSize(frame);
    final displayed = Size(base.width * _scale, base.height * _scale);
    final left = frame.center.dx + _offset.dx - displayed.width / 2;
    final top = frame.center.dy + _offset.dy - displayed.height / 2;

    return GestureDetector(
      key: cropAreaKey,
      onScaleStart: _onScaleStart,
      onScaleUpdate: (d) => _onScaleUpdate(d, frame),
      onDoubleTap: _reset,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            left: left,
            top: top,
            width: displayed.width,
            height: displayed.height,
            child: Image.memory(
              widget.bytes,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          ),
          // Dim everything outside the crop frame.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CropScrimPainter(frame),
              ),
            ),
          ),
          // Crop frame border + rule-of-thirds guides.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: CropFramePainter(frame, theme.colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
        child: Column(
          children: [
            Text(
              'cropHint'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text('cancel'.tr()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _confirm,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text('cropConfirm'.tr()),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a translucent scrim over everything except [frame].
class CropScrimPainter extends CustomPainter {
  /// Creates the scrim painter for [frame].
  const CropScrimPainter(this.frame);

  /// The crop frame, in the painted surface's coordinates.
  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(frame),
    );
    canvas.drawPath(outside, scrim);
  }

  @override
  bool shouldRepaint(CropScrimPainter old) => old.frame != frame;
}

/// Paints the crop frame outline plus rule-of-thirds guides.
class CropFramePainter extends CustomPainter {
  /// Creates the frame painter for [frame]; [accent] colors the corner ticks.
  const CropFramePainter(this.frame, this.accent);

  /// The crop frame, in the painted surface's coordinates.
  final Rect frame;

  /// Highlight color for the corner accents.
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawRect(frame, border);

    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.45);
    for (var i = 1; i < 3; i++) {
      final dx = frame.left + frame.width * i / 3;
      final dy = frame.top + frame.height * i / 3;
      canvas.drawLine(Offset(dx, frame.top), Offset(dx, frame.bottom), guide);
      canvas.drawLine(Offset(frame.left, dy), Offset(frame.right, dy), guide);
    }

    // Small corner accents for a crisper frame.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = accent;
    const len = 18.0;
    final corners = <List<Offset>>[
      [frame.topLeft, frame.topLeft + const Offset(len, 0)],
      [frame.topLeft, frame.topLeft + const Offset(0, len)],
      [frame.topRight, frame.topRight - const Offset(len, 0)],
      [frame.topRight, frame.topRight + const Offset(0, len)],
      [frame.bottomLeft, frame.bottomLeft + const Offset(len, 0)],
      [frame.bottomLeft, frame.bottomLeft - const Offset(0, len)],
      [frame.bottomRight, frame.bottomRight - const Offset(len, 0)],
      [frame.bottomRight, frame.bottomRight - const Offset(0, len)],
    ];
    for (final pair in corners) {
      canvas.drawLine(pair[0], pair[1], corner);
    }
  }

  @override
  bool shouldRepaint(CropFramePainter old) =>
      old.frame != frame || old.accent != accent;
}

/// Opens [ImageCropPage] for [bytes] and resolves with the cropped image, or
/// null when the user cancels.
///
/// Callers pick the image first and read it with `XFile.readAsBytes()` so the
/// flow keeps working on web, where there is no filesystem path.
Future<Uint8List?> openImageCropper({
  required BuildContext context,
  required Uint8List bytes,
  required double aspectRatio,
  required String title,
  int maxOutputWidth = 1024,
  bool preferPng = false,
}) {
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      builder: (_) => ImageCropPage(
        bytes: bytes,
        aspectRatio: aspectRatio,
        title: title,
        maxOutputWidth: maxOutputWidth,
        preferPng: preferPng,
      ),
    ),
  );
}

/// Exposed for tests: the crop rectangle a [viewport] yields for [aspectRatio].
@visibleForTesting
Rect cropRectFor(Size viewport, double aspectRatio, {double padding = 24}) {
  final maxW = math.max(1.0, viewport.width - padding * 2);
  final maxH = math.max(1.0, viewport.height - padding * 2);
  var w = maxW;
  var h = w / aspectRatio;
  if (h > maxH) {
    h = maxH;
    w = h * aspectRatio;
  }
  return Rect.fromCenter(
    center: Offset(viewport.width / 2, viewport.height / 2),
    width: w,
    height: h,
  );
}
