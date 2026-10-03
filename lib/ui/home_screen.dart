import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../content/lessons.dart';
import '../content/templates.dart';
import '../imaging/image_io.dart';
import '../library/recents.dart';
import '../library/share_inbox.dart';
import '../models/trace_document.dart';
import 'overlay_painter.dart';
import 'theme.dart';
import 'trace_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  TemplateCategory? _category;
  bool _opening = false;
  bool _tracing = false;

  /// A picture shared from another app while a drawing was open.
  SharedImage? _waiting;

  @override
  void initState() {
    super.initState();
    RecentsStore.instance.load();
    ShareInbox.listen(_onShared, onError: _toast);
  }

  @override
  void dispose() {
    ShareInbox.stop();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Future<TraceDocument?> Function() load) async {
    if (_opening || _tracing) return;
    setState(() => _opening = true);
    TraceDocument? doc;
    try {
      doc = await load();
    } catch (e) {
      _toast('Could not open that image: $e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (doc != null && mounted) {
      _tracing = true;
      final route = MaterialPageRoute<void>(builder: (_) => TraceScreen(document: doc!));
      await Navigator.of(context).push(route);
      // The tracer keeps the camera until its exit transition has finished;
      // opening the next one earlier would have its camera closed under it.
      await route.completed;
      await WidgetsBinding.instance.endOfFrame;
      _tracing = false;
    }
    final next = _waiting;
    _waiting = null;
    if (next != null && mounted) unawaited(_open(() => _import(next.name, next.bytes)));
  }

  void _onShared(SharedImage image) {
    if (!mounted) return;
    if (_opening || _tracing) {
      _waiting = image;
      if (_tracing) _toast('Picture received. Leave this drawing to start tracing it.');
      return;
    }
    _open(() => _import(image.name, image.bytes));
  }

  /// Decodes an imported picture and keeps a copy on the "Your pieces" shelf.
  Future<TraceDocument?> _import(String fileName, Uint8List bytes) async {
    final img = await decodeLimited(bytes, maxDim: 2048);
    final title = pieceTitle(fileName);
    String? id;
    try {
      id = (await RecentsStore.instance.add(title, bytes)).id;
    } catch (e) {
      debugPrint('could not keep a copy of the picture: $e'); // tracing still works without the shelf
    }
    return TraceDocument.image(title: title, image: img, pieceId: id);
  }

  Future<TraceDocument?> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
    if (file == null) return null;
    return _import(file.name, await file.readAsBytes());
  }

  Future<TraceDocument?> _reopen(RecentPiece piece) async {
    final img = await decodeLimited(await piece.file.readAsBytes(), maxDim: 2048);
    await RecentsStore.instance.touch(piece.id);
    return TraceDocument.image(title: piece.title, image: img, pieceId: piece.id);
  }

  Future<void> _confirmRemove(RecentPiece piece) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.graphite2,
        title: Text('Remove “${piece.title}”?', style: TextStyles.title),
        content: const Text('Vellum forgets its copy. The original in your gallery is not touched.', style: TextStyles.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove ?? false) await RecentsStore.instance.remove(piece.id);
  }

  @override
  Widget build(BuildContext context) {
    final templates = _category == null ? builtInTemplates : builtInTemplates.where((t) => t.category == _category).toList();
    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: CustomScrollView(
              slivers: [
                const SliverToBoxAdapter(child: _Masthead()),
                SliverToBoxAdapter(
                  child: _PhotoHero(
                    onGallery: () => _open(() => _pick(ImageSource.gallery)),
                    onCamera: () => _open(() => _pick(ImageSource.camera)),
                  ),
                ),
                SliverToBoxAdapter(
                  child: ListenableBuilder(
                    listenable: RecentsStore.instance,
                    builder: (context, _) {
                      final pieces = RecentsStore.instance.pieces;
                      if (pieces.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const _SectionTitle('Your pieces', 'Pick up a picture you were tracing. Hold one to remove it.'),
                          SizedBox(
                            height: 196,
                            child: ListView.separated(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              scrollDirection: Axis.horizontal,
                              itemCount: pieces.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 14),
                              itemBuilder: (_, i) {
                                final p = pieces[i];
                                return _PieceCard(
                                  key: ValueKey(p.file.path),
                                  piece: p,
                                  onTap: () => _open(() => _reopen(p)),
                                  onLongPress: () => _confirmRemove(p),
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(
                  child: _SectionTitle('Guided lessons', 'Each step fades in over the last'),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 218,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: builtInLessons.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (_, i) {
                        final l = builtInLessons[i];
                        return _LessonCard(lesson: l, onTap: () => _open(() => TraceDocument.fromLesson(l)));
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: _SectionTitle('Templates', 'Line art and photos to trace')),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 44,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      children: [
                        _CategoryChip(label: 'All', selected: _category == null, onTap: () => setState(() => _category = null)),
                        for (final c in TemplateCategory.values)
                          _CategoryChip(label: c.label, selected: _category == c, onTap: () => setState(() => _category = c)),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.82,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final t = templates[i];
                        return _TemplateCard(template: t, onTap: () => _open(() => TraceDocument.fromTemplate(t)));
                      },
                      childCount: templates.length,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_opening)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x88000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const RegistrationMark(size: 30),
          const SizedBox(width: 12),
          const Text('Vellum', style: TextStyles.display),
          const Spacer(),
          Text('AR TRACING', style: TextStyles.mono.copyWith(letterSpacing: 2)),
        ],
      ),
    );
  }
}

/// The thesis of the app: a sheet of paper under a pinned reference.
class _PhotoHero extends StatelessWidget {
  const _PhotoHero({required this.onGallery, required this.onCamera});
  final VoidCallback onGallery;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.graphite2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Palette.rule),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Trace anything\nonto paper.', style: TextStyles.display.copyWith(fontSize: 27, height: 1.05)),
                          const SizedBox(height: 10),
                          const Text('Prop your phone over the page, pin the picture to the sheet, draw what you see.', style: TextStyles.bodyDim),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    const SizedBox(width: 108, child: _PinnedSheet()),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onGallery,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Choose a photo'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        textStyle: TextStyles.label.copyWith(fontSize: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: onCamera,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Palette.rule),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Tooltip(message: 'Take a photo', child: Icon(Icons.photo_camera_outlined, color: Palette.vellum)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedSheet extends StatelessWidget {
  const _PinnedSheet();

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: PaperThumb(draw: (c) {}, tilt: -0.07),
        ),
        Positioned.fill(
          child: Transform.rotate(
            angle: -0.07,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CustomPaint(painter: _HeroArt()),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroArt extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 1000;
    canvas.save();
    canvas.translate((size.width - 1000 * s) / 2, (size.height - 1000 * s) / 2);
    canvas.scale(s);
    canvas.saveLayer(const Rect.fromLTWH(0, 0, 1000, 1000), Paint()..color = const Color(0x8CFFFFFF));
    builtInLessons.first.drawAll(canvas);
    canvas.restore();
    canvas.restore();
    // Blue registration brackets around the art.
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF2F9BD6);
    final r = Offset.zero & size;
    const l = 12.0;
    for (final (c, dx, dy) in [(r.topLeft, 1.0, 1.0), (r.topRight, -1.0, 1.0), (r.bottomRight, -1.0, -1.0), (r.bottomLeft, 1.0, -1.0)]) {
      canvas.drawLine(c, c.translate(dx * l, 0), p);
      canvas.drawLine(c, c.translate(0, dy * l), p);
      canvas.drawCircle(c, 4, p);
    }
  }

  @override
  bool shouldRepaint(_HeroArt oldDelegate) => false;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, this.caption);
  final String title;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyles.section),
          const SizedBox(height: 3),
          Text(caption, style: TextStyles.bodyDim),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  const _LessonCard({required this.lesson, required this.onTap});
  final LessonSpec lesson;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Lesson: ${lesson.title}, ${lesson.steps.length} steps',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 150,
                child: Stack(
                  children: [
                    Positioned.fill(child: PaperThumb(draw: lesson.drawAll)),
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Palette.graphite, borderRadius: BorderRadius.circular(6)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          child: Text('${lesson.steps.length} STEPS', style: TextStyles.mono.copyWith(fontSize: 10, color: Palette.blue)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(lesson.title, style: TextStyles.label.copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(lesson.blurb, style: TextStyles.bodyDim.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// A saved picture on the "Your pieces" shelf.
class _PieceCard extends StatelessWidget {
  const _PieceCard({super.key, required this.piece, required this.onTap, required this.onLongPress});
  final RecentPiece piece;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  static String _ago(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
    if (days <= 0) return 'TODAY';
    if (days == 1) return 'YESTERDAY';
    if (days < 60) return '$days DAYS AGO';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Your piece: ${piece.title}, opened ${_ago(piece.opened).toLowerCase()}',
      onLongPressHint: 'Remove',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 140,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Palette.paper,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.file(
                      piece.file,
                      fit: BoxFit.cover,
                      width: 112,
                      height: 140,
                      cacheWidth: 336,
                      errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image_outlined, color: Palette.rule)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Text(piece.title, style: TextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Text(_ago(piece.opened), style: TextStyles.mono.copyWith(fontSize: 9.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        labelStyle: TextStyles.label.copyWith(color: selected ? Palette.blueInk : Palette.vellum),
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template, required this.onTap});
  final TemplateSpec template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Template: ${template.name}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: PaperThumb(draw: template.draw, opaque: template.opaque)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(template.name, style: TextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(template.category.label.split(' ').first.toUpperCase(), style: TextStyles.mono.copyWith(fontSize: 9.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
