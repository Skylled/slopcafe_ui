// Guards the display serif, which the web build can lose without saying so.
//
// Flutter's web renderers lay text out in Skia against a font provider they
// build themselves: the fonts declared in `pubspec.yaml` (via the generated
// FontManifest), the Noto faces the fallback manager downloads for glyph
// coverage, and Roboto as the last resort. Neither renderer can see the
// operating system's font list —
//
//   bin/cache/flutter_web_sdk/lib/_engine/engine/canvaskit/fonts.dart
//     `_registerWithFontProvider` registers only `_registeredFonts` (assets)
//     and `registeredFallbackFonts` into a `TypefaceFontProvider`, which is
//     then `setDefaultFontManager`; Roboto is downloaded if the app did not
//     bundle it, "in order to avoid crashing while laying out text with an
//     unregistered font".
//   bin/cache/flutter_web_sdk/lib/_skwasm_impl/skwasm_impl/font_collection.dart
//     same shape, with `setDefaultFontFamilies(['Roboto'])`.
//
// — so a style that names `Georgia` on the web does not fail, it lands on
// Roboto. The app's entire display voice went missing that way, invisibly.
// Bundling one face is the fix; this file is what keeps it bundled.
//
// ## Why this is a source test and not a rendering one
//
// The obvious test — lay out a string in the family, check it does not measure
// like the default — cannot be written. `flutter test` forces all text through
// the "Ahem" test font, which draws every glyph as a square of exactly the font
// size, and it does so under `--platform chrome` too: every family, real or
// invented, measures identically there. An earlier draft of this file "proved"
// the finding that way and was measuring nothing at all. The real evidence is
// the engine source quoted above; what is left to guard is the wiring, which is
// exactly what a source test can see.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/design/typography.dart';

/// Serif styles that deliberately do NOT use the bundled family.
///
/// An exemption list, not a loophole: each entry needs a reason, and the second
/// test below fails if an entry names a style that no longer exists, so a
/// rename cannot leave a hole behind.
const _unbundledSerifStyles = <String>{
  // Only the Regular face is bundled — all asset fonts are fetched before the
  // first web frame, and a second file on that path for a style with no call
  // sites is not worth it. A one-face family asked for an italic renders
  // UPRIGHT rather than synthesising a slant, so this style keeps the platform
  // stack: real italics on native, a slanted default on the web. See the class
  // doc in typography.dart for the two-line change if that stops being true.
  'serifItalic',
};

/// `static const TextStyle name = TextStyle( … );` declarations.
final _styleDecl = RegExp(
  r'static const TextStyle (\w+) = TextStyle\((.*?)\n  \);',
  dotAll: true,
);

void main() {
  group('the bundled display serif stays bundled', () {
    late String pubspec;

    setUpAll(() {
      pubspec = File('pubspec.yaml').readAsStringSync();
    });

    test('pubspec declares the family under the name the styles ask for', () {
      expect(
        pubspec,
        contains('- family: ${AppText.serifFamily}'),
        reason:
            'AppText.serifFamily is "${AppText.serifFamily}" but pubspec.yaml '
            'declares no font family by that name. Flutter registers an asset '
            'font under the name the pubspec gives it, so the two spellings '
            'have to match exactly — a mismatch is not a build error, it is '
            'every serif style silently falling back to the default sans.',
      );
    });

    test('every font file the pubspec promises exists', () {
      final assets = RegExp(r'-\s+asset:\s*(\S+)')
          .allMatches(pubspec)
          .map((m) => m.group(1)!)
          .where((path) => path.startsWith('assets/fonts/'))
          .toList();

      expect(
        assets,
        isNotEmpty,
        reason: 'No font assets declared at all — the family entry above has '
            'nothing under it.',
      );
      for (final path in assets) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is declared in pubspec.yaml but is not on disk. The '
              'web build ships a FontManifest pointing at a 404, and the '
              'engine falls back to Roboto with a console line nobody reads.',
        );
      }
    });

    test('the serif text styles ask for the bundled family', () {
      // The direct check: these are the four styles the app sets its display
      // type in, and they are what a reader sees on every screen.
      final serifStyles = {
        'display': AppText.display,
        'featured': AppText.featured,
        'headline': AppText.headline,
        'titleSerif': AppText.titleSerif,
      };
      serifStyles.forEach((name, style) {
        expect(
          style.fontFamily,
          AppText.serifFamily,
          reason: 'AppText.$name does not name the bundled family, so it '
              'renders in the default sans on the web.',
        );
        expect(
          style.fontFamilyFallback,
          AppText.serif,
          reason: 'AppText.$name dropped the platform serif stack. It is the '
              'layer under the asset — keep it.',
        );
      });
    });

    test('a NEW serif style cannot be added on the old pattern', () {
      // The future-proofing half. The trap is writing the next serif style the
      // way every one of them used to be written — `fontFamilyFallback: serif`
      // and nothing else — which analyses, builds, renders correctly on the
      // development Mac, and is wrong in a browser.
      final source =
          File('lib/core/design/typography.dart').readAsStringSync();
      final offenders = <String>[];

      for (final decl in _styleDecl.allMatches(source)) {
        final name = decl.group(1)!;
        final body = decl.group(2)!;
        if (!body.contains('fontFamilyFallback: serif')) continue;
        if (_unbundledSerifStyles.contains(name)) continue;
        if (body.contains('fontFamily: serifFamily')) continue;
        offenders.add(name);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These serif styles fall back to the platform serif stack without '
            'naming the bundled family first, so on the web they resolve to '
            'nothing and render as the default sans. Add '
            '`fontFamily: serifFamily`, or — if the style genuinely wants the '
            'platform face — name it in _unbundledSerifStyles with the reason.',
      );
    });

    test('_unbundledSerifStyles names only styles that exist', () {
      final source =
          File('lib/core/design/typography.dart').readAsStringSync();
      final declared = _styleDecl
          .allMatches(source)
          .map((m) => m.group(1)!)
          .toSet();

      for (final name in _unbundledSerifStyles) {
        expect(
          declared,
          contains(name),
          reason: '$name is exempted above but no longer exists. Remove the '
              'entry — a stale exemption is a hole in the check.',
        );
      }
    });
  });
}
