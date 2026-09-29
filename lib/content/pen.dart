import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// Graphite ink used for all built-in line art.
const Color ink = Color(0xFF1B1C1F);

/// Lighter colour for construction lines.
const Color guideInk = Color(0xFF6E737C);

Paint pen([double width = 7, Color color = ink]) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..color = color
  ..isAntiAlias = true;

Paint fill([Color color = ink]) => Paint()
  ..style = PaintingStyle.fill
  ..color = color
  ..isAntiAlias = true;

Paint guidePen([double width = 4]) => pen(width, guideInk);

/// Draws [path] as dashes.
void dashed(Canvas c, Path path, Paint paint, {double dash = 18, double gap = 12}) {
  for (final metric in path.computeMetrics()) {
    var d = 0.0;
    while (d < metric.length) {
      final end = math.min(d + dash, metric.length);
      c.drawPath(metric.extractPath(d, end), paint);
      d = end + gap;
    }
  }
}

Path line(double x1, double y1, double x2, double y2) => Path()
  ..moveTo(x1, y1)
  ..lineTo(x2, y2);

/// Mirrors a path around the vertical axis x = 500 (the art board centre).
Path mirrorX(Path p) => p.transform(Float64List.fromList(<double>[-1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 1000, 0, 0, 1]));

/// Strokes [p] and its mirror image.
void sym(Canvas c, Path p, Paint paint) {
  c.drawPath(p, paint);
  c.drawPath(mirrorX(p), paint);
}
