import 'dart:typed_data';

import 'raster.dart';

/// Brightness bands of a photo, darkest first.
class TonalBreakdown {
  TonalBreakdown({required this.thresholds, required this.layers, required this.coverage});

  /// Upper luminance bound (exclusive) of every band except the last.
  final List<int> thresholds;

  /// One alpha mask per band, darkest first.
  final List<Rgba> layers;

  /// Fraction of opaque pixels in each band.
  final List<double> coverage;

  int get levels => layers.length;
}

/// Multi-level Otsu: thresholds that maximise between-class variance of a
/// 256-bin histogram for [levels] classes (2..4).
List<int> multiOtsu(Int32List hist, int levels) {
  assert(levels >= 2 && levels <= 4);
  final p = Float64List(257), s = Float64List(257); // prefix count, prefix sum
  for (var i = 0; i < 256; i++) {
    p[i + 1] = p[i] + hist[i];
    s[i + 1] = s[i] + i * hist[i];
  }
  final total = p[256];
  if (total == 0) return List<int>.generate(levels - 1, (k) => 256 * (k + 1) ~/ levels);
  // Class [a, b) contribution: sum^2 / count.
  double term(int a, int b) {
    final c = p[b] - p[a];
    if (c <= 0) return 0;
    final m = s[b] - s[a];
    return m * m / c;
  }

  var best = -1.0;
  var res = <int>[];
  if (levels == 2) {
    for (var t1 = 1; t1 < 256; t1++) {
      final v = term(0, t1) + term(t1, 256);
      if (v > best) {
        best = v;
        res = [t1];
      }
    }
  } else if (levels == 3) {
    for (var t1 = 1; t1 < 255; t1++) {
      final a = term(0, t1);
      for (var t2 = t1 + 1; t2 < 256; t2++) {
        final v = a + term(t1, t2) + term(t2, 256);
        if (v > best) {
          best = v;
          res = [t1, t2];
        }
      }
    }
  } else {
    for (var t1 = 1; t1 < 254; t1++) {
      final a = term(0, t1);
      for (var t2 = t1 + 1; t2 < 255; t2++) {
        final b = a + term(t1, t2);
        for (var t3 = t2 + 1; t3 < 256; t3++) {
          final v = b + term(t2, t3) + term(t3, 256);
          if (v > best) {
            best = v;
            res = [t1, t2, t3];
          }
        }
      }
    }
  }
  return res;
}

/// Splits [img] into [levels] brightness bands (shadows -> highlights).
/// A 3x3 majority filter removes salt-and-pepper speckle so each band is a
/// set of clean, traceable shapes.
TonalBreakdown tonalBreakdown(Rgba img, {int levels = 3, int smoothPasses = 2}) {
  final w = img.width, h = img.height, n = w * h;
  final lum = gaussianBlur(luminance(img), w, h, 1.2);
  final alpha = Uint8List(n);
  final hist = Int32List(256);
  for (var i = 0; i < n; i++) {
    final a = img.px[i * 4 + 3];
    alpha[i] = a;
    if (a > 16) hist[lum[i].round().clamp(0, 255)]++;
  }
  final th = multiOtsu(hist, levels);
  var label = Uint8List(n);
  for (var i = 0; i < n; i++) {
    final v = lum[i];
    var k = 0;
    while (k < th.length && v >= th[k]) {
      k++;
    }
    label[i] = k;
  }

  // Majority filter.
  final counts = Int32List(levels);
  for (var pass = 0; pass < smoothPasses; pass++) {
    final next = Uint8List.fromList(label);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        counts.fillRange(0, levels, 0);
        for (var dy = -1; dy <= 1; dy++) {
          final r = (y + dy) * w + x;
          counts[label[r - 1]]++;
          counts[label[r]]++;
          counts[label[r + 1]]++;
        }
        var bk = label[y * w + x], bc = counts[bk];
        for (var k = 0; k < levels; k++) {
          if (counts[k] > bc) {
            bc = counts[k];
            bk = k;
          }
        }
        next[y * w + x] = bk;
      }
    }
    label = next;
  }

  final layers = <Rgba>[];
  final coverage = <double>[];
  var opaque = 0;
  for (var i = 0; i < n; i++) {
    if (alpha[i] > 16) opaque++;
  }
  for (var k = 0; k < levels; k++) {
    final mask = Uint8List(n);
    var c = 0;
    for (var i = 0; i < n; i++) {
      if (label[i] == k && alpha[i] > 16) {
        mask[i] = 1;
        c++;
      }
    }
    layers.add(maskToRgba(mask, w, h));
    coverage.add(opaque == 0 ? 0 : c / opaque);
  }
  return TonalBreakdown(thresholds: th, layers: layers, coverage: coverage);
}
