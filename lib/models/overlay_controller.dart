import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../imaging/image_io.dart';
import '../imaging/raster.dart';
import '../imaging/stencil.dart';
import '../imaging/tonal.dart';
import '../tracking/geometry.dart';
import 'lesson_player.dart';
import 'trace_document.dart';

enum ViewMode { original, lines, tones }

enum StrobeStyle {
  blink('On / off'),
  half('50% / off');

  const StrobeStyle(this.label);
  final String label;
}

enum LineInk {
  graphite('Graphite', Color(0xFF141416)),
  blue('Blue', Color(0xFF2F9BD6)),
  red('Red', Color(0xFFD83A2E)),
  white('White', Color(0xFFF7F7F2));

  const LineInk(this.label, this.color);
  final String label;
  final Color color;
}

const List<Color> _grayTones3 = [Color(0xFF1C1C1C), Color(0xFF777777), Color(0xFFD2D2D2)];
const List<Color> _grayTones4 = [Color(0xFF121212), Color(0xFF4E4E4E), Color(0xFF929292), Color(0xFFD8D8D8)];
const List<Color> _codedTones3 = [Color(0xFF3A2FA0), Color(0xFFE0782A), Color(0xFFF3D34A)];
const List<Color> _codedTones4 = [Color(0xFF3A2FA0), Color(0xFF148C84), Color(0xFFE0782A), Color(0xFFF3D34A)];

// Top-level so the isolate closures capture nothing but their arguments.
Future<Rgba> _linesInBackground(Rgba src, double detail, int weight) =>
    Isolate.run(() => extractLineArt(src, detail: detail, weight: weight));

Future<TonalBreakdown> _tonesInBackground(Rgba src, int levels) => Isolate.run(() => tonalBreakdown(src, levels: levels));

/// Builds the similarity transform that moves [from] to [to] while scaling
/// by [scale] and rotating by [rotation] radians around it.
Homography similarityAbout(Offset from, Offset to, double scale, double rotation) {
  final c = math.cos(rotation) * scale, s = math.sin(rotation) * scale;
  final tx = to.dx - (c * from.dx - s * from.dy);
  final ty = to.dy - (s * from.dx + c * from.dy);
  return Homography.fromList(<double>[c, -s, tx, s, c, ty, 0, 0, 1]);
}

/// State of the reference image layer: placement, opacity, lock, strobe and
/// the derived line-art / tonal layers.
class OverlayController extends ChangeNotifier {
  OverlayController(this.doc) : player = doc.isLesson ? LessonPlayer(doc.steps!.length) : null;

  final TraceDocument doc;
  final LessonPlayer? player;

  /// Content pixels -> view (as placed by the user, in "paper space").
  final ValueNotifier<Homography> base = ValueNotifier<Homography>(Homography.identity());

  /// Tracking correction applied on top of [base] (identity when not anchored).
  final ValueNotifier<Homography> pose = ValueNotifier<Homography>(Homography.identity());

  /// Absolute opacity override while the strobe is running (null = off).
  final ValueNotifier<double?> strobeAlpha = ValueNotifier<double?>(null);

  /// 0..1 fade progress of the current lesson step.
  final ValueNotifier<double> stepReveal = ValueNotifier<double>(1);

  late final Listenable repaint = Listenable.merge(<Listenable>[this, base, pose, strobeAlpha, stepReveal]);

  bool _disposed = false;

  Homography get effective => pose.value * base.value;

  // ------------------------------------------------------------ placement

  bool _placed = false;
  bool get placed => _placed;

  /// Centres the content in the part of [view] not covered by the HUD
  /// (top bar, right tool rail, bottom sliders), unless already placed.
  void fitTo(Size view, {bool force = false}) {
    if (_placed && !force) return;
    final cs = doc.size;
    final area = Rect.fromLTRB(16, view.height * 0.1, view.width - 80, view.height * 0.72);
    final s = math.min(area.width / cs.width, area.height / cs.height);
    final tx = area.center.dx - cs.width * s / 2;
    final ty = area.center.dy - cs.height * s / 2;
    final fit = Homography.fromList(<double>[s, 0, tx, 0, s, ty, 0, 0, 1]);
    base.value = (pose.value.inverse() ?? Homography.identity()) * fit;
    _placed = true;
    _flipped = false;
    notifyListeners();
  }

  /// Applies a screen-space gesture delta. While anchored the delta is
  /// expressed in paper space so the image stays pinned afterwards.
  void applyViewDelta(Homography d) {
    if (_locked) return;
    final p = pose.value;
    final pInv = p.inverse() ?? Homography.identity();
    base.value = (pInv * d * p * base.value).normalized();
  }

  bool _flipped = false;
  bool get flipped => _flipped;

  void flip() {
    final w = doc.size.width;
    base.value = base.value * Homography.fromList(<double>[-1, 0, w, 0, 1, 0, 0, 0, 1]);
    _flipped = !_flipped;
    notifyListeners();
  }

  /// Folds the tracking pose into [base] (used when tracking stops).
  void bakePose() {
    base.value = (pose.value * base.value).normalized();
    pose.value = Homography.identity();
  }

  // ------------------------------------------------------------ opacity / lock

  double _opacity = 0.6;
  double get opacity => _opacity;
  set opacity(double v) {
    _opacity = v.clamp(0.0, 1.0);
    notifyListeners();
  }

  bool _locked = false;
  bool get locked => _locked;
  set locked(bool v) {
    _locked = v;
    notifyListeners();
  }

  // ------------------------------------------------------------ strobe

  bool _strobeOn = false;
  double _strobeHz = 4;
  StrobeStyle _strobeStyle = StrobeStyle.blink;
  Timer? _strobeTimer;
  bool _strobePhase = true;

  bool get strobeOn => _strobeOn;
  double get strobeHz => _strobeHz;
  StrobeStyle get strobeStyle => _strobeStyle;

  set strobeOn(bool v) {
    _strobeOn = v;
    _restartStrobe();
    notifyListeners();
  }

  set strobeHz(double v) {
    _strobeHz = v.clamp(1, 10);
    if (_strobeOn) _restartStrobe();
    notifyListeners();
  }

  set strobeStyle(StrobeStyle v) {
    _strobeStyle = v;
    if (_strobeOn) _restartStrobe();
    notifyListeners();
  }

  void _restartStrobe() {
    _strobeTimer?.cancel();
    _strobeTimer = null;
    if (!_strobeOn) {
      strobeAlpha.value = null;
      return;
    }
    _strobePhase = true;
    _applyStrobe();
    final half = Duration(microseconds: (1e6 / (2 * _strobeHz)).round());
    _strobeTimer = Timer.periodic(half, (_) {
      _strobePhase = !_strobePhase;
      _applyStrobe();
    });
  }

  void _applyStrobe() {
    final on = _strobeStyle == StrobeStyle.half ? 0.5 : math.max(_opacity, 0.35);
    strobeAlpha.value = _strobePhase ? on : 0.0;
  }

  // ------------------------------------------------------------ view modes

  ViewMode _mode = ViewMode.original;
  ViewMode get mode => _mode;

  String? _busy;

  /// Non-null while a derived layer is being computed (a user-facing label).
  String? get busy => _busy;

  String? _error;
  String? get error => _error;

  Rgba? _pixels;
  Future<Rgba> _sourcePixels() async => _pixels ??= await imageToRgba(doc.image!, maxDim: 1000);

  Future<void> setMode(ViewMode m) async {
    _mode = m;
    notifyListeners();
    if (m == ViewMode.lines && _lines == null) await recomputeLines();
    if (m == ViewMode.tones && _tones == null) await recomputeTones();
  }

  // Lines
  ui.Image? _lines;
  double _lineDetail = 0.55;
  int _lineWeight = 2;
  LineInk _lineInk = LineInk.graphite;
  int _lineJob = 0;

  ui.Image? get linesImage => _lines;
  double get lineDetail => _lineDetail;
  int get lineWeight => _lineWeight;
  LineInk get lineInk => _lineInk;

  set lineInk(LineInk v) {
    _lineInk = v;
    notifyListeners();
  }

  void setLineParams({double? detail, int? weight}) {
    _lineDetail = detail ?? _lineDetail;
    _lineWeight = weight ?? _lineWeight;
    notifyListeners();
    recomputeLines();
  }

  Future<void> recomputeLines() async {
    if (doc.image == null) return;
    final job = ++_lineJob;
    _busy = 'Tracing outlines';
    notifyListeners();
    try {
      final src = await _sourcePixels();
      final detail = _lineDetail, weight = _lineWeight;
      final out = await _linesInBackground(src, detail, weight);
      final img = await rgbaToImage(out);
      if (_disposed || job != _lineJob) {
        img.dispose();
        return;
      }
      _lines?.dispose();
      _lines = img;
      _error = null;
    } catch (e) {
      _error = 'Could not extract outlines: $e';
    } finally {
      if (job == _lineJob && !_disposed) {
        _busy = null;
        notifyListeners();
      }
    }
  }

  // Tones
  List<ui.Image>? _tones;
  List<double> _toneCoverage = const <double>[];
  List<bool> _toneVisible = const <bool>[];
  int _toneLevels = 3;
  bool _toneColorCoded = false;
  int _toneJob = 0;

  List<ui.Image>? get toneImages => _tones;
  List<double> get toneCoverage => _toneCoverage;
  List<bool> get toneVisible => _toneVisible;
  int get toneLevels => _toneLevels;
  bool get toneColorCoded => _toneColorCoded;

  List<Color> get toneColors => _toneColorCoded
      ? (_toneLevels == 3 ? _codedTones3 : _codedTones4)
      : (_toneLevels == 3 ? _grayTones3 : _grayTones4);

  List<String> get toneNames => _toneLevels == 3
      ? const ['Shadows', 'Mid-tones', 'Highlights']
      : const ['Deep shadows', 'Shadows', 'Mid-tones', 'Highlights'];

  set toneColorCoded(bool v) {
    _toneColorCoded = v;
    notifyListeners();
  }

  void toggleTone(int i) {
    if (i < 0 || i >= _toneVisible.length) return;
    _toneVisible = List<bool>.of(_toneVisible)..[i] = !_toneVisible[i];
    notifyListeners();
  }

  void setToneLevels(int levels) {
    if (levels == _toneLevels) return;
    _toneLevels = levels;
    notifyListeners();
    recomputeTones();
  }

  Future<void> recomputeTones() async {
    if (doc.image == null) return;
    final job = ++_toneJob;
    _busy = 'Separating tones';
    notifyListeners();
    try {
      final src = await _sourcePixels();
      final levels = _toneLevels;
      final result = await _tonesInBackground(src, levels);
      final imgs = <ui.Image>[for (final l in result.layers) await rgbaToImage(l)];
      if (_disposed || job != _toneJob) {
        for (final i in imgs) {
          i.dispose();
        }
        return;
      }
      for (final i in _tones ?? const <ui.Image>[]) {
        i.dispose();
      }
      _tones = imgs;
      _toneCoverage = result.coverage;
      _toneVisible = List<bool>.filled(imgs.length, true);
      _error = null;
    } catch (e) {
      _error = 'Could not separate tones: $e';
    } finally {
      if (job == _toneJob && !_disposed) {
        _busy = null;
        notifyListeners();
      }
    }
  }

  /// Builds a four-step lesson from the current photo: outline first, then
  /// shadows, mid-tones and highlights.
  Future<TraceDocument?> buildPhotoLesson() async {
    if (doc.image == null) return null;
    _busy = 'Building lesson';
    notifyListeners();
    try {
      final src = await _sourcePixels();
      final detail = _lineDetail, weight = _lineWeight;
      final lines = await _linesInBackground(src, detail, weight);
      final tones = await _tonesInBackground(src, 3);
      final steps = <StepLayer>[
        StepLayer(
          image: await rgbaToImage(lines),
          title: 'Outline',
          tip: 'Trace the main contours lightly. Skip tiny details for now.',
          tint: LineInk.graphite.color,
        ),
        StepLayer(
          image: await rgbaToImage(tones.layers[0]),
          title: 'Shadows',
          tip: 'Fill the darkest shapes first. Press harder or use a soft pencil.',
          tint: _codedTones3[0],
        ),
        StepLayer(
          image: await rgbaToImage(tones.layers[1]),
          title: 'Mid-tones',
          tip: 'Shade these areas with even, medium pressure.',
          tint: _codedTones3[1],
        ),
        StepLayer(
          image: await rgbaToImage(tones.layers[2]),
          title: 'Highlights',
          tip: 'Keep these areas light. Lift graphite with an eraser if needed.',
          tint: _codedTones3[2],
        ),
      ];
      return TraceDocument.lesson(
        title: '${doc.title} lesson',
        steps: steps,
        size: Size(src.width.toDouble(), src.height.toDouble()),
      );
    } catch (e) {
      _error = 'Could not build the lesson: $e';
      return null;
    } finally {
      if (!_disposed) {
        _busy = null;
        notifyListeners();
      }
    }
  }

  /// Copies placement and look from another controller (used when swapping
  /// documents inside the same session). Content sizes may differ, so the
  /// placement is rescaled to keep the same on-screen footprint.
  void adoptPlacement(OverlayController o) {
    final sx = o.doc.size.width / doc.size.width;
    final sy = o.doc.size.height / doc.size.height;
    base.value = o.base.value * Homography.fromList(<double>[sx, 0, 0, 0, sy, 0, 0, 0, 1]);
    pose.value = o.pose.value;
    _opacity = o._opacity;
    _placed = o._placed;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _strobeTimer?.cancel();
    _lines?.dispose();
    for (final i in _tones ?? const <ui.Image>[]) {
      i.dispose();
    }
    base.dispose();
    pose.dispose();
    strobeAlpha.dispose();
    stepReveal.dispose();
    player?.dispose();
    super.dispose();
  }
}
