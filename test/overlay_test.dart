import 'dart:ui';

import 'package:ar_drawing/models/overlay_controller.dart';
import 'package:ar_drawing/models/trace_document.dart';
import 'package:flutter_test/flutter_test.dart';

Future<OverlayController> _controller(int w, int h) async =>
    OverlayController(TraceDocument.image(title: 't', image: await createTestImage(width: w, height: h)));

void _expectAt(OverlayController c, double x, double y, double vx, double vy) {
  final p = c.effective.applyXY(x, y);
  expect(p.x, closeTo(vx, 1e-6));
  expect(p.y, closeTo(vy, 1e-6));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('fit to sheet', () {
    test('centres the picture on a flat sheet with an even margin', () async {
      final c = await _controller(200, 100);
      // 400 x 600 sheet: margin 32, so the picture is 336 wide.
      final ok = c.fitToSheet(const [Offset(100, 100), Offset(500, 100), Offset(500, 700), Offset(100, 700)]);
      expect(ok, isTrue);
      _expectAt(c, 0, 0, 132, 316);
      _expectAt(c, 200, 100, 468, 484);
    });

    test('stays upright whatever corner the detector starts from', () async {
      const sheet = [Offset(100, 100), Offset(500, 100), Offset(500, 700), Offset(100, 700)];
      for (final order in [
        [1, 2, 3, 0], // sensor rotated 90 degrees: starts top-right
        [3, 2, 1, 0], // counter-clockwise
      ]) {
        final c = await _controller(200, 100);
        expect(c.fitToSheet([for (final i in order) sheet[i]]), isTrue);
        _expectAt(c, 0, 0, 132, 316);
        _expectAt(c, 200, 100, 468, 484);
      }
    });

    test('follows the perspective of a tilted sheet', () async {
      final c = await _controller(300, 300);
      const quad = [Offset(120, 80), Offset(420, 110), Offset(470, 620), Offset(60, 560)];
      expect(c.fitToSheet(quad), isTrue);
      // The picture centre lands where the sheet's diagonals cross.
      final d1 = quad[2] - quad[0], d2 = quad[3] - quad[1], r = quad[1] - quad[0];
      final t = (r.dx * d2.dy - r.dy * d2.dx) / (d1.dx * d2.dy - d1.dy * d2.dx);
      final cross = quad[0] + d1 * t;
      _expectAt(c, 150, 150, cross.dx, cross.dy);
    });

    test('a locked image does not move', () async {
      final c = await _controller(100, 100)..locked = true;
      expect(c.fitToSheet(const [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)]), isFalse);
      _expectAt(c, 10, 10, 10, 10);
    });
  });

  test('cropping keeps the remaining picture where it was', () async {
    final old = await _controller(400, 300);
    old.fitTo(const Size(400, 800));
    old.flip();
    old
      ..grid = 4
      ..opacity = 0.4;
    const crop = Rect.fromLTWH(120, 60, 200, 150);
    final next = await _controller(200, 150)
      ..adoptCrop(old, crop);
    for (final (x, y) in [(0.0, 0.0), (200.0, 150.0), (50.0, 100.0)]) {
      final was = old.effective.applyXY(crop.left + x, crop.top + y);
      _expectAt(next, x, y, was.x, was.y);
    }
    expect(next.flipped, isTrue);
    expect(next.grid, 4);
    expect(next.opacity, 0.4);
  });
}
