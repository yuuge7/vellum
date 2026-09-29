import 'dart:math' as math;
import 'dart:typed_data';

/// RGBA8888 pixel buffer that can cross isolate boundaries cheaply.
class Rgba {
  Rgba(this.width, this.height, this.px) : assert(px.length == width * height * 4);
  final int width;
  final int height;
  final Uint8List px;
}

/// Luminance (0..255) with transparent pixels composited over white paper.
Float32List luminance(Rgba img) {
  final n = img.width * img.height;
  final out = Float32List(n);
  final p = img.px;
  for (var i = 0, j = 0; i < n; i++, j += 4) {
    final a = p[j + 3] / 255.0;
    final l = 0.299 * p[j] + 0.587 * p[j + 1] + 0.114 * p[j + 2];
    out[i] = l * a + 255.0 * (1 - a);
  }
  return out;
}

/// Separable Gaussian blur on a float plane.
Float32List gaussianBlur(Float32List src, int w, int h, double sigma) {
  if (sigma < 0.3) return Float32List.fromList(src);
  final r = math.max(1, (sigma * 3).ceil());
  final k = Float32List(2 * r + 1);
  var sum = 0.0;
  for (var i = -r; i <= r; i++) {
    final v = math.exp(-(i * i) / (2 * sigma * sigma));
    k[i + r] = v;
    sum += v;
  }
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  final tmp = Float32List(w * h), out = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        final xx = (x + i).clamp(0, w - 1);
        s += src[row + xx] * k[i + r];
      }
      tmp[row + x] = s;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var i = -r; i <= r; i++) {
        final yy = (y + i).clamp(0, h - 1);
        s += tmp[yy * w + x] * k[i + r];
      }
      out[y * w + x] = s;
    }
  }
  return out;
}

/// Converts a 0/1 mask into an RGBA image: white where set, transparent
/// elsewhere. The UI tints it with a colour filter.
Rgba maskToRgba(Uint8List mask, int w, int h) {
  final out = Uint8List(w * h * 4);
  for (var i = 0, j = 0; i < w * h; i++, j += 4) {
    if (mask[i] != 0) {
      out[j] = 255;
      out[j + 1] = 255;
      out[j + 2] = 255;
      out[j + 3] = 255;
    }
  }
  return Rgba(w, h, out);
}
