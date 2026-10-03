import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../content/lessons.dart';
import '../content/templates.dart';
import '../imaging/image_io.dart';

/// One layer of a lesson.
class StepLayer {
  StepLayer({required this.image, required this.title, required this.tip, this.tint});
  final ui.Image image;
  final String title;
  final String tip;

  /// When set, the layer is an alpha mask painted in this colour.
  final Color? tint;
}

/// Everything that can be traced: a single image (photo or template) or an
/// ordered set of lesson layers.
class TraceDocument {
  TraceDocument.image({required this.title, required ui.Image this.image, this.isPhoto = true, this.pieceId})
      : steps = null,
        size = Size(image.width.toDouble(), image.height.toDouble());

  TraceDocument.lesson({required this.title, required List<StepLayer> this.steps, required this.size})
      : image = null,
        isPhoto = false,
        pieceId = null;

  final String title;
  final ui.Image? image;
  final List<StepLayer>? steps;
  final Size size;

  /// Photos (and photo-like templates) unlock line and tone extraction.
  final bool isPhoto;

  /// Id of the saved piece (see `RecentsStore`) this image was opened from.
  final String? pieceId;

  bool get isLesson => steps != null;

  static const int boardPixels = 1400;

  static Future<TraceDocument> fromTemplate(TemplateSpec t) async {
    final img = await renderToImage(boardPixels, boardPixels, (c, s) {
      c.scale(s.width / 1000, s.height / 1000);
      t.draw(c);
    });
    return TraceDocument.image(title: t.name, image: img, isPhoto: t.opaque);
  }

  static Future<TraceDocument> fromLesson(LessonSpec l) async {
    final layers = <StepLayer>[];
    for (final s in l.steps) {
      final img = await renderToImage(boardPixels, boardPixels, (c, size) {
        c.scale(size.width / 1000, size.height / 1000);
        s.draw(c);
      });
      layers.add(StepLayer(image: img, title: s.title, tip: s.tip));
    }
    return TraceDocument.lesson(
      title: l.title,
      steps: layers,
      size: const Size(1.0 * boardPixels, 1.0 * boardPixels),
    );
  }

  void dispose() {
    image?.dispose();
    for (final s in steps ?? const <StepLayer>[]) {
      s.image.dispose();
    }
  }
}
