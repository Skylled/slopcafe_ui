// The web document renderer, exercised against a real browser.
//
//     flutter test --platform chrome test/document_renderer_web_browser_test.dart
//
// `flutter test` on its own SKIPS this file — `@TestOn('browser')` keeps it out
// of the VM suite, which cannot even compile it (`dart:ui_web` and
// `package:web` do not exist there). That is stated up front because a test
// nobody runs is worse than no test: the always-on guard on this file's
// security posture is the source pin in `document_renderer_test.dart`, which
// runs in the ordinary suite. THIS file is the behavioural proof — the only
// place anything actually renders a document, clicks a link in one, or checks
// that a `<script>` stayed dead.
//
// It earns its keep. The first version of the renderer used
// `target.isA<web.Element>()` to find the clicked node, which is correct-looking
// Dart and completely broken here: `isA` compiles to `instanceof`, every
// same-origin child document is its own JavaScript realm with its own `Element`
// constructor, and so the check answered false for every click in a document.
// Link interception simply did not happen — no error, no console line, links
// just inert. Nothing but a browser was ever going to catch that.
//
// The renderer is driven directly rather than through a widget: mounting a real
// `HtmlElementView` needs the Flutter web engine's platform-view pipeline, and
// what is under test is the iframe and its listeners, not the engine. The two
// calls the engine would make — `attachFrame()` from the view factory, then
// appending the returned element — are made by hand, in that order, which also
// exercises the load-before-mount path the Reader actually takes.

@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/document_view/document_renderer_web.dart';
import 'package:web/web.dart' as web;

const _base = 'https://slopcafe.com';

Future<void> _tick([int ms = 40]) =>
    Future<void>.delayed(Duration(milliseconds: ms));

/// Mounts a renderer exactly as the platform-view factory does — ask for the
/// frame, then append it — and waits for the child document to be readable.
///
/// Callers load *before* mounting, which is the real sequence: the Reader
/// resolves its base URL, builds a renderer, loads bytes into it and only then
/// runs the build that first paints the surface.
Future<web.Document> _mount(DocumentRendererImpl renderer) async {
  web.document.body!.append(renderer.attachFrame());
  return _awaitBody(renderer);
}

Future<web.Document> _awaitBody(
  DocumentRendererImpl renderer, {
  String? containing,
}) async {
  final frame = renderer.attachFrame();
  for (var attempt = 0; attempt < 75; attempt++) {
    await _tick();
    final document = frame.contentDocument;
    final text = document?.body?.textContent ?? '';
    if (document != null &&
        text.isNotEmpty &&
        (containing == null || text.contains(containing))) {
      return document;
    }
  }
  fail(
    containing == null
        ? 'the child document never became readable'
        : 'the child document never showed "$containing"',
  );
}

/// Dispatches a bubbling, cancellable mouse event and asserts the renderer
/// cancelled it. Every link click must be cancelled: an uncancelled one either
/// navigates the frame away from the document on screen or dead-ends silently
/// against the missing `allow-popups`.
void _clickLink(web.Document document, String id, {String type = 'click'}) {
  final event = web.MouseEvent(
    type,
    web.MouseEventInit(bubbles: true, cancelable: true),
  );
  document.getElementById(id)!.dispatchEvent(event);
  expect(
    event.defaultPrevented,
    isTrue,
    reason: '$type on #$id was not preventDefault()ed',
  );
}

void main() {
  test('the frame is created with exactly the pinned attributes', () {
    final renderer = DocumentRendererImpl(baseUrl: _base, onLinkTap: (_) {});
    final frame = renderer.attachFrame();

    expect(frame.tagName.toLowerCase(), 'iframe');
    expect(frame.getAttribute('sandbox'), kDocumentFrameSandbox);
    expect(frame.getAttribute('sandbox'), 'allow-same-origin');
    expect(frame.getAttribute('referrerpolicy'), 'no-referrer');
    expect(frame.getAttribute('allow'), '');

    renderer.dispose();
  });

  test('a document renders, and its script does not run', () async {
    final renderer = DocumentRendererImpl(baseUrl: _base, onLinkTap: (_) {});
    // Loaded while still detached — nothing happens until the mount, which is
    // the property that lets the renderer own its surface before a widget does.
    await renderer.loadHtml(
      '<html><head><title>t</title></head><body>'
      '<h1>Hello</h1>'
      '<script>window.parent.__scriptRan = true;</script>'
      '<img src="x" onerror="window.parent.__handlerRan = true;">'
      '</body></html>',
    );
    final document = await _mount(renderer);

    expect(document.body!.textContent, contains('Hello'));
    expect(
      document.documentElement!.innerHTML.toString(),
      contains('Content-Security-Policy'),
      reason: 'the seam\'s CSP meta did not reach the rendered document',
    );

    // The whole wall, observed rather than argued. Neither a `<script>` block
    // nor an `on*=` handler can run in a frame sandboxed without
    // `allow-scripts`, whatever the sanitizer let through.
    await _tick(250);
    expect(
      globalContext.has('__scriptRan'),
      isFalse,
      reason: 'an inline <script> executed inside the document frame',
    );
    expect(
      globalContext.has('__handlerRan'),
      isFalse,
      reason: 'an inline event handler executed inside the document frame',
    );

    renderer.dispose();
  });

  test('a document keeps its own styling', () async {
    // The other half of the CSP story, and the reason `web/index.html` carries
    // a warning: documents style themselves, the sanitizer passes that through
    // deliberately, and the injected policy allows inline CSS on purpose. A
    // policy that stripped it would leave every document rendering as plain
    // text with nothing to say why.
    final renderer = DocumentRendererImpl(baseUrl: _base, onLinkTap: (_) {});
    await renderer.loadHtml(
      '<html><head><style>body { background-color: rgb(1, 2, 3); }</style>'
      '</head><body>styled</body></html>',
    );
    final document = await _mount(renderer);
    final childWindow = renderer.attachFrame().contentWindow!;

    expect(
      childWindow.getComputedStyle(document.body!).backgroundColor,
      'rgb(1, 2, 3)',
    );

    renderer.dispose();
  });

  test('links are intercepted, resolved, filtered and reported', () async {
    final tapped = <String>[];
    final renderer = DocumentRendererImpl(
      baseUrl: _base,
      onLinkTap: tapped.add,
    );
    await renderer.loadHtml(
      '<html><body>'
      // target="_blank" is what the backend sanitizer stamps on external and
      // on-platform links alike. Without interception these dead-end against
      // the missing `allow-popups`, which is why interception is what makes
      // links work rather than what stops them.
      '<a id="onPlatform" href="/d/abc" target="_blank">a</a>'
      '<a id="external" href="https://example.com/x" target="_blank">b</a>'
      '<a id="mail" href="mailto:someone@example.com">c</a>'
      '<a id="scripted" href="javascript:alert(1)">d</a>'
      '<a id="nested" href="/s/a-slug"><strong><em id="deep">e</em></strong></a>'
      '</body></html>',
    );
    final document = await _mount(renderer);

    _clickLink(document, 'onPlatform');
    _clickLink(document, 'external');
    _clickLink(document, 'mail');
    // Clicking the innermost node still finds the anchor above it.
    _clickLink(document, 'deep');
    expect(tapped, <String>[
      // Resolved against the deployment origin, NOT against this app's origin —
      // a srcdoc document inherits the embedder's base URL, so the DOM's own
      // resolution would point back into the Flutter app.
      '$_base/d/abc',
      'https://example.com/x',
      'mailto:someone@example.com',
      '$_base/s/a-slug',
    ]);

    // Dropped, not reported: onLinkTap is not a dead end (the Reader hands an
    // external URL to url_launcher), so the scheme allowlist has to be on this
    // side of the callback.
    tapped.clear();
    _clickLink(document, 'scripted');
    expect(tapped, isEmpty);

    // A middle click fires only auxclick, and is just as much a link tap.
    _clickLink(document, 'external', type: 'auxclick');
    expect(tapped, <String>['https://example.com/x']);

    renderer.dispose();
  });

  test('a #fragment scrolls in place and is not reported as a link', () async {
    final tapped = <String>[];
    final renderer = DocumentRendererImpl(
      baseUrl: _base,
      onLinkTap: tapped.add,
    );
    await renderer.loadHtml(
      '<html><body style="margin:0">'
      '<a id="jump" href="#far">jump</a>'
      '<div style="height: 4000px"></div>'
      '<h2 id="far">far</h2>'
      '</body></html>',
    );
    final document = await _mount(renderer);

    _clickLink(document, 'jump');
    await _tick(150);

    expect(tapped, isEmpty, reason: 'a section jump is not a navigation');
    expect(
      document.documentElement!.scrollTop + (document.body?.scrollTop ?? 0),
      greaterThan(0),
      reason: 'the fragment did not scroll the child document',
    );

    renderer.dispose();
  });

  test('the error card renders without the document CSP', () async {
    final renderer = DocumentRendererImpl(baseUrl: _base, onLinkTap: (_) {});
    await renderer.loadNotice(
      '<html><body><p>could not load</p></body></html>',
    );
    final document = await _mount(renderer);

    expect(document.body!.textContent, contains('could not load'));
    expect(
      document.documentElement!.innerHTML.toString(),
      isNot(contains('Content-Security-Policy')),
      reason:
          'app-authored chrome must not get the document policy — '
          "default-src 'none' would strip the card of its own styling",
    );

    renderer.dispose();
  });

  test('a re-mount restores the document that was in the frame', () async {
    // What happens when the framework tears a platform view down and builds it
    // again: the engine removes its wrapper (detaching the iframe, which
    // discards the child document) and later calls the factory again. The
    // renderer has to come back with its content, not an empty frame.
    final renderer = DocumentRendererImpl(baseUrl: _base, onLinkTap: (_) {});
    await renderer.loadHtml('<html><body><p>still here</p></body></html>');
    await _mount(renderer);

    renderer.attachFrame().remove();
    await _tick(60);
    web.document.body!.append(renderer.attachFrame());

    final document = await _awaitBody(renderer, containing: 'still here');
    expect(document.body!.textContent, contains('still here'));

    renderer.dispose();
  });

  test('a disposed renderer stops rendering and detaches its frame', () async {
    final renderer = DocumentRendererImpl(baseUrl: _base, onLinkTap: (_) {});
    await renderer.loadHtml('<html><body><p>before</p></body></html>');
    final frame = renderer.attachFrame();
    await _mount(renderer);

    renderer.dispose();
    expect(frame.isConnected, isFalse);

    // Idempotent, and inert afterwards.
    renderer.dispose();
    await renderer.loadHtml('<html><body><p>after</p></body></html>');
    expect(frame.getAttribute('srcdoc'), isNot(contains('after')));
  });
}
