import 'package:flutter/material.dart';

/// Graphite surfaces, vellum text, non-photo-blue accent (the pencil artists
/// use for construction lines), masking-tape yellow for "attention".
abstract final class Palette {
  static const graphite = Color(0xFF131416);
  static const graphite2 = Color(0xFF1C1E21);
  static const graphite3 = Color(0xFF282B30);
  static const rule = Color(0xFF3A3E45);
  static const vellum = Color(0xFFECE9E2);
  static const vellumDim = Color(0xFFA9A69F);
  static const paper = Color(0xFFF4F2EC);
  static const blue = Color(0xFF7CC9EE);
  static const blueInk = Color(0xFF0E3446);
  static const tape = Color(0xFFE9BE5A);
  static const rec = Color(0xFFF0524F);
}

abstract final class Fonts {
  static const display = 'Bricolage';
  static const body = 'Instrument';
  static const mono = 'JetBrainsMono';
}

abstract final class TextStyles {
  static const display = TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w800, fontSize: 34, height: 1.0, letterSpacing: -0.8, color: Palette.vellum);
  static const title = TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w700, fontSize: 19, height: 1.15, letterSpacing: -0.2, color: Palette.vellum);
  static const section = TextStyle(fontFamily: Fonts.display, fontWeight: FontWeight.w700, fontSize: 21, height: 1.1, letterSpacing: -0.3, color: Palette.vellum);
  static const body = TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w400, fontSize: 14.5, height: 1.35, color: Palette.vellum);
  static const bodyDim = TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w400, fontSize: 13.5, height: 1.35, color: Palette.vellumDim);
  static const label = TextStyle(fontFamily: Fonts.body, fontWeight: FontWeight.w600, fontSize: 13, height: 1.2, color: Palette.vellum);
  static const mono = TextStyle(fontFamily: Fonts.mono, fontWeight: FontWeight.w500, fontSize: 12, height: 1.2, letterSpacing: 0.2, color: Palette.vellumDim);
}

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: Palette.blue,
    onPrimary: Palette.blueInk,
    secondary: Palette.tape,
    onSecondary: Palette.graphite,
    surface: Palette.graphite2,
    onSurface: Palette.vellum,
    error: Palette.rec,
    outline: Palette.rule,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.graphite,
    fontFamily: Fonts.body,
    splashFactory: InkSparkle.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: Palette.vellum, displayColor: Palette.vellum),
    sliderTheme: const SliderThemeData(
      trackHeight: 3,
      activeTrackColor: Palette.blue,
      inactiveTrackColor: Palette.rule,
      thumbColor: Palette.vellum,
      overlayColor: Color(0x337CC9EE),
      showValueIndicator: ShowValueIndicator.never,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Palette.graphite3,
      contentTextStyle: TextStyles.body,
      actionTextColor: Palette.blue,
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Palette.graphite2,
      selectedColor: Palette.blue,
      side: const BorderSide(color: Palette.rule),
      labelStyle: TextStyles.label,
      secondaryLabelStyle: TextStyles.label.copyWith(color: Palette.blueInk),
      checkmarkColor: Palette.blueInk,
      shape: const StadiumBorder(),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        side: const WidgetStatePropertyAll(BorderSide(color: Palette.rule)),
        textStyle: const WidgetStatePropertyAll(TextStyles.label),
        backgroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.blue : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.blueInk : Palette.vellum),
        visualDensity: VisualDensity.compact,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.blueInk : Palette.vellumDim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Palette.blue : Palette.graphite3),
      trackOutlineColor: const WidgetStatePropertyAll(Palette.rule),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Palette.blue, linearTrackColor: Palette.graphite3),
  );
}
