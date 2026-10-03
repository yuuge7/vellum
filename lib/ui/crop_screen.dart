import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

enum _Grip { none, move, topLeft, topRight, bottomRight, bottomLeft, left, top, right, bottom }

/// Full-screen crop. Pops with the chosen rectangle in image pixels, or null
/// when cancelled. Pins saved from the web often carry borders, captions or
/// several drawings; this keeps just the part worth tracing.
class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.image});
  final ui.Image image;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  late Rect _crop = _full;
  _Grip _grip = _Grip.none;

  /// Where the whole image sits inside the gesture area.
  Rect _shown = Rect.zero;

  Rect get _full => Rect.fromLTWH(0, 0, widget.image.width.toDouble(), widget.image.height.toDouble());
  double get _scale => _shown.width / widget.image.width;
  double get _minSide => math.min(48.0, _full.shortestSide);

  Rect get _cropInView => Rect.fromLTRB(
        _shown.left + _crop.left * _scale,
        _shown.top + _crop.top * _scale,
        _shown.left + _crop.right * _scale,
        _shown.top + _crop.bottom * _scale,
      );

  void _onStart(DragStartDetails d) {
    final p = d.localPosition, r = _cropInView;
    const reach = 30.0;
    bool near(Offset c) => (p - c).distance <= reach;
    final inX = p.dx > r.left - reach && p.dx < r.right + reach;
    final inY = p.dy > r.top - reach && p.dy < r.bottom + reach;
    if (near(r.topLeft)) {
      _grip = _Grip.topLeft;
    } else if (near(r.topRight)) {
      _grip = _Grip.topRight;
    } else if (near(r.bottomRight)) {
      _grip = _Grip.bottomRight;
    } else if (near(r.bottomLeft)) {
      _grip = _Grip.bottomLeft;
    } else if ((p.dx - r.left).abs() <= reach && inY) {
      _grip = _Grip.left;
    } else if ((p.dx - r.right).abs() <= reach && inY) {
      _grip = _Grip.right;
    } else if ((p.dy - r.top).abs() <= reach && inX) {
      _grip = _Grip.top;
    } else if ((p.dy - r.bottom).abs() <= reach && inX) {
      _grip = _Grip.bottom;
    } else {
      _grip = r.contains(p) ? _Grip.move : _Grip.none;
    }
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_grip == _Grip.none || _scale <= 0) return;
    final dx = d.delta.dx / _scale, dy = d.delta.dy / _scale;
    final w = _full.width, h = _full.height, m = _minSide;
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    if (_grip == _Grip.move) {
      final sx = dx.clamp(-l, w - r), sy = dy.clamp(-t, h - b);
      l += sx;
      r += sx;
      t += sy;
      b += sy;
    } else {
      const lefts = {_Grip.topLeft, _Grip.bottomLeft, _Grip.left};
      const rights = {_Grip.topRight, _Grip.bottomRight, _Grip.right};
      const tops = {_Grip.topLeft, _Grip.topRight, _Grip.top};
      const bottoms = {_Grip.bottomLeft, _Grip.bottomRight, _Grip.bottom};
      if (lefts.contains(_grip)) l = (l + dx).clamp(0.0, r - m);
      if (rights.contains(_grip)) r = (r + dx).clamp(l + m, w);
      if (tops.contains(_grip)) t = (t + dy).clamp(0.0, b - m);
      if (bottoms.contains(_grip)) b = (b + dy).clamp(t + m, h);
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  Rect get _rounded {
    final l = _crop.left.roundToDouble(), t = _crop.top.roundToDouble();
    return Rect.fromLTRB(l, t, math.max(l + 1, _crop.right.roundToDouble()), math.max(t + 1, _crop.bottom.roundToDouble()));
  }

  @override
  Widget build(BuildContext context) {
    final out = _rounded;
    final changed = out != _full;
    // Keep the corner grips clear of the system back-swipe strips.
    final edges = MediaQuery.systemGestureInsetsOf(context);
    final side = math.max(24.0, math.max(edges.left, edges.right) + 14);
    return Scaffold(
      backgroundColor: Palette.graphite,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: [
                  HudButton(icon: Icons.close, tooltip: 'Cancel crop', onPressed: () => Navigator.of(context).pop()),
                  const SizedBox(width: 12),
                  const Text('Crop', style: TextStyles.title),
                  const Spacer(),
                  TextButton(
                    onPressed: changed ? () => setState(() => _crop = _full) : null,
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: side, vertical: 24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final area = constraints.biggest;
                    final s = math.min(area.width / _full.width, area.height / _full.height);
                    _shown = Rect.fromCenter(center: area.center(Offset.zero), width: _full.width * s, height: _full.height * s);
                    return Semantics(
                      label: 'Crop frame. Drag a corner or an edge to resize, drag inside to move',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: _onStart,
                        onPanUpdate: _onUpdate,
                        onPanEnd: (_) => _grip = _Grip.none,
                        child: CustomPaint(
                          painter: _CropPainter(widget.image, _shown, _cropInView),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Drag a corner or an edge. Drag inside to move the frame.', style: TextStyles.bodyDim),
                      ),
                      const SizedBox(width: 12),
                      Text('${out.width.round()} × ${out.height.round()} px', style: TextStyles.mono),
                    ],
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: changed ? () => Navigator.of(context).pop(out) : null,
                    icon: const Icon(Icons.crop, size: 18),
                    label: const Text('Crop'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      textStyle: TextStyles.label.copyWith(fontSize: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.shown, this.crop);
  final ui.Image image;
  final Rect shown;
  final Rect crop;

  @override
  void paint(Canvas canvas, Size size) {
    // Line-art templates are transparent, so the picture sits on paper.
    canvas.drawRect(shown, Paint()..color = Palette.paper);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      shown,
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(shown), Path()..addRect(crop)),
      Paint()..color = Palette.graphite.withValues(alpha: 0.72),
    );
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Palette.blue.withValues(alpha: 0.55);
    for (var i = 1; i < 3; i++) {
      final x = crop.left + crop.width * i / 3, y = crop.top + crop.height * i / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), thin);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), thin);
    }
    canvas.drawRect(crop, thin..color = Palette.blue);
    // Registration brackets on the corners, as on the tracing screen.
    final bracket = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = Palette.blue;
    final len = math.min(22.0, crop.shortestSide / 3);
    for (final (c, dx, dy) in [
      (crop.topLeft, 1.0, 1.0),
      (crop.topRight, -1.0, 1.0),
      (crop.bottomRight, -1.0, -1.0),
      (crop.bottomLeft, 1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + dx * len, c.dy)
          ..lineTo(c.dx, c.dy)
          ..lineTo(c.dx, c.dy + dy * len),
        bracket,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.crop != crop || old.shown != shown || old.image != image;
}
