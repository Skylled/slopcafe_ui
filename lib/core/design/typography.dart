import 'package:flutter/material.dart';

/// Craft typography.
///
/// The mockup uses Instrument Serif (display), Hanken Grotesk (sans) and Space
/// Mono (mono). Per the chosen "system fallback" approach we don't bundle font
/// files; instead we resolve to the closest platform fonts via fallback stacks:
///   - display -> a system serif (Georgia / Times / generic serif)
///   - sans    -> the platform default (SF Pro / Roboto), via `fontFamily: null`
///   - mono    -> a system monospace (Menlo / SF Mono / Roboto Mono)
///
/// Styles intentionally omit color; color is inherited from the ambient
/// [DefaultTextStyle] / [TextTheme] (onSurface) or applied at the call site with
/// `.copyWith(color: ...)`.
class AppText {
  AppText._();

  static const List<String> serif = ['Georgia', 'Times New Roman', 'serif'];
  static const List<String> monoStack = [
    'Menlo',
    'SF Mono',
    'Consolas',
    'Roboto Mono',
    'monospace',
  ];

  // ---- Display / serif ----
  static const TextStyle display = TextStyle(
    fontFamilyFallback: serif,
    fontSize: 34,
    fontWeight: FontWeight.w400,
    height: 1.0,
    letterSpacing: -0.4,
  );
  static const TextStyle featured = TextStyle(
    fontFamilyFallback: serif,
    fontSize: 27,
    fontWeight: FontWeight.w400,
    height: 1.1,
    letterSpacing: -0.3,
  );
  static const TextStyle headline = TextStyle(
    fontFamilyFallback: serif,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
  );
  static const TextStyle titleSerif = TextStyle(
    fontFamilyFallback: serif,
    fontSize: 19,
    fontWeight: FontWeight.w400,
    height: 1.15,
  );
  static const TextStyle serifItalic = TextStyle(
    fontFamilyFallback: serif,
    fontSize: 18,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    height: 1.45,
  );

  // ---- Sans ----
  static const TextStyle title = TextStyle(
    fontSize: 15.5,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const TextStyle titleSm = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );
  static const TextStyle body = TextStyle(fontSize: 14, height: 1.4);
  static const TextStyle bodyLg = TextStyle(fontSize: 16.5, height: 1.5);
  static const TextStyle small = TextStyle(fontSize: 12.5, height: 1.35);

  /// Uppercase eyebrow label (apply `.toUpperCase()` to the text yourself).
  static const TextStyle label = TextStyle(
    fontSize: 11.5,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
  );
  static const TextStyle pill = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );

  // ---- Mono ----
  static const TextStyle monoLabel = TextStyle(
    fontFamilyFallback: monoStack,
    fontSize: 11.5,
    letterSpacing: 0.3,
  );
  static const TextStyle mono = TextStyle(
    fontFamilyFallback: monoStack,
    fontSize: 12.5,
    height: 1.5,
  );

  /// Builds a Material [TextTheme] so plain [Text] widgets inherit sensible
  /// Craft defaults (sans body, serif display) coloured for [onSurface].
  static TextTheme textTheme(Color onSurface) {
    final base = ThemeData(brightness: Brightness.light).textTheme;
    return base
        .copyWith(
          displayLarge: display,
          displayMedium: featured,
          headlineSmall: headline,
          titleLarge: titleSerif,
          titleMedium: title,
          titleSmall: titleSm,
          bodyLarge: bodyLg,
          bodyMedium: body,
          bodySmall: small,
          labelLarge: title,
          labelSmall: label,
        )
        .apply(bodyColor: onSurface, displayColor: onSurface);
  }
}
