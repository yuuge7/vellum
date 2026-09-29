import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'image_ops.dart';

/// Four corners of a detected sheet, clockwise in image coordinates
/// (y pointing down), starting from the corner closest to the top-left.
class Quad {
  Quad(List<Pt> corners) : corners = List<Pt>.unmodifiable(corners) {
    assert(corners.length == 4);
  }

  final List<Pt> corners;

  double get area => polygonArea(corners).abs();

  Pt get centroid {
    var x = 0.0, y = 0.0;
    for (final c in corners) {
      x += c.x;
      y += c.y;
    }
    return Pt(x / 4, y / 4);
  }

  double get diagonal => math.max(corners[0].dist(corners[2]), corners[1].dist(corners[3]));

  Quad map(Pt Function(Pt) f) => Quad([for (final c in corners) f(c)]);

  Quad transformed(Homography h) => map(h.apply);

  /// Largest distance between corresponding corners.
  double maxCornerDistance(Quad o) {
    var m = 0.0;
    for (var i = 0; i < 4; i++) {
      m = math.max(m, corners[i].dist(o.corners[i]));
    }
    return m;
  }

  /// Returns this quad with its corner order cyclically rotated so that each
  /// corner best matches the corresponding corner of [ref].
  Quad alignedTo(Quad ref) {
    var bestR = 0;
    var best = double.infinity;
    for (var r = 0; r < 4; r++) {
      var s = 0.0;
      for (var i = 0; i < 4; i++) {
        s += corners[(i + r) % 4].dist2(ref.corners[i]);
      }
      if (s < best) {
        best = s;
        bestR = r;
      }
    }
    return Quad([for (var i = 0; i < 4; i++) corners[(i + bestR) % 4]]);
  }

  bool get isConvex {
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = corners[i], b = corners[(i + 1) % 4], c = corners[(i + 2) % 4];
      final cross = (b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x);
      final s = cross > 0 ? 1 : (cross < 0 ? -1 : 0);
      if (s == 0) return false;
      if (sign == 0) {
        sign = s;
      } else if (s != sign) {
        return false;
      }
    }
    return true;
  }

  /// Smallest interior angle in degrees.
  double get minAngle {
    var m = 180.0;
    for (var i = 0; i < 4; i++) {
      final p = corners[(i + 3) % 4], c = corners[i], n = corners[(i + 1) % 4];
      final a = p - c, b = n - c;
      final cos = (a.x * b.x + a.y * b.y) / (math.sqrt(a.x * a.x + a.y * a.y) * math.sqrt(b.x * b.x + b.y * b.y) + 1e-9);
      m = math.min(m, math.acos(cos.clamp(-1.0, 1.0)) * 180 / math.pi);
    }
    return m;
  }

  List<double> toList() => [for (final c in corners) ...[c.x, c.y]];

  static Quad fromList(List<double> v) => Quad([for (var i = 0; i < 4; i++) Pt(v[2 * i], v[2 * i + 1])]);

  /// Orders arbitrary four corners clockwise starting nearest the top-left.
  static Quad ordered(List<Pt> pts) {
    final c = Pt(pts.fold(0.0, (s, p) => s + p.x) / 4, pts.fold(0.0, (s, p) => s + p.y) / 4);
    final sorted = List<Pt>.of(pts)..sort((a, b) => math.atan2(a.y - c.y, a.x - c.x).compareTo(math.atan2(b.y - c.y, b.x - c.x)));
    // atan2 ascending with y down is clockwise on screen.
    var start = 0;
    var best = double.infinity;
    for (var i = 0; i < 4; i++) {
      final v = sorted[i].x + sorted[i].y;
      if (v < best) {
        best = v;
        start = i;
      }
    }
    return Quad([for (var i = 0; i < 4; i++) sorted[(start + i) % 4]]);
  }
}

/// Finds a bright, roughly rectangular sheet of paper in a luminance image.
class PaperDetector {
  PaperDetector({this.minAreaFraction = 0.04, this.minContrast = 10});

  final double minAreaFraction;
  final double minContrast;

  Quad? detect(Gray src, {Quad? hint}) {
    final g = boxBlur3(src);
    final w = g.width, h = g.height, n = w * h;
    final (t, sep) = otsu(g.px, n);
    if (sep < minContrast) return null;

    // A single global threshold merges a sheet with light desks, walls or
    // ceilings. Also try thresholds part-way up the bright class, and keep
    // the cleanest (or, when tracking, the most consistent) sheet.
    var hiSum = 0, hiCount = 0;
    for (var i = 0; i < n; i++) {
      final v = g.px[i];
      if (v > t) {
        hiSum += v;
        hiCount++;
      }
    }
    final hiMean = hiCount == 0 ? t.toDouble() : hiSum / hiCount;
    _Found? best;
    for (final f in const [0.0, 0.4, 0.7]) {
      final th = (t + (hiMean - t) * f).round();
      if (f > 0 && th <= t) break;
      final found = _detectAt(g, th, hint);
      if (found == null) continue;
      if (best == null) {
        best = found;
      } else if (hint != null) {
        final dNew = found.quad.alignedTo(hint).maxCornerDistance(hint);
        final dOld = best.quad.alignedTo(hint).maxCornerDistance(hint);
        if (dNew < dOld) best = found;
      } else if (found.fill > best.fill + 0.03) {
        best = found;
      }
    }
    return best?.quad;
  }

  _Found? _detectAt(Gray g, int t, Quad? hint) {
    final w = g.width, h = g.height, n = w * h;
    // Connected components of pixels brighter than t (4-connectivity).
    final labels = Int32List(n);
    final queue = Int32List(n);
    final areas = <int>[0];
    final sumX = <double>[0], sumY = <double>[0];
    var next = 1;
    for (var start = 0; start < n; start++) {
      if (labels[start] != 0 || g.px[start] <= t) continue;
      final id = next++;
      var head = 0, tail = 0;
      queue[tail++] = start;
      labels[start] = id;
      var area = 0;
      var sx = 0.0, sy = 0.0;
      while (head < tail) {
        final i = queue[head++];
        final x = i % w, y = i ~/ w;
        area++;
        sx += x;
        sy += y;
        if (x > 0 && labels[i - 1] == 0 && g.px[i - 1] > t) {
          labels[i - 1] = id;
          queue[tail++] = i - 1;
        }
        if (x < w - 1 && labels[i + 1] == 0 && g.px[i + 1] > t) {
          labels[i + 1] = id;
          queue[tail++] = i + 1;
        }
        if (y > 0 && labels[i - w] == 0 && g.px[i - w] > t) {
          labels[i - w] = id;
          queue[tail++] = i - w;
        }
        if (y < h - 1 && labels[i + w] == 0 && g.px[i + w] > t) {
          labels[i + w] = id;
          queue[tail++] = i + w;
        }
      }
      areas.add(area);
      sumX.add(sx);
      sumY.add(sy);
    }

    // Rank candidate components.
    final minArea = minAreaFraction * n;
    final center = hint?.centroid ?? Pt(w / 2, h / 2);
    final diag = math.sqrt(w * w + h * h.toDouble());
    final candidates = <int>[];
    for (var id = 1; id < next; id++) {
      if (areas[id] >= minArea) candidates.add(id);
    }
    double score(int id) {
      final c = Pt(sumX[id] / areas[id], sumY[id] / areas[id]);
      final d = c.dist(center) / diag;
      var s = areas[id] * (1.0 - 0.8 * d);
      if (hint != null) {
        final ratio = areas[id] / math.max(1.0, hint.area);
        s *= ratio > 1 ? 1 / ratio : ratio; // prefer similar size to last sheet
      }
      return s;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    for (final id in candidates.take(3)) {
      final found = _quadForComponent(g, labels, id, areas[id]);
      if (found != null) return found;
    }
    return null;
  }

  _Found? _quadForComponent(Gray g, Int32List labels, int id, int area) {
    final w = g.width, h = g.height;
    final boundary = <Pt>[];
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (labels[i] != id) continue;
        if (x == 0 || y == 0 || x == w - 1 || y == h - 1 ||
            labels[i - 1] != id || labels[i + 1] != id || labels[i - w] != id || labels[i + w] != id) {
          boundary.add(Pt(x.toDouble(), y.toDouble()));
        }
      }
    }
    if (boundary.length < 16) return null;
    final hull = convexHull(boundary);
    if (hull.length < 4) return null;
    final hullArea = polygonArea(hull).abs();
    var eps = 1.0;
    var simple = simplifyClosed(hull, eps);
    while (simple.length > 40) {
      eps *= 1.5;
      simple = simplifyClosed(hull, eps);
    }
    if (simple.length < 4) return null;
    final quadPts = maxAreaQuad(simple);
    if (quadPts == null) return null;
    var quad = Quad.ordered(quadPts);
    final qa = quad.area;
    if (qa < minAreaFraction * w * h) return null;
    if (qa / hullArea < 0.88) return null; // not quadrilateral-shaped
    if (area / qa < 0.55) return null; // mostly hollow: not a sheet
    if (!quad.isConvex || quad.minAngle < 30) return null;
    // Sheet cut off by the frame edge: corners on the border are not real.
    for (final c in quad.corners) {
      if (c.x < 2 || c.y < 2 || c.x > w - 3 || c.y > h - 3) return null;
    }
    quad = _refine(quad, boundary) ?? quad;
    return _Found(quad, math.min(1.0, area / qa));
  }

  /// Fits a line to the boundary pixels along each side and intersects
  /// neighbouring lines for sub-pixel corners.
  Quad? _refine(Quad q, List<Pt> boundary) {
    final lines = <(Pt, Pt)>[]; // (point, unit direction)
    for (var s = 0; s < 4; s++) {
      final a = q.corners[s], b = q.corners[(s + 1) % 4];
      final len = a.dist(b);
      if (len < 4) return null;
      final dx = (b.x - a.x) / len, dy = (b.y - a.y) / len;
      var cx = 0.0, cy = 0.0, cnt = 0;
      final sel = <Pt>[];
      for (final p in boundary) {
        final rx = p.x - a.x, ry = p.y - a.y;
        final t = (rx * dx + ry * dy) / len;
        if (t < 0.12 || t > 0.88) continue;
        final dist = (rx * -dy + ry * dx).abs();
        if (dist > 2.5) continue;
        sel.add(p);
        cx += p.x;
        cy += p.y;
        cnt++;
      }
      if (cnt < 6) {
        lines.add((a, Pt(dx, dy)));
        continue;
      }
      cx /= cnt;
      cy /= cnt;
      var sxx = 0.0, sxy = 0.0, syy = 0.0;
      for (final p in sel) {
        final ux = p.x - cx, uy = p.y - cy;
        sxx += ux * ux;
        sxy += ux * uy;
        syy += uy * uy;
      }
      final angle = 0.5 * math.atan2(2 * sxy, sxx - syy);
      lines.add((Pt(cx, cy), Pt(math.cos(angle), math.sin(angle))));
    }
    final out = <Pt>[];
    for (var i = 0; i < 4; i++) {
      final l1 = lines[(i + 3) % 4], l2 = lines[i];
      final p = _intersect(l1.$1, l1.$2, l2.$1, l2.$2);
      if (p == null || p.dist(q.corners[i]) > 6) {
        out.add(q.corners[i]);
      } else {
        out.add(p);
      }
    }
    return Quad(out);
  }

  static Pt? _intersect(Pt p1, Pt d1, Pt p2, Pt d2) {
    final den = d1.x * d2.y - d1.y * d2.x;
    if (den.abs() < 1e-6) return null;
    final t = ((p2.x - p1.x) * d2.y - (p2.y - p1.y) * d2.x) / den;
    return Pt(p1.x + d1.x * t, p1.y + d1.y * t);
  }
}

class _Found {
  _Found(this.quad, this.fill);
  final Quad quad;

  /// Fraction of the quad covered by the bright component (1 = clean sheet).
  final double fill;
}

/// Andrew's monotone chain. Returns hull vertices in clockwise order for
/// image coordinates (y down).
List<Pt> convexHull(List<Pt> points) {
  final pts = List<Pt>.of(points)..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));
  if (pts.length < 3) return pts;
  double cross(Pt o, Pt a, Pt b) => (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x);
  final lower = <Pt>[];
  for (final p in pts) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
      lower.removeLast();
    }
    lower.add(p);
  }
  final upper = <Pt>[];
  for (final p in pts.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
      upper.removeLast();
    }
    upper.add(p);
  }
  lower.removeLast();
  upper.removeLast();
  return [...lower, ...upper];
}

/// Douglas-Peucker simplification of a closed polygon.
List<Pt> simplifyClosed(List<Pt> poly, double eps) {
  if (poly.length <= 4) return poly;
  // Split at the two mutually farthest-ish vertices.
  var far = 0;
  var best = -1.0;
  for (var i = 1; i < poly.length; i++) {
    final d = poly[i].dist2(poly[0]);
    if (d > best) {
      best = d;
      far = i;
    }
  }
  final a = _dp([...poly.sublist(0, far + 1)], eps);
  final b = _dp([...poly.sublist(far), poly[0]], eps);
  return [...a.sublist(0, a.length - 1), ...b.sublist(0, b.length - 1)];
}

List<Pt> _dp(List<Pt> pts, double eps) {
  if (pts.length < 3) return pts;
  final a = pts.first, b = pts.last;
  final len = a.dist(b);
  var idx = -1;
  var maxD = 0.0;
  for (var i = 1; i < pts.length - 1; i++) {
    final p = pts[i];
    final d = len < 1e-9
        ? p.dist(a)
        : ((b.x - a.x) * (a.y - p.y) - (a.x - p.x) * (b.y - a.y)).abs() / len;
    if (d > maxD) {
      maxD = d;
      idx = i;
    }
  }
  if (maxD <= eps || idx < 0) return [a, b];
  final l = _dp(pts.sublist(0, idx + 1), eps);
  final r = _dp(pts.sublist(idx), eps);
  return [...l.sublist(0, l.length - 1), ...r];
}

/// Largest-area quadrilateral using vertices of a convex polygon.
List<Pt>? maxAreaQuad(List<Pt> v) {
  final m = v.length;
  if (m < 4) return null;
  double tri(Pt a, Pt b, Pt c) => ((b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)).abs() * 0.5;
  var best = -1.0;
  List<Pt>? res;
  for (var i = 0; i < m; i++) {
    for (var j = i + 2; j < m; j++) {
      if (i == 0 && j == m - 1) continue;
      var bestA = -1.0, ka = -1;
      for (var k = i + 1; k < j; k++) {
        final a = tri(v[i], v[k], v[j]);
        if (a > bestA) {
          bestA = a;
          ka = k;
        }
      }
      var bestB = -1.0, lb = -1;
      for (var l = j + 1; l < i + m; l++) {
        final ll = l % m;
        final a = tri(v[j], v[ll], v[i]);
        if (a > bestB) {
          bestB = a;
          lb = ll;
        }
      }
      if (ka < 0 || lb < 0) continue;
      final total = bestA + bestB;
      if (total > best) {
        best = total;
        res = [v[i], v[ka], v[j], v[lb]];
      }
    }
  }
  return res;
}
