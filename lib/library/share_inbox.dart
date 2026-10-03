import 'package:flutter/services.dart';

/// A picture handed to Vellum by another app (Share or Open with).
class SharedImage {
  const SharedImage(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Receives pictures from other apps over the `vellum/share` channel. The
/// native side only announces an arrival; the bytes are pulled from here.
abstract final class ShareInbox {
  static const MethodChannel _channel = MethodChannel('vellum/share');

  /// Delivers every incoming picture to [onImage], starting with the one the
  /// app was launched with (if any). [onError] gets a user-facing message.
  static void listen(void Function(SharedImage image) onImage, {required void Function(String message) onError}) {
    Future<void> take() async {
      try {
        final m = await _channel.invokeMapMethod<String, Object?>('take');
        if (m == null) return;
        onImage(SharedImage(m['name'] as String? ?? '', m['bytes']! as Uint8List));
      } on PlatformException catch (e) {
        onError('Could not open the shared picture: ${e.message}');
      } on MissingPluginException {
        // No native side (tests, other platforms): nothing to receive.
      }
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'incoming') await take();
    });
    take();
  }

  static void stop() => _channel.setMethodCallHandler(null);
}
