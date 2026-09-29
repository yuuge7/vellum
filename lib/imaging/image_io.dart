import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'raster.dart';

/// Reads pixels of [image], downscaling first so the longest side is at most
/// [maxDim].
Future<Rgba> imageToRgba(ui.Image image, {int maxDim = 1024}) async {
  var src = image;
  ui.Image? scaled;
  final longest = math.max(image.width, image.height);
  if (longest > maxDim) {
    final s = maxDim / longest;
    final w = math.max(1, (image.width * s).round()), h = math.max(1, (image.height * s).round());
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImageRect(
      image,
      ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final pic = rec.endRecording();
    scaled = await pic.toImage(w, h);
    pic.dispose();
    src = scaled;
  }
  final data = await src.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  final out = Rgba(src.width, src.height, data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  scaled?.dispose();
  return out;
}

/// Uploads RGBA pixels as a GPU image.
Future<ui.Image> rgbaToImage(Rgba img) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(img.px, img.width, img.height, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// Decodes encoded bytes (PNG/JPEG/...) limiting the longest side.
Future<ui.Image> decodeLimited(Uint8List bytes, {int maxDim = 2048}) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final longest = math.max(desc.width, desc.height);
  int? tw, th;
  if (longest > maxDim) {
    final s = maxDim / longest;
    tw = (desc.width * s).round();
    th = (desc.height * s).round();
  }
  final codec = await desc.instantiateCodec(targetWidth: tw, targetHeight: th);
  final frame = await codec.getNextFrame();
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  return frame.image;
}

/// Renders a vector drawing callback into an image.
Future<ui.Image> renderToImage(int width, int height, void Function(ui.Canvas canvas, ui.Size size) draw) async {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  draw(canvas, ui.Size(width.toDouble(), height.toDouble()));
  final pic = rec.endRecording();
  final img = await pic.toImage(width, height);
  pic.dispose();
  return img;
}
