import 'package:flutter/material.dart';

import '../content/lessons.dart';
import '../content/templates.dart';
import 'theme.dart';

/// Translucent graphite panel that floats over the camera feed.
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(12), this.radius = 18});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Palette.graphite.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: Palette.rule.withValues(alpha: 0.8)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Round HUD button with an optional caption and "on" state.
class HudButton extends StatelessWidget {
  const HudButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.active = false,
    this.activeColor = Palette.blue,
    this.badge = false,
  });

  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final bool active;
  final Color activeColor;
  final bool badge;

  @override
  Widget build(BuildContext context) {
    final fg = active ? Palette.graphite : Palette.vellum;
    final button = Semantics(
      button: true,
      toggled: active,
      label: tooltip,
      excludeSemantics: true,
      child: Material(
        color: active ? activeColor : Palette.graphite.withValues(alpha: 0.78),
        shape: CircleBorder(side: BorderSide(color: active ? activeColor : Palette.rule.withValues(alpha: 0.8))),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, size: 22, color: onPressed == null ? Palette.vellumDim : fg),
                if (badge)
                  Positioned(
                    right: 9,
                    top: 9,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: Palette.blue, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: label == null
          ? button
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                button,
                const SizedBox(height: 4),
                Text(
                  label!,
                  style: TextStyles.mono.copyWith(
                    fontSize: 10.5,
                    color: Palette.vellum,
                    shadows: const [Shadow(blurRadius: 4, color: Colors.black)],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Round HUD button that reports press and release, for controls that act
/// while held. Looks like [HudButton]; [onTap] serves screen readers, which
/// cannot hold.
class HoldButton extends StatefulWidget {
  const HoldButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onDown,
    required this.onUp,
    required this.onCancel,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onDown;
  final VoidCallback onUp;
  final VoidCallback onCancel;
  final VoidCallback onTap;
  final bool active;

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  bool _down = false;

  void _set(bool v, VoidCallback notify) {
    setState(() => _down = v);
    notify();
  }

  @override
  Widget build(BuildContext context) {
    final lit = widget.active || _down;
    return Semantics(
      button: true,
      toggled: widget.active,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      excludeSemantics: true,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _set(true, widget.onDown),
        onPointerUp: (_) => _set(false, widget.onUp),
        onPointerCancel: (_) => _set(false, widget.onCancel),
        child: AnimatedScale(
          scale: _down ? 0.92 : 1,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: lit ? Palette.blue : Palette.graphite.withValues(alpha: 0.78),
              border: Border.all(color: lit ? Palette.blue : Palette.rule.withValues(alpha: 0.8)),
            ),
            child: Icon(widget.icon, size: 22, color: lit ? Palette.graphite : Palette.vellum),
          ),
        ),
      ),
    );
  }
}

/// Small uppercase-free caption row used inside panels.
class PanelHeader extends StatelessWidget {
  const PanelHeader(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(title, style: TextStyles.title.copyWith(fontSize: 17))),
        ?trailing,
      ],
    );
  }
}

/// A sheet of drawing paper showing built-in art.
class PaperThumb extends StatelessWidget {
  const PaperThumb({super.key, required this.draw, this.opaque = false, this.tilt = 0});
  final ArtDraw draw;
  final bool opaque;
  final double tilt;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: tilt,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.paper,
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: RepaintBoundary(
            child: CustomPaint(painter: _ArtPainter(draw, opaque), child: const SizedBox.expand()),
          ),
        ),
      ),
    );
  }
}

class _ArtPainter extends CustomPainter {
  _ArtPainter(this.draw, this.opaque);
  final ArtDraw draw;
  final bool opaque;

  @override
  void paint(Canvas canvas, Size size) {
    // Photos cover the card; line art sits on the sheet with a margin.
    final s = opaque ? size.longestSide : size.shortestSide;
    final pad = opaque ? 0.0 : s * 0.06;
    final scale = (s - 2 * pad) / 1000;
    canvas.translate((size.width - 1000 * scale) / 2, (size.height - 1000 * scale) / 2);
    canvas.scale(scale);
    draw(canvas);
  }

  @override
  bool shouldRepaint(_ArtPainter old) => old.draw != draw;
}

TemplateSpec templateById(String id) => builtInTemplates.firstWhere((t) => t.id == id);
