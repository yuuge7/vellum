import 'dart:math' as math;
import 'dart:ui';

import '../tracking/geometry.dart';

/// Maps camera analysis-frame pixels (sensor orientation) to logical view
/// coordinates of a full-screen, cover-fitted, upright camera preview.
class CameraGeometry {
  CameraGeometry({
    required this.viewSize,
    required this.previewSize,
    required this.sensorOrientation,
    required this.frameSize,
  });

  /// Logical size of the view that shows the preview (cover fit).
  final Size viewSize;

  /// Preview buffer size as reported by the camera (sensor orientation,
  /// usually landscape).
  final Size previewSize;

  /// Degrees the sensor image must be rotated clockwise to be upright.
  final int sensorOrientation;

  /// Analysis frame size (sensor orientation).
  final Size frameSize;

  bool get _swaps => sensorOrientation % 180 != 0;

  Size get uprightPreview => _swaps ? Size(previewSize.height, previewSize.width) : previewSize;

  /// Where the upright preview lands in view coordinates (may extend past the
  /// view edges because of cover fitting).
  Rect get previewRect {
    final up = uprightPreview;
    final s = math.max(viewSize.width / up.width, viewSize.height / up.height);
    final w = up.width * s, h = up.height * s;
    return Rect.fromLTWH((viewSize.width - w) / 2, (viewSize.height - h) / 2, w, h);
  }

  /// Frame pixel -> view point transform.
  Homography get frameToView {
    final n = Homography.fromList(<double>[1 / frameSize.width, 0, 0, 0, 1 / frameSize.height, 0, 0, 0, 1]);
    // Frame and preview are centre crops of the same sensor area.
    final af = frameSize.width / frameSize.height, ap = previewSize.width / previewSize.height;
    Homography crop;
    if ((af - ap).abs() < 1e-3) {
      crop = Homography.identity();
    } else if (af < ap) {
      final k = ap / af;
      crop = Homography.fromList(<double>[1, 0, 0, 0, k, 0.5 - 0.5 * k, 0, 0, 1]);
    } else {
      final k = af / ap;
      crop = Homography.fromList(<double>[k, 0, 0.5 - 0.5 * k, 0, 1, 0, 0, 0, 1]);
    }
    final Homography rot = switch (sensorOrientation % 360) {
      90 => Homography.fromList(<double>[0, -1, 1, 1, 0, 0, 0, 0, 1]),
      180 => Homography.fromList(<double>[-1, 0, 1, 0, -1, 1, 0, 0, 1]),
      270 => Homography.fromList(<double>[0, 1, 0, -1, 0, 1, 0, 0, 1]),
      _ => Homography.identity(),
    };
    final r = previewRect;
    final v = Homography.fromList(<double>[r.width, 0, r.left, 0, r.height, r.top, 0, 0, 1]);
    return v * rot * crop * n;
  }

  /// Axis-aligned view rectangle covered by the whole analysis frame.
  Rect get frameRectInView {
    final h = frameToView;
    final pts = [
      h.applyXY(0, 0),
      h.applyXY(frameSize.width, 0),
      h.applyXY(frameSize.width, frameSize.height),
      h.applyXY(0, frameSize.height),
    ];
    final xs = pts.map((p) => p.x), ys = pts.map((p) => p.y);
    return Rect.fromLTRB(xs.reduce(math.min), ys.reduce(math.min), xs.reduce(math.max), ys.reduce(math.max));
  }
}
