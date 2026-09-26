import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:openfield/core/widgets/image_crop_page.dart';

/// The crop geometry is the correctness-critical part of the cropper: a wrong
/// viewport → pixel mapping silently exports the wrong region. These tests pin
/// the invariants that make the preview and the exported crop agree.
void main() {
  group('cropRectFor', () {
    test('produces the requested aspect ratio', () {
      for (final ratio in const [1.0, 3.0, 0.75, 16 / 9]) {
        final rect = cropRectFor(const Size(400, 700), ratio);
        expect(rect.width / rect.height, closeTo(ratio, 1e-9));
      }
    });

    test('fits inside the viewport with padding', () {
      const viewport = Size(400, 700);
      final rect = cropRectFor(viewport, 1);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.top, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.width));
      expect(rect.bottom, lessThanOrEqualTo(viewport.height));
    });

    test('stays centred', () {
      const viewport = Size(400, 700);
      final rect = cropRectFor(viewport, 3);
      expect(rect.center.dx, closeTo(viewport.width / 2, 1e-9));
      expect(rect.center.dy, closeTo(viewport.height / 2, 1e-9));
    });

    test('does not collapse on a degenerate viewport', () {
      final rect = cropRectFor(const Size(1, 1), 1);
      expect(rect.width, greaterThan(0));
      expect(rect.height, greaterThan(0));
    });
  });

  group('cropBaseSize', () {
    test('covers the frame for a wider-than-frame image', () {
      const frame = Rect.fromLTWH(0, 0, 200, 200);
      final base = cropBaseSize(const Size(1000, 250), frame);
      expect(base.width, greaterThanOrEqualTo(frame.width));
      expect(base.height, greaterThanOrEqualTo(frame.height));
      // Aspect ratio is preserved.
      expect(base.width / base.height, closeTo(1000 / 250, 1e-9));
    });

    test('covers the frame for a taller-than-frame image', () {
      const frame = Rect.fromLTWH(0, 0, 200, 200);
      final base = cropBaseSize(const Size(250, 1000), frame);
      expect(base.width, greaterThanOrEqualTo(frame.width));
      expect(base.height, greaterThanOrEqualTo(frame.height));
      expect(base.width / base.height, closeTo(250 / 1000, 1e-9));
    });

    test('covers the frame for a wide crop and a square image', () {
      const frame = Rect.fromLTWH(0, 0, 300, 100);
      final base = cropBaseSize(const Size(400, 400), frame);
      expect(base.width, greaterThanOrEqualTo(frame.width));
      expect(base.height, greaterThanOrEqualTo(frame.height));
    });
  });

  group('cropSourceRect', () {
    const imageSize = Size(1000, 500);

    test('selects the whole image when the aspect ratios match', () {
      const frame = Rect.fromLTWH(0, 0, 200, 100); // 2:1, same as the image.
      final src = cropSourceRect(
        frame: frame,
        offset: Offset.zero,
        scale: 1,
        imageSize: imageSize,
      );
      expect(src.left, closeTo(0, 1e-6));
      expect(src.top, closeTo(0, 1e-6));
      expect(src.width, closeTo(1000, 1e-6));
      expect(src.height, closeTo(500, 1e-6));
    });

    test('selects a centred square window from a wide image', () {
      const frame = Rect.fromLTWH(50, 40, 100, 100); // 1:1 crop.
      final src = cropSourceRect(
        frame: frame,
        offset: Offset.zero,
        scale: 1,
        imageSize: imageSize,
      );
      // A square crop of a 2:1 image is half the width, full height, centred.
      expect(src.width, closeTo(500, 1e-6));
      expect(src.height, closeTo(500, 1e-6));
      expect(src.left, closeTo(250, 1e-6));
      expect(src.top, closeTo(0, 1e-6));
    });

    test('halves the window when zoomed to 2x', () {
      const frame = Rect.fromLTWH(0, 0, 100, 100);
      final src = cropSourceRect(
        frame: frame,
        offset: Offset.zero,
        scale: 2,
        imageSize: imageSize,
      );
      expect(src.width, closeTo(250, 1e-6));
      expect(src.height, closeTo(250, 1e-6));
    });

    test('panning right reveals the right part of the image', () {
      const frame = Rect.fromLTWH(0, 0, 100, 100);
      // Displayed size is 1000x500 for a 1:1 frame? No — 1:1 frame with a 2:1
      // image yields a 200x100 base at scale 2 -> 400x200. Panning the image to
      // the left (negative offset) shows more of the right-hand side.
      final base = cropBaseSize(imageSize, frame);
      expect(base, const Size(200, 100));
      final src = cropSourceRect(
        frame: frame,
        offset: const Offset(-50, 0),
        scale: 2,
        imageSize: imageSize,
      );
      // Window stays the same size but moves right in image space.
      expect(src.width, closeTo(250, 1e-6));
      expect(src.left, greaterThan(0));
    });

    test('always yields the crop frame aspect ratio', () {
      const frame = Rect.fromLTWH(20, 30, 300, 100); // 3:1
      for (final scale in const [1.0, 1.5, 3.0]) {
        final src = cropSourceRect(
          frame: frame,
          offset: const Offset(12, -7),
          scale: scale,
          imageSize: imageSize,
        );
        expect(src.width / src.height, closeTo(3, 1e-6));
      }
    });
  });

  group('cropClampOffset', () {
    const imageSize = Size(1000, 500);

    /// Simulates the full gesture pipeline and returns the source rect that a
    /// clamp would produce.
    Rect sourceFor(Rect frame, Offset rawOffset, double scale) {
      final base = cropBaseSize(imageSize, frame);
      final displayed = Size(base.width * scale, base.height * scale);
      final clamped = cropClampOffset(rawOffset, frame, displayed);
      return cropSourceRect(
        frame: frame,
        offset: clamped,
        scale: scale,
        imageSize: imageSize,
      );
    }

    test('keeps the window inside the image for extreme pans', () {
      const frame = Rect.fromLTWH(0, 0, 100, 100); // 1:1 crop of a 2:1 image.
      for (final scale in const [1.0, 2.0, 5.0]) {
        for (final dx in const [-9999.0, -50.0, 0.0, 50.0, 9999.0]) {
          for (final dy in const [-9999.0, 0.0, 9999.0]) {
            final src = sourceFor(frame, Offset(dx, dy), scale);
            expect(src.left, greaterThanOrEqualTo(-1e-6),
                reason: 'scale=$scale dx=$dx dy=$dy');
            expect(src.top, greaterThanOrEqualTo(-1e-6),
                reason: 'scale=$scale dx=$dx dy=$dy');
            expect(src.right, lessThanOrEqualTo(imageSize.width + 1e-6),
                reason: 'scale=$scale dx=$dx dy=$dy');
            expect(src.bottom, lessThanOrEqualTo(imageSize.height + 1e-6),
                reason: 'scale=$scale dx=$dx dy=$dy');
          }
        }
      }
    });

    test('is a no-op inside the allowed range', () {
      const frame = Rect.fromLTWH(0, 0, 100, 100);
      final base = cropBaseSize(imageSize, frame);
      final displayed = Size(base.width * 2, base.height * 2);
      // dx must stay within +-(displayed.width - frame.width)/2.
      final maxDx = (displayed.width - frame.width) / 2;
      expect(
        cropClampOffset(Offset(maxDx / 2, 0), frame, displayed),
        Offset(maxDx / 2, 0),
      );
    });

    test('clamps to zero for an exact cover', () {
      const frame = Rect.fromLTWH(0, 0, 100, 100);
      // An image whose aspect matches the frame covers exactly at scale 1.
      final base = cropBaseSize(const Size(100, 100), frame);
      final displayed = Size(base.width, base.height);
      expect(cropClampOffset(const Offset(50, 50), frame, displayed), Offset.zero);
    });
  });

  group('end-to-end geometry', () {
    test('the exported rect never falls outside the source image', () {
      const imageSize = Size(4032, 3024); // a typical phone photo.
      for (final ratio in const [1.0, 3.0, 0.8]) {
        for (final viewport in const [Size(360, 640), Size(1280, 420)]) {
          final frame = cropRectFor(viewport, ratio);
          final base = cropBaseSize(imageSize, frame);
          for (final scale in const [1.0, 2.2, 6.0]) {
            for (final offset in const [
              Offset.zero,
              Offset(1000, -1000),
              Offset(-1000, 1000),
            ]) {
              final displayed = Size(base.width * scale, base.height * scale);
              final clamped = cropClampOffset(offset, frame, displayed);
              final src = cropSourceRect(
                frame: frame,
                offset: clamped,
                scale: scale,
                imageSize: imageSize,
              );
              expect(src.width, greaterThan(0));
              expect(src.height, greaterThan(0));
              expect(src.left, greaterThanOrEqualTo(-0.5));
              expect(src.top, greaterThanOrEqualTo(-0.5));
              expect(src.right, lessThanOrEqualTo(imageSize.width + 0.5));
              expect(src.bottom, lessThanOrEqualTo(imageSize.height + 0.5));
              expect(src.width / src.height, closeTo(ratio, 1e-6));
            }
          }
        }
      }
    });

    test('a square crop of a wide photo is centred at rest', () {
      const imageSize = Size(4000, 2000);
      const viewport = Size(400, 600);
      final frame = cropRectFor(viewport, 1);
      final src = cropSourceRect(
        frame: frame,
        offset: Offset.zero,
        scale: 1,
        imageSize: imageSize,
      );
      expect(src.center.dx, closeTo(imageSize.width / 2, 1e-6));
      expect(src.center.dy, closeTo(imageSize.height / 2, 1e-6));
      expect(math.max(src.width, src.height), lessThanOrEqualTo(imageSize.height + 1e-6));
    });
  });

  group('cropImageBytes', () {
    /// A 4x2 image with a distinct, solid colour in each quadrant, so the
    /// exported pixels reveal exactly which region was cropped.
    ///
    ///   red   | green
    ///   ------+------
    ///   blue  | yellow
    List<int> quadrantPng({int width = 40, int height = 20}) {
      final canvas = img.Image(width: width, height: height);
      for (final px in canvas) {
        final left = px.x < width / 2;
        final top = px.y < height / 2;
        final color = left
            ? (top ? img.ColorRgb8(255, 0, 0) : img.ColorRgb8(0, 0, 255))
            : (top ? img.ColorRgb8(0, 255, 0) : img.ColorRgb8(255, 255, 0));
        canvas.setPixel(px.x, px.y, color);
      }
      return img.encodeJpg(canvas, quality: 100);
    }

    /// The average colour of [bytes], ignoring nothing.
    img.Color averageColor(List<int> bytes) {
      final decoded = img.decodeImage(Uint8List.fromList(bytes))!;
      var r = 0, g = 0, b = 0;
      for (final px in decoded) {
        r += px.r.toInt();
        g += px.g.toInt();
        b += px.b.toInt();
      }
      final n = decoded.width * decoded.height;
      return img.ColorRgb8(r ~/ n, g ~/ n, b ~/ n);
    }

    test('keeps only the requested region', () {
      final source = quadrantPng();
      // Top-left quadrant only.
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(0, 0, 20, 10),
        preferPng: true,
      );
      final color = averageColor(out);
      // Red dominates; green/blue are absent.
      expect(color.r, greaterThan(180));
      expect(color.g, lessThan(80));
      expect(color.b, lessThan(80));
    });

    test('selects the bottom-right quadrant when asked', () {
      final source = quadrantPng();
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(20, 10, 20, 10),
        preferPng: true,
      );
      final color = averageColor(out);
      // Yellow: red and green high, blue low.
      expect(color.r, greaterThan(180));
      expect(color.g, greaterThan(180));
      expect(color.b, lessThan(80));
    });

    test('honours the aspect ratio of the requested rectangle', () {
      final source = quadrantPng();
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(5, 5, 20, 10),
      );
      final decoded = img.decodeImage(Uint8List.fromList(out))!;
      expect(decoded.width / decoded.height, closeTo(2, 0.05));
    });

    test('downscales to maxOutputWidth', () {
      final source = quadrantPng(width: 400, height: 200);
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(0, 0, 400, 200),
        maxOutputWidth: 100,
      );
      final decoded = img.decodeImage(Uint8List.fromList(out))!;
      expect(decoded.width, 100);
      expect(decoded.height, 50);
    });

    test('does not upscale beyond the source', () {
      final source = quadrantPng(width: 40, height: 20);
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(0, 0, 40, 20),
        maxOutputWidth: 1024,
      );
      final decoded = img.decodeImage(Uint8List.fromList(out))!;
      expect(decoded.width, 40);
    });

    test('clamps a rectangle that runs past the image edge', () {
      final source = quadrantPng(width: 40, height: 20);
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        // Deliberately oversized / out of bounds.
        source: const Rect.fromLTWH(30, 10, 100, 100),
      );
      final decoded = img.decodeImage(Uint8List.fromList(out))!;
      expect(decoded.width, lessThanOrEqualTo(40));
      expect(decoded.height, lessThanOrEqualTo(20));
      expect(decoded.width, greaterThan(0));
      expect(decoded.height, greaterThan(0));
    });

    test('produces a PNG when preferPng is set', () {
      final source = quadrantPng();
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(0, 0, 10, 10),
        preferPng: true,
      );
      // PNG magic number.
      expect(out.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });

    test('produces a JPEG by default', () {
      final source = quadrantPng();
      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: const Rect.fromLTWH(0, 0, 10, 10),
      );
      // JPEG SOI marker.
      expect(out.sublist(0, 2), [0xFF, 0xD8]);
    });

    test('throws on undecodable bytes', () {
      expect(
        () => cropImageBytes(
          bytes: Uint8List.fromList([1, 2, 3, 4]),
          source: const Rect.fromLTWH(0, 0, 10, 10),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('the geometry feeds a correct pixel crop end to end', () {
      // A wide photo cropped to a centred square must land in the middle.
      final canvas = img.Image(width: 200, height: 100);
      img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
      // Paint a bright marker in the exact centre.
      img.fillRect(canvas,
          x1: 90, y1: 40, x2: 110, y2: 60, color: img.ColorRgb8(255, 255, 255));
      final source = img.encodeJpg(canvas, quality: 100);

      const imageSize = Size(200, 100);
      const viewport = Size(300, 300);
      final frame = cropRectFor(viewport, 1);
      final src = cropSourceRect(
        frame: frame,
        offset: Offset.zero,
        scale: 1,
        imageSize: imageSize,
      );
      // A centred square of a 2:1 image: full height, half the width.
      expect(src, const Rect.fromLTWH(50, 0, 100, 100));

      final out = cropImageBytes(
        bytes: Uint8List.fromList(source),
        source: src,
        preferPng: true,
      );
      final decoded = img.decodeImage(Uint8List.fromList(out))!;
      expect(decoded.width, 100);
      expect(decoded.height, 100);

      // The centre marker (source x90..110, y40..60) lands at output (40..60,
      // 40..60), so the output centre must be white and the corners black.
      final centre = decoded.getPixel(50, 50);
      expect(centre.r, greaterThan(200));
      expect(centre.g, greaterThan(200));
      expect(centre.b, greaterThan(200));

      final corner = decoded.getPixel(2, 2);
      expect(corner.r, lessThan(60));
      expect(corner.g, lessThan(60));
      expect(corner.b, lessThan(60));

      // The marker occupies 20x20 of the 100x100 crop, so roughly 400 of the
      // 10000 output pixels are bright.
      var bright = 0;
      for (final px in decoded) {
        if (px.r > 200 && px.g > 200 && px.b > 200) bright++;
      }
      expect(bright, greaterThan(200));
      expect(bright, lessThan(900));
    });
  });

  group('ImageCropPage layout', () {
    /// A small solid-colour JPEG the page can decode and display.
    Uint8List sampleImage() {
      final canvas = img.Image(width: 80, height: 40);
      img.fill(canvas, color: img.ColorRgb8(10, 200, 120));
      return img.encodeJpg(canvas);
    }

    /// Pumps the page and lets the real image codec finish decoding.
    ///
    /// `pumpAndSettle` cannot be used: `decodeImageFromList` runs on the real
    /// event loop (hence `runAsync`) and the loading state shows an indefinitely
    /// animating progress indicator.
    Future<void> pumpPage(WidgetTester tester, {double aspectRatio = 1}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageCropPage(
            bytes: sampleImage(),
            aspectRatio: aspectRatio,
          ),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
    }

    /// The crop frame the page actually painted, read off the overlay painter.
    /// This is the real laid-out frame, not a recomputation.
    Rect paintedFrame(WidgetTester tester) {
      final painters = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<CropFramePainter>();
      expect(painters, hasLength(1));
      return painters.single.frame;
    }

    testWidgets('renders the confirm and cancel controls', (tester) async {
      await pumpPage(tester);
      // Without an EasyLocalization scope, .tr() resolves to the key itself.
      expect(find.text('cropConfirm'), findsOneWidget);
      expect(find.text('cancel'), findsOneWidget);
    });

    testWidgets('lays the crop area out above the controls', (tester) async {
      await pumpPage(tester);
      final cropArea = tester.getRect(find.byKey(cropAreaKey));
      final confirm = tester.getRect(find.text('cropConfirm'));
      final cancel = tester.getRect(find.text('cancel'));

      // Controls sit strictly below the gesture surface.
      expect(confirm.top, greaterThanOrEqualTo(cropArea.bottom - 1e-6));
      expect(cancel.top, greaterThanOrEqualTo(cropArea.bottom - 1e-6));
      // And the gesture surface is non-empty.
      expect(cropArea.height, greaterThan(0));
      expect(cropArea.width, greaterThan(0));
    });

    testWidgets('paints the crop frame inside the gesture area', (tester) async {
      await pumpPage(tester);
      final cropArea = tester.getSize(find.byKey(cropAreaKey));
      final frame = paintedFrame(tester);
      expect(frame.top, greaterThanOrEqualTo(0));
      expect(frame.left, greaterThanOrEqualTo(0));
      expect(frame.bottom, lessThanOrEqualTo(cropArea.height + 1e-6));
      expect(frame.right, lessThanOrEqualTo(cropArea.width + 1e-6));
    });

    testWidgets('centres the painted frame in the gesture area, not the body',
        (tester) async {
      await pumpPage(tester);
      final cropAreaSize = tester.getSize(find.byKey(cropAreaKey));
      final cropAreaRect = tester.getRect(find.byKey(cropAreaKey));
      final frame = paintedFrame(tester);

      // The regression this guards: deriving the frame from the whole body
      // (which also contains the control strip) shifts it down, so its centre
      // lands below the gesture area's centre and it can spill past its bottom.
      expect(frame.center.dy, closeTo(cropAreaSize.height / 2, 1e-6));
      expect(frame.center.dx, closeTo(cropAreaSize.width / 2, 1e-6));

      // The frame must be painted within the gesture area's bounds on screen.
      final paintedOnScreen = frame.shift(cropAreaRect.topLeft);
      expect(paintedOnScreen.top, greaterThanOrEqualTo(cropAreaRect.top - 1e-6));
      expect(paintedOnScreen.bottom,
          lessThanOrEqualTo(cropAreaRect.bottom + 1e-6));
    });

    testWidgets('the painted frame respects the requested aspect ratio',
        (tester) async {
      await pumpPage(tester, aspectRatio: 3);
      final frame = paintedFrame(tester);
      expect(frame.width / frame.height, closeTo(3, 1e-6));

      final cropAreaSize = tester.getSize(find.byKey(cropAreaKey));
      expect(frame.bottom, lessThanOrEqualTo(cropAreaSize.height + 1e-6));
    });

    testWidgets('surfaces an undecodable image instead of crashing',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ImageCropPage(bytes: Uint8List.fromList([1, 2, 3, 4])),
        ),
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      // The failure view offers a way out rather than an empty screen.
      expect(find.text('cancel'), findsOneWidget);
      expect(find.text('cropConfirm'), findsNothing);
    });
  });
}
