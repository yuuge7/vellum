import 'dart:math' as math;

import 'package:ar_drawing/tracking/geometry.dart';
import 'package:ar_drawing/tracking/paper_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final truth = Homography.fromList(<double>[1.1, -0.2, 35, 0.15, 0.95, -12, 0.0004, -0.0002, 1]);

  test('DLT recovers a homography from four exact correspondences', () {
    final src = [const Pt(0, 0), const Pt(300, 10), const Pt(310, 420), const Pt(-5, 400)];
    final dst = [for (final p in src) truth.apply(p)];
    final h = homographyFromPoints(src, dst)!;
    for (final p in [const Pt(150, 200), const Pt(10, 390), const Pt(280, 30)]) {
      expect(h.apply(p).dist(truth.apply(p)), lessThan(1e-6));
    }
  });

  test('inverse undoes the transform', () {
    final inv = truth.inverse()!;
    final p = const Pt(123.4, 56.7);
    expect(inv.apply(truth.apply(p)).dist(p), lessThan(1e-9));
  });

  test('RANSAC ignores 35% gross outliers', () {
    final rng = math.Random(3);
    final src = <Pt>[], dst = <Pt>[];
    for (var i = 0; i < 120; i++) {
      final p = Pt(rng.nextDouble() * 400, rng.nextDouble() * 300);
      src.add(p);
      if (i % 3 == 0 && i < 126 * 0.35 * 3) {
        dst.add(Pt(rng.nextDouble() * 500, rng.nextDouble() * 400));
      } else {
        final q = truth.apply(p);
        dst.add(Pt(q.x + (rng.nextDouble() - 0.5) * 0.6, q.y + (rng.nextDouble() - 0.5) * 0.6));
      }
    }
    final r = ransacHomography(src, dst, threshold: 2)!;
    expect(r.inlierCount, greaterThan(70));
    for (final p in [const Pt(50, 50), const Pt(350, 250), const Pt(200, 150)]) {
      expect(r.h.apply(p).dist(truth.apply(p)), lessThan(0.6));
    }
  });

  test('plausibility check rejects mirrored transforms', () {
    expect(isPlausibleHomography(Homography.fromList(<double>[-1, 0, 0, 0, 1, 0, 0, 0, 1])), isFalse);
    expect(isPlausibleHomography(Homography.identity()), isTrue);
  });

  test('quad ordering and alignment', () {
    final q = Quad.ordered([const Pt(100, 110), const Pt(10, 5), const Pt(12, 100), const Pt(95, 8)]);
    expect(q.corners.first.x, 10); // top-left first
    expect(polygonArea(q.corners), greaterThan(0)); // clockwise on screen
    final rotated = Quad([q.corners[2], q.corners[3], q.corners[0], q.corners[1]]);
    expect(rotated.alignedTo(q).maxCornerDistance(q), 0);
  });

  test('convex hull and max-area quad of a noisy rectangle outline', () {
    final pts = <Pt>[];
    for (var i = 0; i <= 50; i++) {
      pts.add(Pt(i * 4.0, 0));
      pts.add(Pt(i * 4.0, 120));
    }
    for (var i = 0; i <= 30; i++) {
      pts.add(Pt(0, i * 4.0));
      pts.add(Pt(200, i * 4.0));
    }
    final hull = convexHull(pts);
    final quad = maxAreaQuad(simplifyClosed(hull, 1))!;
    expect(Quad.ordered(quad).area, closeTo(200 * 120, 1));
  });
}
