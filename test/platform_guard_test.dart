// Guards against the one class of bug the web build cannot report: a `dart:io`
// reach-through that compiles cleanly and then throws in a browser.
//
// Under dart2js `dart:io` is not absent, it is a *throwing stub* — every
// `Platform` member raises `UnsupportedError` at runtime. So the usual three
// safety nets all miss it:
//
//   - `flutter build web` succeeds, because the import resolves.
//   - `flutter analyze` is silent, because the types are real.
//   - The browser console is EMPTY, because Flutter catches the throw during
//     the build phase and swaps the subtree for an `ErrorWidget`. In a release
//     build that widget is `RenderErrorBox`, a bare grey rectangle
//     (`0xF0C0C0C0`) — it reads as a layout bug, not a crash.
//
// That combination is how `deepLinksSupported` took out the entire shell: it is
// read by `inboundDeepLinksProvider`, which `AppShell` initialises in
// `initState`, so a *configured* install painted grey and nothing else in the
// app was reachable. First run was fine, because it routes to Settings instead
// — which is precisely why it survived casual testing.
//
// Hermetic: reads source files off disk, exactly like the Gradle↔Dart host
// invariant in deep_link_test.dart. Nothing here needs a platform channel.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that still import `dart:io` and are NOT yet web-safe.
///
/// This list is a to-do, not an exemption — every entry is a screen or service
/// that misbehaves in a browser, and it is meant to sit **empty**, which it now
/// does. It held two names and both were fixed by the same move rather than by
/// a `kIsWeb` branch:
///
///   * `lib/core/document_cache.dart` — `path_provider` + `File`/`Directory`.
///     Now a conditional-export barrel over `document_cache_io.dart` and
///     `document_cache_web.dart` (an in-memory LRU plus `sessionStorage`), so
///     the browser's cache is a deliberate implementation instead of the
///     accidental silent no-op every method's swallowed error used to produce.
///   * `lib/screens/reader_screen.dart` — `Platform.isAndroid/isIOS/isMacOS` in
///     `_openExternalBrowser`, which in a browser threw on the first read and
///     reported "could not launch" on the one platform that *is* a browser.
///     The ladder now lives behind `lib/core/external_browser.dart`.
///
/// Adding a name back here is a deliberate act, and it should be the last
/// resort: the seam below is a better answer whenever the platform difference
/// is real rather than incidental. A NEW file reaching for `dart:io` with
/// neither a `kIsWeb` guard, a barrel, nor an entry here fails this test.
const _pendingWebPort = <String>{};

final _importsDartIo = RegExp(r'''^\s*import\s+['"]dart:io['"]''', multiLine: true);

/// Matches the two platform-split file suffixes the app uses.
final _platformImplSuffix = RegExp(r'_(io|web)\.dart$');

/// Every `.dart` file under `lib/`, keyed by path.
Map<String, String> _libSources() {
  final sources = <String, String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    sources[entity.path] = entity.readAsStringSync();
  }
  return sources;
}

String _basename(String path) => path.split(Platform.pathSeparator).last;
String _dirname(String path) =>
    path.substring(0, path.length - _basename(path).length);

/// The barrel that should select [implPath] per platform: the sibling with the
/// `_io` / `_web` suffix stripped.
String _barrelFor(String implPath) =>
    '${_dirname(implPath)}${_basename(implPath).replaceFirst(_platformImplSuffix, '.dart')}';

/// The conditional directive a barrel must carry to select `<base>_io.dart`,
/// in either the `import` or the `export` spelling.
///
/// Both are in use and the difference is not stylistic: `document_view/` needs
/// an **import** because its redirecting factory wants the implementation's
/// name in scope, while a barrel over plain top-level declarations
/// (`document_cache.dart`, `external_browser.dart`) can re-**export** them.
RegExp _conditionalSelection(String base) {
  final io = RegExp.escape("'${base}_io.dart'");
  final web = RegExp.escape("'${base}_web.dart'");
  return RegExp(
    '(?:import|export)\\s+$io\\s*if\\s*\\(dart\\.library\\.js_interop\\)\\s*$web',
  );
}

/// An `import`/`export` directive naming [fileName], through any relative path.
///
/// Deliberately anchored to the directive keyword rather than matching the bare
/// quoted name: these files discuss each other by name in prose, and a guard
/// that fires on a doc comment is a guard people delete.
RegExp _directiveNaming(String fileName) {
  final name = RegExp.escape(fileName);
  return RegExp("(?:import|export)\\s+'[^']*$name'");
}

/// True when [path] is one half of a platform seam whose barrel really does
/// choose between an io and a web sibling.
///
/// Everything is re-derived from the files on disk, so the exemption this backs
/// cannot outlive the structure that justifies it: delete the barrel, or the
/// web half, and the io half goes back to being an unguarded `dart:io` import.
bool _isPlatformSelected(String path, Map<String, String> sources) {
  if (!_platformImplSuffix.hasMatch(path)) return false;
  final barrel = _barrelFor(path);
  final barrelSource = sources[barrel];
  if (barrelSource == null) return false;
  final base = _basename(barrel).replaceFirst('.dart', '');
  if (!sources.containsKey('${_dirname(path)}${base}_web.dart')) return false;
  return _conditionalSelection(base).hasMatch(barrelSource);
}

void main() {
  group('dart:io is not reachable from the web build', () {
    test('every lib/ file importing dart:io is guarded, split or declared pending', () {
      final sources = _libSources();
      final offenders = <String>[];

      for (final entry in sources.entries) {
        final path = entry.key;
        final source = entry.value;
        if (!_importsDartIo.hasMatch(source)) continue;

        if (_pendingWebPort.contains(path)) continue;
        // Guarded files must consult kIsWeb before they touch the stub.
        if (source.contains('kIsWeb')) continue;
        // An `_io.dart` implementation is *supposed* to be full of dart:io —
        // it is the half of a seam the web build never compiles. The exemption
        // is structural, not a name on a list: it holds only while a barrel
        // really does select between it and a web sibling, which the group
        // below verifies independently.
        if (_isPlatformSelected(path, sources)) continue;

        offenders.add(path);
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'These files import dart:io with no kIsWeb guard. On the web that '
            'compiles and then throws at runtime with no console output. Add a '
            'kIsWeb guard, move the call behind a conditional-import barrel, or '
            '— if the breakage is known and accepted for now — name the file in '
            '_pendingWebPort with a comment saying what breaks.',
      );
    });

    test('_pendingWebPort names only files that exist', () {
      // Keeps the to-do honest: a renamed or ported file must not leave a stale
      // exemption behind that would silently cover a future reach-through.
      // Vacuous while the set is empty, which is the goal state — it earns its
      // keep the moment someone adds a name back.
      for (final path in _pendingWebPort) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is listed in _pendingWebPort but does not exist. '
              'Remove the entry (or fix the path) — a stale exemption is a hole.',
        );
      }
    });
  });

  group('platform-split implementations are reached only through their barrel', () {
    // The seam pattern is what replaced both _pendingWebPort entries, so it now
    // carries the weight the list used to. Two ways it can rot, both silent:
    //
    //   - A `_io.dart` with no barrel selecting it. Then it is not a seam at
    //     all, just a file full of `dart:io` that the web build compiles and
    //     dies in — the exact hole the exemption above would be papering over.
    //   - A caller importing `foo_io.dart` (or `foo_web.dart`) directly instead
    //     of `foo.dart`. That pins one platform's implementation into every
    //     build, which is precisely what the conditional exists to prevent, and
    //     it still compiles on both targets.
    late Map<String, String> sources;
    late List<String> impls;

    setUpAll(() {
      sources = _libSources();
      impls = sources.keys.where((p) => _platformImplSuffix.hasMatch(p)).toList()
        ..sort();
    });

    test('there is at least one seam to check', () {
      // Guards the two tests below against passing because the discovery found
      // nothing — a renamed suffix convention would otherwise read as green.
      expect(impls, isNotEmpty);
    });

    test('each has a barrel that selects between an io and a web half', () {
      for (final impl in impls) {
        final barrel = _barrelFor(impl);
        final base = _basename(barrel).replaceFirst('.dart', '');

        expect(
          sources.containsKey(barrel),
          isTrue,
          reason:
              '$impl has no barrel at $barrel. A `_io`/`_web` file is only safe '
              'because something picks between the two per platform; on its own '
              'it is a dart:io reach-through (or a dart:ui_web one) that '
              'compiles for the wrong target.',
        );
        expect(
          sources.containsKey('${_dirname(impl)}${base}_io.dart'),
          isTrue,
          reason: '$barrel names ${base}_io.dart, which is missing.',
        );
        expect(
          sources.containsKey('${_dirname(impl)}${base}_web.dart'),
          isTrue,
          reason: '$barrel names ${base}_web.dart, which is missing. Half a '
              'seam is worse than none: the barrel resolves to the io file on '
              'both targets and the web build breaks at runtime.',
        );
        expect(
          _conditionalSelection(base).hasMatch(sources[barrel] ?? ''),
          isTrue,
          reason:
              '$barrel does not conditionally select ${base}_io.dart / '
              '${base}_web.dart on dart.library.js_interop. An unconditional '
              'import of the io half still COMPILES for the web and then throws '
              'in a browser, which Flutter paints as a bare grey rectangle with '
              'an empty console. js_interop rather than the older '
              'dart.library.html because it is true on both dart2js and '
              'dart2wasm.',
        );
      }
    });

    test('no other lib/ file imports one half directly', () {
      for (final impl in impls) {
        final name = _basename(impl);
        final barrel = _barrelFor(impl);
        final directive = _directiveNaming(name);

        for (final entry in sources.entries) {
          // The barrel is the one library allowed to name either half; an
          // implementation importing its own barrel back (for a shared type) is
          // the established shape and not what this is looking for.
          if (entry.key == impl || entry.key == barrel) continue;
          expect(
            directive.hasMatch(entry.value),
            isFalse,
            reason:
                '${entry.key} imports $name directly. Import '
                '${_basename(barrel)} instead — naming one half pins that '
                'platform into every build, and it compiles happily on the '
                'other one before failing at runtime.',
          );
        }
      }
    });
  });

  group('deepLinksSupported keeps its web guard', () {
    // The specific regression. This getter is the one `dart:io` reference that
    // runs during shell construction, so it is the one that turns the whole app
    // grey rather than degrading a single screen.
    late String source;

    /// Just the getter's own body.
    ///
    /// Scoping this to the declaration is load-bearing, and both of the obvious
    /// shortcuts are broken. Searching the whole FILE for `kIsWeb` always finds
    /// it — the import says `show kIsWeb` and the doc comment discusses it — so
    /// a file-wide `indexOf` reports a guard that is not there. Stripping
    /// comments is not enough either, because the import survives. Earlier
    /// revisions of this test made both mistakes and passed with the guard
    /// deleted.
    late String body;

    setUpAll(() {
      source = File('lib/providers/deep_link_provider.dart').readAsStringSync();
      final decl = RegExp(
        r'bool\s+get\s+deepLinksSupported\s*(\{.*?\}|=>[^;]*;)',
        dotAll: true,
      ).firstMatch(source);
      expect(
        decl,
        isNotNull,
        reason: 'could not find the deepLinksSupported declaration — if it was '
            'renamed or moved, retarget this test rather than deleting it.',
      );
      body = decl!.group(1)!;
    });

    test('consults kIsWeb before it touches Platform', () {
      final guard = body.indexOf('kIsWeb');
      final platform = body.indexOf('Platform.');

      expect(
        guard,
        isNot(-1),
        reason: 'deepLinksSupported must consult kIsWeb in its own body. '
            'Without it the web build evaluates a throwing dart:io stub during '
            'shell construction and the whole app paints a grey rectangle.',
      );
      expect(platform, isNot(-1), reason: 'expected the native branch to survive.');
      expect(
        guard,
        lessThan(platform),
        reason: 'kIsWeb must be checked BEFORE Platform is touched.',
      );
    });

    test('is a statement body, not an expression that evaluates Platform', () {
      // `bool get deepLinksSupported => ... Platform ...` — even with a kIsWeb
      // term — is the shape to keep out. The early return is what lets dart2js
      // drop the Platform reference as dead code on the web target.
      final arrowWithPlatform = RegExp(
        r'bool\s+get\s+deepLinksSupported\s*=>[^;]*Platform\.',
      );
      expect(
        arrowWithPlatform.hasMatch(source),
        isFalse,
        reason: 'deepLinksSupported must use a statement body with an early '
            '`if (kIsWeb) return false;` so the Platform reference is dropped '
            'from the web build rather than merely short-circuited at runtime.',
      );
    });
  });
}
