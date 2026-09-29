import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../camera/ar_session.dart';
import '../camera/camera_geometry.dart';
import '../camera/camera_service.dart';
import '../capture/timelapse_recorder.dart';
import '../models/overlay_controller.dart';
import '../models/trace_document.dart';
import '../tracking/tracker.dart';
import 'overlay_painter.dart';
import 'theme.dart';
import 'widgets.dart';

enum Tool { pin, strobe, look, record, adjust }

class TraceScreen extends StatefulWidget {
  const TraceScreen({super.key, required this.document});
  final TraceDocument document;

  @override
  State<TraceScreen> createState() => _TraceScreenState();
}

class _TraceScreenState extends State<TraceScreen> with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final CameraService _camera = CameraService();
  late OverlayController _overlay;
  late final ArSession _ar;
  late final TimelapseRecorder _rec;
  late final AnimationController _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 700), value: 1);
  final List<TraceDocument> _docs = <TraceDocument>[];

  Tool? _tool;
  bool _hud = true;
  Size _view = Size.zero;
  bool _backgrounded = false;
  String? _lastOverlayError;
  String? _lastRecError;
  double? _detailDraft;

  Offset _lastFocal = Offset.zero;
  double _lastScale = 1;
  double _lastRotation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _docs.add(widget.document);
    _overlay = OverlayController(widget.document);
    _ar = ArSession(camera: _camera, overlay: _overlay);
    _rec = TimelapseRecorder(camera: _camera, composer: _compose);
    _attach(_overlay);
    _reveal.addListener(() => _overlay.stepReveal.value = Curves.easeOutCubic.transform(_reveal.value));
    _rec.addListener(_onRecorderChanged);
    _camera.start();
    WakelockPlus.enable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _attach(OverlayController o) {
    o.player?.addListener(_onStepChanged);
    o.addListener(_onOverlayChanged);
  }

  void _detach(OverlayController o) {
    o.player?.removeListener(_onStepChanged);
    o.removeListener(_onOverlayChanged);
  }

  void _onStepChanged() => _reveal.forward(from: 0);

  void _onOverlayChanged() {
    final e = _overlay.error;
    if (e != null && e != _lastOverlayError) _toast(e);
    _lastOverlayError = e;
  }

  void _onRecorderChanged() {
    final saved = _rec.consumeSavedMessage();
    if (saved != null) _toast(saved);
    final e = _rec.error;
    if (e != null && e != _lastRecError) _toast(e);
    _lastRecError = e;
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_backgrounded) return;
      _backgrounded = true;
      _rec.pause();
      _camera.stop();
    } else if (state == AppLifecycleState.resumed) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      if (!_backgrounded) return;
      _backgrounded = false;
      _camera.start();
      _rec.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rec.removeListener(_onRecorderChanged);
    _rec.dispose();
    _ar.dispose();
    _detach(_overlay);
    _overlay.dispose();
    _camera.dispose();
    _reveal.dispose();
    for (final d in _docs) {
      d.dispose();
    }
    WakelockPlus.disable().catchError((_) {});
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ------------------------------------------------------------------ actions

  void _selectTool(Tool t) {
    final next = _tool == t ? null : t;
    setState(() => _tool = next);
    _ar.setPreview(next == Tool.pin);
  }

  Future<void> _toggleTorch() async {
    final err = await _camera.setTorch(!_camera.torchOn);
    if (err != null) _toast(err);
  }

  void _rotate90() {
    final w = _overlay.doc.size.width, h = _overlay.doc.size.height;
    final c = _overlay.effective.applyXY(w / 2, h / 2);
    final center = Offset(c.x, c.y);
    _overlay.applyViewDelta(similarityAbout(center, center, 1, math.pi / 2));
  }

  Future<void> _makeLesson() async {
    final doc = await _overlay.buildPhotoLesson();
    if (doc == null || !mounted) return;
    _docs.add(doc);
    final old = _overlay;
    final next = OverlayController(doc)..adoptPlacement(old);
    next.locked = old.locked;
    _detach(old);
    _overlay = next;
    _ar.overlay = next;
    _attach(next);
    _reveal.value = 1;
    setState(() => _tool = null);
    _ar.setPreview(false);
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _toast('Lesson ready: outline, shadows, mid-tones, highlights.');
  }

  Future<bool> _confirmLeave() async {
    if (_rec.state != RecordState.recording) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.graphite2,
        title: const Text('Time-lapse is recording', style: TextStyles.title),
        content: const Text('Save the video before leaving?', style: TextStyles.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'stay'), child: const Text('Keep drawing')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Discard')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save video')),
        ],
      ),
    );
    if (choice == 'save') {
      await _rec.stop();
      return true;
    }
    // Discarding: dispose() cancels the native encoder and deletes the file.
    if (choice == 'discard') return true;
    return false;
  }

  // ------------------------------------------------------------------ gestures

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.localFocalPoint;
    _lastScale = 1;
    _lastRotation = 0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final ds = _lastScale == 0 ? 1.0 : d.scale / _lastScale;
    final dr = d.rotation - _lastRotation;
    _overlay.applyViewDelta(similarityAbout(_lastFocal, d.localFocalPoint, ds, dr));
    _lastFocal = d.localFocalPoint;
    _lastScale = d.scale;
    _lastRotation = d.rotation;
  }

  // ------------------------------------------------------------------ export

  CameraGeometry? _geometryFor(Size frameSize) {
    final ps = _camera.previewSize;
    if (ps == null || _view.isEmpty) return null;
    return CameraGeometry(viewSize: _view, previewSize: ps, sensorOrientation: _camera.sensorOrientation, frameSize: frameSize);
  }

  Future<ui.Image> _compose(Size out, ui.Image? cam) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Offset.zero & out, Paint()..color = const Color(0xFF000000));
    if (!_view.isEmpty) {
      canvas.scale(out.width / _view.width, out.height / _view.height);
      if (cam != null) {
        final swaps = _camera.sensorOrientation % 180 != 0;
        final frameSize = swaps
            ? Size(cam.height.toDouble(), cam.width.toDouble())
            : Size(cam.width.toDouble(), cam.height.toDouble());
        final geo = _geometryFor(frameSize);
        if (geo != null) {
          canvas.drawImageRect(
            cam,
            Rect.fromLTWH(0, 0, cam.width.toDouble(), cam.height.toDouble()),
            geo.frameRectInView,
            Paint()..filterQuality = FilterQuality.low,
          );
        }
      }
      paintOverlay(canvas, _overlay, forExport: true);
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(out.width.round(), out.height.round());
    pic.dispose();
    return img;
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        if (await _confirmLeave() && mounted) nav.pop();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final size = constraints.biggest;
            if (size != _view) {
              _view = size;
              _ar.viewSize = size;
              WidgetsBinding.instance.addPostFrameCallback((_) => _overlay.fitTo(size));
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                _CameraView(camera: _camera),
                ListenableBuilder(
                  listenable: _overlay,
                  builder: (context, _) => IgnorePointer(
                    ignoring: _overlay.locked,
                    child: Semantics(
                      label: _overlay.locked ? 'Reference image, locked' : 'Reference image. Pinch, drag or twist to adjust',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: _onScaleStart,
                        onScaleUpdate: _onScaleUpdate,
                        child: CustomPaint(painter: OverlayPainter(_overlay), child: const SizedBox.expand()),
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: ListenableBuilder(
                    listenable: _ar,
                    builder: (context, _) => CustomPaint(
                      painter: MarksPainter(_overlay, _ar, showTracking: _tool == Tool.pin || _ar.anchoring),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
                if (_hud) _buildHud(context) else _buildHiddenHud(context),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildHiddenHud(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    return Stack(
      children: [
        Positioned(
          right: 14,
          bottom: pad.bottom + 16,
          child: HudButton(icon: Icons.visibility_outlined, tooltip: 'Show controls', onPressed: () => setState(() => _hud = true)),
        ),
        Positioned(
          left: 14,
          top: pad.top + 14,
          child: ListenableBuilder(
            listenable: Listenable.merge(<Listenable>[_rec, _overlay]),
            builder: (context, _) => Row(
              children: [
                if (_rec.state == RecordState.recording) _RecBadge(rec: _rec),
                if (_overlay.locked) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.lock, color: Palette.tape, size: 20, shadows: [Shadow(blurRadius: 6)]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHud(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final doc = _overlay.doc;
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[_overlay, _camera, _rec, _ar]),
      builder: (context, _) {
        final recording = _rec.state == RecordState.recording;
        return Stack(
          children: [
            Positioned(
              top: pad.top + 10,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  HudButton(icon: Icons.arrow_back, tooltip: 'Back', onPressed: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Glass(
                      radius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      child: Text(doc.title, style: TextStyles.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (recording || _rec.state == RecordState.saving) _RecBadge(rec: _rec),
                  const Spacer(),
                  HudButton(
                    icon: _camera.torchOn ? Icons.flashlight_on : Icons.flashlight_off_outlined,
                    tooltip: _camera.torchOn ? 'Turn flashlight off' : 'Turn flashlight on',
                    active: _camera.torchOn,
                    activeColor: Palette.tape,
                    onPressed: _camera.ready ? _toggleTorch : null,
                  ),
                  const SizedBox(width: 8),
                  HudButton(
                    icon: _overlay.locked ? Icons.lock : Icons.lock_open,
                    tooltip: _overlay.locked ? 'Unlock image' : 'Lock image',
                    active: _overlay.locked,
                    activeColor: Palette.tape,
                    onPressed: () => _overlay.locked = !_overlay.locked,
                  ),
                ],
              ),
            ),
            if (_overlay.locked)
              Positioned(
                top: pad.top + 70,
                left: 0,
                right: 0,
                child: Center(
                  child: Glass(
                    radius: 30,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Text('Image locked. Touches won’t move it.', style: TextStyles.label.copyWith(color: Palette.tape)),
                  ),
                ),
              ),
            Positioned(
              right: 12,
              top: pad.top + 110,
              child: Column(
                children: [
                  HudButton(
                    icon: _ar.engaged ? Icons.push_pin : Icons.push_pin_outlined,
                    tooltip: 'Pin to paper',
                    label: 'Pin',
                    active: _tool == Tool.pin,
                    badge: _ar.anchored && _tool != Tool.pin,
                    onPressed: () => _selectTool(Tool.pin),
                  ),
                  const SizedBox(height: 12),
                  HudButton(
                    icon: Icons.flare,
                    tooltip: 'Strobe',
                    label: 'Strobe',
                    active: _tool == Tool.strobe,
                    badge: _overlay.strobeOn && _tool != Tool.strobe,
                    onPressed: () => _selectTool(Tool.strobe),
                  ),
                  if (doc.isPhoto) ...[
                    const SizedBox(height: 12),
                    HudButton(
                      icon: Icons.contrast,
                      tooltip: 'Lines and tones',
                      label: 'Look',
                      active: _tool == Tool.look,
                      badge: _overlay.mode != ViewMode.original && _tool != Tool.look,
                      onPressed: () => _selectTool(Tool.look),
                    ),
                  ],
                  const SizedBox(height: 12),
                  HudButton(
                    icon: Icons.fiber_manual_record,
                    tooltip: 'Time-lapse',
                    label: 'Rec',
                    active: _tool == Tool.record,
                    activeColor: Palette.rec,
                    badge: recording && _tool != Tool.record,
                    onPressed: () => _selectTool(Tool.record),
                  ),
                  const SizedBox(height: 12),
                  HudButton(
                    icon: Icons.tune,
                    tooltip: 'Adjust placement',
                    label: 'Adjust',
                    active: _tool == Tool.adjust,
                    onPressed: () => _selectTool(Tool.adjust),
                  ),
                  const SizedBox(height: 12),
                  HudButton(
                    icon: Icons.visibility_off_outlined,
                    tooltip: 'Hide controls',
                    label: 'Hide',
                    onPressed: () {
                      setState(() => _hud = false);
                      if (_tool == Tool.pin) _ar.setPreview(false);
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: pad.bottom + 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_tool != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 72),
                      child: Glass(padding: const EdgeInsets.fromLTRB(14, 12, 14, 12), child: _panel(_tool!)),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (doc.isLesson) ...[
                    _LessonBar(controller: _overlay, recording: recording),
                    const SizedBox(height: 10),
                  ],
                  _OpacityBar(controller: _overlay),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _panel(Tool t) => switch (t) {
        Tool.pin => _pinPanel(),
        Tool.strobe => _strobePanel(),
        Tool.look => _lookPanel(),
        Tool.record => _recordPanel(),
        Tool.adjust => _adjustPanel(),
      };

  Widget _pinPanel() {
    final status = _ar.status;
    final (Color dot, String state) = switch (status) {
      TrackStatus.tracking => (Palette.blue, 'Pinned'),
      TrackStatus.searching => (Palette.tape, 'Searching'),
      TrackStatus.lost => (Palette.rec, 'Lost'),
      TrackStatus.idle => (Palette.vellumDim, 'Not pinned'),
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(
          'Pin to paper',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(state, style: TextStyles.mono.copyWith(color: dot)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<List<Offset>?>(
          valueListenable: _ar.sheet,
          builder: (context, sheet, _) {
            String text;
            if (_ar.anchored && status == TrackStatus.tracking) {
              text = _ar.note ?? 'The image now follows the paper if it or the phone moves.';
            } else if (_ar.engaged) {
              text = _ar.note ?? 'Hold steady…';
            } else if (_ar.target == TrackTarget.paper) {
              text = sheet != null
                  ? 'Sheet found. Place the image, then pin it.'
                  : 'Lay the paper flat on a darker surface with all four corners in view.';
            } else {
              text = 'Point at a textured page or sketchbook, then pin.';
            }
            return Text(text, style: TextStyles.bodyDim);
          },
        ),
        const SizedBox(height: 10),
        SegmentedButton<TrackTarget>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: TrackTarget.paper, label: Text('Sheet edges'), icon: Icon(Icons.crop_portrait, size: 18)),
            ButtonSegment(value: TrackTarget.surface, label: Text('Surface'), icon: Icon(Icons.texture, size: 18)),
          ],
          selected: {_ar.target},
          onSelectionChanged: (s) => _ar.target = s.first,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _camera.ready ? () => _ar.anchor() : null,
                icon: const Icon(Icons.push_pin, size: 18),
                label: Text(_ar.engaged ? 'Re-pin here' : 'Pin image here'),
              ),
            ),
            if (_ar.engaged) ...[
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: () => _ar.release(),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Palette.rule), foregroundColor: Palette.vellum),
                child: const Text('Unpin'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        ValueListenableBuilder<List<Offset>>(
          valueListenable: _ar.points,
          builder: (context, pts, _) => Text(
            '${pts.length} points · ${_ar.millis.toStringAsFixed(0)} ms per frame',
            style: TextStyles.mono.copyWith(fontSize: 10.5),
          ),
        ),
      ],
    );
  }

  Widget _strobePanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PanelHeader(
          'Strobe',
          trailing: Switch(value: _overlay.strobeOn, onChanged: (v) => _overlay.strobeOn = v),
        ),
        const Text('Flickers the image so gaps between your lines and the reference jump out.', style: TextStyles.bodyDim),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Speed', style: TextStyles.label),
            Expanded(
              child: Slider(
                value: _overlay.strobeHz,
                min: 1,
                max: 8,
                divisions: 7,
                onChanged: (v) => _overlay.strobeHz = v,
                semanticFormatterCallback: (v) => '${v.round()} flashes per second',
              ),
            ),
            SizedBox(width: 44, child: Text('${_overlay.strobeHz.round()} Hz', style: TextStyles.mono, textAlign: TextAlign.right)),
          ],
        ),
        SegmentedButton<StrobeStyle>(
          showSelectedIcon: false,
          segments: [for (final s in StrobeStyle.values) ButtonSegment(value: s, label: Text(s.label))],
          selected: {_overlay.strobeStyle},
          onSelectionChanged: (s) => _overlay.strobeStyle = s.first,
        ),
      ],
    );
  }

  Widget _lookPanel() {
    final o = _overlay;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<ViewMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ViewMode.original, label: Text('Photo')),
            ButtonSegment(value: ViewMode.lines, label: Text('Lines')),
            ButtonSegment(value: ViewMode.tones, label: Text('Tones')),
          ],
          selected: {o.mode},
          onSelectionChanged: (s) => o.setMode(s.first),
        ),
        if (o.busy != null) ...[
          const SizedBox(height: 10),
          Text(o.busy!, style: TextStyles.mono),
          const SizedBox(height: 4),
          const LinearProgressIndicator(minHeight: 2),
        ],
        const SizedBox(height: 8),
        if (o.mode == ViewMode.original)
          const Text('Lines turns the photo into clean outlines. Tones splits it into shading layers.', style: TextStyles.bodyDim),
        if (o.mode == ViewMode.lines) ...[
          Row(
            children: [
              const SizedBox(width: 56, child: Text('Detail', style: TextStyles.label)),
              Expanded(
                child: Slider(
                  value: _detailDraft ?? o.lineDetail,
                  onChanged: (v) => setState(() => _detailDraft = v),
                  onChangeEnd: (v) {
                    _detailDraft = null;
                    o.setLineParams(detail: v);
                  },
                ),
              ),
            ],
          ),
          Row(
            children: [
              const SizedBox(width: 56, child: Text('Weight', style: TextStyles.label)),
              for (final w in [1, 2, 3])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$w'),
                    selected: o.lineWeight == w,
                    showCheckmark: false,
                    onSelected: (_) => o.setLineParams(weight: w),
                    labelStyle: TextStyles.label.copyWith(color: o.lineWeight == w ? Palette.blueInk : Palette.vellum),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const SizedBox(width: 56, child: Text('Ink', style: TextStyles.label)),
              for (final ink in LineInk.values) _InkSwatch(ink: ink, selected: o.lineInk == ink, onTap: () => o.lineInk = ink),
            ],
          ),
        ],
        if (o.mode == ViewMode.tones) ...[
          Row(
            children: [
              const Text('Layers', style: TextStyles.label),
              const SizedBox(width: 8),
              for (final n in [3, 4])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text('$n'),
                    selected: o.toneLevels == n,
                    showCheckmark: false,
                    onSelected: (_) => o.setToneLevels(n),
                    labelStyle: TextStyles.label.copyWith(color: o.toneLevels == n ? Palette.blueInk : Palette.vellum),
                  ),
                ),
              const Spacer(),
              const Text('Colour-code', style: TextStyles.label),
              Switch(value: o.toneColorCoded, onChanged: (v) => o.toneColorCoded = v),
            ],
          ),
          const SizedBox(height: 4),
          if (o.toneImages != null)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 0; i < o.toneImages!.length && i < o.toneNames.length; i++)
                  FilterChip(
                    avatar: CircleAvatar(backgroundColor: o.toneColors[i], radius: 7),
                    label: Text('${o.toneNames[i]} ${(o.toneCoverage[i] * 100).round()}%'),
                    selected: o.toneVisible[i],
                    showCheckmark: false,
                    onSelected: (_) => o.toggleTone(i),
                    labelStyle: TextStyles.label.copyWith(color: o.toneVisible[i] ? Palette.blueInk : Palette.vellumDim),
                  ),
              ],
            ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: o.busy == null ? _makeLesson : null,
            icon: const Icon(Icons.stairs_outlined, size: 18),
            label: const Text('Make a step-by-step lesson'),
          ),
        ),
      ],
    );
  }

  Widget _recordPanel() {
    final recording = _rec.state == RecordState.recording;
    final saving = _rec.state == RecordState.saving;
    String two(int v) => v.toString().padLeft(2, '0');
    final e = _rec.elapsed;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelHeader('Time-lapse'),
        const SizedBox(height: 4),
        const Text('Snapshots of your page and the overlay become a sped-up video in your gallery.', style: TextStyles.bodyDim),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final i in CaptureInterval.values)
              ChoiceChip(
                label: Text('Every ${i.label} · ${i.speedUp(TimelapseRecorder.outputFps)}×'),
                selected: _rec.interval == i,
                showCheckmark: false,
                onSelected: recording || saving ? null : (_) => setState(() => _rec.interval = i),
                labelStyle: TextStyles.label.copyWith(color: _rec.interval == i ? Palette.blueInk : Palette.vellum),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: Palette.rec, foregroundColor: Colors.white),
              onPressed: saving || !_camera.ready
                  ? null
                  : () => recording ? _rec.stop() : _rec.start(_view),
              icon: Icon(recording ? Icons.stop : Icons.fiber_manual_record, size: 18),
              label: Text(saving ? 'Saving…' : (recording ? 'Stop and save' : 'Start recording')),
            ),
            const SizedBox(width: 12),
            if (recording || saving)
              Expanded(
                child: Text(
                  '${two(e.inMinutes)}:${two(e.inSeconds % 60)} · ${_rec.frames} frames',
                  style: TextStyles.mono,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _adjustPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const PanelHeader('Placement'),
        const SizedBox(height: 4),
        const Text('Pinch to resize, drag to move, twist to rotate.', style: TextStyles.bodyDim),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PanelAction(icon: Icons.fit_screen_outlined, label: 'Fit', onTap: _overlay.locked ? null : () => _overlay.fitTo(_view, force: true)),
            _PanelAction(icon: Icons.flip, label: 'Mirror', onTap: _overlay.locked ? null : _overlay.flip),
            _PanelAction(icon: Icons.rotate_90_degrees_cw_outlined, label: 'Rotate 90°', onTap: _overlay.locked ? null : _rotate90),
          ],
        ),
      ],
    );
  }
}

class _InkSwatch extends StatelessWidget {
  const _InkSwatch({required this.ink, required this.selected, required this.onTap});
  final LineInk ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${ink.label} lines',
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: selected ? Palette.blue : Colors.transparent, width: 2),
          ),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: ink.color,
              shape: BoxShape.circle,
              border: Border.all(color: Palette.rule),
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelAction extends StatelessWidget {
  const _PanelAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(side: const BorderSide(color: Palette.rule), foregroundColor: Palette.vellum),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _CameraView extends StatelessWidget {
  const _CameraView({required this.camera});
  final CameraService camera;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: camera,
      builder: (context, _) {
        final error = camera.error;
        if (error != null) {
          return ColoredBox(
            color: Palette.graphite,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.no_photography_outlined, color: Palette.vellumDim, size: 40),
                    const SizedBox(height: 12),
                    Text(error, style: TextStyles.body, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: camera.start, child: const Text('Try again')),
                  ],
                ),
              ),
            ),
          );
        }
        final c = camera.controller;
        final ps = camera.previewSize;
        if (c == null || !c.value.isInitialized || ps == null) {
          return const ColoredBox(color: Palette.graphite, child: Center(child: CircularProgressIndicator()));
        }
        final swaps = camera.sensorOrientation % 180 != 0;
        final w = swaps ? ps.height : ps.width, h = swaps ? ps.width : ps.height;
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(width: w, height: h, child: CameraPreview(c)),
          ),
        );
      },
    );
  }
}

class _RecBadge extends StatelessWidget {
  const _RecBadge({required this.rec});
  final TimelapseRecorder rec;

  @override
  Widget build(BuildContext context) {
    final e = rec.elapsed;
    String two(int v) => v.toString().padLeft(2, '0');
    final saving = rec.state == RecordState.saving;
    return Glass(
      radius: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 9, height: 9, decoration: const BoxDecoration(color: Palette.rec, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(
            saving ? 'SAVING' : '${two(e.inMinutes)}:${two(e.inSeconds % 60)}',
            style: TextStyles.mono.copyWith(color: Palette.vellum),
          ),
        ],
      ),
    );
  }
}

class _OpacityBar extends StatelessWidget {
  const _OpacityBar({required this.controller});
  final OverlayController controller;

  @override
  Widget build(BuildContext context) {
    final pct = (controller.opacity * 100).round();
    return Glass(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
      child: Row(
        children: [
          const Icon(Icons.opacity, color: Palette.vellumDim, size: 20),
          Expanded(
            child: Slider(
              value: controller.opacity,
              onChanged: (v) => controller.opacity = v,
              semanticFormatterCallback: (v) => 'Image opacity ${(v * 100).round()} percent',
            ),
          ),
          SizedBox(width: 44, child: Text('$pct%', style: TextStyles.mono.copyWith(color: Palette.vellum, fontSize: 13), textAlign: TextAlign.right)),
        ],
      ),
    );
  }
}

class _LessonBar extends StatelessWidget {
  const _LessonBar({required this.controller, required this.recording});
  final OverlayController controller;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    final player = controller.player!;
    final steps = controller.doc.steps!;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final done = player.isComplete;
        final step = steps[player.index];
        final title = done ? 'Lesson complete' : step.title;
        final tip = done
            ? (recording ? 'All layers are showing. Stop the time-lapse to save your video.' : 'All layers are showing. Use the strobe to check your drawing.')
            : step.tip;
        return Glass(
          padding: const EdgeInsets.fromLTRB(6, 10, 10, 10),
          child: Row(
            children: [
              IconButton(
                onPressed: player.canGoBack ? player.previous : null,
                tooltip: 'Previous step',
                icon: const Icon(Icons.chevron_left),
                color: Palette.vellum,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Text(
                          done ? 'DONE' : 'STEP ${player.index + 1} OF ${player.stepCount}',
                          style: TextStyles.mono.copyWith(color: Palette.blue, fontSize: 11),
                        ),
                        const SizedBox(width: 10),
                        for (var i = 0; i < player.stepCount; i++)
                          Container(
                            width: 14,
                            height: 3,
                            margin: const EdgeInsets.only(right: 3),
                            decoration: BoxDecoration(
                              color: done || i <= player.index ? Palette.blue : Palette.rule,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(title, style: TextStyles.title.copyWith(fontSize: 17)),
                    const SizedBox(height: 2),
                    Text(tip, style: TextStyles.bodyDim.copyWith(fontSize: 12.5), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              if (done)
                IconButton.filledTonal(onPressed: player.restart, tooltip: 'Start over', icon: const Icon(Icons.replay))
              else
                IconButton.filled(
                  onPressed: player.next,
                  tooltip: player.isLastStep ? 'Finish lesson' : 'Next step',
                  icon: Icon(player.isLastStep ? Icons.check : Icons.chevron_right),
                ),
            ],
          ),
        );
      },
    );
  }
}
