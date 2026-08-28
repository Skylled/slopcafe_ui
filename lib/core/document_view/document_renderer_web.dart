/// The browser implementation of the [DocumentRenderer] seam.
///
/// One `<iframe>` per renderer, fed by `srcdoc`, mounted into the Flutter tree
/// as a registered platform view. It is the same shape the backend uses to
/// serve its own bytes (`src/serve.ts`: a shell page wrapping the document in
/// `<iframe sandbox>`) and the same shape the MCP Apps viewer uses to nest a
/// document inside its host frame — three copies of one idea, because the idea
/// is the only thing standing between agent-authored HTML and this app.
///
/// ## Why `srcdoc` and not `<iframe src="…/d/:id/raw">`
///
/// Pointing the frame straight at the deployment would be less code and it
/// cannot work. Three independent reasons, any one of them fatal, so do not
/// "simplify" to it later:
///
///  1. `/d/:id/raw` is served under `frame-ancestors 'self'`. This app is a
///     different origin from the deployment, so the browser refuses the embed
///     outright — a blank frame with a console line, on the *happy* path.
///  2. A frame navigation carries no `Authorization` header. Every private
///     document and every operator-gated `/d/:id/v/:n/raw` read — which is
///     both panes of the Review screen — would come back 404.
///  3. It can only render what the server will send. The offline cache and the
///     app's themed error card ([DocumentRenderer.loadNotice]) are bytes the
///     app itself produced, and there is no URL for them.
///
/// So the app fetches the bytes with its own credentials (that part stays in
/// the screens, see the seam's library doc) and hands them here as a string.
///
/// ## The sandbox is the load-bearing part
///
/// The frame's attributes are exactly:
///
/// ```html
/// <iframe sandbox="allow-same-origin" referrerpolicy="no-referrer" allow="">
/// ```
///
/// plus [injectDocumentCsp]'s meta policy inside the document itself.
///
/// **No `allow-scripts` means the browser refuses to execute any script in
/// that frame at all** — not as a policy it evaluates per resource, but as a
/// property of the browsing context. That is a stronger guarantee than the
/// mobile side's `JavaScriptMode.disabled`, and it holds even if the CSP meta
/// were stripped and even if the backend sanitizer had let something through.
///
/// `allow-same-origin` on its own is **not** a weakening. A document that can
/// never run script cannot exercise an origin: there is nothing in it to read
/// cookies, open a same-origin window or issue a fetch. The escape everyone
/// remembers is `allow-scripts` **together with** `allow-same-origin`, which
/// lets the framed document reach `frameElement` and rewrite its own `sandbox`
/// attribute — script plus origin, not origin alone. We take the origin so
/// this side can reach into the child to intercept its links, and we never
/// take the script.
///
/// The one-line version, because it will be needed: **the first document that
/// renders oddly will make "just add `allow-scripts`" look like the fix.** It
/// is not; it is the whole wall. `test/document_renderer_test.dart` pins the
/// literal for exactly that moment.
///
/// ## A coupling that lives in another file
///
/// An `about:srcdoc` child **inherits the embedder's Content-Security-Policy**.
/// This app currently ships no CSP in `web/index.html`, so today the only
/// policy in force inside the frame is the one [injectDocumentCsp] writes. The
/// day someone adds a hardening header or meta there, it lands on every
/// rendered document too, and the failure is silent and total:
/// `style-src 'self'` strips *all* document styling (the sanitizer passes
/// inline CSS through on purpose), and `img-src 'self'` kills every `data:`
/// image. The same note is in `web/index.html`; keep the two together.
///
/// Trusted Types is the neighbouring trap: assigning a string to `srcdoc`
/// throws under `require-trusted-types-for 'script'`. Adding that header
/// without a policy here breaks rendering outright rather than quietly.
///
/// ## What has no analogue here
///
/// The macOS synthetic base-URL load (`document_renderer_io.dart`'s
/// `_expectSyntheticBaseLoad`) does not exist on the web. Assigning `srcdoc` is
/// not a navigation the embedder observes — there is no navigation delegate to
/// mistake our own content load for a link — so the flag, the bare-base-URL
/// predicate and the whole arm/consume dance are genuinely *absent*, not
/// dropped. Nothing here needs to distinguish a load we performed from a link
/// the reader tapped, because only one of the two ever reaches this code.
library;

import 'dart:js_interop';
// For `has`, which is a plain JS `in` test. Needed because the child document
// is a separate JS realm and `instanceof` does not cross one — see the comment
// in [DocumentRendererImpl._onChildClick].
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import 'document_renderer.dart';

/// The `sandbox` attribute every document frame is created with.
///
/// Pinned as a named constant so the security posture has one spelling, and so
/// `test/document_renderer_test.dart` can assert on it. See the library doc for
/// why `allow-same-origin` alone is not a weakening and why `allow-scripts`
/// must never join it.
const String kDocumentFrameSandbox = 'allow-same-origin';

/// The Permissions-Policy the frame is granted: none of it.
///
/// An empty `allow` denies every delegated feature (camera, microphone,
/// geolocation, clipboard, …). Those all require script to reach, and this
/// frame has none — but the attribute costs nothing and means a future change
/// to the sandbox does not silently hand a document a second capability.
const String kDocumentFrameAllow = '';

/// One platform-view type for the whole app.
///
/// **Not one per document, and this is the reason:**
/// `ui_web.platformViewRegistry` has a `registerViewFactory` and no matching
/// unregister. A view type registered once is registered for the life of the
/// page, along with the closure behind it. Minting a type per document would
/// leak one entry and one closure per document the operator opens — unbounded
/// growth over a long session, invisible to every tool we have.
///
/// So there is a single type and a single factory, and the per-document part
/// is a lookup key passed through [HtmlElementView.creationParams]. That entry
/// *is* removed, in [DocumentRendererImpl.dispose].
const String _kDocumentViewType = 'slopcafe-document-frame';

/// Live renderers, by the key their [HtmlElementView] passes to the factory.
///
/// The factory has to answer with an element it did not create, so it needs a
/// way back to the renderer that owns one. A map keyed by string is that way,
/// and the key is a string rather than the renderer itself because
/// `creationParams` is not handed to the factory directly: it round-trips
/// through `SystemChannels.platform_views` under the `StandardMethodCodec`,
/// which encodes nulls, booleans, numbers, strings, byte lists, lists and maps
/// — and nothing else. Passing `this` would throw inside the codec.
final Map<String, DocumentRendererImpl> _renderersByViewKey =
    <String, DocumentRendererImpl>{};

bool _viewFactoryRegistered = false;

/// Registers the one view factory, once.
///
/// `registerFactory` already returns `false` for a repeat rather than throwing,
/// so the guard is belt and braces; it is here to say out loud that this is
/// meant to happen exactly once, and never from inside a `build`.
void _ensureViewFactoryRegistered() {
  if (_viewFactoryRegistered) return;
  _viewFactoryRegistered = true;
  ui_web.platformViewRegistry.registerViewFactory(_kDocumentViewType, (
    int viewId, {
    Object? params,
  }) {
    final renderer = params is String ? _renderersByViewKey[params] : null;
    // A renderer disposed between build and platform-view creation (a route
    // popped mid-frame) leaves nothing to mount. Return an inert element
    // rather than throwing: a throw here escapes into the engine's platform
    // channel handler, which rejects the create and paints an error box over
    // a screen that is already on its way out.
    return renderer?.attachFrame() ?? _inertPlaceholder();
  });
}

/// An empty, correctly-sized element for the no-renderer case.
///
/// The engine warns on stdout when a platform view's content has no explicit
/// width/height, so set both even though this paints nothing.
web.HTMLDivElement _inertPlaceholder() => web.HTMLDivElement()
  ..style.width = '100%'
  ..style.height = '100%';

int _nextViewKey = 0;

/// The schemes a refused link is allowed to be reported as.
///
/// The frame cannot navigate anywhere regardless — but [DocumentLinkTap] is
/// not a dead end: the Reader hands an external URL to `url_launcher`. So the
/// filter is here, on our side of the callback, and it is an allowlist. The
/// backend sanitizer already strips scriptable schemes at write time; this is
/// the second wall, applied to bytes that may have come from a cache written
/// by an older sanitizer.
const Set<String> _kReportableSchemes = <String>{
  'http',
  'https',
  'mailto',
  'tel',
};

/// A document surface backed by a sandboxed `srcdoc` iframe.
///
/// The iframe is created in the **constructor**, before any widget exists, and
/// belongs to this object for its whole life. That is not incidental: it is
/// what makes the seam's ownership rule true on the web. The Review screen
/// keeps two of these alive and paints one, and it can only do that because
/// nothing about the surface is created in a `build`.
///
/// The corollary is that a renderer has exactly **one** surface: painting the
/// same renderer from two [DocumentSurface]s at once would ask the factory for
/// the same element twice, and the second mount would move the iframe out of
/// the first (and reload it). One renderer, one place on screen.
class DocumentRendererImpl implements DocumentRenderer {
  DocumentRendererImpl({required this.baseUrl, required this.onLinkTap})
    : _viewKey = 'slopcafe-doc-${_nextViewKey++}' {
    _ensureViewFactoryRegistered();

    _frame = web.HTMLIFrameElement()
      // The wall. See the library doc before touching any of these three.
      ..setAttribute('sandbox', kDocumentFrameSandbox)
      ..setAttribute('referrerpolicy', 'no-referrer')
      ..setAttribute('allow', kDocumentFrameAllow)
      // Fill the box Flutter gives us and scroll inside it. Deliberately
      // *not* the measure-the-content-and-grow machinery the MCP Apps
      // viewer runs: there the host owns layout and the app must report a
      // height, here the framework hands us a rect and the child document
      // scrolls within it like any other scrollable.
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = '0';

    // Wired through the `onload` *property*, never `addEventListener`. Every
    // assignment to `srcdoc` produces a fresh child document, so this fires
    // once per render; a property holds one handler by definition, so an
    // idempotent re-render cannot stack them or leave an older closure live.
    _frame.onload = _onFrameLoad.toJS;

    _renderersByViewKey[_viewKey] = this;
  }

  /// The configured deployment's origin.
  ///
  /// Not given to the browser — a `srcdoc` document has no base URL of ours to
  /// set, and [kDocumentCspMeta]'s `base-uri 'none'` stops the document
  /// choosing one for itself. It is used by *this* code, to resolve a relative
  /// `href` into the absolute URL the screen expects at [onLinkTap].
  final String baseUrl;

  /// Where a refused navigation goes.
  final DocumentLinkTap onLinkTap;

  /// This renderer's key in [_renderersByViewKey], and the `creationParams` its
  /// [HtmlElementView] carries.
  final String _viewKey;

  late final web.HTMLIFrameElement _frame;

  /// The document currently in the frame, kept so a re-mount can restore it.
  String? _html;

  /// One JS callable for the child-document click listener.
  ///
  /// `.toJS` wraps a Dart closure in a new JS function each time it is called,
  /// so the wrapper is made once and reused. The listener is added to each
  /// fresh child document; it never needs removing, because the document it is
  /// attached to is destroyed by the next load.
  late final JSFunction _clickListener = _onChildClick.toJS;

  bool _disposed = false;

  // ----------------------------------------------------------------
  // DocumentRenderer
  // ----------------------------------------------------------------

  @override
  Future<void> loadHtml(String html) async => _render(injectDocumentCsp(html));

  @override
  Future<void> loadNotice(String html) async {
    // No injected CSP — the app wrote this card and `default-src 'none'` would
    // strip its styling. The other half of the io contract, "and no base URL",
    // has no analogue here: `srcdoc` takes no base URL to withhold. Nothing is
    // lost by that, because the card contains no links; if one is ever added,
    // it will resolve against `baseUrl` like a document's would.
    _render(html);
  }

  @override
  Widget buildSurface(BuildContext context) => HtmlElementView(
    // Keyed on the renderer, not left to position. `HtmlElementView` creates
    // its platform view once and reads `creationParams` only then, so a screen
    // that swapped which renderer it paints at one position would keep showing
    // the first renderer's iframe forever. The key makes that a remount.
    key: ValueKey<String>(_viewKey),
    viewType: _kDocumentViewType,
    creationParams: _viewKey,
  );

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // The registry entry is the only per-document thing that outlives the
    // widget, so it is the only thing that can leak. Drop it first: a
    // platform-view create racing this now lands on the placeholder instead of
    // re-mounting a frame nobody owns.
    _renderersByViewKey.remove(_viewKey);
    _frame.onload = null;
    // Detaching discards the child browsing context and with it the document,
    // its listeners and its decoded images. The engine also removes its own
    // wrapper when the platform view goes; this covers the case where the
    // renderer was built and disposed without ever being painted.
    _frame.remove();
    _html = null;
  }

  // ----------------------------------------------------------------
  // Platform-view plumbing
  // ----------------------------------------------------------------

  /// Hands the frame to the view factory, re-asserting its content.
  ///
  /// Called once per mount, just before the engine appends the element. The
  /// re-assert is what makes a re-mount heal itself. The browser would very
  /// likely do it anyway — the `srcdoc` *attribute* survives detaching, and
  /// re-inserting an iframe reloads it from its attributes — but "very likely"
  /// is not a property to rest a blank screen on, and stating it here means a
  /// future change that clears the attribute on teardown does not silently
  /// turn every re-mount into an empty frame.
  ///
  /// Assigning `srcdoc` while detached is inert: an iframe outside a document
  /// has no browsing context, so nothing loads until the engine appends it.
  /// That is also why the constructor can set content before any widget exists.
  web.HTMLIFrameElement attachFrame() {
    final html = _html;
    if (html != null) _frame.srcdoc = html.toJS;
    return _frame;
  }

  void _render(String document) {
    if (_disposed) return;
    _html = document;
    _frame.srcdoc = document.toJS;
    // Both callers' futures therefore complete on HAND-OFF, not on the child's
    // `load` event, and that is load-bearing rather than lazy. The Reader
    // `await`s `loadHtml` *before* the build that first mounts the surface, so
    // at that moment the frame is still detached and no load can happen; a
    // future that waited for one would never complete and the Reader would sit
    // on its spinner forever. It also matches the io side, whose
    // `loadHtmlString` future resolves when the platform accepts the load, not
    // when anything is painted.
  }

  // ----------------------------------------------------------------
  // Link interception
  // ----------------------------------------------------------------

  /// Re-attaches the click listeners to the newly loaded child document.
  ///
  /// Both `click` and `auxclick`: a middle-click fires *only* the latter, and
  /// on a document whose links are all stamped `target="_blank"` a middle click
  /// is a completely ordinary thing for a reader to do.
  void _onFrameLoad(web.Event event) {
    if (_disposed) return;
    final document = _frame.contentDocument;
    // Null only if the frame is cross-origin or has no browsing context —
    // neither is reachable with `allow-same-origin` on an attached frame, but
    // the whole link path depends on this reach, so it fails quietly rather
    // than throwing into an event handler.
    if (document == null) return;
    document.addEventListener('click', _clickListener);
    document.addEventListener('auxclick', _clickListener);
  }

  /// Every link click in a rendered document ends here.
  ///
  /// **Interception is what makes links work at all**, which is worth stating
  /// because it looks like a restriction. The backend sanitizer stamps
  /// `target="_blank"` on external *and* on-platform (`/d/…`, `/s/…`) links,
  /// and this frame is granted no `allow-popups`, so an *un*-intercepted click
  /// silently does nothing: no navigation, no new tab, no error. Handing the
  /// URL to the screen is the only path a link has. Granting `allow-popups`
  /// would "fix" that by letting untrusted content open windows out of the app
  /// — never do that; the screen decides what a link means.
  void _onChildClick(web.Event event) {
    if (_disposed) return;

    // DUCK-TYPED ON PURPOSE. The obvious spelling, `isA<web.Element>()`, is
    // *wrong* here and fails silently — this file shipped with it until
    // `document_renderer_web_browser_test.dart` ran in a real browser. `isA`
    // compiles to `instanceof`, and every same-origin child document is its own
    // JavaScript realm with its own `Element` constructor, so an element from
    // the frame is not `instanceof` the app window's `Element`. The check
    // answers false for every click, interception stops happening entirely, and
    // nothing says so: no error, no console line, links simply go dead. `in`
    // walks the object's own prototype chain, so it is realm-agnostic.
    final target = event.target;
    if (target == null || !target.has('closest')) return;
    final anchor = (target as web.Element).closest('a[href]');
    if (anchor == null) return;

    // Unconditional, and before any decision about what the link *is*: every
    // path below either handles the click or drops it, and a dropped click
    // that kept its default action would navigate the frame out of the
    // document the reader is looking at.
    event.preventDefault();

    // The raw attribute, never `anchor.href`. A `srcdoc` document inherits its
    // base URL from the embedder, which here is the *app's* origin — so the
    // DOM's resolved `.href` would point somewhere in this Flutter app. The
    // deployment origin is [baseUrl], and resolving against it is ours to do.
    final href = anchor.getAttribute('href')?.trim() ?? '';
    if (href.isEmpty) return;

    if (href.startsWith('#')) {
      // A section jump is movement within the document on screen, not a link
      // out of it: scroll in place and tell the screen nothing. (Real fragment
      // navigation would not work anyway — the ids live in the child document,
      // which has no address of its own.)
      final id = href.substring(1);
      if (id.isEmpty) return;
      anchor.ownerDocument?.getElementById(id)?.scrollIntoView();
      return;
    }

    final absolute = _resolveAgainstBase(href);
    if (absolute == null) return;
    onLinkTap(absolute);
  }

  /// Resolves a document's `href` to the absolute URL the screen will see, or
  /// null if it is unparseable or not a scheme we are willing to report.
  String? _resolveAgainstBase(String href) {
    final base = Uri.tryParse(baseUrl);
    final reference = Uri.tryParse(href);
    if (base == null || reference == null || !base.hasScheme) return null;
    final Uri absolute;
    try {
      absolute = base.resolveUri(reference);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null;
    }
    if (!_kReportableSchemes.contains(absolute.scheme)) return null;
    return absolute.toString();
  }
}
