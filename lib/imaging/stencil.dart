import 'dart:math' as math;
import 'dart:typed_data';

import 'raster.dart';

/// Canny-style line art extraction: grayscale, Gaussian blur, Sobel
/// gradients, non-maximum suppression, hysteresis, speck removal and
/// optional thickening. Returns an alpha mask (white lines on transparent).
///
/// [detail] 0..1 trades smoothness for detail; [weight] 1..3 thickens lines.
Rgba extractLineArt(Rgba img, {double detail = 0.5, int weight = 1}) {
  final w = img.width, h = img.height, n = w * h;
  final d = detail.clamp(0.0, 1.0);
  final sigma = 2.6 - 1.8 * d;
  final g = gaussianBlur(luminance(img), w, h, sigma);

  // Sobel gradients.
  final mag = Float32List(n);
  final dir = Uint8List(n); // 0: horizontal edge normal, 1: 45, 2: vertical, 3: 135
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = (g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1]) - (g[i - w - 1] + 2 * g[i - 1] + g[i + w - 1]);
      final gy = (g[i + w - 1] + 2 * g[i + w] + g[i + w + 1]) - (g[i - w - 1] + 2 * g[i - w] + g[i - w + 1]);
      mag[i] = math.sqrt(gx * gx + gy * gy);
      var a = math.atan2(gy, gx) * 180 / math.pi;
      if (a < 0) a += 180;
      dir[i] = a < 22.5 || a >= 157.5
          ? 0
          : a < 67.5
              ? 1
              : a < 112.5
                  ? 2
                  : 3;
    }
  }

  // Non-maximum suppression.
  final thin = Float32List(n);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final m = mag[i];
      if (m == 0) continue;
      double a, b;
      switch (dir[i]) {
        case 0:
          a = mag[i - 1];
          b = mag[i + 1];
        case 1:
          a = mag[i - w - 1];
          b = mag[i + w + 1];
        case 2:
          a = mag[i - w];
          b = mag[i + w];
        default:
          a = mag[i - w + 1];
          b = mag[i + w - 1];
      }
      if (m >= a && m > b) thin[i] = m;
    }
  }

  // Thresholds from the distribution of surviving magnitudes.
  final values = <double>[];
  for (var i = 0; i < n; i++) {
    if (thin[i] > 0) values.add(thin[i]);
  }
  final out = Uint8List(n);
  if (values.isEmpty) return maskToRgba(out, w, h);
  values.sort();
  final strongFraction = 0.10 + 0.25 * d;
  var high = values[((1 - strongFraction) * (values.length - 1)).round()];
  high = math.max(high, 24.0);
  final low = high * 0.45;

  // Hysteresis.
  final stack = Int32List(n);
  var sp = 0;
  for (var i = 0; i < n; i++) {
    if (thin[i] >= high && out[i] == 0) {
      out[i] = 1;
      stack[sp++] = i;
      while (sp > 0) {
        final c = stack[--sp];
        final cx = c % w, cy = c ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          final yy = cy + dy;
          if (yy < 0 || yy >= h) continue;
          for (var dx = -1; dx <= 1; dx++) {
            final xx = cx + dx;
            if (xx < 0 || xx >= w) continue;
            final j = yy * w + xx;
            if (out[j] == 0 && thin[j] >= low) {
              out[j] = 1;
              stack[sp++] = j;
            }
          }
        }
      }
    }
  }

  // Remove short specks (8-connected components below a length budget).
  final minLen = math.max(4, ((12 - 8 * d) * math.max(w, h) / 1000).round());
  final seen = Uint8List(n);
  final comp = <int>[];
  for (var i = 0; i < n; i++) {
    if (out[i] == 0 || seen[i] != 0) continue;
    comp.clear();
    sp = 0;
    stack[sp++] = i;
    seen[i] = 1;
    while (sp > 0) {
      final c = stack[--sp];
      comp.add(c);
      final cx = c % w, cy = c ~/ w;
      for (var dy = -1; dy <= 1; dy++) {
        final yy = cy + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final xx = cx + dx;
          if (xx < 0 || xx >= w) continue;
          final j = yy * w + xx;
          if (out[j] != 0 && seen[j] == 0) {
            seen[j] = 1;
            stack[sp++] = j;
          }
        }
      }
    }
    if (comp.length < minLen) {
      for (final c in comp) {
        out[c] = 0;
      }
    }
  }

  return maskToRgba(dilate(out, w, h, weight - 1), w, h);
}

/// Square dilation by [radius] pixels.
Uint8List dilate(Uint8List mask, int w, int h, int radius) {
  if (radius <= 0) return mask;
  final tmp = Uint8List(w * h), out = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 0;
      for (var dx = -radius; dx <= radius && v == 0; dx++) {
        final xx = x + dx;
        if (xx >= 0 && xx < w && mask[y * w + xx] != 0) v = 1;
      }
      tmp[y * w + x] = v;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var v = 0;
      for (var dy = -radius; dy <= radius && v == 0; dy++) {
        final yy = y + dy;
        if (yy >= 0 && yy < h && tmp[yy * w + x] != 0) v = 1;
      }
      out[y * w + x] = v;
    }
  }
  return out;
}
