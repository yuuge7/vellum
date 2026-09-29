import 'dart:math' as math;
import 'dart:typed_data';

/// 8-bit single channel image.
class Gray {
  Gray(this.width, this.height, this.px) : assert(px.length >= width * height);
  Gray.blank(this.width, this.height) : px = Uint8List(width * height);

  final int width;
  final int height;
  final Uint8List px;

  int at(int x, int y) => px[y * width + x];
}

/// Float single channel image (used for pyramids and gradients).
class FImage {
  FImage(this.width, this.height, this.px);
  FImage.blank(this.width, this.height) : px = Float32List(width * height);

  final int width;
  final int height;
  final Float32List px;

  /// Bilinear sample; caller guarantees 0 <= x < w-1 and 0 <= y < h-1.
  double sample(double x, double y) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    final i = y0 * width + x0;
    final a = px[i], b = px[i + 1], c = px[i + width], d = px[i + width + 1];
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy;
  }
}

/// Box-averaged downsample of a camera luminance plane by an integer
/// [factor]. Handles padded rows via [rowStride].
Gray downsampleLuma(Uint8List src, int width, int height, int rowStride, int factor) {
  if (factor <= 1) {
    final out = Gray.blank(width, height);
    for (var y = 0; y < height; y++) {
      out.px.setRange(y * width, y * width + width, src, y * rowStride);
    }
    return out;
  }
  final ow = width ~/ factor, oh = height ~/ factor;
  final out = Gray.blank(ow, oh);
  final area = factor * factor;
  final acc = Int32List(ow);
  for (var oy = 0; oy < oh; oy++) {
    acc.fillRange(0, ow, 0);
    for (var dy = 0; dy < factor; dy++) {
      final rowStart = (oy * factor + dy) * rowStride;
      var sx = rowStart;
      for (var ox = 0; ox < ow; ox++) {
        var s = 0;
        for (var dx = 0; dx < factor; dx++) {
          s += src[sx++];
        }
        acc[ox] += s;
      }
    }
    final o = oy * ow;
    for (var ox = 0; ox < ow; ox++) {
      out.px[o + ox] = acc[ox] ~/ area;
    }
  }
  return out;
}

/// 3x3 box blur (edge pixels clamp).
Gray boxBlur3(Gray g) {
  final w = g.width, h = g.height;
  final tmp = Uint16List(w * h);
  final out = Gray.blank(w, h);
  for (var y = 0; y < h; y++) {
    final r = y * w;
    for (var x = 0; x < w; x++) {
      final xl = x > 0 ? x - 1 : 0, xr = x < w - 1 ? x + 1 : w - 1;
      tmp[r + x] = g.px[r + xl] + g.px[r + x] + g.px[r + xr];
    }
  }
  for (var y = 0; y < h; y++) {
    final yu = (y > 0 ? y - 1 : 0) * w, yd = (y < h - 1 ? y + 1 : h - 1) * w, r = y * w;
    for (var x = 0; x < w; x++) {
      out.px[r + x] = (tmp[yu + x] + tmp[r + x] + tmp[yd + x]) ~/ 9;
    }
  }
  return out;
}

FImage toFloat(Gray g) {
  final f = FImage.blank(g.width, g.height);
  for (var i = 0; i < g.width * g.height; i++) {
    f.px[i] = g.px[i].toDouble();
  }
  return f;
}

/// Separable [1 2 1]/4 smoothing followed by 2x decimation.
FImage pyrDown(FImage src) {
  final w = src.width, h = src.height;
  final ow = w ~/ 2, oh = h ~/ 2;
  final tmp = Float32List(ow * h);
  for (var y = 0; y < h; y++) {
    final r = y * w;
    for (var ox = 0; ox < ow; ox++) {
      final x = ox * 2;
      final xl = x > 0 ? x - 1 : 0, xr = x + 1 < w ? x + 1 : w - 1;
      tmp[y * ow + ox] = (src.px[r + xl] + 2 * src.px[r + x] + src.px[r + xr]) * 0.25;
    }
  }
  final out = FImage.blank(ow, oh);
  for (var oy = 0; oy < oh; oy++) {
    final y = oy * 2;
    final yu = (y > 0 ? y - 1 : 0) * ow, yc = y * ow, yd = (y + 1 < h ? y + 1 : h - 1) * ow;
    for (var ox = 0; ox < ow; ox++) {
      out.px[oy * ow + ox] = (tmp[yu + ox] + 2 * tmp[yc + ox] + tmp[yd + ox]) * 0.25;
    }
  }
  return out;
}

/// Scharr derivatives (scaled to approximate unit-step gradients).
(FImage, FImage) gradients(FImage img) {
  final w = img.width, h = img.height, p = img.px;
  final gx = FImage.blank(w, h), gy = FImage.blank(w, h);
  const k = 1.0 / 32.0;
  for (var y = 1; y < h - 1; y++) {
    final r = y * w;
    for (var x = 1; x < w - 1; x++) {
      final i = r + x;
      final tl = p[i - w - 1], t = p[i - w], tr = p[i - w + 1];
      final l = p[i - 1], rr = p[i + 1];
      final bl = p[i + w - 1], b = p[i + w], br = p[i + w + 1];
      gx.px[i] = (3 * (tr - tl) + 10 * (rr - l) + 3 * (br - bl)) * k;
      gy.px[i] = (3 * (bl - tl) + 10 * (b - t) + 3 * (br - tr)) * k;
    }
  }
  return (gx, gy);
}

/// Image pyramid with per-level gradients for pyramidal Lucas-Kanade.
class Pyramid {
  Pyramid(this.levels, this.gx, this.gy);

  factory Pyramid.build(Gray g, {int levels = 3}) {
    final imgs = <FImage>[toFloat(g)];
    while (imgs.length < levels && imgs.last.width >= 40 && imgs.last.height >= 40) {
      imgs.add(pyrDown(imgs.last));
    }
    final gxs = <FImage>[], gys = <FImage>[];
    for (final im in imgs) {
      final (a, b) = gradients(im);
      gxs.add(a);
      gys.add(b);
    }
    return Pyramid(imgs, gxs, gys);
  }

  final List<FImage> levels;
  final List<FImage> gx;
  final List<FImage> gy;
}

/// Otsu threshold over a 256-bin histogram. Returns (threshold, separation)
/// where separation is the between-class standard deviation (0..~128).
(int, double) otsu(Uint8List px, int count) {
  final hist = Int32List(256);
  for (var i = 0; i < count; i++) {
    hist[px[i]]++;
  }
  var sum = 0.0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }
  var sumB = 0.0, wB = 0, best = 0.0, t = 127;
  for (var i = 0; i < 256; i++) {
    wB += hist[i];
    if (wB == 0) continue;
    final wF = count - wB;
    if (wF == 0) break;
    sumB += i * hist[i];
    final mB = sumB / wB, mF = (sum - sumB) / wF;
    final between = wB.toDouble() * wF * (mB - mF) * (mB - mF);
    if (between > best) {
      best = between;
      t = i;
    }
  }
  final sep = math.sqrt(best / (count.toDouble() * count));
  return (t, sep);
}
