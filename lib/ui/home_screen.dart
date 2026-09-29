import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../content/lessons.dart';
import '../content/templates.dart';
import '../imaging/image_io.dart';
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

  Future<void> _open(Future<TraceDocument?> Function() load) async {
    if (_opening) return;
    setState(() => _opening = true);
    TraceDocument? doc;
    try {
      doc = await load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not open that image: $e')));
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
    if (doc == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TraceScreen(document: doc!)));
  }

  Future<TraceDocument?> _pick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, requestFullMetadata: false);
    if (file == null) return null;
    final img = await decodeLimited(await file.readAsBytes(), maxDim: 2048);
    final name = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
    // Pickers often hand back generated names (numeric ids, cache prefixes).
    final generated = name.isEmpty || RegExp(r'^[0-9_-]+$').hasMatch(name) || name.startsWith('image_picker') || name.startsWith('scaled_');
    return TraceDocument.image(title: generated ? 'Your photo' : name, image: img);
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
