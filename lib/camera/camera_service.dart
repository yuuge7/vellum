import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef FrameListener = void Function(CameraImage image);

/// Owns the back camera: preview, torch and a shared image stream that is
/// only running while someone (tracker, time-lapse) listens to it.
class CameraService extends ChangeNotifier {
  CameraController? _controller;
  CameraDescription? _description;
  String? _error;
  bool _starting = false;
  bool _torchOn = false;
  bool _streaming = false;
  bool _disposed = false;
  Future<void> _streamOp = Future<void>.value();
  final Set<FrameListener> _listeners = <FrameListener>{};

  /// Closing a controller unbinds the camera for every controller, so a new
  /// one must not open until the previous one has finished letting go.
  static Future<void> _released = Future<void>.value();

  static void _close(CameraController c) {
    _released = _released.then((_) async {
      try {
        if (c.value.isStreamingImages) await c.stopImageStream();
      } catch (_) {}
      try {
        await c.dispose();
      } catch (_) {}
    });
  }

  CameraController? get controller => _controller;
  CameraDescription? get description => _description;
  bool get ready => _controller?.value.isInitialized ?? false;
  String? get error => _error;
  bool get torchOn => _torchOn;
  int get sensorOrientation => _description?.sensorOrientation ?? 90;

  /// Preview buffer size in sensor orientation (landscape on phones).
  Size? get previewSize => _controller?.value.previewSize;

  Future<void> start() async {
    if (_starting || ready || _disposed) return;
    _starting = true;
    _error = null;
    notifyListeners();
    try {
      await _released;
      final cams = await availableCameras();
      if (cams.isEmpty) {
        _error = 'No camera found on this device.';
        return;
      }
      _description = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back, orElse: () => cams.first);
      final c = CameraController(
        _description!,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await c.initialize();
      if (_disposed) {
        _close(c);
        return;
      }
      _controller = c;
      try {
        await c.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      try {
        await c.setFocusMode(FocusMode.auto);
      } catch (_) {}
      if (_torchOn) await _applyTorch(true);
      _syncStream();
    } on CameraException catch (e) {
      _error = switch (e.code) {
        'CameraAccessDenied' || 'CameraAccessDeniedWithoutPrompt' || 'CameraAccessRestricted' =>
          'Camera access is off. Allow camera access for Vellum in system settings.',
        _ => 'Camera failed to start: ${e.description ?? e.code}',
      };
    } catch (e) {
      _error = 'Camera failed to start: $e';
    } finally {
      _starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// Releases the camera (app backgrounded). [start] brings it back.
  Future<void> stop() async {
    final c = _controller;
    _controller = null;
    _streaming = false;
    if (!_disposed) notifyListeners();
    if (c != null) {
      _close(c);
      await _released;
    }
  }

  /// Turns the flashlight on or off. Returns an error message on failure.
  Future<String?> setTorch(bool on) async {
    _torchOn = on;
    notifyListeners();
    if (!ready) return null;
    final err = await _applyTorch(on);
    if (err != null) {
      _torchOn = false;
      notifyListeners();
    }
    return err;
  }

  Future<String?> _applyTorch(bool on) async {
    try {
      await _controller!.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      return null;
    } on CameraException catch (e) {
      return 'Flashlight unavailable: ${e.description ?? e.code}';
    } catch (e) {
      return 'Flashlight unavailable: $e';
    }
  }

  void addFrameListener(FrameListener l) {
    _listeners.add(l);
    _syncStream();
  }

  void removeFrameListener(FrameListener l) {
    _listeners.remove(l);
    _syncStream();
  }

  void _syncStream() {
    _streamOp = _streamOp.then((_) async {
      final c = _controller;
      if (c == null || !c.value.isInitialized || _disposed) return;
      final want = _listeners.isNotEmpty;
      try {
        if (want && !_streaming) {
          await c.startImageStream(_onImage);
          _streaming = true;
        } else if (!want && _streaming) {
          _streaming = false;
          await c.stopImageStream();
        }
      } catch (e) {
        debugPrint('image stream toggle failed: $e');
      }
    });
  }

  void _onImage(CameraImage image) {
    for (final l in List<FrameListener>.of(_listeners)) {
      l(image);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _listeners.clear();
    final c = _controller;
    _controller = null;
    if (c != null) _close(c);
    super.dispose();
  }
}
