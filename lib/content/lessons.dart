import 'dart:math' as math;
import 'dart:ui';

import 'pen.dart';

typedef ArtDraw = void Function(Canvas c);

/// One stage of a guided drawing.
class LessonStepSpec {
  const LessonStepSpec(this.title, this.tip, this.draw);
  final String title;
  final String tip;
  final ArtDraw draw;
}

/// A guided drawing: an ordered list of layers on a 1000 x 1000 art board.
class LessonSpec {
  const LessonSpec({required this.id, required this.title, required this.blurb, required this.steps});
  final String id;
  final String title;
  final String blurb;
  final List<LessonStepSpec> steps;

  /// Draws every step (used for thumbnails and as a finished template).
  void drawAll(Canvas c) {
    for (final s in steps) {
      s.draw(c);
    }
  }
}

// ---------------------------------------------------------------- Cat face

void _catHead(Canvas c) {
  c.drawOval(Rect.fromCenter(center: const Offset(500, 560), width: 520, height: 460), pen(8));
  final g = guidePen();
  dashed(c, line(500, 320, 500, 800), g);
  dashed(c, line(250, 540, 750, 540), g);
  dashed(c, Path()..addOval(Rect.fromCircle(center: const Offset(500, 655), radius: 95)), g);
}

void _catEars(Canvas c) {
  final outer = Path()
    ..moveTo(292, 432)
    ..quadraticBezierTo(248, 290, 288, 168)
    ..quadraticBezierTo(382, 238, 452, 338);
  final inner = Path()
    ..moveTo(314, 382)
    ..quadraticBezierTo(292, 285, 307, 228)
    ..quadraticBezierTo(362, 272, 408, 336);
  sym(c, outer, pen(8));
  sym(c, inner, pen(5));
}

void _catEyes(Canvas c) {
  final eye = Path()
    ..moveTo(338, 542)
    ..quadraticBezierTo(400, 478, 462, 542)
    ..quadraticBezierTo(400, 594, 338, 542)
    ..close();
  sym(c, eye, pen(7));
  for (final x in [400.0, 600.0]) {
    c.drawOval(Rect.fromCenter(center: Offset(x, 540), width: 26, height: 62), fill());
  }
  final nose = Path()
    ..moveTo(468, 622)
    ..quadraticBezierTo(500, 610, 532, 622)
    ..quadraticBezierTo(516, 650, 500, 662)
    ..quadraticBezierTo(484, 650, 468, 622)
    ..close();
  c.drawPath(nose, fill());
}

void _catDetails(Canvas c) {
  final p = pen(6);
  c.drawPath(line(500, 662, 500, 690), p);
  sym(
    c,
    Path()
      ..moveTo(500, 690)
      ..quadraticBezierTo(470, 728, 434, 702),
    p,
  );
  final w = pen(4);
  for (final (y0, y1) in [(648.0, 608.0), (668.0, 668.0), (688.0, 730.0)]) {
    sym(
      c,
      Path()
        ..moveTo(382, y0)
        ..quadraticBezierTo(280, (y0 + y1) / 2 - 8, 176, y1),
      w,
    );
  }
  sym(
    c,
    Path()
      ..moveTo(254, 568)
      ..lineTo(226, 598)
      ..lineTo(250, 610)
      ..lineTo(230, 642)
      ..lineTo(258, 648),
    pen(6),
  );
  c.drawPath(
    Path()
      ..moveTo(468, 748)
      ..quadraticBezierTo(500, 764, 532, 748),
    pen(5),
  );
  for (final (x, bend) in [(472.0, -6.0), (500.0, 0.0), (528.0, 6.0)]) {
    c.drawPath(
      Path()
        ..moveTo(x, 356)
        ..quadraticBezierTo(x + bend, 392, x + bend * 0.5, 424),
      pen(5),
    );
  }
}

// ---------------------------------------------------------------- Tulip

void _tulipGuide(Canvas c) {
  c.drawPath(
    Path()
      ..moveTo(500, 960)
      ..cubicTo(522, 800, 474, 650, 500, 480),
    pen(9),
  );
  dashed(c, Path()..addOval(Rect.fromCenter(center: const Offset(500, 360), width: 270, height: 310)), guidePen());
}

void _tulipPetals(Canvas c) {
  final p = pen(7);
  c.drawPath(
    Path()
      ..moveTo(420, 470)
      ..cubicTo(388, 380, 428, 262, 500, 208)
      ..cubicTo(572, 262, 612, 380, 580, 470)
      ..quadraticBezierTo(500, 512, 420, 470)
      ..close(),
    p,
  );
  sym(
    c,
    Path()
      ..moveTo(426, 482)
      ..cubicTo(356, 452, 336, 330, 358, 236)
      ..cubicTo(410, 278, 448, 330, 468, 398),
    p,
  );
}

void _tulipLeaves(Canvas c) {
  final p = pen(7);
  c.drawPath(
    Path()
      ..moveTo(496, 902)
      ..cubicTo(420, 822, 332, 722, 300, 560)
      ..cubicTo(392, 640, 470, 742, 498, 842),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(503, 862)
      ..cubicTo(560, 782, 640, 702, 692, 600)
      ..cubicTo(652, 722, 582, 822, 505, 922),
    p,
  );
}

void _tulipDetails(Canvas c) {
  final p = pen(4);
  c.drawPath(
    Path()
      ..moveTo(500, 232)
      ..quadraticBezierTo(506, 352, 500, 482),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(492, 872)
      ..quadraticBezierTo(382, 742, 312, 582),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(506, 892)
      ..quadraticBezierTo(612, 762, 684, 612),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(330, 962)
      ..quadraticBezierTo(500, 944, 680, 962),
    pen(6),
  );
}

// ---------------------------------------------------------------- Head (Loomis)

void _headBall(Canvas c) {
  c.drawCircle(const Offset(500, 420), 210, pen(8));
}

void _headLines(Canvas c) {
  final g = guidePen();
  dashed(c, line(500, 180, 500, 780), g);
  for (final (y, half) in [(260.0, 150.0), (420.0, 230.0), (580.0, 190.0), (740.0, 70.0)]) {
    dashed(c, line(500 - half, y, 500 + half, y), g);
  }
  // Side plane of the cranium.
  dashed(c, Path()..addOval(Rect.fromCenter(center: const Offset(500, 420), width: 250, height: 330)), g);
}

void _headJaw(Canvas c) {
  final p = pen(8);
  c.drawPath(
    Path()
      ..moveTo(318, 520)
      ..cubicTo(322, 650, 380, 718, 450, 736)
      ..quadraticBezierTo(500, 752, 550, 736)
      ..cubicTo(620, 718, 678, 650, 682, 520),
    p,
  );
  sym(
    c,
    Path()
      ..moveTo(300, 440)
      ..cubicTo(254, 430, 250, 562, 312, 584),
    pen(7),
  );
  sym(c, line(402, 712, 392, 890), pen(7));
}

void _headFeatures(Canvas c) {
  final p = pen(6);
  final eye = Path()
    ..moveTo(372, 472)
    ..quadraticBezierTo(420, 438, 468, 472)
    ..quadraticBezierTo(420, 494, 372, 472)
    ..close();
  sym(c, eye, p);
  c.drawCircle(const Offset(420, 469), 15, fill());
  c.drawCircle(const Offset(580, 469), 15, fill());
  sym(
    c,
    Path()
      ..moveTo(366, 432)
      ..quadraticBezierTo(420, 404, 472, 426),
    pen(9),
  );
  c.drawPath(
    Path()
      ..moveTo(488, 482)
      ..lineTo(480, 556),
    pen(5),
  );
  c.drawPath(
    Path()
      ..moveTo(462, 574)
      ..quadraticBezierTo(500, 594, 538, 574),
    p,
  );
  sym(
    c,
    Path()
      ..moveTo(470, 560)
      ..quadraticBezierTo(458, 572, 466, 580),
    pen(5),
  );
  c.drawPath(
    Path()
      ..moveTo(452, 632)
      ..quadraticBezierTo(478, 616, 500, 624)
      ..quadraticBezierTo(522, 616, 548, 632),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(448, 634)
      ..quadraticBezierTo(500, 644, 552, 634),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(466, 646)
      ..quadraticBezierTo(500, 672, 534, 646),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(296, 392)
      ..cubicTo(306, 238, 420, 216, 500, 246)
      ..cubicTo(580, 216, 694, 238, 704, 392),
    pen(8),
  );
}

// ---------------------------------------------------------------- Cube

const _vp1 = Offset(60, 330), _vp2 = Offset(940, 330);
const _frontTop = Offset(470, 480), _frontBottom = Offset(470, 800);

Offset _along(Offset from, Offset to, double x) {
  final t = (x - from.dx) / (to.dx - from.dx);
  return Offset(x, from.dy + (to.dy - from.dy) * t);
}

Offset _intersect(Offset a1, Offset a2, Offset b1, Offset b2) {
  final d = (a2.dx - a1.dx) * (b2.dy - b1.dy) - (a2.dy - a1.dy) * (b2.dx - b1.dx);
  final t = ((b1.dx - a1.dx) * (b2.dy - b1.dy) - (b1.dy - a1.dy) * (b2.dx - b1.dx)) / d;
  return Offset(a1.dx + (a2.dx - a1.dx) * t, a1.dy + (a2.dy - a1.dy) * t);
}

final _leftTop = _along(_frontTop, _vp1, 260), _leftBottom = _along(_frontBottom, _vp1, 260);
final _rightTop = _along(_frontTop, _vp2, 700), _rightBottom = _along(_frontBottom, _vp2, 700);
final _backTop = _intersect(_leftTop, _vp2, _rightTop, _vp1);

void _cubeHorizon(Canvas c) {
  c.drawLine(const Offset(30, 330), const Offset(970, 330), pen(5));
  for (final vp in [_vp1, _vp2]) {
    c.drawCircle(vp, 12, fill());
    c.drawLine(vp.translate(-26, 0), vp.translate(26, 0), pen(4));
    c.drawLine(vp.translate(0, -26), vp.translate(0, 26), pen(4));
  }
}

void _cubeEdge(Canvas c) {
  c.drawLine(_frontTop, _frontBottom, pen(9));
}

void _cubeSides(Canvas c) {
  final g = guidePen(3);
  for (final p in [_frontTop, _frontBottom]) {
    dashed(c, Path()..moveTo(p.dx, p.dy)..lineTo(_vp1.dx, _vp1.dy), g);
    dashed(c, Path()..moveTo(p.dx, p.dy)..lineTo(_vp2.dx, _vp2.dy), g);
  }
  final p = pen(8);
  c.drawLine(_leftTop, _leftBottom, p);
  c.drawLine(_rightTop, _rightBottom, p);
  c.drawLine(_frontTop, _leftTop, p);
  c.drawLine(_frontBottom, _leftBottom, p);
  c.drawLine(_frontTop, _rightTop, p);
  c.drawLine(_frontBottom, _rightBottom, p);
}

void _cubeTop(Canvas c) {
  final g = guidePen(3);
  dashed(c, Path()..moveTo(_leftTop.dx, _leftTop.dy)..lineTo(_vp2.dx, _vp2.dy), g);
  dashed(c, Path()..moveTo(_rightTop.dx, _rightTop.dy)..lineTo(_vp1.dx, _vp1.dy), g);
  final p = pen(8);
  c.drawLine(_leftTop, _backTop, p);
  c.drawLine(_rightTop, _backTop, p);
  // Hatch the shadow side (right face).
  final face = Path()
    ..moveTo(_frontTop.dx, _frontTop.dy)
    ..lineTo(_rightTop.dx, _rightTop.dy)
    ..lineTo(_rightBottom.dx, _rightBottom.dy)
    ..lineTo(_frontBottom.dx, _frontBottom.dy)
    ..close();
  c.save();
  c.clipPath(face);
  final h = pen(4);
  for (var x = 380.0; x < 820; x += 22) {
    c.drawLine(Offset(x, 900), Offset(x + 160, 300), h);
  }
  c.restore();
}

final List<LessonSpec> builtInLessons = <LessonSpec>[
  const LessonSpec(
    id: 'cat',
    title: 'Cat face',
    blurb: 'Circles first, whiskers last',
    steps: [
      LessonStepSpec('Block in the head', 'Trace the big oval, then the faint cross that places the eyes and muzzle.', _catHead),
      LessonStepSpec('Add the ears', 'Two soft triangles sitting on the top of the oval.', _catEars),
      LessonStepSpec('Eyes and nose', 'Almond eyes sit on the horizontal guide. Fill the pupils solid.', _catEyes),
      LessonStepSpec('Mouth, whiskers, fur', 'Light, quick strokes for whiskers. Finish with the cheek fur.', _catDetails),
    ],
  ),
  const LessonSpec(
    id: 'tulip',
    title: 'Tulip',
    blurb: 'Stem, cup, leaves',
    steps: [
      LessonStepSpec('Stem and bloom guide', 'One confident curve for the stem, a light oval for the flower.', _tulipGuide),
      LessonStepSpec('Petals', 'Draw the front cup, then the two side petals behind it.', _tulipPetals),
      LessonStepSpec('Leaves', 'Long leaves grow from the base and taper to a point.', _tulipLeaves),
      LessonStepSpec('Details', 'Centre lines on the petal and leaves, and a ground line.', _tulipDetails),
    ],
  ),
  const LessonSpec(
    id: 'head',
    title: 'Head proportions',
    blurb: 'The Loomis method, front view',
    steps: [
      LessonStepSpec('Cranium', 'Start with a ball for the cranium.', _headBall),
      LessonStepSpec('Guide lines', 'Hairline, brow, nose and chin are evenly spaced.', _headLines),
      LessonStepSpec('Jaw, ears, neck', 'Jaw runs from the side plane to the chin. Ears sit between brow and nose.', _headJaw),
      LessonStepSpec('Features', 'Eyes sit just under the brow line, one eye-width apart.', _headFeatures),
    ],
  ),
  LessonSpec(
    id: 'cube',
    title: 'Cube in perspective',
    blurb: 'Two-point perspective',
    steps: [
      const LessonStepSpec('Horizon and vanishing points', 'A level horizon with a vanishing point at each end.', _cubeHorizon),
      const LessonStepSpec('Nearest edge', 'The corner closest to you is one vertical line.', _cubeEdge),
      const LessonStepSpec('Sides', 'Pull both ends of the edge toward each vanishing point, then close with verticals.', _cubeSides),
      const LessonStepSpec('Top and shading', 'Cross lines to the opposite points to find the back corner. Hatch the shadow side.', _cubeTop),
    ],
  ),
];

/// Radians helper used by several templates.
double rad(double deg) => deg * math.pi / 180;
