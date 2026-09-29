import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';

import '../camera/camera_service.dart';
import '../imaging/image_io.dart';
import '../imaging/raster.dart';
import '../imaging/yuv.dart';

enum RecordState { idle, recording, saving }

/// Draws one composite frame (camera + overlay) at [size] pixels. [camera]
/// is the upright camera frame or null when no frame was available.
typedef FrameComposer = Future<ui.Image> Function(ui.Size size, ui.Image? camera);

/// Snapshot interval choices and the speed-up they produce at [outputFps].
enum CaptureInterval {
  fast(Duration(milliseconds: 500)),
  normal(Duration(seconds: 1)),
  slow(Duration(seconds: 2)),
  slowest(Duration(seconds: 4));

  const CaptureInterval(this.period);
  final Duration period;

  int speedUp(int fps) => (period.inMilliseconds * fps / 1000).round();

  String get label {
    final s = period.inMilliseconds / 1000;
    return s == s.roundToDouble() ? '${s.round()} s' : '$s s';
  }
}

Future<Rgba> _toUpright(YuvFrame f, int rotation) => Isolate.run(() => yuvToUprightRgba(f, rotation, step: 2));

/// Periodically composites the camera feed with the overlay and streams the
/// frames into a native H.264 encoder. Stopping finalises an MP4 and saves it
/// to the gallery.
class TimelapseRecorder extends ChangeNotifier {
  TimelapseRecorder({required this.camera, required this.composer});

  static const MethodChannel _channel = MethodChannel('vellum/timelapse');
  static const int outputFps = 30;

  final CameraService camera;
  final FrameComposer composer;

  RecordState _state = RecordState.idle;
  CaptureInterval interval = CaptureInterval.normal;
  int _frames = 0;
  final Stopwatch _elapsed = Stopwatch();
  Timer? _timer;
  Timer? _ticker;
  bool _busy = false;
  Completer<YuvFrame?>? _frameRequest;
  ui.Size _outSize = ui.Size.zero;
  String? _error;
  String? _savedMessage;
  bool _disposed = false;

  RecordState get state => _state;
  int get frames => _frames;
  Duration get elapsed => _elapsed.elapsed;
  String? get error => _error;

  /// Set after a successful save; cleared by [consumeSavedMessage].
  String? get savedMessage => _savedMessage;

  /// Length of the finished clip so far.
  Duration get clipLength => Duration(milliseconds: (_frames * 1000 / outputFps).round());

  String? consumeSavedMessage() {
    final m = _savedMessage;
    _savedMessage = null;
    return m;
  }

  /// Starts recording. [viewSize] is the logical size of the screen so the
  /// clip keeps the same framing.
  Future<void> start(ui.Size viewSize) async {
    if (_state != RecordState.idle) return;
    _error = null;
    const width = 576;
    var height = (width * viewSize.height / viewSize.width / 16).round() * 16;
    if (height <= 0) height = 1024;
    try {
      final res = await _channel.invokeMapMethod<String, Object?>('start', <String, Object?>{
        'width': width,
        'height': height,
        'fps': outputFps,
        'bitrate': (width * height * outputFps * 0.2).round(),
      });
      _outSize = ui.Size((res!['width']! as int).toDouble(), (res['height']! as int).toDouble());
    } on PlatformException catch (e) {
      _error = 'Could not start the recorder: ${e.message}';
      notifyListeners();
      return;
    }
    _frames = 0;
    _state = RecordState.recording;
    _elapsed
      ..reset()
      ..start();
    camera.addFrameListener(_onFrame);
    _timer = Timer.periodic(interval.period, (_) => _capture());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    notifyListeners();
    unawaited(_capture());
  }

  /// Pauses snapshotting while the app is in the background.
  void pause() {
    if (_state != RecordState.recording) return;
    _elapsed.stop();
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    if (_state != RecordState.recording || _timer != null) return;
    _elapsed.start();
    _timer = Timer.periodic(interval.period, (_) => _capture());
  }

  void _onFrame(CameraImage img) {
    final req = _frameRequest;
    if (req == null || req.isCompleted) return;
    _frameRequest = null;
    if (img.planes.length < 3) {
      req.complete(null);
      return;
    }
    final y = img.planes[0], u = img.planes[1], v = img.planes[2];
    req.complete(YuvFrame(
      width: img.width,
      height: img.height,
      y: Uint8List.fromList(y.bytes),
      u: Uint8List.fromList(u.bytes),
      v: Uint8List.fromList(v.bytes),
      yRowStride: y.bytesPerRow,
      uvRowStride: u.bytesPerRow,
      uvPixelStride: u.bytesPerPixel ?? 1,
    ));
  }

  Future<YuvFrame?> _grabFrame() {
    final c = Completer<YuvFrame?>();
    _frameRequest = c;
    return c.future.timeout(const Duration(milliseconds: 600), onTimeout: () {
      if (identical(_frameRequest, c)) _frameRequest = null;
      return null;
    });
  }

  Future<void> _capture() async {
    if (_busy || _state != RecordState.recording) return;
    _busy = true;
    ui.Image? cam;
    ui.Image? frame;
    try {
      final yuv = camera.ready ? await _grabFrame() : null;
      if (yuv != null) cam = await rgbaToImage(await _toUpright(yuv, camera.sensorOrientation));
      frame = await composer(_outSize, cam);
      final data = await frame.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data != null && _state == RecordState.recording) {
        await _channel.invokeMethod<int>('frame', <String, Object?>{
          'rgba': data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        });
        _frames++;
      }
    } catch (e) {
      debugPrint('time-lapse frame failed: $e');
    } finally {
      cam?.dispose();
      frame?.dispose();
      _busy = false;
    }
  }

  /// Finishes the clip and saves it to the gallery.
  Future<void> stop() async {
    if (_state != RecordState.recording) return;
    _timer?.cancel();
    _timer = null;
    _ticker?.cancel();
    _ticker = null;
    _elapsed.stop();
    camera.removeFrameListener(_onFrame);
    _state = RecordState.saving;
    notifyListeners();
    while (_busy) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    try {
      if (_frames == 0) {
        await _channel.invokeMethod<void>('cancel');
        _error = 'Nothing recorded yet. Keep the time-lapse running a little longer.';
        return;
      }
      final path = await _channel.invokeMethod<String>('finish', <String, Object?>{'holdFrames': outputFps});
      if (path == null) throw StateError('encoder returned no file');
      if (!await Gal.hasAccess(toAlbum: true)) {
        await Gal.requestAccess(toAlbum: true);
      }
      await Gal.putVideo(path, album: 'Vellum');
      try {
        await File(path).delete();
      } catch (_) {}
      final secs = (clipLength.inMilliseconds / 1000 + 1).toStringAsFixed(1);
      _savedMessage = 'Time-lapse saved to Gallery › Vellum ($secs s, ${interval.speedUp(outputFps)}× speed)';
    } on GalException catch (e) {
      _error = 'Could not save to the gallery: ${e.type.message}';
    } on PlatformException catch (e) {
      _error = 'Could not finish the video: ${e.message}';
    } catch (e) {
      _error = 'Could not finish the video: $e';
    } finally {
      _state = RecordState.idle;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _ticker?.cancel();
    camera.removeFrameListener(_onFrame);
    if (_state == RecordState.recording) {
      _channel.invokeMethod<void>('cancel');
    }
    super.dispose();
  }
}
