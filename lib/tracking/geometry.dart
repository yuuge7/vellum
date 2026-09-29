import 'dart:math' as math;
import 'dart:typed_data';

/// Lightweight 2D point used by the vision code (kept free of dart:ui so it
/// runs identically in background isolates and plain unit tests).
class Pt {
  const Pt(this.x, this.y);
  final double x;
  final double y;

  Pt operator +(Pt o) => Pt(x + o.x, y + o.y);
  Pt operator -(Pt o) => Pt(x - o.x, y - o.y);
  Pt operator *(double s) => Pt(x * s, y * s);

  double dist2(Pt o) {
    final dx = x - o.x, dy = y - o.y;
    return dx * dx + dy * dy;
  }

  double dist(Pt o) => math.sqrt(dist2(o));

  @override
  String toString() => 'Pt(${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})';
}

/// Row-major 3x3 projective transform: [x', y', w'] = H * [x, y, 1].
class Homography {
  Homography(this.m) : assert(m.length == 9);

  factory Homography.identity() => Homography(Float64List.fromList(<double>[1, 0, 0, 0, 1, 0, 0, 0, 1]));

  factory Homography.fromList(List<double> v) => Homography(Float64List.fromList(v));

  /// Scale by [s] about the origin, then translate by ([tx], [ty]).
  factory Homography.scaleTranslate(double s, double tx, double ty) =>
      Homography(Float64List.fromList(<double>[s, 0, tx, 0, s, ty, 0, 0, 1]));

  final Float64List m;

  Pt apply(Pt p) => applyXY(p.x, p.y);

  Pt applyXY(double x, double y) {
    final w = m[6] * x + m[7] * y + m[8];
    final iw = w.abs() < 1e-12 ? 1e12 : 1.0 / w;
    return Pt((m[0] * x + m[1] * y + m[2]) * iw, (m[3] * x + m[4] * y + m[5]) * iw);
  }

  Homography operator *(Homography o) {
    final a = m, b = o.m;
    final r = Float64List(9);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        r[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j];
      }
    }
    return Homography(r);
  }

  double get determinant =>
      m[0] * (m[4] * m[8] - m[5] * m[7]) - m[1] * (m[3] * m[8] - m[5] * m[6]) + m[2] * (m[3] * m[7] - m[4] * m[6]);

  Homography? inverse() {
    final det = determinant;
    if (det.abs() < 1e-14) return null;
    final inv = 1.0 / det;
    return Homography(Float64List.fromList(<double>[
      (m[4] * m[8] - m[5] * m[7]) * inv,
      (m[2] * m[7] - m[1] * m[8]) * inv,
      (m[1] * m[5] - m[2] * m[4]) * inv,
      (m[5] * m[6] - m[3] * m[8]) * inv,
      (m[0] * m[8] - m[2] * m[6]) * inv,
      (m[2] * m[3] - m[0] * m[5]) * inv,
      (m[3] * m[7] - m[4] * m[6]) * inv,
      (m[1] * m[6] - m[0] * m[7]) * inv,
      (m[0] * m[4] - m[1] * m[3]) * inv,
    ]));
  }

  /// Returns a copy scaled so that m[8] == 1 (when possible).
  Homography normalized() {
    final s = m[8].abs() < 1e-12 ? 1.0 : 1.0 / m[8];
    return Homography(Float64List.fromList(<double>[for (final v in m) v * s]));
  }

  List<double> toList() => List<double>.of(m);

  @override
  String toString() => 'H[${m.map((v) => v.toStringAsFixed(4)).join(', ')}]';
}

/// Solves A x = b in place for a small dense system (Gaussian elimination
/// with partial pivoting). Returns null when the system is singular.
Float64List? solveLinear(List<Float64List> a, Float64List b) {
  final n = b.length;
  for (var col = 0; col < n; col++) {
    var pivot = col;
    var best = a[col][col].abs();
    for (var r = col + 1; r < n; r++) {
      final v = a[r][col].abs();
      if (v > best) {
        best = v;
        pivot = r;
      }
    }
    if (best < 1e-12) return null;
    if (pivot != col) {
      final tmp = a[pivot];
      a[pivot] = a[col];
      a[col] = tmp;
      final tb = b[pivot];
      b[pivot] = b[col];
      b[col] = tb;
    }
    final inv = 1.0 / a[col][col];
    for (var r = col + 1; r < n; r++) {
      final f = a[r][col] * inv;
      if (f == 0) continue;
      final row = a[r], prow = a[col];
      for (var c = col; c < n; c++) {
        row[c] -= f * prow[c];
      }
      b[r] -= f * b[col];
    }
  }
  final x = Float64List(n);
  for (var r = n - 1; r >= 0; r--) {
    var s = b[r];
    for (var c = r + 1; c < n; c++) {
      s -= a[r][c] * x[c];
    }
    x[r] = s / a[r][r];
  }
  return x;
}

/// Hartley normalisation: translate centroid to the origin and scale so the
/// mean distance is sqrt(2). Returns the normalising transform.
Homography _normalizer(List<Pt> pts) {
  var cx = 0.0, cy = 0.0;
  for (final p in pts) {
    cx += p.x;
    cy += p.y;
  }
  cx /= pts.length;
  cy /= pts.length;
  var d = 0.0;
  for (final p in pts) {
    d += math.sqrt((p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy));
  }
  d /= pts.length;
  final s = d < 1e-9 ? 1.0 : math.sqrt2 / d;
  return Homography.scaleTranslate(s, -s * cx, -s * cy);
}

/// Direct linear transform estimate of the homography mapping [src] onto
/// [dst] (least squares for more than four correspondences).
Homography? homographyFromPoints(List<Pt> src, List<Pt> dst) {
  final n = src.length;
  if (n < 4 || dst.length != n) return null;
  final ts = _normalizer(src), td = _normalizer(dst);
  final ata = List<Float64List>.generate(8, (_) => Float64List(8));
  final atb = Float64List(8);
  final row = Float64List(8);
  void accumulate(double rhs) {
    for (var i = 0; i < 8; i++) {
      final ri = row[i];
      if (ri == 0) continue;
      final ai = ata[i];
      for (var j = 0; j < 8; j++) {
        ai[j] += ri * row[j];
      }
      atb[i] += ri * rhs;
    }
  }

  for (var k = 0; k < n; k++) {
    final s = ts.apply(src[k]);
    final d = td.apply(dst[k]);
    row
      ..[0] = s.x
      ..[1] = s.y
      ..[2] = 1
      ..[3] = 0
      ..[4] = 0
      ..[5] = 0
      ..[6] = -s.x * d.x
      ..[7] = -s.y * d.x;
    accumulate(d.x);
    row
      ..[0] = 0
      ..[1] = 0
      ..[2] = 0
      ..[3] = s.x
      ..[4] = s.y
      ..[5] = 1
      ..[6] = -s.x * d.y
      ..[7] = -s.y * d.y;
    accumulate(d.y);
  }
  final h = solveLinear(ata, atb);
  if (h == null || h.any((v) => v.isNaN || v.isInfinite)) return null;
  final hn = Homography(Float64List.fromList(<double>[h[0], h[1], h[2], h[3], h[4], h[5], h[6], h[7], 1]));
  final tdInv = td.inverse();
  if (tdInv == null) return null;
  return (tdInv * hn * ts).normalized();
}

/// Sanity checks that reject degenerate or mirrored transforms which can come
/// out of noisy correspondences.
bool isPlausibleHomography(Homography h, {double minScale = 0.15, double maxScale = 6.0}) {
  final n = h.normalized().m;
  if (n.any((v) => v.isNaN || v.isInfinite)) return false;
  final det = n[0] * n[4] - n[1] * n[3];
  if (det <= 0) return false; // mirrored or collapsed
  final scale = math.sqrt(det);
  if (scale < minScale || scale > maxScale) return false;
  if (n[6].abs() > 0.01 || n[7].abs() > 0.01) return false; // extreme perspective
  return true;
}

class RansacResult {
  RansacResult(this.h, this.inliers, this.inlierCount);
  final Homography h;
  final List<bool> inliers;
  final int inlierCount;
}

double _triArea2(Pt a, Pt b, Pt c) => ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)).abs();

/// Robust homography estimate. [threshold] is the reprojection error (in the
/// units of [dst]) under which a correspondence counts as an inlier.
RansacResult? ransacHomography(
  List<Pt> src,
  List<Pt> dst, {
  double threshold = 3.0,
  int maxIterations = 300,
  double confidence = 0.995,
  math.Random? random,
}) {
  final n = src.length;
  if (n < 4) return null;
  final rng = random ?? math.Random(7);
  final t2 = threshold * threshold;
  var bestCount = 0;
  List<bool>? bestMask;
  var iterations = maxIterations;
  final idx = List<int>.filled(4, 0);

  int score(Homography h, List<bool> mask) {
    var c = 0;
    for (var k = 0; k < n; k++) {
      final p = h.apply(src[k]);
      final ok = p.dist2(dst[k]) < t2;
      mask[k] = ok;
      if (ok) c++;
    }
    return c;
  }

  final mask = List<bool>.filled(n, false);
  for (var it = 0; it < iterations; it++) {
    // Pick 4 distinct samples.
    for (var i = 0; i < 4; i++) {
      int v;
      do {
        v = rng.nextInt(n);
      } while (idx.take(i).contains(v));
      idx[i] = v;
    }
    final s = [for (final i in idx) src[i]];
    final d = [for (final i in idx) dst[i]];
    // Skip near-collinear samples.
    const minArea = 1.0;
    if (_triArea2(s[0], s[1], s[2]) < minArea ||
        _triArea2(s[0], s[1], s[3]) < minArea ||
        _triArea2(s[0], s[2], s[3]) < minArea ||
        _triArea2(s[1], s[2], s[3]) < minArea) {
      continue;
    }
    final h = homographyFromPoints(s, d);
    if (h == null || !isPlausibleHomography(h)) continue;
    final c = score(h, mask);
    if (c > bestCount) {
      bestCount = c;
      bestMask = List<bool>.of(mask);
      final w = c / n;
      final denom = math.log(1 - math.pow(w, 4).toDouble().clamp(1e-9, 1 - 1e-9));
      final needed = (math.log(1 - confidence) / denom).ceil();
      iterations = math.min(maxIterations, math.max(needed, 12));
    }
  }
  if (bestMask == null || bestCount < 4) return null;

  // Refit on all inliers, then re-score once.
  var inl = bestMask;
  Homography? h;
  for (var refine = 0; refine < 2; refine++) {
    final s = <Pt>[], d = <Pt>[];
    for (var k = 0; k < n; k++) {
      if (inl[k]) {
        s.add(src[k]);
        d.add(dst[k]);
      }
    }
    final hr = homographyFromPoints(s, d);
    if (hr == null || !isPlausibleHomography(hr)) break;
    h = hr;
    final m2 = List<bool>.filled(n, false);
    final c = score(hr, m2);
    if (c < 4) break;
    inl = m2;
    bestCount = c;
  }
  if (h == null) {
    final s = <Pt>[], d = <Pt>[];
    for (var k = 0; k < n; k++) {
      if (bestMask[k]) {
        s.add(src[k]);
        d.add(dst[k]);
      }
    }
    h = homographyFromPoints(s, d);
    if (h == null) return null;
    inl = bestMask;
  }
  return RansacResult(h, inl, bestCount);
}

/// Signed polygon area (positive when vertices run clockwise in image
/// coordinates, i.e. y pointing down).
double polygonArea(List<Pt> p) {
  var a = 0.0;
  for (var i = 0; i < p.length; i++) {
    final j = (i + 1) % p.length;
    a += p[i].x * p[j].y - p[j].x * p[i].y;
  }
  return a / 2;
}

bool pointInPolygon(double x, double y, List<Pt> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final pi = poly[i], pj = poly[j];
    if (((pi.y > y) != (pj.y > y)) && (x < (pj.x - pi.x) * (y - pi.y) / (pj.y - pi.y) + pi.x)) {
      inside = !inside;
    }
  }
  return inside;
}
