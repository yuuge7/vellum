import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/overlay_controller.dart';
import '../tracking/geometry.dart';
import '../tracking/one_euro.dart';
import '../tracking/tracker.dart';
import '../tracking/tracker_worker.dart';
import 'camera_geometry.dart';
import 'camera_service.dart';

/// Glue between camera frames, the background tracker and the overlay pose.
class ArSession extends ChangeNotifier {
  ArSession({required this.camera, required this.overlay});

  final CameraService camera;
  OverlayController overlay;

  /// Logical size of the camera view; set by the screen on layout.
  Size viewSize = Size.zero;

  TrackerWorker? _worker;
  StreamSubscription<TrackResult>? _sub;
  bool _listening = false;
  bool _wantPreview = false;
  bool _disposed = false;

  TrackTarget _target = TrackTarget.paper;
  TrackStatus _status = TrackStatus.idle;
  String? _note;
  bool _anchored = false;
  bool _anchorPending = false;
  Size? _frameSize;

  /// Sheet outline and feature points in view coordinates (debug overlay).
  final ValueNotifier<List<Offset>?> sheet = ValueNotifier<List<Offset>?>(null);
  final ValueNotifier<List<Offset>> points = ValueNotifier<List<Offset>>(const <Offset>[]);
  double millis = 0;

  final List<OneEuroFilter> _filters = List<OneEuroFilter>.generate(8, (_) => OneEuroFilter());
  final Stopwatch _clock = Stopwatch()..start();

  TrackTarget get target => _target;
  TrackStatus get status => _status;
  String? get note => _note;
  bool get anchored => _anchored;
  bool get anchoring => _anchorPending;
  bool get engaged => _anchored || _anchorPending;

  CameraGeometry? get geometry {
    final ps = camera.previewSize;
    final fs = _frameSize;
    if (ps == null || viewSize.isEmpty) return null;
    return CameraGeometry(
      viewSize: viewSize,
      previewSize: ps,
      sensorOrientation: camera.sensorOrientation,
      frameSize: fs ?? ps,
    );
  }

  /// Keeps frames flowing to the tracker so the sheet outline can be shown
  /// before anchoring (while the AR panel is open).
  Future<void> setPreview(bool on) async {
    _wantPreview = on;
    await _syncListening();
  }

  Future<void> _ensureWorker() async {
    if (_worker != null) return;
    final w = await TrackerWorker.start();
    if (_disposed) {
      w.dispose();
      return;
    }
    _worker = w;
    w.setTarget(_target);
    _sub = w.results.listen(_onResult);
  }

  Future<void> _syncListening() async {
    final want = _wantPreview || engaged;
    if (want) {
      await _ensureWorker();
      if (!_listening && !_disposed) {
        camera.addFrameListener(_onFrame);
        _listening = true;
      }
    } else if (_listening) {
      camera.removeFrameListener(_onFrame);
      _listening = false;
      sheet.value = null;
      points.value = const <Offset>[];
    }
  }

  void _onFrame(CameraImage img) {
    final w = _worker;
    if (w == null || w.busy) return;
    final y = img.planes.first;
    _frameSize = Size(img.width.toDouble(), img.height.toDouble());
    w.submit(y.bytes, img.width, img.height, y.bytesPerRow);
  }

  set target(TrackTarget t) {
    if (t == _target) return;
    _target = t;
    _worker?.setTarget(t);
    if (engaged) anchor();
    notifyListeners();
  }

  /// Pins the image to whatever the camera sees right now.
  Future<void> anchor() async {
    overlay.bakePose();
    for (final f in _filters) {
      f.reset();
    }
    _anchored = false;
    _anchorPending = true;
    _status = TrackStatus.searching;
    _note = _target == TrackTarget.paper ? 'Looking for the sheet edges' : 'Looking for surface detail';
    notifyListeners();
    await _syncListening();
    _worker?.anchor(_target);
  }

  /// Stops tracking; the image stays exactly where it is on screen.
  Future<void> release() async {
    overlay.bakePose();
    _worker?.release();
    _anchored = false;
    _anchorPending = false;
    _status = TrackStatus.idle;
    _note = null;
    notifyListeners();
    await _syncListening();
  }

  void _onResult(TrackResult r) {
    if (_disposed) return;
    millis = r.millis;
    final geo = geometry;
    if (geo == null) return;
    final f2v = geo.frameToView;
    final v2f = f2v.inverse();
    if (v2f == null) return;

    final q = r.quad;
    sheet.value = q == null ? null : [for (var i = 0; i < 4; i++) _toOffset(f2v.applyXY(q[2 * i], q[2 * i + 1]))];
    final pts = <Offset>[];
    for (var i = 0; i + 1 < r.points.length && pts.length < 160; i += 2) {
      pts.add(_toOffset(f2v.applyXY(r.points[i], r.points[i + 1])));
    }
    points.value = pts;

    final prevStatus = _status, prevNote = _note, prevAnchored = _anchored;
    if (_anchorPending) {
      if (r.status == TrackStatus.tracking) {
        _anchorPending = false;
        _anchored = true;
        _status = TrackStatus.tracking;
        _note = r.note;
        overlay.pose.value = Homography.identity();
      } else if (r.status != TrackStatus.idle) {
        _status = r.status;
        _note = r.note ?? _note;
      }
    } else if (_anchored) {
      _status = r.status;
      if (r.status == TrackStatus.tracking) {
        if (r.note != null || prevStatus != TrackStatus.tracking) _note = r.note;
        final h = r.homography;
        if (h != null) {
          final hv = f2v * Homography.fromList(h) * v2f;
          overlay.pose.value = _smooth(hv);
        }
      } else {
        _note = r.note;
      }
    }
    if (prevStatus != _status || prevNote != _note || prevAnchored != _anchored) notifyListeners();
  }

  static Offset _toOffset(Pt p) => Offset(p.x, p.y);

  Homography _smooth(Homography hv) {
    final t = _clock.elapsedMicroseconds / 1e6;
    final w = viewSize.width, h = viewSize.height;
    final refs = <Pt>[Pt(0.25 * w, 0.3 * h), Pt(0.75 * w, 0.3 * h), Pt(0.75 * w, 0.7 * h), Pt(0.25 * w, 0.7 * h)];
    final dst = <Pt>[];
    for (var i = 0; i < 4; i++) {
      final p = hv.apply(refs[i]);
      dst.add(Pt(_filters[2 * i].filter(p.x, t), _filters[2 * i + 1].filter(p.y, t)));
    }
    return homographyFromPoints(refs, dst) ?? hv;
  }

  @override
  void dispose() {
    _disposed = true;
    if (_listening) camera.removeFrameListener(_onFrame);
    _sub?.cancel();
    _worker?.dispose();
    sheet.dispose();
    points.dispose();
    super.dispose();
  }
}
