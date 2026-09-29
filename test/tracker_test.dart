import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ar_drawing/tracking/geometry.dart';
import 'package:ar_drawing/tracking/image_ops.dart';
import 'package:ar_drawing/tracking/paper_detector.dart';
import 'package:ar_drawing/tracking/tracker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic_scene.dart';

const w = 800, h = 600;
const paperW = 300.0, paperH = 400.0;

List<Pt> paperCorners(Homography paperToImage) =>
    [for (final p in const [Pt(0, 0), Pt(paperW, 0), Pt(paperW, paperH), Pt(0, paperH)]) paperToImage.apply(p)];

/// Max error (pixels) between where the tracker thinks the anchor-frame
/// sheet corners are now and where they really are.
double poseError(TrackResult r, Homography paperAtAnchor, Homography paperNow) {
  final hm = Homography.fromList(r.homography!);
  var worst = 0.0;
  final a = paperCorners(paperAtAnchor), b = paperCorners(paperNow);
  for (var i = 0; i < 4; i++) {
    worst = math.max(worst, hm.apply(a[i]).dist(b[i]));
  }
  return worst;
}

void main() {
  final baseDesk = Homography.identity();
  final basePaper = place(tx: 250, ty: 90, angle: 0.08, cx: 150, cy: 200);

  test('paper detector finds the sheet corners with sub-pixel-ish accuracy', () {
    final frame = renderScene(width: w, height: h, paperToImage: basePaper, deskToImage: baseDesk);
    final g = downsampleLuma(frame, w, h, w, 2);
    final q = PaperDetector().detect(g);
    expect(q, isNotNull);
    final truth = Quad.ordered([for (final c in paperCorners(basePaper)) Pt((c.x - 0.5) / 2, (c.y - 0.5) / 2)]);
    final err = q!.alignedTo(truth).maxCornerDistance(truth);
    expect(err, lessThan(1.5), reason: 'corners $q vs $truth');
  });

  test('paper detector separates a sheet from a light wall and desk', () {
    // Light wall (top), light desk (bottom), white sheet overlapping both:
    // one global Otsu threshold merges the sheet with the wall.
    const gw = 400, gh = 240;
    final truth = Quad.ordered([const Pt(120, 40), const Pt(290, 52), const Pt(282, 200), const Pt(110, 190)]);
    final px = Uint8List(gw * gh);
    for (var y = 0; y < gh; y++) {
      for (var x = 0; x < gw; x++) {
        final noise = ((x * 7919 + y * 104729) % 9) - 4;
        var v = y < 90 ? 212 : 150;
        if (pointInPolygon(x + 0.5, y + 0.5, truth.corners)) v = 246;
        px[y * gw + x] = (v + noise).clamp(0, 255);
      }
    }
    final q = PaperDetector().detect(Gray(gw, gh, px));
    expect(q, isNotNull);
    // A high threshold on a blurred edge biases corners ~1 px inward; the
    // bias is identical in the anchor and live frames, so tracking is unaffected.
    expect(q!.alignedTo(truth).maxCornerDistance(truth), lessThan(3.5));
  });

  test('paper detector rejects a sheet cut off by the frame edge', () {
    final off = place(tx: 600, ty: 90);
    final frame = renderScene(width: w, height: h, paperToImage: off, deskToImage: baseDesk);
    expect(PaperDetector().detect(downsampleLuma(frame, w, h, w, 2)), isNull);
  });

  test('sheet mode follows a moving phone (whole scene warps)', () {
    final tracker = Tracker(target: TrackTarget.paper);
    tracker.requestAnchor();
    var r = tracker.process(renderScene(width: w, height: h, paperToImage: basePaper, deskToImage: baseDesk), w, h, w);
    expect(r.status, TrackStatus.tracking);
    expect(r.usingPaper, isTrue);
    var worst = 0.0;
    for (var i = 1; i <= 12; i++) {
      // Camera drifts: translate, rotate, zoom and tilt a little each frame.
      final cam = place(tx: 4.0 * i, ty: -2.5 * i, angle: 0.012 * i, scale: 1 + 0.008 * i, px: 0.00002 * i, cx: 400, cy: 300);
      r = tracker.process(renderScene(width: w, height: h, paperToImage: cam * basePaper, deskToImage: cam * baseDesk), w, h, w);
      expect(r.status, TrackStatus.tracking, reason: 'frame $i: ${r.note}');
      worst = math.max(worst, poseError(r, basePaper, cam * basePaper));
    }
    expect(worst, lessThan(3.0));
  });

  test('sheet mode follows the paper when it slides on a static desk', () {
    final tracker = Tracker(target: TrackTarget.paper);
    tracker.requestAnchor();
    tracker.process(renderScene(width: w, height: h, paperToImage: basePaper, deskToImage: baseDesk), w, h, w);
    TrackResult? r;
    var worst = 0.0;
    for (var i = 1; i <= 10; i++) {
      final slide = place(tx: -5.0 * i, ty: 3.0 * i, angle: -0.015 * i, cx: 400, cy: 300);
      final paperNow = slide * basePaper;
      r = tracker.process(renderScene(width: w, height: h, paperToImage: paperNow, deskToImage: baseDesk), w, h, w);
      expect(r.status, TrackStatus.tracking, reason: 'frame $i: ${r.note}');
      worst = math.max(worst, poseError(r, basePaper, paperNow));
    }
    expect(worst, lessThan(3.0));
  });

  test('sheet mode keeps tracking while a hand covers one corner', () {
    final tracker = Tracker(target: TrackTarget.paper);
    tracker.requestAnchor();
    tracker.process(renderScene(width: w, height: h, paperToImage: basePaper, deskToImage: baseDesk), w, h, w);
    var worst = 0.0;
    for (var i = 1; i <= 8; i++) {
      final cam = place(tx: 3.0 * i, ty: 2.0 * i, cx: 400, cy: 300);
      final frame = renderScene(width: w, height: h, paperToImage: cam * basePaper, deskToImage: cam * baseDesk);
      // Dark "hand" blob over the bottom-right corner of the sheet.
      final corner = (cam * basePaper).apply(const Pt(paperW, paperH));
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final dx = x - corner.x, dy = y - corner.y;
          if (dx * dx + dy * dy < 70 * 70) frame[y * w + x] = 55;
        }
      }
      final r = tracker.process(frame, w, h, w);
      expect(r.status, TrackStatus.tracking, reason: 'frame $i: ${r.note}');
      worst = math.max(worst, poseError(r, basePaper, cam * basePaper));
    }
    expect(worst, lessThan(4.0));
  });

  test('surface mode tracks texture without needing a sheet', () {
    final tracker = Tracker(target: TrackTarget.surface);
    tracker.requestAnchor();
    var r = tracker.process(renderScene(width: w, height: h, paperToImage: basePaper, deskToImage: baseDesk), w, h, w);
    expect(r.status, TrackStatus.tracking);
    expect(r.featureCount, greaterThan(40));
    var worst = 0.0;
    for (var i = 1; i <= 10; i++) {
      final cam = place(tx: -3.0 * i, ty: 4.0 * i, angle: -0.01 * i, scale: 1 - 0.006 * i, cx: 400, cy: 300);
      r = tracker.process(renderScene(width: w, height: h, paperToImage: cam * basePaper, deskToImage: cam * baseDesk), w, h, w);
      expect(r.status, TrackStatus.tracking, reason: 'frame $i: ${r.note}');
      worst = math.max(worst, poseError(r, basePaper, cam * basePaper));
    }
    expect(worst, lessThan(3.0));
  });

  test('reports lost when the view no longer shows the page, and recovers', () {
    final tracker = Tracker(target: TrackTarget.paper);
    tracker.requestAnchor();
    tracker.process(renderScene(width: w, height: h, paperToImage: basePaper, deskToImage: baseDesk), w, h, w);
    final blank = Uint8List(w * h)..fillRange(0, w * h, 30);
    final r = tracker.process(blank, w, h, w);
    expect(r.status, TrackStatus.lost);
    final cam = place(tx: 10, ty: 6, cx: 400, cy: 300);
    final back = tracker.process(renderScene(width: w, height: h, paperToImage: cam * basePaper, deskToImage: cam * baseDesk), w, h, w);
    expect(back.status, TrackStatus.tracking);
    expect(poseError(back, basePaper, cam * basePaper), lessThan(3.0));
  });
}
