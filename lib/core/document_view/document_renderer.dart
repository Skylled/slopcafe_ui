/// The platform seam for painting a document's HTML.
///
/// Two screens render agent-authored bytes — the Reader ("the plate") and the
/// two-pane Review surface — and until this file existed both of them reached
/// straight for `webview_flutter`. That is the single hardest dependency in the
/// app to carry to the web target: `webview_flutter` has no web implementation
/// at all, so a browser build cannot even construct the thing those screens are
/// built around. This library is the line those screens now talk to instead. An
/// io implementation ([DocumentRendererImpl] in `document_renderer_io.dart`)
/// keeps today's WKWebView/Android WebView behaviour byte for byte; a web
/// implementation lands beside it later and swaps in through the conditional
/// import below, with no edit to either screen.
///
/// ## The split this interface exists to preserve
///
/// The Review screen holds **two live renderers and paints one of them**,
/// flipping which is on screen rather than driving a single surface back and
/// forth (see the class doc on `ReviewScreen`). That only works because of one
/// property, and it is the property this interface is shaped around:
///
/// > **The renderer owns the platform surface; the widget only paints it.**
///
/// A [DocumentRenderer] is a plain object with a lifetime the screen controls —
/// it is created once, loaded into, and disposed. [DocumentSurface] is a
/// throwaway widget that displays whichever renderer it is handed and holds no
/// state of its own. So an `IndexedStack` can stop painting a pane without the
/// pane's surface being torn down: it stays loaded, stays warm, and — the
/// point of the whole screen — stays scrolled where the operator left it.
///
/// Any implementation that inverts this (a stateful widget that owns the
/// surface and rebuilds it from props) regresses the Review screen into the
/// shared-surface tab switcher it deliberately is not. On web that means the
/// `<iframe>`, or the platform-view registration behind it, must belong to the
/// renderer and survive being unpainted — not be created in `build`.
///
/// ## What every implementation owes
///
/// * **JavaScript must not run.** Document bytes are untrusted content authored
///   by agents. The backend sanitizes them and serves them behind its own
///   sandbox + CSP, and this app renders them behind a second copy of that
///   posture rather than trusting the first.
/// * **[injectDocumentCsp] must be applied to every document body**, which is
///   why it lives *here* rather than in either implementation: it is the one
///   part of the contract that must not diverge between platforms. If the io
///   surface renders under a strict CSP and the web surface does not, the app
///   has two security models and nobody notices until it matters.
/// * **A refused navigation must be reported, never silently dropped.** The
///   screens decide what a link means — the Reader resolves an on-platform one
///   into a new Reader route and confirms an external one; the Review panes
///   refuse everything with a toast — and they can only do that if the surface
///   hands the URL back through [DocumentLinkTap].
///
/// ## What this interface deliberately does NOT carry
///
/// * **A scroll offset.** Nothing in the app reads or restores one. Scroll
///   survives a pane flip because the surface is never torn down, not because
///   anyone saves a number — and `webview_flutter` can only report scroll
///   asynchronously (`getScrollPosition()`), so a synchronous getter here could
///   only ever answer null on io. A getter that is structurally a lie would
///   invite the web implementation to hand-roll scroll restoration the io side
///   never needed. If a real caller ever appears, add
///   `Future<Offset> get scrollPosition` and implement it on both sides.
/// * **A base URL setter.** Both screens resolve the configured deployment once
///   and never change it while the screen is alive, so the renderer takes it at
///   construction and treats it as immutable.
/// * **Anything about *fetching* bytes.** The version-first cache, the
///   conditional `If-None-Match` GET, the 304 path and the served-version
///   reconciliation all stay in the screens. This seam paints HTML it is
///   handed; it never asks for any.
library;

import 'package:flutter/widgets.dart';

// The seam's one platform-specific edge. It is an `import` rather than the
// `export` an outside reader might expect, because the redirecting factory on
// [DocumentRenderer] needs `DocumentRendererImpl` resolvable in *this* library's
// scope, and an `export` directive does not put a name in scope.
//
// The condition is `dart.library.js_interop` rather than the older
// `dart.library.html`: it is true on both web compilers (dart2js and dart2wasm)
// and false everywhere else, which is exactly the split we want.
//
// This line is load-bearing in a way that fails *quietly* if it is reverted.
// Importing the io file unconditionally still compiles for the web —
// `webview_flutter`'s Dart resolves fine — and then throws at controller
// construction in the browser, which Flutter catches during build and paints as
// a bare grey rectangle. `test/document_renderer_test.dart` pins the
// conditional for that reason.
import 'document_renderer_io.dart'
    if (dart.library.js_interop) 'document_renderer_web.dart';

/// A navigation the surface refused, handed back to the screen as the absolute
/// URL the document asked for.
///
/// "Refused" is the whole vocabulary here: the surface has already allowed
/// everything it handles natively (its own content load, an in-page `#fragment`
/// jump), so anything reaching this callback is a real outbound link the screen
/// must decide about. The renderer takes no position on what that decision is.
typedef DocumentLinkTap = void Function(String absoluteUrl);

/// A live document surface: one platform view, owned by whoever constructed it.
///
/// Create one per pane, load into it, dispose it when the screen goes away.
/// Paint it with [DocumentSurface] — see the library doc for why the ownership
/// runs this way round.
abstract class DocumentRenderer {
  /// Builds the implementation for this platform.
  ///
  /// [baseUrl] is the configured deployment's origin. Document bytes are loaded
  /// *against* it so that relative links in a document resolve to the
  /// deployment rather than to nothing, which is also what makes an on-platform
  /// link arrive at [onLinkTap] as an absolute URL the screen can match on host.
  factory DocumentRenderer({
    required String baseUrl,
    required DocumentLinkTap onLinkTap,
  }) = DocumentRendererImpl;

  /// Render untrusted document bytes.
  ///
  /// Applies [injectDocumentCsp] internally — callers hand over the server's
  /// HTML exactly as it arrived and must not pre-secure it, or the document
  /// ends up carrying two policies.
  Future<void> loadHtml(String html);

  /// Render app-authored HTML into the same surface (today: the themed error
  /// card both screens build when a body cannot be fetched).
  ///
  /// Distinct from [loadHtml] on two counts, both load-bearing. It carries **no
  /// injected CSP**, because the app wrote it and a `default-src 'none'` policy
  /// would strip the card's own styling; and it loads with **no base URL**,
  /// because it is not a document at that address — it is chrome that happens
  /// to be drawn in HTML so the platform view never has to be swapped out for a
  /// Flutter widget mid-load.
  Future<void> loadNotice(String html);

  /// Paint the platform surface this renderer owns.
  ///
  /// Call sites use [DocumentSurface] instead of calling this directly; it is
  /// on the interface only because the renderer is the thing that knows what
  /// its surface is.
  Widget buildSurface(BuildContext context);

  /// Release the platform surface.
  ///
  /// A no-op on io — `webview_flutter` exposes no controller disposal, and the
  /// platform view goes away when its widget leaves the tree — but the screens
  /// call it anyway, because a web implementation that registers a view factory
  /// or attaches an `<iframe>` has something real to clean up and must not have
  /// to add the call sites itself.
  void dispose();
}

/// The Content-Security-Policy every document body is rendered under.
///
/// The same posture the backend serves its own `/d/:id/raw` bytes with: nothing
/// loads, nothing executes, nothing navigates the frame away. `img-src`/
/// `font-src` are limited to `data:` (inlined assets survive, remote fetches do
/// not), `style-src` allows the inline CSS the sanitizer deliberately passes
/// through, and `base-uri`/`form-action` are shut so a document cannot rewrite
/// where its own relative URLs point or post anywhere.
const String kDocumentCspMeta =
    '<meta http-equiv="Content-Security-Policy" content="default-src \'none\'; '
    'img-src data:; style-src \'unsafe-inline\' data:; font-src data:; '
    'base-uri \'none\'; form-action \'none\'">';

/// Splices [kDocumentCspMeta] into a document body.
///
/// Prefers the first `<head>` so the policy is in force before anything in the
/// document is parsed; a fragment with no head gets the meta prepended, which
/// the HTML parser hoists into the head it synthesises. Shared by every
/// platform implementation on purpose — see the library doc.
String injectDocumentCsp(String html) {
  if (html.contains('<head>')) {
    return html.replaceFirst('<head>', '<head>\n$kDocumentCspMeta');
  }
  return '$kDocumentCspMeta\n$html';
}

/// Paints a [DocumentRenderer]'s surface.
///
/// Stateless and disposable by design: it holds no part of the surface, so it
/// can be rebuilt, moved or (as in the Review screen's `IndexedStack`) left
/// unpainted without the renderer behind it noticing.
class DocumentSurface extends StatelessWidget {
  const DocumentSurface({super.key, required this.renderer});

  final DocumentRenderer renderer;

  @override
  Widget build(BuildContext context) => renderer.buildSurface(context);
}
