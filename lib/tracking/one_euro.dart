import 'dart:math' as math;

/// One Euro filter (Casiez et al.): strong smoothing when still, low lag when
/// moving fast. Used to steady the tracked pose without making it sluggish.
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.2, this.beta = 0.015, this.dCutoff = 1.0});

  final double minCutoff;
  final double beta;
  final double dCutoff;

  double? _x;
  double _dx = 0;
  double? _t;

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double filter(double x, double tSeconds) {
    final prevX = _x, prevT = _t;
    if (prevX == null || prevT == null) {
      _x = x;
      _t = tSeconds;
      return x;
    }
    final dt = math.max(1e-3, tSeconds - prevT);
    final dx = (x - prevX) / dt;
    final ad = _alpha(dCutoff, dt);
    _dx = _dx + ad * (dx - _dx);
    final cutoff = minCutoff + beta * _dx.abs();
    final a = _alpha(cutoff, dt);
    final out = prevX + a * (x - prevX);
    _x = out;
    _t = tSeconds;
    return out;
  }

  void reset() {
    _x = null;
    _t = null;
    _dx = 0;
  }
}
