import 'dart:math' as math;
import 'dart:typed_data';

import 'raster.dart';

/// Lifts finished artwork off its page: the page colour becomes transparent
/// and every mark keeps an alpha proportional to how far it stands out, so
/// only the drawing itself is overlaid on the paper. Unlike edge detection
/// this keeps a pen line as one line instead of outlining both of its sides.
///
/// The page is taken from the image border, so light art on a dark page
/// works too. [detail] 0..1 keeps progressively fainter marks (shading,
/// pencil texture). Returns premultiplied white; the UI tints it.
Rgba extractInk(Rgba img, {double detail = 0.5}) {
  final w = img.width, h = img.height, n = w * h;
  final lum = luminance(img);
  final out = Uint8List(n * 4);
  if (n == 0) return Rgba(w, h, out);

  // Median brightness of a thin frame around the image = the page.
  final hist = Int32List(256);
  final t = math.max(1, math.min(w, h) ~/ 40);
  var count = 0;
  for (var y = 0; y < h; y++) {
    final edgeRow = y < t || y >= h - t;
    for (var x = 0; x < w; x++) {
      if (!edgeRow && x >= t && x < w - t) {
        x = w - t - 1; // jump across the interior
        continue;
      }
      hist[lum[y * w + x].round().clamp(0, 255)]++;
      count++;
    }
  }
  var page = 255, acc = 0;
  for (var v = 0; v < 256; v++) {
    acc += hist[v];
    if (acc * 2 >= count) {
      page = v;
      break;
    }
  }
  final darkPage = page < 110;
  final span = math.max(darkPage ? 255.0 - page : page.toDouble(), 1.0);

  final lo = 0.45 - 0.4 * detail.clamp(0.0, 1.0), hi = lo + 0.2;
  for (var i = 0, j = 0; i < n; i++, j += 4) {
    final d = (darkPage ? lum[i] - page : page - lum[i]) / span;
    final s = ((d - lo) / (hi - lo)).clamp(0.0, 1.0);
    final a = (s * s * (3 - 2 * s) * 255).round();
    out[j] = a;
    out[j + 1] = a;
    out[j + 2] = a;
    out[j + 3] = a;
  }
  return Rgba(w, h, out);
}
