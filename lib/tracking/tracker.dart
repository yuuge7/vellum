import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'image_ops.dart';
import 'klt.dart';
import 'paper_detector.dart';

/// What the tracker locks onto.
enum TrackTarget {
  /// Sheet outline (corner/edge detection) fused with feature points on it.
  paper,

  /// Feature points anywhere in view (textured surfaces, sketchbooks).
  surface,
}

enum TrackStatus { idle, searching, tracking, lost }

/// Result for one processed camera frame. All coordinates are in full camera
/// frame pixels (sensor orientation), so the UI can map them to the screen.
class TrackResult {
  const TrackResult({
    required this.status,
    this.homography,
    this.quad,
    this.points = const <double>[],
    this.usingPaper = false,
    this.featureCount = 0,
    this.millis = 0,
    this.note,
    this.frameWidth = 0,
    this.frameHeight = 0,
  });

  final TrackStatus status;

  /// Anchor frame -> current frame (row-major 3x3), when tracking.
  final List<double>? homography;

  /// Current sheet outline (4 corners, flattened x,y), when known.
  final List<double>? quad;

  /// Flattened x,y of the features currently supporting the pose.
  final List<double> points;
  final bool usingPaper;
  final int featureCount;
  final double millis;
  final String? note;
  final int frameWidth;
  final int frameHeight;
}

/// Hybrid paper/feature tracker. Pure Dart and synchronous so it can run in a
/// background isolate and be unit tested with synthetic frames.
class Tracker {
  Tracker({this.target = TrackTarget.paper, this.processingWidth = 400});

  TrackTarget target;
  final int processingWidth;

  final PaperDetector _paper = PaperDetector();
  final LucasKanade _lk = LucasKanade();

  bool _anchorRequested = false;
  bool _anchored = false;
  int _anchorAttempts = 0;
  Pyramid? _prev;
  List<Pt> _anchorPts = <Pt>[];
  List<Pt> _curPts = <Pt>[];
  Quad? _anchorQuad;
  Quad? _lastQuad;
  Homography _h = Homography.identity();
  int _lostFrames = 0;
  final math.Random _rng = math.Random(11);

  bool get anchored => _anchored;

  /// Consecutive frames without a pose while anchored.
  int get lostFrames => _lostFrames;

  void requestAnchor() {
    _anchorRequested = true;
    _anchorAttempts = 0;
  }

  void release() {
    _anchorRequested = false;
    _anchored = false;
    _anchorPts = <Pt>[];
    _curPts = <Pt>[];
    _anchorQuad = null;
    _lastQuad = null;
    _h = Homography.identity();
    _lostFrames = 0;
  }

  TrackResult process(Uint8List luma, int width, int height, int rowStride) {
    final sw = Stopwatch()..start();
    final factor = math.max(1, (width / processingWidth).round());
    final g = downsampleLuma(luma, width, height, rowStride, factor);

    _Step step;
    if (!_anchorRequested && !_anchored) {
      // Not anchored: only preview the sheet outline (no pyramid needed).
      final q = target == TrackTarget.paper ? _paper.detect(g) : null;
      step = _Step(TrackStatus.idle, quad: q, usingPaper: q != null);
      _prev = null;
    } else {
      final pyr = Pyramid.build(g, levels: 3);
      step = _anchorRequested ? _anchor(g, pyr) : _track(g, pyr);
      _prev = pyr;
    }

    // Processing-resolution -> full-resolution transform.
    final c = (factor - 1) / 2.0;
    final s = Homography.scaleTranslate(factor.toDouble(), c, c);
    final sInv = s.inverse()!;
    List<double>? hFull;
    if (step.h != null) hFull = (s * step.h! * sInv).normalized().toList();
    final pts = <double>[];
    for (final p in step.points) {
      final q = s.apply(p);
      pts
        ..add(q.x)
        ..add(q.y);
    }
    return TrackResult(
      status: step.status,
      homography: hFull,
      quad: step.quad?.transformed(s).toList(),
      points: pts,
      usingPaper: step.usingPaper,
      featureCount: step.points.length,
      millis: sw.elapsedMicroseconds / 1000.0,
      note: step.note,
      frameWidth: width,
      frameHeight: height,
    );
  }

  List<Pt> _expanded(Quad q, double px) {
    final c = q.centroid;
    return [
      for (final p in q.corners)
        () {
          final d = p - c;
          final len = math.sqrt(d.x * d.x + d.y * d.y);
          return len < 1e-6 ? p : p + d * (px / len);
        }(),
    ];
  }

  _Step _anchor(Gray g, Pyramid pyr) {
    _anchorAttempts++;
    Quad? quad;
    if (target == TrackTarget.paper) {
      quad = _paper.detect(g);
      // Give the sheet detector a few frames before settling for texture.
      if (quad == null && _anchorAttempts < 12) {
        return _Step(TrackStatus.searching, note: 'Looking for the sheet edges');
      }
    }
    final mask = quad == null ? null : _expanded(quad, 4);
    final feats = goodFeatures(pyr, mask: mask, maxCorners: 150, minDistance: 7);
    if (quad == null && feats.length < 12) {
      return _Step(TrackStatus.searching, note: 'Not enough detail to lock on. Add light or show more of the page');
    }
    _anchorRequested = false;
    _anchored = true;
    _anchorQuad = quad;
    _lastQuad = quad;
    _anchorPts = feats;
    _curPts = List<Pt>.of(feats);
    _h = Homography.identity();
    _lostFrames = 0;
    return _Step(
      TrackStatus.tracking,
      h: _h,
      quad: quad,
      points: feats,
      usingPaper: quad != null,
      note: target == TrackTarget.paper && quad == null ? 'No sheet edges found: locked to surface texture' : null,
    );
  }

  _Step _track(Gray g, Pyramid pyr) {
    Homography? hKlt;
    if (_prev != null && _curPts.isNotEmpty) {
      final tracked = _lk.trackChecked(_prev!, pyr, _curPts, maxError: 1.0);
      final src = <Pt>[], dst = <Pt>[];
      for (var i = 0; i < tracked.length; i++) {
        final t = tracked[i];
        if (t != null) {
          src.add(_anchorPts[i]);
          dst.add(t);
        }
      }
      _anchorPts = src;
      _curPts = dst;
      if (src.length >= 8) {
        final rr = ransacHomography(src, dst, threshold: 2.0, random: _rng);
        if (rr != null && rr.inlierCount >= 8 && rr.inlierCount >= 0.35 * src.length && isPlausibleHomography(rr.h)) {
          hKlt = rr.h;
          final a = <Pt>[], c = <Pt>[];
          for (var i = 0; i < src.length; i++) {
            if (rr.inliers[i]) {
              a.add(src[i]);
              c.add(dst[i]);
            }
          }
          _anchorPts = a;
          _curPts = c;
        }
      }
    }

    Homography? hPaper;
    Quad? seen;
    if (target == TrackTarget.paper && _anchorQuad != null) {
      final predicted = _anchorQuad!.transformed(hKlt ?? _h);
      final q = _paper.detect(g, hint: predicted);
      if (q != null) {
        final qa = q.alignedTo(predicted);
        final tol = (hKlt != null ? 0.08 : 0.35) * predicted.diagonal;
        if (qa.maxCornerDistance(predicted) < tol) {
          final hp = homographyFromPoints(_anchorQuad!.corners, qa.corners);
          if (hp != null && isPlausibleHomography(hp)) {
            hPaper = hp;
            seen = qa;
          }
        }
      }
    }

    TrackStatus status;
    var usingPaper = false;
    // Feature tracking is smoother and more precise than the sheet outline;
    // the outline only steps in when the features drift away from it.
    if (hPaper != null && hKlt != null && seen != null) {
      final viaKlt = _anchorQuad!.transformed(hKlt);
      final agree = math.max(2.0, 0.012 * seen.diagonal);
      if (viaKlt.maxCornerDistance(seen) <= agree) {
        hPaper = null;
        _lastQuad = seen;
      }
    }
    if (hPaper != null) {
      _h = hPaper;
      _lastQuad = seen;
      usingPaper = true;
      status = TrackStatus.tracking;
      // Re-register the feature anchors against the drift-free sheet pose.
      final inv = hPaper.inverse();
      if (inv != null && hKlt != null) {
        _anchorPts = [for (final p in _curPts) inv.apply(p)];
      } else if (hKlt == null) {
        _anchorPts = <Pt>[];
        _curPts = <Pt>[];
      }
    } else if (hKlt != null) {
      _h = hKlt;
      usingPaper = seen != null;
      if (seen == null) _lastQuad = _anchorQuad?.transformed(hKlt);
      status = TrackStatus.tracking;
    } else {
      status = TrackStatus.lost;
    }

    if (status == TrackStatus.tracking) {
      _lostFrames = 0;
      if (_curPts.length < 60) _replenish(pyr);
    } else {
      _lostFrames++;
    }

    return _Step(
      status,
      h: _h,
      quad: _lastQuad,
      points: _curPts,
      usingPaper: usingPaper,
      note: status == TrackStatus.lost
          ? (target == TrackTarget.paper && _anchorQuad != null
              ? 'Lost the sheet. Bring all four corners back into view'
              : 'Lost the surface. Point back at the page')
          : null,
    );
  }

  void _replenish(Pyramid pyr) {
    final inv = _h.inverse();
    if (inv == null) return;
    final mask = _lastQuad == null ? null : _expanded(_lastQuad!, 4);
    final fresh = goodFeatures(
      pyr,
      mask: mask,
      existing: _curPts,
      maxCorners: math.max(0, 150 - _curPts.length),
      minDistance: 7,
    );
    for (final p in fresh) {
      _curPts.add(p);
      _anchorPts.add(inv.apply(p));
    }
  }
}

class _Step {
  _Step(this.status, {this.h, this.quad, this.points = const <Pt>[], this.usingPaper = false, this.note});
  final TrackStatus status;
  final Homography? h;
  final Quad? quad;
  final List<Pt> points;
  final bool usingPaper;
  final String? note;
}
