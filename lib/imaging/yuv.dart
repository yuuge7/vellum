import 'dart:typed_data';

import 'raster.dart';

/// Copy of a YUV_420_888 camera frame that is safe to keep after the camera
/// recycles its buffers.
class YuvFrame {
  YuvFrame({
    required this.width,
    required this.height,
    required this.y,
    required this.u,
    required this.v,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
  });

  final int width;
  final int height;
  final Uint8List y;
  final Uint8List u;
  final Uint8List v;
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
}

/// Converts [f] to upright RGBA, rotating clockwise by [rotation] degrees
/// and subsampling by [step] (nearest neighbour).
Rgba yuvToUprightRgba(YuvFrame f, int rotation, {int step = 2}) {
  final sw = f.width ~/ step, sh = f.height ~/ step;
  final swaps = rotation % 180 != 0;
  final ow = swaps ? sh : sw, oh = swaps ? sw : sh;
  final out = Uint8List(ow * oh * 4);
  final y = f.y, u = f.u, v = f.v;
  final ys = f.yRowStride, uvs = f.uvRowStride, ups = f.uvPixelStride;
  final rot = rotation % 360;
  var o = 0;
  for (var oy = 0; oy < oh; oy++) {
    for (var ox = 0; ox < ow; ox++) {
      int sx, sy;
      switch (rot) {
        case 90:
          sx = oy;
          sy = sh - 1 - ox;
        case 180:
          sx = sw - 1 - ox;
          sy = sh - 1 - oy;
        case 270:
          sx = sw - 1 - oy;
          sy = ox;
        default:
          sx = ox;
          sy = oy;
      }
      final px = sx * step, py = sy * step;
      final yy = y[py * ys + px];
      final ci = (py >> 1) * uvs + (px >> 1) * ups;
      final cu = (ci < u.length ? u[ci] : 128) - 128;
      final cv = (ci < v.length ? v[ci] : 128) - 128;
      var r = yy + ((1436 * cv) >> 10);
      var g = yy - ((352 * cu + 731 * cv) >> 10);
      var b = yy + ((1815 * cu) >> 10);
      out[o++] = r < 0 ? 0 : (r > 255 ? 255 : r);
      out[o++] = g < 0 ? 0 : (g > 255 ? 255 : g);
      out[o++] = b < 0 ? 0 : (b > 255 ? 255 : b);
      out[o++] = 255;
    }
  }
  return Rgba(ow, oh, out);
}
