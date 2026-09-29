import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'image_ops.dart';

/// Shi-Tomasi "good features to track" on the finest pyramid level.
///
/// [mask] (optional) restricts detection to a polygon; [existing] points
/// suppress new detections within [minDistance].
List<Pt> goodFeatures(
  Pyramid pyr, {
  int maxCorners = 120,
  double quality = 0.02,
  double minDistance = 8,
  int border = 8,
  List<Pt>? mask,
  List<Pt> existing = const <Pt>[],
}) {
  final gx = pyr.gx[0], gy = pyr.gy[0];
  final w = gx.width, h = gx.height;
  // Structure tensor entries, box-summed over a 5x5 window (separable).
  final xx = Float32List(w * h), xy = Float32List(w * h), yy = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    final a = gx.px[i], b = gy.px[i];
    xx[i] = a * a;
    xy[i] = a * b;
    yy[i] = b * b;
  }
  Float32List box5(Float32List s) {
    final t = Float32List(w * h), o = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      final r = y * w;
      for (var x = 2; x < w - 2; x++) {
        final i = r + x;
        t[i] = s[i - 2] + s[i - 1] + s[i] + s[i + 1] + s[i + 2];
      }
    }
    for (var y = 2; y < h - 2; y++) {
      final r = y * w;
      for (var x = 0; x < w; x++) {
        final i = r + x;
        o[i] = t[i - 2 * w] + t[i - w] + t[i] + t[i + w] + t[i + 2 * w];
      }
    }
    return o;
  }

  final sxx = box5(xx), sxy = box5(xy), syy = box5(yy);
  final eig = Float32List(w * h);
  var maxEig = 0.0;
  final b = math.max(border, 3);
  for (var y = b; y < h - b; y++) {
    for (var x = b; x < w - b; x++) {
      final i = y * w + x;
      final a = sxx[i], c = syy[i], d = sxy[i];
      final half = (a - c) * 0.5;
      final l = (a + c) * 0.5 - math.sqrt(half * half + d * d);
      eig[i] = l;
      if (l > maxEig) maxEig = l;
    }
  }
  if (maxEig <= 1e-6) return <Pt>[];
  // Absolute floor keeps flat, noisy frames from producing junk features.
  final thr = math.max(maxEig * quality, 25.0);
  final cand = <int>[];
  for (var y = b; y < h - b; y++) {
    for (var x = b; x < w - b; x++) {
      final i = y * w + x;
      final v = eig[i];
      if (v < thr) continue;
      // 3x3 non-maximum suppression.
      if (v < eig[i - 1] || v < eig[i + 1] || v < eig[i - w] || v < eig[i + w] ||
          v < eig[i - w - 1] || v < eig[i - w + 1] || v < eig[i + w - 1] || v < eig[i + w + 1]) {
        continue;
      }
      if (mask != null && !pointInPolygon(x.toDouble(), y.toDouble(), mask)) continue;
      cand.add(i);
    }
  }
  cand.sort((p, q) => eig[q].compareTo(eig[p]));

  // Grid-accelerated minimum distance filter.
  final cell = math.max(1, minDistance.ceil());
  final gw = (w / cell).ceil() + 1, gh = (h / cell).ceil() + 1;
  final grid = List<List<Pt>?>.filled(gw * gh, null);
  final md2 = minDistance * minDistance;
  bool free(double x, double y) {
    final cx = x ~/ cell, cy = y ~/ cell;
    for (var j = math.max(0, cy - 1); j <= math.min(gh - 1, cy + 1); j++) {
      for (var i = math.max(0, cx - 1); i <= math.min(gw - 1, cx + 1); i++) {
        final bucket = grid[j * gw + i];
        if (bucket == null) continue;
        for (final p in bucket) {
          final dx = p.x - x, dy = p.y - y;
          if (dx * dx + dy * dy < md2) return false;
        }
      }
    }
    return true;
  }

  void put(Pt p) {
    final k = (p.y ~/ cell) * gw + (p.x ~/ cell);
    if (k < 0 || k >= grid.length) return;
    (grid[k] ??= <Pt>[]).add(p);
  }

  for (final p in existing) {
    put(p);
  }
  final out = <Pt>[];
  for (final i in cand) {
    final x = (i % w).toDouble(), y = (i ~/ w).toDouble();
    if (!free(x, y)) continue;
    final p = Pt(x, y);
    out.add(p);
    put(p);
    if (out.length >= maxCorners) break;
  }
  return out;
}

/// Pyramidal Lucas-Kanade (Bouguet) point tracker.
class LucasKanade {
  LucasKanade({this.halfWindow = 5, this.maxIterations = 15, this.epsilon = 0.02, this.minEigen = 1.0});

  final int halfWindow;
  final int maxIterations;
  final double epsilon;
  final double minEigen;

  /// Tracks [pts] from [prev] into [next]. Returns a parallel list where lost
  /// points are null.
  List<Pt?> track(Pyramid prev, Pyramid next, List<Pt> pts, {List<Pt>? guesses}) {
    final out = List<Pt?>.filled(pts.length, null);
    final topLevel = math.min(prev.levels.length, next.levels.length) - 1;
    final hw = halfWindow;
    final ws = 2 * hw + 1;
    final n = ws * ws;
    final ip = Float32List(n), ix = Float32List(n), iy = Float32List(n);

    for (var k = 0; k < pts.length; k++) {
      final p0 = pts[k];
      final guessOffset = guesses == null ? null : guesses[k] - p0;
      var gx = 0.0, gy = 0.0;
      if (guessOffset != null) {
        final s = 1.0 / (1 << topLevel);
        gx = guessOffset.x * s;
        gy = guessOffset.y * s;
      }
      var ok = true;
      for (var level = topLevel; level >= 0; level--) {
        final scale = 1.0 / (1 << level);
        final px = p0.x * scale, py = p0.y * scale;
        final a = prev.levels[level], agx = prev.gx[level], agy = prev.gy[level];
        final bimg = next.levels[level];
        final w = a.width, h = a.height;
        if (px - hw < 1 || py - hw < 1 || px + hw >= w - 2 || py + hw >= h - 2) {
          if (level == 0) {
            ok = false;
            break;
          }
          gx *= 2;
          gy *= 2;
          continue;
        }
        var g11 = 0.0, g12 = 0.0, g22 = 0.0;
        var idx = 0;
        for (var dy = -hw; dy <= hw; dy++) {
          for (var dx = -hw; dx <= hw; dx++) {
            final sx = px + dx, sy = py + dy;
            final vx = agx.sample(sx, sy), vy = agy.sample(sx, sy);
            ip[idx] = a.sample(sx, sy);
            ix[idx] = vx;
            iy[idx] = vy;
            g11 += vx * vx;
            g12 += vx * vy;
            g22 += vy * vy;
            idx++;
          }
        }
        final det = g11 * g22 - g12 * g12;
        final half = (g11 - g22) * 0.5;
        final minEig = ((g11 + g22) * 0.5 - math.sqrt(half * half + g12 * g12)) / n;
        if (det.abs() < 1e-9 || minEig < minEigen) {
          ok = false;
          break;
        }
        final invDet = 1.0 / det;
        var vx = 0.0, vy = 0.0;
        for (var it = 0; it < maxIterations; it++) {
          final cx = px + gx + vx, cy = py + gy + vy;
          if (cx - hw < 0 || cy - hw < 0 || cx + hw >= bimg.width - 1 || cy + hw >= bimg.height - 1) {
            ok = false;
            break;
          }
          var b1 = 0.0, b2 = 0.0;
          idx = 0;
          for (var dy = -hw; dy <= hw; dy++) {
            for (var dx = -hw; dx <= hw; dx++) {
              final diff = ip[idx] - bimg.sample(cx + dx, cy + dy);
              b1 += diff * ix[idx];
              b2 += diff * iy[idx];
              idx++;
            }
          }
          final ex = (g22 * b1 - g12 * b2) * invDet;
          final ey = (g11 * b2 - g12 * b1) * invDet;
          vx += ex;
          vy += ey;
          if (ex * ex + ey * ey < epsilon * epsilon) break;
        }
        if (!ok) break;
        if (level > 0) {
          gx = 2 * (gx + vx);
          gy = 2 * (gy + vy);
        } else {
          gx += vx;
          gy += vy;
        }
      }
      if (ok) out[k] = Pt(p0.x + gx, p0.y + gy);
    }
    return out;
  }

  /// Forward-backward tracking: only keeps points whose round trip lands
  /// within [maxError] pixels of the start.
  List<Pt?> trackChecked(Pyramid prev, Pyramid next, List<Pt> pts, {double maxError = 1.0}) {
    final fwd = track(prev, next, pts);
    final valid = <int>[];
    final fwdPts = <Pt>[];
    for (var i = 0; i < pts.length; i++) {
      final f = fwd[i];
      if (f != null) {
        valid.add(i);
        fwdPts.add(f);
      }
    }
    final back = track(next, prev, fwdPts, guesses: [for (final i in valid) pts[i]]);
    final out = List<Pt?>.filled(pts.length, null);
    final e2 = maxError * maxError;
    for (var j = 0; j < valid.length; j++) {
      final b = back[j];
      final i = valid[j];
      if (b != null && b.dist2(pts[i]) <= e2) out[i] = fwd[i];
    }
    return out;
  }
}
