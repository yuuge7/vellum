import 'dart:math' as math;
import 'dart:ui';

import 'lessons.dart';
import 'pen.dart';

enum TemplateCategory {
  animals('Animals'),
  botanical('Botanical'),
  objects('Objects'),
  people('People'),
  patterns('Patterns & grids'),
  photos('Photos');

  const TemplateCategory(this.label);
  final String label;
}

/// A built-in reference drawn procedurally on a 1000 x 1000 board.
class TemplateSpec {
  const TemplateSpec({required this.id, required this.name, required this.category, required this.draw, this.opaque = false});
  final String id;
  final String name;
  final TemplateCategory category;
  final ArtDraw draw;

  /// Photo-like templates fill the board; line art is transparent.
  final bool opaque;
}

LessonSpec _lesson(String id) => builtInLessons.firstWhere((l) => l.id == id);

final List<TemplateSpec> builtInTemplates = <TemplateSpec>[
  TemplateSpec(id: 't-cat', name: 'Cat', category: TemplateCategory.animals, draw: (c) => _lesson('cat').drawAll(c)),
  const TemplateSpec(id: 't-fish', name: 'Koi', category: TemplateCategory.animals, draw: _fish),
  const TemplateSpec(id: 't-butterfly', name: 'Butterfly', category: TemplateCategory.animals, draw: _butterfly),
  const TemplateSpec(id: 't-owl', name: 'Owl', category: TemplateCategory.animals, draw: _owl),
  TemplateSpec(id: 't-tulip', name: 'Tulip', category: TemplateCategory.botanical, draw: (c) => _lesson('tulip').drawAll(c)),
  const TemplateSpec(id: 't-sunflower', name: 'Sunflower', category: TemplateCategory.botanical, draw: _sunflower),
  const TemplateSpec(id: 't-leaf', name: 'Leaf', category: TemplateCategory.botanical, draw: _leaf),
  const TemplateSpec(id: 't-pine', name: 'Pine', category: TemplateCategory.botanical, draw: _pine),
  const TemplateSpec(id: 't-mug', name: 'Mug', category: TemplateCategory.objects, draw: _mug),
  const TemplateSpec(id: 't-house', name: 'House', category: TemplateCategory.objects, draw: _house),
  const TemplateSpec(id: 't-bulb', name: 'Light bulb', category: TemplateCategory.objects, draw: _bulb),
  TemplateSpec(id: 't-cube', name: 'Cube', category: TemplateCategory.objects, draw: (c) => _lesson('cube').drawAll(c)),
  TemplateSpec(id: 't-head', name: 'Head proportions', category: TemplateCategory.people, draw: (c) => _lesson('head').drawAll(c)),
  const TemplateSpec(id: 't-eye', name: 'Eye study', category: TemplateCategory.people, draw: _eye),
  const TemplateSpec(id: 't-mandala', name: 'Mandala', category: TemplateCategory.patterns, draw: _mandala),
  const TemplateSpec(id: 't-spiral', name: 'Spiral', category: TemplateCategory.patterns, draw: _spiral),
  const TemplateSpec(id: 't-grid', name: 'Thirds grid', category: TemplateCategory.patterns, draw: _grid),
  const TemplateSpec(id: 't-still', name: 'Still life', category: TemplateCategory.photos, draw: _stillLife, opaque: true),
  const TemplateSpec(id: 't-hills', name: 'Hills at dusk', category: TemplateCategory.photos, draw: _hills, opaque: true),
];

// ---------------------------------------------------------------- Animals

void _fish(Canvas c) {
  final p = pen(7);
  c.drawPath(
    Path()
      ..moveTo(180, 500)
      ..cubicTo(270, 338, 540, 308, 720, 482)
      ..lineTo(720, 518)
      ..cubicTo(540, 692, 270, 662, 180, 500)
      ..close(),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(716, 486)
      ..cubicTo(780, 420, 830, 362, 884, 330)
      ..cubicTo(850, 420, 850, 580, 884, 670)
      ..cubicTo(830, 640, 780, 580, 716, 514),
    p,
  );
  for (final y in [430.0, 500.0, 570.0]) {
    c.drawPath(
      Path()
        ..moveTo(730, 500)
        ..quadraticBezierTo(800, y, 858, y + (y - 500) * 1.6),
      pen(3),
    );
  }
  c.drawCircle(const Offset(292, 468), 26, pen(6));
  c.drawCircle(const Offset(296, 468), 11, fill());
  c.drawPath(
    Path()
      ..moveTo(372, 398)
      ..quadraticBezierTo(330, 500, 372, 604),
    pen(6),
  );
  c.drawPath(
    Path()
      ..moveTo(420, 352)
      ..quadraticBezierTo(520, 226, 642, 330),
    pen(6),
  );
  c.drawPath(
    Path()
      ..moveTo(420, 540)
      ..quadraticBezierTo(470, 612, 522, 582)
      ..quadraticBezierTo(480, 562, 420, 540),
    pen(5),
  );
  c.drawPath(
    Path()
      ..moveTo(500, 640)
      ..quadraticBezierTo(540, 722, 602, 648),
    pen(5),
  );
  final scale = pen(3.5);
  for (final (y, x0, x1) in [(446.0, 450.0, 620.0), (506.0, 430.0, 660.0), (566.0, 460.0, 610.0)]) {
    for (var x = x0; x <= x1; x += 52) {
      c.drawArc(Rect.fromCircle(center: Offset(x, y), radius: 26), -math.pi / 2, math.pi, false, scale);
    }
  }
}

void _butterfly(Canvas c) {
  final p = pen(7);
  c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(486, 330, 514, 700), const Radius.circular(14)), p);
  c.drawCircle(const Offset(500, 304), 26, p);
  sym(
    c,
    Path()
      ..moveTo(490, 284)
      ..cubicTo(470, 220, 440, 172, 402, 152),
    pen(5),
  );
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(396, 148), radius: 10)), fill());
  sym(
    c,
    Path()
      ..moveTo(488, 382)
      ..cubicTo(400, 200, 160, 160, 150, 300)
      ..cubicTo(140, 420, 300, 500, 488, 500),
    p,
  );
  sym(
    c,
    Path()
      ..moveTo(488, 512)
      ..cubicTo(330, 500, 220, 600, 260, 720)
      ..cubicTo(300, 820, 440, 760, 494, 640),
    p,
  );
  final d = pen(4);
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(290, 312), radius: 46)), d);
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(372, 424), radius: 22)), d);
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(334, 660), radius: 32)), d);
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(290, 312), radius: 16)), fill());
  sym(
    c,
    Path()
      ..moveTo(484, 430)
      ..quadraticBezierTo(360, 380, 200, 260),
    pen(3),
  );
  sym(
    c,
    Path()
      ..moveTo(486, 560)
      ..quadraticBezierTo(380, 600, 290, 730),
    pen(3),
  );
}

void _owl(Canvas c) {
  final p = pen(7);
  c.drawPath(
    Path()
      ..moveTo(500, 222)
      ..cubicTo(700, 222, 760, 500, 720, 700)
      ..cubicTo(690, 840, 310, 840, 280, 700)
      ..cubicTo(240, 500, 300, 222, 500, 222)
      ..close(),
    p,
  );
  sym(
    c,
    Path()
      ..moveTo(342, 292)
      ..lineTo(312, 170)
      ..lineTo(422, 244),
    p,
  );
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(410, 400), radius: 96)), pen(5));
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(410, 400), radius: 48)), pen(6));
  sym(c, Path()..addOval(Rect.fromCircle(center: const Offset(410, 402), radius: 22)), fill());
  c.drawPath(
    Path()
      ..moveTo(478, 452)
      ..lineTo(522, 452)
      ..lineTo(500, 512)
      ..close(),
    fill(),
  );
  sym(
    c,
    Path()
      ..moveTo(304, 520)
      ..cubicTo(262, 620, 292, 732, 362, 792),
    p,
  );
  final f = pen(4);
  for (final (y, n) in [(560.0, 3), (620.0, 4), (680.0, 3)]) {
    for (var i = 0; i < n; i++) {
      final x = 500 + (i - (n - 1) / 2) * 62;
      c.drawPath(
        Path()
          ..moveTo(x - 18, y)
          ..lineTo(x, y + 16)
          ..lineTo(x + 18, y),
        f,
      );
    }
  }
  c.drawPath(
    Path()
      ..moveTo(150, 830)
      ..quadraticBezierTo(500, 800, 862, 842),
    pen(8),
  );
  c.drawPath(
    Path()
      ..moveTo(150, 866)
      ..quadraticBezierTo(500, 836, 862, 876),
    pen(6),
  );
  for (final x in [440.0, 560.0]) {
    for (final dx in [-18.0, 0.0, 18.0]) {
      c.drawLine(Offset(x + dx * 0.5, 800), Offset(x + dx, 836), pen(6));
    }
  }
}

// ---------------------------------------------------------------- Botanical

void _sunflower(Canvas c) {
  const center = Offset(500, 380);
  final p = pen(6);
  c.save();
  c.translate(center.dx, center.dy);
  for (var i = 0; i < 18; i++) {
    c.save();
    c.rotate(i * 2 * math.pi / 18);
    c.drawPath(
      Path()
        ..moveTo(122, 0)
        ..quadraticBezierTo(190, -44, 262, 0)
        ..quadraticBezierTo(190, 44, 122, 0),
      p,
    );
    c.restore();
  }
  c.restore();
  c.drawCircle(center, 120, pen(7));
  c.drawCircle(center, 92, pen(4));
  const golden = 2.39996323;
  for (var i = 1; i < 130; i++) {
    final r = 7.6 * math.sqrt(i.toDouble());
    final a = i * golden;
    c.drawCircle(center + Offset(math.cos(a) * r, math.sin(a) * r), 3.2, fill());
  }
  c.drawPath(
    Path()
      ..moveTo(500, 500)
      ..cubicTo(512, 650, 490, 800, 500, 962),
    pen(8),
  );
  c.drawPath(
    Path()
      ..moveTo(503, 722)
      ..cubicTo(600, 640, 720, 660, 762, 702)
      ..cubicTo(700, 762, 600, 772, 503, 742),
    pen(6),
  );
  c.drawPath(
    Path()
      ..moveTo(506, 732)
      ..quadraticBezierTo(640, 700, 740, 704),
    pen(3),
  );
}

void _leaf(Canvas c) {
  c.drawPath(
    Path()
      ..moveTo(500, 118)
      ..cubicTo(762, 260, 802, 620, 500, 880)
      ..cubicTo(198, 620, 238, 260, 500, 118)
      ..close(),
    pen(8),
  );
  c.drawLine(const Offset(500, 880), const Offset(504, 962), pen(8));
  c.drawPath(
    Path()
      ..moveTo(500, 140)
      ..quadraticBezierTo(512, 500, 500, 878),
    pen(5),
  );
  final v = pen(3.5);
  for (var y = 250.0; y <= 770; y += 86) {
    final t = (y - 118) / (880 - 118);
    final half = 300 * math.sin(math.pi * math.pow(t, 0.8)) * 0.82;
    sym(
      c,
      Path()
        ..moveTo(504, y)
        ..quadraticBezierTo(500 - half * 0.45, y - 22, 500 - half, y - 92),
      v,
    );
  }
}

void _pine(Canvas c) {
  final p = pen(7);
  c.drawRect(const Rect.fromLTRB(470, 812, 530, 930), p);
  final tiers = [(150.0, 360.0, 130.0), (290.0, 520.0, 200.0), (430.0, 680.0, 270.0), (570.0, 820.0, 330.0)];
  for (final (top, bottom, half) in tiers) {
    final path = Path()..moveTo(500, top);
    path.lineTo(500 + half, bottom);
    const n = 6;
    for (var i = 1; i <= n; i++) {
      final x = 500 + half - (2 * half) * i / n;
      final up = i.isOdd ? 26.0 : 0.0;
      path.lineTo(x, bottom - up);
    }
    path.close();
    c.drawPath(path, p);
  }
  c.drawPath(
    Path()
      ..moveTo(200, 932)
      ..quadraticBezierTo(500, 912, 800, 932),
    pen(6),
  );
}

// ---------------------------------------------------------------- Objects

void _mug(Canvas c) {
  final p = pen(7);
  c.drawOval(Rect.fromCenter(center: const Offset(460, 330), width: 400, height: 110), p);
  c.drawLine(const Offset(260, 330), const Offset(282, 782), p);
  c.drawLine(const Offset(660, 330), const Offset(638, 782), p);
  c.drawArc(Rect.fromCenter(center: const Offset(460, 782), width: 356, height: 92), 0, math.pi, false, p);
  c.drawArc(Rect.fromCenter(center: const Offset(460, 346), width: 350, height: 78), math.pi, -math.pi, false, pen(4));
  c.drawPath(
    Path()
      ..moveTo(656, 420)
      ..cubicTo(806, 400, 826, 642, 646, 682),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(654, 470)
      ..cubicTo(744, 460, 752, 612, 646, 632),
    pen(5),
  );
  for (final x in [390.0, 460.0, 530.0]) {
    c.drawPath(
      Path()
        ..moveTo(x, 250)
        ..cubicTo(x - 30, 210, x + 30, 170, x, 130)
        ..cubicTo(x - 20, 104, x + 10, 88, x, 70),
      pen(4),
    );
  }
}

void _house(Canvas c) {
  final p = pen(7);
  c.drawRect(const Rect.fromLTRB(250, 480, 750, 850), p);
  c.drawPath(
    Path()
      ..moveTo(200, 500)
      ..lineTo(500, 230)
      ..lineTo(800, 500),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(620, 338)
      ..lineTo(620, 262)
      ..lineTo(682, 262)
      ..lineTo(682, 394),
    p,
  );
  c.drawRect(const Rect.fromLTRB(450, 652, 550, 850), p);
  c.drawCircle(const Offset(532, 752), 7, fill());
  for (final l in [300.0, 600.0]) {
    final r = Rect.fromLTWH(l, 560, 100, 100);
    c.drawRect(r, p);
    c.drawLine(r.topCenter, r.bottomCenter, pen(4));
    c.drawLine(r.centerLeft, r.centerRight, pen(4));
  }
  c.drawCircle(const Offset(500, 400), 40, p);
  c.drawLine(const Offset(120, 850), const Offset(880, 850), pen(6));
}

void _bulb(Canvas c) {
  final p = pen(7);
  c.drawPath(
    Path()
      ..moveTo(420, 650)
      ..cubicTo(410, 560, 300, 520, 300, 390)
      ..cubicTo(300, 262, 400, 180, 500, 180)
      ..cubicTo(600, 180, 700, 262, 700, 390)
      ..cubicTo(700, 520, 590, 560, 580, 650)
      ..close(),
    p,
  );
  for (final (y, inset) in [(650.0, 0.0), (694.0, 4.0), (738.0, 10.0)]) {
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(418 + inset, y, 582 - inset, y + 44), const Radius.circular(12)), p);
  }
  c.drawPath(
    Path()
      ..moveTo(462, 782)
      ..quadraticBezierTo(500, 830, 538, 782),
    p,
  );
  final f = pen(4);
  c.drawLine(const Offset(462, 650), const Offset(450, 480), f);
  c.drawLine(const Offset(538, 650), const Offset(550, 480), f);
  c.drawPath(
    Path()
      ..moveTo(450, 480)
      ..lineTo(466, 452)
      ..lineTo(484, 480)
      ..lineTo(500, 452)
      ..lineTo(516, 480)
      ..lineTo(534, 452)
      ..lineTo(550, 480),
    f,
  );
  for (var i = 0; i < 7; i++) {
    final a = math.pi + i * math.pi / 6;
    final d = Offset(math.cos(a), math.sin(a));
    c.drawLine(const Offset(500, 390) + d * 250, const Offset(500, 390) + d * 310, pen(6));
  }
}

// ---------------------------------------------------------------- People

void _eye(Canvas c) {
  final p = pen(8);
  c.drawPath(
    Path()
      ..moveTo(170, 520)
      ..cubicTo(300, 330, 700, 320, 840, 500)
      ..cubicTo(700, 660, 320, 680, 170, 520)
      ..close(),
    p,
  );
  c.drawPath(
    Path()
      ..moveTo(190, 470)
      ..cubicTo(320, 290, 680, 270, 850, 440),
    pen(5),
  );
  c.drawCircle(const Offset(505, 500), 150, pen(7));
  c.drawCircle(const Offset(505, 500), 62, fill());
  c.drawCircle(const Offset(460, 450), 26, Paint()..color = const Color(0xFFFFFFFF));
  final r = pen(3);
  for (var i = 0; i < 24; i++) {
    final a = i * 2 * math.pi / 24;
    final d = Offset(math.cos(a), math.sin(a));
    c.drawLine(const Offset(505, 500) + d * 72, const Offset(505, 500) + d * 138, r);
  }
  final lash = pen(5);
  for (var i = 0; i < 9; i++) {
    final t = 0.15 + i * 0.085;
    final x = 170 + (840 - 170) * t;
    final y = 520 - math.sin(t * math.pi) * 190;
    c.drawLine(Offset(x, y), Offset(x + 18 + 20 * t, y - 64 + 10 * (t - 0.5).abs() * 4), lash);
  }
  c.drawPath(
    Path()
      ..moveTo(150, 280)
      ..cubicTo(330, 150, 650, 140, 860, 260),
    pen(12),
  );
}

// ---------------------------------------------------------------- Patterns

void _mandala(Canvas c) {
  const o = Offset(500, 500);
  final p = pen(5);
  for (final r in [60.0, 130.0, 210.0, 300.0, 410.0]) {
    c.drawCircle(o, r, p);
  }
  c.save();
  c.translate(o.dx, o.dy);
  for (var i = 0; i < 12; i++) {
    c.save();
    c.rotate(i * math.pi / 6);
    c.drawPath(
      Path()
        ..moveTo(60, 0)
        ..quadraticBezierTo(98, -34, 130, 0)
        ..quadraticBezierTo(98, 34, 60, 0),
      p,
    );
    c.restore();
  }
  for (var i = 0; i < 16; i++) {
    c.save();
    c.rotate(i * math.pi / 8 + math.pi / 16);
    c.drawPath(
      Path()
        ..moveTo(130, -30)
        ..quadraticBezierTo(180, -20, 210, 0)
        ..quadraticBezierTo(180, 20, 130, 30),
      p,
    );
    c.restore();
  }
  for (var i = 0; i < 24; i++) {
    c.save();
    c.rotate(i * math.pi / 12);
    c.drawCircle(const Offset(255, 0), 22, p);
    c.drawArc(Rect.fromCircle(center: const Offset(300, 0), radius: 78), -0.45, 0.9, false, p);
    c.drawCircle(const Offset(440, 0), 7, fill());
    c.restore();
  }
  c.restore();
  c.drawCircle(o, 22, fill());
}

void _spiral(Canvas c) {
  final path = Path()..moveTo(500, 500);
  for (var t = 0.0; t < 36; t += 0.05) {
    final r = 11.5 * t;
    path.lineTo(500 + r * math.cos(t), 500 + r * math.sin(t));
  }
  c.drawPath(path, pen(6));
}

void _grid(Canvas c) {
  final g = guidePen(3);
  for (var i = 1; i < 9; i++) {
    final v = 100 + i * 100.0;
    if (i % 3 == 0) continue;
    dashed(c, line(v, 100, v, 900), g, dash: 10, gap: 10);
    dashed(c, line(100, v, 900, v), g, dash: 10, gap: 10);
  }
  final p = pen(6);
  c.drawRect(const Rect.fromLTRB(100, 100, 900, 900), pen(8));
  for (final v in [366.67, 633.33]) {
    c.drawLine(Offset(v, 100), Offset(v, 900), p);
    c.drawLine(Offset(100, v), Offset(900, v), p);
  }
  c.drawLine(const Offset(100, 100), const Offset(900, 900), pen(3));
  c.drawLine(const Offset(900, 100), const Offset(100, 900), pen(3));
  c.drawCircle(const Offset(500, 500), 10, fill());
}

// ---------------------------------------------------------------- Photos

void _stillLife(Canvas c) {
  const board = Rect.fromLTWH(0, 0, 1000, 1000);
  c.drawRect(
    board,
    Paint()
      ..shader = Gradient.linear(const Offset(0, 0), const Offset(0, 640), [const Color(0xFF7A746C), const Color(0xFF4E4A45)]),
  );
  c.drawRect(
    const Rect.fromLTRB(0, 640, 1000, 1000),
    Paint()
      ..shader = Gradient.linear(const Offset(0, 640), const Offset(0, 1000), [const Color(0xFFA08C74), const Color(0xFF5A4C3E)]),
  );
  c.drawRect(const Rect.fromLTRB(0, 636, 1000, 646), fill(const Color(0xFFC8B49A)));
  final shadow = Paint()
    ..color = const Color(0xCC231D18)
    ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22);
  c.drawOval(Rect.fromCenter(center: const Offset(520, 720), width: 420, height: 80), shadow);
  c.drawOval(Rect.fromCenter(center: const Offset(810, 716), width: 260, height: 60), shadow);
  // Cup (cylinder).
  const cup = Rect.fromLTRB(640, 470, 800, 704);
  c.drawRect(
    cup,
    Paint()
      ..shader = Gradient.linear(
        cup.centerLeft,
        cup.centerRight,
        [const Color(0xFF4A433C), const Color(0xFFD9D0C4), const Color(0xFFF6F2EC), const Color(0xFFA69C90), const Color(0xFF3E3832)],
        [0, 0.28, 0.42, 0.75, 1],
      ),
  );
  c.drawOval(Rect.fromCenter(center: const Offset(720, 704), width: 160, height: 36), fill(const Color(0xFF6E655A)));
  c.drawOval(Rect.fromCenter(center: const Offset(720, 470), width: 160, height: 40), fill(const Color(0xFFE6DED2)));
  c.drawOval(Rect.fromCenter(center: const Offset(720, 474), width: 136, height: 28), fill(const Color(0xFF3B2A1F)));
  // Big sphere.
  c.drawCircle(
    const Offset(420, 540),
    180,
    Paint()
      ..shader = Gradient.radial(
        const Offset(420, 540),
        180,
        [const Color(0xFFF7F3EE), const Color(0xFFC4BBAF), const Color(0xFF6E655B), const Color(0xFF3A342E)],
        [0, 0.35, 0.82, 1],
        TileMode.clamp,
        null,
        const Offset(350, 460),
        0,
      ),
  );
  // Small sphere.
  c.drawCircle(
    const Offset(250, 760),
    62,
    Paint()
      ..shader = Gradient.radial(
        const Offset(250, 760),
        62,
        [const Color(0xFFE9E0D4), const Color(0xFF8A7E70), const Color(0xFF2E2924)],
        [0, 0.55, 1],
        TileMode.clamp,
        null,
        const Offset(228, 736),
        0,
      ),
  );
}

void _hills(Canvas c) {
  c.drawRect(
    const Rect.fromLTWH(0, 0, 1000, 1000),
    Paint()
      ..shader = Gradient.linear(
        const Offset(0, 0),
        const Offset(0, 620),
        [const Color(0xFF26304F), const Color(0xFF8B6F8E), const Color(0xFFF1B67E)],
        [0, 0.55, 1],
      ),
  );
  c.drawCircle(const Offset(640, 470), 74, fill(const Color(0xFFFFF1D2)));
  final layers = [
    (520.0, 36.0, 0.010, const Color(0xFF9C7C95)),
    (600.0, 52.0, 0.007, const Color(0xFF6B5676)),
    (690.0, 60.0, 0.006, const Color(0xFF41365A)),
    (800.0, 70.0, 0.005, const Color(0xFF1D1829)),
  ];
  var seed = 0.0;
  for (final (base, amp, freq, color) in layers) {
    final path = Path()..moveTo(0, 1000);
    for (var x = 0.0; x <= 1000; x += 10) {
      final y = base - amp * math.sin(x * freq + seed) - amp * 0.4 * math.sin(x * freq * 2.7 + seed * 2);
      path.lineTo(x, y);
    }
    path
      ..lineTo(1000, 1000)
      ..close();
    c.drawPath(path, fill(color));
    seed += 1.7;
  }
  final tree = fill(const Color(0xFF0E0B14));
  for (final (x, h) in [(120.0, 150.0), (170.0, 110.0), (820.0, 170.0), (880.0, 120.0), (930.0, 90.0)]) {
    final base = 800 - 70 * math.sin(x * 0.005 + 5.1) - 28 * math.sin(x * 0.0135 + 10.2);
    c.drawPath(
      Path()
        ..moveTo(x, base - h)
        ..lineTo(x + h * 0.28, base + 6)
        ..lineTo(x - h * 0.28, base + 6)
        ..close(),
      tree,
    );
  }
}
