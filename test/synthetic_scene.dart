import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ar_drawing/tracking/geometry.dart';

/// Renders a luminance frame of a sheet of paper (with pencil marks) lying on
/// a textured desk. [paperToImage] / [deskToImage] place each plane in the
/// frame, so a moving phone warps both and a sliding sheet warps only the
/// paper. 2x2 supersampling keeps the sheet edges sub-pixel accurate.
Uint8List renderScene({
  required int width,
  required int height,
  required Homography paperToImage,
  required Homography deskToImage,
  double paperWidth = 300,
  double paperHeight = 400,
  bool marks = true,
}) {
  final pInv = paperToImage.inverse()!;
  final dInv = deskToImage.inverse()!;
  final out = Uint8List(width * height);

  double sample(double x, double y) {
    final p = pInv.applyXY(x, y);
    if (p.x >= 0 && p.y >= 0 && p.x < paperWidth && p.y < paperHeight) {
      if (!marks) return 228;
      // Dots on a grid + a couple of pencil strokes give trackable texture.
      final cx = (p.x / 38).floor() * 38 + 19, cy = (p.y / 38).floor() * 38 + 19;
      final cell = ((p.x / 38).floor() * 7 + (p.y / 38).floor() * 13) % 5;
      if (cell != 0 && (p.x - cx) * (p.x - cx) + (p.y - cy) * (p.y - cy) < 16 + cell * 6) return 70;
      final d1 = ((p.y - 0.6 * p.x - 60)).abs() / math.sqrt(1.36);
      if (d1 < 1.6 && p.x > 30 && p.x < 260) return 90;
      return 228;
    }
    final d = dInv.applyXY(x, y);
    final v = 72 +
        26 * math.sin(d.x * 0.23) * math.cos(d.y * 0.19) +
        18 * math.sin((d.x + 2 * d.y) * 0.11) +
        ((((d.x * 0.7).floor() * 73856093) ^ ((d.y * 0.7).floor() * 19349663)) & 15);
    return v;
  }

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final v = (sample(x + 0.25, y + 0.25) + sample(x + 0.75, y + 0.25) + sample(x + 0.25, y + 0.75) + sample(x + 0.75, y + 0.75)) / 4;
      out[y * width + x] = v.round().clamp(0, 255);
    }
  }
  return out;
}

/// Similarity + mild perspective placement helper.
Homography place({double tx = 0, double ty = 0, double scale = 1, double angle = 0, double px = 0, double py = 0, double cx = 0, double cy = 0}) {
  final c = math.cos(angle) * scale, s = math.sin(angle) * scale;
  // Rotate/scale about (cx, cy), then translate.
  final m = Homography.fromList(<double>[c, -s, cx - c * cx + s * cy + tx, s, c, cy - s * cx - c * cy + ty, px, py, 1]);
  return m;
}
