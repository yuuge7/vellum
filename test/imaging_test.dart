import 'dart:typed_data';
import 'dart:ui';

import 'package:ar_drawing/camera/camera_geometry.dart';
import 'package:ar_drawing/imaging/ink.dart';
import 'package:ar_drawing/imaging/raster.dart';
import 'package:ar_drawing/imaging/stencil.dart';
import 'package:ar_drawing/imaging/tonal.dart';
import 'package:ar_drawing/imaging/yuv.dart';
import 'package:ar_drawing/models/lesson_player.dart';
import 'package:flutter_test/flutter_test.dart';

Rgba _image(int w, int h, int Function(int x, int y) lum, {int alpha = 255}) {
  final px = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4, v = lum(x, y);
      px[i] = v;
      px[i + 1] = v;
      px[i + 2] = v;
      px[i + 3] = alpha;
    }
  }
  return Rgba(w, h, px);
}

bool _on(Rgba m, int x, int y) => m.px[(y * m.width + x) * 4 + 3] != 0;

void main() {
  group('line art', () {
    test('outlines a dark square and leaves flat areas empty', () {
      final img = _image(200, 200, (x, y) => (x >= 60 && x < 140 && y >= 60 && y < 140) ? 30 : 235);
      final lines = extractLineArt(img, detail: 0.6, weight: 1);
      var onEdge = 0, offEdge = 0;
      for (var y = 0; y < 200; y++) {
        for (var x = 0; x < 200; x++) {
          if (!_on(lines, x, y)) continue;
          final nearEdge = ((x - 60).abs() <= 3 || (x - 139).abs() <= 3 || (y - 60).abs() <= 3 || (y - 139).abs() <= 3) &&
              x >= 55 && x <= 144 && y >= 55 && y <= 144;
          nearEdge ? onEdge++ : offEdge++;
        }
      }
      expect(onEdge, greaterThan(250)); // ~4 x 80 px of outline
      expect(offEdge, 0);
      expect(_on(lines, 100, 100), isFalse); // interior stays clear
      expect(_on(lines, 10, 10), isFalse); // background stripped
    });

    test('a flat image produces no lines', () {
      final img = _image(100, 100, (x, y) => 128);
      expect(extractLineArt(img).px.where((v) => v != 0), isEmpty);
    });

    test('weight thickens lines', () {
      final img = _image(120, 120, (x, y) => x < 60 ? 30 : 230);
      int count(Rgba m) => [for (var i = 3; i < m.px.length; i += 4) m.px[i]].where((a) => a != 0).length;
      expect(count(extractLineArt(img, weight: 3)), greaterThan(count(extractLineArt(img, weight: 1)) * 2));
    });
  });

  group('ink', () {
    int alpha(Rgba m, int x, int y) => m.px[(y * m.width + x) * 4 + 3];

    test('keeps a pen line whole and drops the page', () {
      // 5 px line: edge detection would outline both sides and leave the middle empty.
      final img = _image(120, 80, (x, y) => (x - 60).abs() <= 2 ? 20 : 250);
      final ink = extractInk(img);
      for (var x = 58; x <= 62; x++) {
        expect(alpha(ink, x, 40), 255);
      }
      expect(alpha(ink, 20, 40), 0);
      expect(alpha(ink, 100, 40), 0);
    });

    test('detail decides whether faint shading survives', () {
      final img = _image(120, 80, (x, y) => x >= 40 && x < 80 ? 215 : 250);
      expect(alpha(extractInk(img, detail: 0.5), 60, 40), 0);
      expect(alpha(extractInk(img, detail: 1), 60, 40), greaterThan(60));
    });

    test('light art on a dark page is lifted too', () {
      final img = _image(120, 80, (x, y) => (y - 40).abs() <= 2 ? 240 : 12);
      final ink = extractInk(img);
      expect(alpha(ink, 60, 40), 255);
      expect(alpha(ink, 60, 10), 0);
    });

    test('output is premultiplied white', () {
      final img = _image(60, 60, (x, y) => x >= 20 && x < 40 ? 150 : 250);
      final ink = extractInk(img);
      final i = (30 * 60 + 30) * 4;
      expect(ink.px[i + 3], inExclusiveRange(0, 255));
      expect(ink.px.sublist(i, i + 3), everyElement(ink.px[i + 3]));
    });
  });

  group('tonal breakdown', () {
    test('three flat bands map to three layers', () {
      final img = _image(90, 30, (x, y) => x < 30 ? 25 : (x < 60 ? 125 : 225));
      final t = tonalBreakdown(img, levels: 3, smoothPasses: 0);
      expect(t.levels, 3);
      expect(t.thresholds[0], inInclusiveRange(26, 125));
      expect(t.thresholds[1], inInclusiveRange(126, 225));
      expect(_on(t.layers[0], 10, 15), isTrue);
      expect(_on(t.layers[1], 45, 15), isTrue);
      expect(_on(t.layers[2], 80, 15), isTrue);
      expect(_on(t.layers[0], 80, 15), isFalse);
      for (final c in t.coverage) {
        expect(c, closeTo(1 / 3, 0.05));
      }
    });

    test('four levels on a gradient are ordered dark to light', () {
      final img = _image(256, 8, (x, y) => x);
      final t = tonalBreakdown(img, levels: 4);
      expect(t.thresholds, hasLength(3));
      expect(t.thresholds[0] < t.thresholds[1] && t.thresholds[1] < t.thresholds[2], isTrue);
      expect(_on(t.layers[0], 5, 4), isTrue);
      expect(_on(t.layers[3], 250, 4), isTrue);
    });

    test('multi-Otsu finds the gap in a bimodal histogram', () {
      final hist = Int32List(256);
      hist[40] = 1000;
      hist[200] = 1000;
      final th = multiOtsu(hist, 2);
      expect(th.single, inInclusiveRange(41, 200));
    });
  });

  group('YUV conversion', () {
    YuvFrame frame(int w, int h, int Function(int x, int y) luma) {
      final y = Uint8List(w * h);
      for (var j = 0; j < h; j++) {
        for (var i = 0; i < w; i++) {
          y[j * w + i] = luma(i, j);
        }
      }
      final uv = Uint8List((w ~/ 2) * (h ~/ 2))..fillRange(0, (w ~/ 2) * (h ~/ 2), 128);
      return YuvFrame(width: w, height: h, y: y, u: uv, v: uv, yRowStride: w, uvRowStride: w ~/ 2, uvPixelStride: 1);
    }

    test('neutral chroma gives gray pixels', () {
      final out = yuvToUprightRgba(frame(8, 4, (x, y) => 100), 0, step: 1);
      expect(out.px.sublist(0, 4), [100, 100, 100, 255]);
    });

    test('90 degree rotation puts the sensor top-left at upright top-right', () {
      final f = frame(8, 4, (x, y) => x == 0 && y == 0 ? 255 : 0);
      final out = yuvToUprightRgba(f, 90, step: 1);
      expect(out.width, 4);
      expect(out.height, 8);
      expect(out.px[(0 * 4 + 3) * 4], 255); // (x=3, y=0)
      expect(out.px[0], 0);
    });
  });

  group('camera geometry', () {
    test('sensor 90: frame corners map to the rotated, cover-fitted view', () {
      final g = CameraGeometry(
        viewSize: const Size(400, 800),
        previewSize: const Size(1280, 720),
        sensorOrientation: 90,
        frameSize: const Size(1280, 720),
      );
      // Upright preview 720x1280 cover-fits 400x800 at scale 0.625 -> 450x800.
      expect(g.previewRect, const Rect.fromLTWH(-25, 0, 450, 800));
      final tl = g.frameToView.applyXY(0, 0);
      expect(tl.x, closeTo(425, 1e-6)); // sensor top-left -> view top-right
      expect(tl.y, closeTo(0, 1e-6));
      final br = g.frameToView.applyXY(1280, 720);
      expect(br.x, closeTo(-25, 1e-6));
      expect(br.y, closeTo(800, 1e-6));
      expect(g.frameRectInView, const Rect.fromLTRB(-25, 0, 425, 800));
    });

    test('a 4:3 analysis frame extends past a 16:9 preview', () {
      final g = CameraGeometry(
        viewSize: const Size(360, 640),
        previewSize: const Size(1280, 720),
        sensorOrientation: 90,
        frameSize: const Size(640, 480),
      );
      final r = g.frameRectInView;
      expect(r.height, closeTo(640, 1e-6));
      expect(r.width, greaterThan(360)); // wider field of view sideways
    });
  });

  group('lesson player', () {
    test('walks forward to completion and back', () {
      final p = LessonPlayer(3);
      expect(p.index, 0);
      expect(p.canGoBack, isFalse);
      p.next();
      p.next();
      expect(p.index, 2);
      expect(p.isLastStep, isTrue);
      expect(p.isComplete, isFalse);
      p.next();
      expect(p.isComplete, isTrue);
      expect(p.canGoForward, isFalse);
      p.next(); // no-op once complete
      expect(p.index, 2);
      p.previous();
      expect(p.isComplete, isFalse);
      expect(p.index, 2);
      p.previous();
      expect(p.index, 1);
      expect(p.lastDirection, -1);
      p.restart();
      expect(p.index, 0);
      expect(p.phase, LessonPhase.tracing);
    });

    test('previous at the first step does nothing', () {
      final p = LessonPlayer(2);
      var notified = 0;
      p.addListener(() => notified++);
      p.previous();
      expect(notified, 0);
      expect(p.index, 0);
    });
  });
}
