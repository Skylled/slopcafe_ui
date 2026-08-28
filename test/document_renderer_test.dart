// The document-rendering seam's security-bearing state, pinned: the
// Content-Security-Policy every document body is rendered under, and — on the
// web, where the browser enforces it for us — the `<iframe sandbox>` that keeps
// script out of a document frame entirely.
//
// `lib/core/document_view/document_renderer.dart` was extracted from the Reader
// and Review screens, which each carried their own copy of this policy and
// their own splice. The extraction is only worth anything if the surviving copy
// is the *same* copy — a refactor that quietly widened the policy would leave
// the app rendering untrusted agent HTML under a weaker rule with nothing on
// screen to say so. So the pre-extraction literal is pinned here verbatim.
//
// Hermetic: pure string work plus a handful of source reads, exactly like the
// Gradle↔Dart host invariant in deep_link_test.dart. Nothing constructs a
// renderer — that needs a platform WebView on io, and on the web it needs
// `dart:ui_web`, which does not exist on the VM this suite runs on. A test that
// imported `document_renderer_web.dart` would not fail an assertion, it would
// fail to *compile*; `flutter test --platform chrome` could run one, but a
// guard that only fires under a command nobody runs is worse than no guard on
// the thing it guards. So the web frame's posture is pinned the same way the
// CSP is: read the source, assert the literal.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/document_view/document_renderer.dart';

const _webRendererPath = 'lib/core/document_view/document_renderer_web.dart';
const _seamPath = 'lib/core/document_view/document_renderer.dart';

/// The source with whole-line comments removed.
///
/// Load-bearing for every negative assertion below, and for the reason
/// `platform_guard_test.dart` spells out at length: these files *discuss* the
/// dangerous tokens at length, because explaining why `allow-scripts` must
/// never appear is most of the point of the comment above it. A naive
/// `contains('allow-scripts')` over the raw source therefore always fires.
///
/// The rule this imposes on the source: **keep prose about a forbidden token on
/// its own comment line.** A trailing `// …allow-scripts…` after real code will
/// fail these tests. That direction of mistake is the safe one.
String _codeOnly(String source) => source
    .split('\n')
    .where((line) {
      final trimmed = line.trimLeft();
      return !(trimmed.startsWith('//') ||
          trimmed.startsWith('*') ||
          trimmed.startsWith('/*'));
    })
    .join('\n');

/// The literal of a `const String <name> = '…';` declaration, or null.
String? _constLiteral(String source, String name) =>
    RegExp("const String $name = '([^']*)';").firstMatch(source)?.group(1);

/// The exact `_injectCspMeta` literal both screens carried before the seam
/// existed. Written out longhand rather than referenced, so a change to the
/// constant has to be made twice — once in the source and once here, where the
/// second edit is a deliberate act.
const _preExtractionCsp =
    '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
    'img-src data:; style-src \'unsafe-inline\' data:; font-src data:; '
    'base-uri \'none\'; form-action \'none\'">';

void main() {
  group('the document CSP', () {
    test('is byte-identical to the policy the screens used before the seam', () {
      expect(kDocumentCspMeta, _preExtractionCsp);
    });

    test('nothing loads, executes or navigates away', () {
      // Spelled out as separate expectations so a failure names which
      // protection went missing rather than just "the string changed".
      expect(kDocumentCspMeta, contains("default-src 'none'"));
      expect(kDocumentCspMeta, contains("base-uri 'none'"));
      expect(kDocumentCspMeta, contains("form-action 'none'"));
      // Remote fetches are refused; inlined assets survive.
      expect(kDocumentCspMeta, contains('img-src data:'));
      expect(kDocumentCspMeta, contains('font-src data:'));
      // The sanitizer deliberately passes inline CSS through, so style-src is
      // the one relaxation — and it is still limited to inline and data:.
      expect(kDocumentCspMeta, contains("style-src 'unsafe-inline' data:"));
      expect(kDocumentCspMeta, isNot(contains('script-src')));
    });
  });

  group('injectDocumentCsp', () {
    test('splices into the first head so the policy precedes the document', () {
      const html = '<html><head><title>t</title></head><body>b</body></html>';
      expect(
        injectDocumentCsp(html),
        '<html><head>\n$kDocumentCspMeta<title>t</title></head><body>b</body></html>',
      );
    });

    test('prepends when the fragment has no head', () {
      const html = '<p>a fragment</p>';
      expect(injectDocumentCsp(html), '$kDocumentCspMeta\n$html');
    });

    test('touches only the first head', () {
      // A document body that mentions `<head>` again — in escaped prose, say —
      // must not collect a second policy.
      const html = '<head>a</head><body>&lt;head&gt; and <head>b</head></body>';
      expect(
        kDocumentCspMeta.allMatches(injectDocumentCsp(html)).length,
        1,
      );
    });
  });

  group('the screens no longer carry their own copy', () {
    // The whole point of the extraction. A future edit that re-inlines a policy
    // into one screen would leave the two rendering surfaces under different
    // rules, which is precisely the drift the seam removed — and it would be
    // invisible, because both screens would still render.
    for (final path in const [
      'lib/screens/reader_screen.dart',
      'lib/screens/review_screen.dart',
    ]) {
      test('$path defers to the seam', () {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('Content-Security-Policy'),
          isFalse,
          reason:
              '$path declares a CSP of its own again. The policy belongs to '
              'lib/core/document_view/document_renderer.dart so every platform '
              'implementation renders untrusted HTML under the same rule.',
        );
      });
    }
  });

  group('the web renderer keeps script out of the document frame', () {
    // THE most important guard in the web port. On the web the app does not
    // ask the frame not to run script (the io side's `JavaScriptMode.disabled`)
    // — it withholds the capability: an iframe sandboxed without
    // `allow-scripts` has no script execution at all, whatever the document
    // contains and whatever any CSP says. That is a stronger property than the
    // mobile one, and it rests entirely on one attribute string.
    //
    // It is also the property most likely to be traded away by accident. The
    // first document that renders oddly in a browser will make granting script
    // look like the obvious fix, and the change is one word long, invisible in
    // review, and produces no error when it lands.
    late String source;
    late String code;

    setUpAll(() {
      source = File(_webRendererPath).readAsStringSync();
      code = _codeOnly(source);
    });

    test('the sandbox is exactly allow-same-origin', () {
      expect(
        _constLiteral(source, 'kDocumentFrameSandbox'),
        'allow-same-origin',
        reason:
            'The document frame\'s sandbox changed. `allow-same-origin` alone '
            'is not a weakening — a document that can never run script cannot '
            'exercise an origin, and this side needs the origin to reach into '
            'the child and intercept its links. The escape is allow-scripts '
            'TOGETHER with allow-same-origin, which lets a framed document '
            'rewrite its own sandbox attribute. If this assertion is failing '
            'because a document did not render, the fix is in the document or '
            'in the injected CSP, not here.',
      );
    });

    test('the pinned sandbox is the one actually applied to the frame', () {
      // A constant nothing reads is a comment. Assert the wiring too, so the
      // pin above cannot be satisfied by a declaration the frame ignores.
      expect(
        code,
        contains("setAttribute('sandbox', kDocumentFrameSandbox)"),
        reason:
            'The frame no longer takes its sandbox from kDocumentFrameSandbox, '
            'so pinning that constant proves nothing about what the browser '
            'is actually told.',
      );
    });

    test('no sandbox capability is granted beyond same-origin', () {
      // Belt and braces around the pin: a second `setAttribute`, a `sandbox.add`
      // or a rebuilt literal elsewhere in the file would all sail past an
      // equality check on the constant.
      for (final token in const [
        'allow-scripts',
        'allow-popups',
        'allow-popups-to-escape-sandbox',
        'allow-top-navigation',
        'allow-top-navigation-by-user-activation',
        'allow-forms',
        'allow-modals',
        'allow-downloads',
        'allow-pointer-lock',
        'allow-presentation',
      ]) {
        expect(
          code,
          isNot(contains(token)),
          reason:
              '`$token` appears in the executable part of $_webRendererPath. '
              'The document frame is granted exactly one capability. If this '
              'is prose explaining why the token is forbidden, put it on its '
              'own comment line — this test strips whole-line comments and '
              'nothing else.',
        );
      }
      // `allow-popups` specifically: the backend sanitizer stamps
      // target="_blank" on external AND on-platform links, so an un-intercepted
      // click in this frame silently dead-ends. Granting popups is the obvious
      // fix and the wrong one — link interception is what makes links work, and
      // it hands the URL to the screen instead of to the document.
    });

    test('the frame leaks no referrer and is delegated no browser feature', () {
      expect(
        code,
        contains("setAttribute('referrerpolicy', 'no-referrer')"),
        reason:
            'A rendered document must not tell anything it touches where it '
            'was rendered from.',
      );
      expect(
        _constLiteral(source, 'kDocumentFrameAllow'),
        '',
        reason:
            'An empty `allow` denies every Permissions-Policy feature. Naming '
            'one here would hand a capability to untrusted content.',
      );
      expect(code, contains("setAttribute('allow', kDocumentFrameAllow)"));
    });

    test('document bytes go through the seam\'s shared CSP injection', () {
      expect(
        code,
        isNot(contains('Content-Security-Policy')),
        reason:
            '$_webRendererPath declares a policy of its own. The CSP belongs '
            'to document_renderer.dart so both platforms render untrusted HTML '
            'under the same rule.',
      );
      expect(
        'injectDocumentCsp('.allMatches(code).length,
        1,
        reason:
            'Expected exactly one call to injectDocumentCsp: loadHtml applies '
            'it to untrusted document bytes, and loadNotice deliberately does '
            'not (a default-src \'none\' policy would strip the app\'s own '
            'error card of its styling). Zero calls means documents render '
            'unprotected on the web while io protects them; two means the '
            'notice card is broken.',
      );
    });
  });

  group('the seam picks its implementation per platform', () {
    // Reverting to an unconditional io import fails *quietly* on the web:
    // `webview_flutter`'s Dart compiles for dart2js just fine, and then throws
    // at controller construction in a browser — which Flutter catches during
    // build and paints as a bare grey rectangle with an empty console. Exactly
    // the failure mode platform_guard_test.dart exists for, one layer down.
    late String source;

    setUpAll(() => source = File(_seamPath).readAsStringSync());

    test('the io implementation is the default', () {
      expect(source, contains("import 'document_renderer_io.dart'"));
    });

    test('the web implementation is selected by dart.library.js_interop', () {
      expect(
        source,
        contains("if (dart.library.js_interop) 'document_renderer_web.dart'"),
        reason:
            'The conditional import is gone, so a browser build resolves the '
            'webview_flutter implementation, compiles cleanly and paints grey. '
            'js_interop rather than the older dart.library.html because it is '
            'true on both web compilers, dart2js and dart2wasm.',
      );
    });

    test('both implementations exist', () {
      for (final path in const [
        'lib/core/document_view/document_renderer_io.dart',
        _webRendererPath,
      ]) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: '$path is named by the conditional import but is missing.',
        );
      }
    });
  });
}
