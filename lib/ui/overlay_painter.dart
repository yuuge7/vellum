import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../camera/ar_session.dart';
import '../models/overlay_controller.dart';
import '../tracking/geometry.dart';
import '../tracking/tracker.dart';
import 'theme.dart';

/// 3x3 homography -> column-major 4x4 matrix usable by [Canvas.transform].
Float64List homographyToMatrix4(Homography h) {
  final m = h.m;
  return Float64List.fromList(<double>[
    m[0], m[3], 0, m[6], //
    m[1], m[4], 0, m[7], //
    0, 0, 1, 0, //
    m[2], m[5], 0, m[8], //
  ]);
}

Paint _layerPaint(double alpha, Color? tint) => Paint()
  ..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0))
  ..filterQuality = FilterQuality.medium
  ..colorFilter = tint == null ? null : ColorFilter.mode(tint, BlendMode.srcIn);

void _drawLayer(Canvas c, ui.Image img, Rect dst, double alpha, [Color? tint]) {
  if (alpha <= 0.002) return;
  c.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, _layerPaint(alpha, tint));
}

/// Paints the reference layer. With [forExport] the strobe is ignored so
/// recorded frames don't flicker.
void paintOverlay(Canvas canvas, OverlayController c, {bool forExport = false}) {
  final alpha = forExport ? c.opacity : (c.strobeAlpha.value ?? c.opacity);
  if (alpha <= 0.002) return;
  final rect = Offset.zero & c.doc.size;
  canvas.save();
  canvas.transform(homographyToMatrix4(c.effective));
  canvas.saveLayer(rect, Paint()..color = Color.fromRGBO(255, 255, 255, alpha));
  final doc = c.doc;
  final player = c.player;
  if (doc.isLesson && player != null) {
    final steps = doc.steps!;
    final reveal = c.stepReveal.value;
    final idx = player.index;
    final dir = player.lastDirection;
    for (var i = 0; i < steps.length; i++) {
      double a;
      if (player.isComplete) {
        a = i == idx ? 1 : 0.5 + 0.5 * reveal;
      } else if (i < idx) {
        a = (dir > 0 && i == idx - 1) ? 1 - 0.5 * reveal : 0.5;
      } else if (i == idx) {
        a = dir > 0 ? reveal : (dir < 0 ? 0.5 + 0.5 * reveal : 1);
      } else if (i == idx + 1 && dir < 0) {
        a = 1 - reveal;
      } else {
        a = 0;
      }
      _drawLayer(canvas, steps[i].image, rect, a, steps[i].tint);
    }
  } else {
    switch (c.mode) {
      case ViewMode.original:
        _drawLayer(canvas, doc.image!, rect, 1);
      case ViewMode.ink:
        final k = c.inkImage;
        if (k == null) {
          _drawLayer(canvas, doc.image!, rect, 0.25);
        } else {
          _drawLayer(canvas, k, rect, 1, c.lineInk.color);
        }
      case ViewMode.lines:
        final l = c.linesImage;
        if (l == null) {
          _drawLayer(canvas, doc.image!, rect, 0.25);
        } else {
          _drawLayer(canvas, l, rect, 1, c.lineInk.color);
        }
      case ViewMode.tones:
        final t = c.toneImages;
        if (t == null) {
          _drawLayer(canvas, doc.image!, rect, 0.25);
        } else {
          final colors = c.toneColors;
          for (var i = 0; i < t.length; i++) {
            if (i < c.toneVisible.length && c.toneVisible[i]) _drawLayer(canvas, t[i], rect, 1, colors[i]);
          }
        }
    }
  }
  canvas.restore();
  if (c.grid > 0) _drawGrid(canvas, c, rect, alpha);
  canvas.restore();
}

/// Square guide cells counted across the short side, in content space so the
/// grid sticks to the picture. Stays readable when the image is faint, but
/// goes dark with it (opacity 0, strobe off-phase): those moments are for
/// looking at the bare drawing.
void _drawGrid(Canvas canvas, OverlayController c, Rect rect, double alpha) {
  final m = c.effective.m;
  final w8 = m[8].abs() < 1e-9 ? 1.0 : m[8].abs();
  final scale = math.sqrt((m[0] * m[4] - m[1] * m[3]).abs()) / w8;
  if (scale < 1e-6) return;
  final cell = rect.shortestSide / c.grid;
  final path = Path()..addRect(rect);
  for (var x = cell; x < rect.width - 0.5; x += cell) {
    path
      ..moveTo(x, 0)
      ..lineTo(x, rect.height);
  }
  for (var y = cell; y < rect.height - 0.5; y += cell) {
    path
      ..moveTo(0, y)
      ..lineTo(rect.width, y);
  }
  final a = math.max(alpha, 0.5);
  final stroke = Paint()..style = PaintingStyle.stroke;
  canvas.drawPath(
    path,
    stroke
      ..strokeWidth = 3 / scale
      ..color = Colors.black.withValues(alpha: 0.3 * a),
  );
  canvas.drawPath(
    path,
    stroke
      ..strokeWidth = 1.2 / scale
      ..color = Palette.blue.withValues(alpha: a),
  );
}

class OverlayPainter extends CustomPainter {
  OverlayPainter(this.controller) : super(repaint: controller.repaint);
  final OverlayController controller;

  @override
  void paint(Canvas canvas, Size size) => paintOverlay(canvas, controller);

  @override
  bool shouldRepaint(OverlayPainter old) => old.controller != controller;
}

/// Registration marks at the image corners, coloured by state, plus the
/// detected sheet outline and tracked feature points while pinning.
class MarksPainter extends CustomPainter {
  MarksPainter(this.overlay, this.ar, {required this.showTracking})
      : super(repaint: Listenable.merge(<Listenable>[overlay.repaint, ar, ar.sheet, ar.points]));

  final OverlayController overlay;
  final ArSession ar;
  final bool showTracking;

  @override
  void paint(Canvas canvas, Size size) {
    if (showTracking) {
      final sheet = ar.sheet.value;
      if (sheet != null) {
        final path = Path()..addPolygon(sheet, true);
        canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Palette.blue.withValues(alpha: ar.anchored ? 0.55 : 0.9),
        );
        for (final p in sheet) {
          canvas.drawCircle(p, 4, Paint()..color = Palette.blue);
        }
      }
      final dot = Paint()..color = Palette.tape.withValues(alpha: 0.85);
      for (final p in ar.points.value) {
        canvas.drawCircle(p, 2.2, dot);
      }
    }

    final Color color;
    if (ar.engaged) {
      color = ar.status == TrackStatus.tracking ? Palette.blue : Palette.tape;
    } else {
      color = overlay.locked ? Palette.tape : Palette.vellum.withValues(alpha: 0.9);
    }
    final h = overlay.effective;
    final w = overlay.doc.size.width, ht = overlay.doc.size.height;
    final corners = <Offset>[
      for (final p in [h.applyXY(0, 0), h.applyXY(w, 0), h.applyXY(w, ht), h.applyXY(0, ht)]) Offset(p.x, p.y),
    ];
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    final shadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = Colors.black.withValues(alpha: 0.35);
    for (var i = 0; i < 4; i++) {
      final p = corners[i], a = corners[(i + 3) % 4], b = corners[(i + 1) % 4];
      final da = _unit(a - p), db = _unit(b - p);
      if (da == null || db == null) continue;
      final len = math.min(26.0, 0.18 * math.min((a - p).distance, (b - p).distance));
      final path = Path()
        ..moveTo(p.dx + da.dx * len, p.dy + da.dy * len)
        ..lineTo(p.dx, p.dy)
        ..lineTo(p.dx + db.dx * len, p.dy + db.dy * len)
        // Registration target: crosshair tails outside the corner + ring.
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx - da.dx * 12, p.dy - da.dy * 12)
        ..moveTo(p.dx, p.dy)
        ..lineTo(p.dx - db.dx * 12, p.dy - db.dy * 12)
        ..addOval(Rect.fromCircle(center: p, radius: 6));
      canvas.drawPath(path, shadow);
      canvas.drawPath(path, stroke);
    }
  }

  static Offset? _unit(Offset v) {
    final d = v.distance;
    return d < 1e-3 ? null : v / d;
  }

  @override
  bool shouldRepaint(MarksPainter old) => old.showTracking != showTracking || old.overlay != overlay;
}

/// Printer's registration mark used as the app mark.
class RegistrationMark extends StatelessWidget {
  const RegistrationMark({super.key, this.size = 28, this.color = Palette.blue});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _RegMarkPainter(color));
}

class _RegMarkPainter extends CustomPainter {
  _RegMarkPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.6, r * 0.12)
      ..color = color;
    canvas.drawCircle(c, r * 0.55, p);
    canvas.drawLine(c.translate(-r, 0), c.translate(r, 0), p);
    canvas.drawLine(c.translate(0, -r), c.translate(0, r), p);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.55), -math.pi / 2, math.pi / 2, true, Paint()..color = color);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r * 0.55), math.pi / 2, math.pi / 2, true, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_RegMarkPainter old) => old.color != color;
}
