import 'package:flutter/material.dart';

/// Cortado typography.
///
/// The mockup uses Instrument Serif (display), Hanken Grotesk (sans) and Space
/// Mono (mono). Only the display face is bundled; the other two resolve to the
/// closest platform fonts through fallback stacks:
///   - display -> **Instrument Serif**, shipped at assets/fonts (see below),
///                with the old system-serif stack still beneath it
///   - sans    -> the platform default (SF Pro / Roboto), via `fontFamily: null`
///   - mono    -> a system monospace (Menlo / SF Mono / Roboto Mono)
///
/// ## Why the display face had to be bundled, and only that one
///
/// Every style here used to name its family and let the platform find it —
/// `fontFamilyFallback: ['Georgia', 'Times New Roman', 'serif']`. That works on
/// macOS, iOS and Android, where the engine can ask the OS for a font by name.
/// **It cannot work in a browser.** Flutter's web engine lays text out in Skia
/// with the typefaces it was given: assets declared in the pubspec, plus its
/// own fallbacks. It has no access to the system font list at all, so an
/// unknown family is not an error — it is a silent miss that lands on the
/// default sans.
///
/// Measured, not assumed. Laying the same string out under `Georgia`,
/// `Times New Roman`, `serif`, the stack above and a family invented on the
/// spot gives five identical widths in Chrome, and the same width as no family
/// at all. So on the web the serif simply was not there: every screen title,
/// every card headline, the whole display voice of the design, rendered as
/// Roboto and nothing said so. `test/web_fonts_browser_test.dart` is that
/// measurement, kept.
///
/// The sans and mono stacks are left alone on purpose. They miss on the web in
/// exactly the same way, but what they miss *onto* is the engine's default —
/// Roboto, a perfectly good grotesque, and a monospace for the mono styles —
/// so the cost is a shade of difference rather than the loss of a voice. A
/// serif replaced by a sans is a different design; Hanken Grotesk replaced by
/// Roboto is the same design in a near neighbour. Bundling those two as well
/// would put another ~200 KB in front of the first frame to fix something
/// nobody can see.
///
/// ## One face, upright
///
/// The bundle is Instrument Serif Regular alone. All asset fonts are fetched
/// before the web build paints, so a second file is a real cost on the launch
/// path, and every serif style the app uses is upright. [serifItalic] is the
/// exception and it keeps the old behaviour deliberately: it stays on the
/// platform stack, so it italicises properly on native and degrades to a
/// slanted default on the web. Asking a one-face family for an italic does not
/// synthesise one — it renders upright, which is worse than a fallback,
/// because it looks like a style that was never applied.
///
/// If [serifItalic] ever acquires a call site where the serif identity matters,
/// the fix is two lines: add `InstrumentSerif-Italic.ttf` (OFL, same source)
/// under the family in pubspec.yaml with `style: italic`, and give this style
/// the same `fontFamily` as its siblings.
///
/// Styles intentionally omit color; color is inherited from the ambient
/// [DefaultTextStyle] / [TextTheme] (onSurface) or applied at the call site with
/// `.copyWith(color: ...)`.
class AppText {
  AppText._();

  /// The bundled display family, as declared in pubspec.yaml.
  ///
  /// The two spellings must match exactly — Flutter registers an asset font
  /// under the name the pubspec gives it, and a typo here is another silent
  /// miss onto the default sans rather than a build error.
  static const String serifFamily = 'Instrument Serif';

  /// The platform serifs, kept as the layer *under* [serifFamily].
  ///
  /// Not vestigial: it is what renders if the asset ever fails to load, and it
  /// is the whole story for [serifItalic]. On the web it resolves to nothing
  /// (see the class doc), which is exactly why it is no longer alone.
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
    fontFamily: serifFamily,
    fontFamilyFallback: serif,
    fontSize: 34,
    fontWeight: FontWeight.w400,
    height: 1.0,
    letterSpacing: -0.4,
  );
  static const TextStyle featured = TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: serif,
    fontSize: 27,
    fontWeight: FontWeight.w400,
    height: 1.1,
    letterSpacing: -0.3,
  );
  static const TextStyle headline = TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: serif,
    fontSize: 22,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.2,
  );
  static const TextStyle titleSerif = TextStyle(
    fontFamily: serifFamily,
    fontFamilyFallback: serif,
    fontSize: 19,
    fontWeight: FontWeight.w400,
    height: 1.15,
  );

  /// The one serif style with no bundled face — see the class doc's "One face,
  /// upright". Left on the platform stack so it is genuinely italic where a
  /// real italic exists, rather than upright everywhere.
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
  /// Cortado defaults (sans body, serif display) coloured for [onSurface].
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
