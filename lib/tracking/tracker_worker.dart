import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'tracker.dart';

class _Frame {
  _Frame(this.bytes, this.width, this.height, this.rowStride);
  final TransferableTypedData bytes;
  final int width;
  final int height;
  final int rowStride;
}

class _Anchor {
  _Anchor(this.target);
  final TrackTarget target;
}

class _Target {
  _Target(this.target);
  final TrackTarget target;
}

class _Release {}

class _Stop {}

/// Runs a [Tracker] on a background isolate. Frames are dropped while the
/// worker is busy so tracking never queues up behind the camera.
class TrackerWorker {
  TrackerWorker._(this._isolate, this._send, this._inbox) {
    _inbox.listen((msg) {
      if (msg is TrackResult) {
        busy = false;
        _results.add(msg);
      }
    });
  }

  static Future<TrackerWorker> start() async {
    final inbox = ReceivePort();
    final isolate = await Isolate.spawn(_main, inbox.sendPort, debugName: 'tracker');
    final completer = Completer<SendPort>();
    late StreamSubscription<dynamic> sub;
    final broadcast = inbox.asBroadcastStream();
    sub = broadcast.listen((m) {
      if (m is SendPort) {
        completer.complete(m);
        sub.cancel();
      }
    });
    final send = await completer.future;
    return TrackerWorker._(isolate, send, broadcast);
  }

  final Isolate _isolate;
  final SendPort _send;
  final Stream<dynamic> _inbox;
  final StreamController<TrackResult> _results = StreamController<TrackResult>.broadcast();

  bool busy = false;

  Stream<TrackResult> get results => _results.stream;

  /// Submits a luminance plane. Returns false (and ignores the frame) when the
  /// previous frame is still being processed.
  bool submit(Uint8List luma, int width, int height, int rowStride) {
    if (busy) return false;
    busy = true;
    _send.send(_Frame(TransferableTypedData.fromList(<Uint8List>[luma]), width, height, rowStride));
    return true;
  }

  void anchor(TrackTarget target) => _send.send(_Anchor(target));

  void setTarget(TrackTarget target) => _send.send(_Target(target));

  void release() => _send.send(_Release());

  void dispose() {
    _send.send(_Stop());
    _results.close();
    _isolate.kill(priority: Isolate.beforeNextEvent);
  }

  static void _main(SendPort out) {
    final inbox = ReceivePort();
    out.send(inbox.sendPort);
    final tracker = Tracker();
    inbox.listen((dynamic msg) {
      switch (msg) {
        case _Frame f:
          final bytes = f.bytes.materialize().asUint8List();
          TrackResult r;
          try {
            r = tracker.process(bytes, f.width, f.height, f.rowStride);
          } catch (e) {
            r = TrackResult(status: TrackStatus.lost, note: 'Tracker error: $e');
          }
          out.send(r);
        case _Anchor a:
          tracker
            ..target = a.target
            ..requestAnchor();
        case _Target t:
          tracker.target = t.target;
        case _Release _:
          tracker.release();
        case _Stop _:
          inbox.close();
      }
    });
  }
}
