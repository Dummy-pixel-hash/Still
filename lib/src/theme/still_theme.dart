import 'package:flutter/material.dart';

/// Visual language carried over from the `still-frontend` prototype
/// (kept intact as reference; see `../still-frontend prototype`).
///
/// Black/deep-charcoal spatial surfaces, subtle red ambient light, tactile
/// depth (inset highlight + hairline ring + deep shadow), restrained
/// controls. Deliberately NOT Material-dashboard / SaaS / glass / neon.
abstract class StillTheme {
  // Surfaces.
  static const ink = Color(0xFF050505);
  static const cardTop = Color(0xFF141416);
  static const cardBottom = Color(0xFF0B0B0C);
  static const previewWell = Color(0xFF050505);
  static const chrome = Color(0xFF121214);

  // Red ambient.
  static const red = Color(0xFFFF4A4A);
  static const redDeep = Color(0xFFB3161C);
  static const redSoft = Color(0xFFFF6A6A);

  // Text.
  static const fg = Color(0xFFE2DCE5);
  static const cardFg = Color(0xFFD6D2DA);
  static const dim = Color(0xFF99929F);
  static const faint = Color(0xFF6B6764);
  static const monoBody = Color(0xFFB0AAB8);

  // Hairlines.
  static const ring = Color(0xFFFFFFFF); // used at very low alpha

  static const double cardRadius = 20;
  static const double wellRadius = 12;

  /// Serif italic voice ("Still", "Sessions"). System serif fallback chain
  /// so no font downloads / new deps are needed on Windows + Android.
  static const serifFallbacks = ['Georgia', 'serif'];
  static const monoFallbacks = ['Consolas', 'monospace'];

  static TextStyle get serifTitle => const TextStyle(
        fontFamily: 'Georgia',
        fontFamilyFallback: serifFallbacks,
        fontStyle: FontStyle.italic,
        color: fg,
      );

  static TextStyle get sans => const TextStyle(color: fg);

  static TextStyle get mono => const TextStyle(
        fontFamily: 'monospace',
        fontFamilyFallback: monoFallbacks,
        color: monoBody,
      );

  /// Tactile card decoration: top inset highlight, hairline ring,
  /// deep drop shadow. Matches the prototype's layered box-shadow.
  static BoxDecoration get cardDecoration => BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [cardTop, cardBottom],
        ),
        border: Border.all(color: Colors.white.withAlpha(15)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(255, 255, 255, 0.07),
            offset: Offset(0, 1),
            blurRadius: 0,
            spreadRadius: 0,
          ),
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.9),
            offset: Offset(0, 24),
            blurRadius: 40,
            spreadRadius: -18,
          ),
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.5),
            offset: Offset(0, 2),
            blurRadius: 6,
          ),
        ],
      );

  /// Inset terminal-preview well.
  static BoxDecoration get wellDecoration => BoxDecoration(
        borderRadius: BorderRadius.circular(wellRadius),
        color: previewWell,
        border: Border.all(color: Colors.white.withAlpha(10)),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.9),
            offset: Offset(0, 1),
            blurRadius: 6,
            spreadRadius: 0,
          ),
        ],
      );

  /// Red ambient glows behind the workspace (prototype: blurred red orbs).
  static List<Widget> ambientGlows(Size size) => [
        Positioned(
          top: -size.height * 0.35,
          left: size.width * 0.08,
          child: Container(
            width: size.width * 0.6,
            height: size.height * 0.5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: red.withAlpha(23),
            ),
          ),
        ),
        Positioned(
          bottom: -size.height * 0.33,
          right: -size.width * 0.08,
          child: Container(
            width: size.width * 0.44,
            height: size.height * 0.42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: redDeep.withAlpha(26),
            ),
          ),
        ),
      ];

  static ThemeData get materialTheme {
    const scheme = ColorScheme.dark(
      surface: ink,
      primary: red,
      onSurface: fg,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: redSoft,
        selectionColor: Color(0x66FF4A4A),
        selectionHandleColor: redSoft,
      ),
    );
  }
}
