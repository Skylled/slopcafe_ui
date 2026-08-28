/// The `webview_flutter` implementation of the [DocumentRenderer] seam — macOS,
/// iOS and Android.
///
/// Everything here was lifted out of `reader_screen.dart` and
/// `review_screen.dart`, where it existed **twice**, copy-pasted: the CSP
/// injection, the bare-base-URL predicate, the same-document-fragment
/// predicate, the macOS synthetic-base-load flag, the navigation delegate and
/// its `about:blank` / `data:` allowances. Two copies of a security posture is
/// one copy too many — the pair had already begun to drift in wording, and the
/// next drift would have been in behaviour. This is a move, not a rewrite: the
/// logic below is the logic those two screens ran, in the same order, with the
/// same outcomes.
///
/// Nothing in this file imports `dart:io`. It is web-*unsafe* for a different
/// reason — `webview_flutter` simply has no web implementation — which is
/// exactly why the seam exists.
library;

import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'document_renderer.dart';

/// One `WebViewController` and the navigation policy around it.
///
/// The controller — not this object and not the widget painting it — owns the
/// underlying platform WebView, which is what lets the Review screen keep two
/// of these alive and paint one. See the seam's library doc.
class DocumentRendererImpl implements DocumentRenderer {
  DocumentRendererImpl({required this.baseUrl, required this.onLinkTap}) {
    _controller = WebViewController()
      // Document HTML is untrusted content authored by agents. No JavaScript,
      // plus the injected CSP on every body — the same posture the backend
      // serves its own `/d/:id/raw` bytes under, applied a second time on this
      // side rather than trusting the first.
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(onNavigationRequest: _decideNavigation),
      );
  }

  /// The configured deployment's origin. Document bodies load against it, and
  /// both navigation predicates below are relative to it.
  final String baseUrl;

  /// Where a refused navigation goes. Never called for a load this renderer
  /// performed itself, nor for an in-page anchor.
  final DocumentLinkTap onLinkTap;

  late final WebViewController _controller;

  /// Armed around each programmatic `loadHtmlString(..., baseUrl: baseUrl)`.
  ///
  /// On macOS, WKWebView reports that synthetic load to the navigation delegate
  /// as a request for the bare base URL. It must be allowed through, or the
  /// surface intercepts its *own* content load — the WebView stays blank and
  /// the screen shows an "open in browser?" prompt for a document it was in the
  /// middle of rendering. On macOS the synthetic navigation consumes the flag
  /// immediately, so a real link tap never runs with it set.
  ///
  /// iOS and Android never fire the delegate for `loadHtmlString` at all, so
  /// there the flag simply stays armed until the next load. That is harmless
  /// because it is only half the condition: the other half is
  /// [_isBareBaseUrl], and the base URL is not a document address, so an armed
  /// flag can never excuse a link the screen should have been asked about.
  ///
  /// **One flag per renderer, and that matters.** The Review screen builds a
  /// renderer per pane and loads both concurrently; a single shared flag would
  /// let whichever load finished first disarm the other's, leaving the second
  /// pane to intercept its own content. Under the old design that property was
  /// maintained by hand (a field on each `_Pane`); now it falls out of the
  /// object graph.
  bool _expectSyntheticBaseLoad = false;

  @override
  Future<void> loadHtml(String html) {
    _expectSyntheticBaseLoad = true;
    return _controller.loadHtmlString(injectDocumentCsp(html), baseUrl: baseUrl);
  }

  @override
  Future<void> loadNotice(String html) {
    // No CSP and no base URL — see [DocumentRenderer.loadNotice]. With no base
    // URL WKWebView reports the load as `about:blank`, which the delegate
    // allows outright, so the synthetic-base-load flag is deliberately left
    // untouched here.
    return _controller.loadHtmlString(html);
  }

  @override
  Widget buildSurface(BuildContext context) =>
      WebViewWidget(controller: _controller);

  @override
  void dispose() {
    // Nothing to do. `webview_flutter` exposes no disposal on the controller;
    // the platform view is torn down when the `WebViewWidget` painting it
    // leaves the tree. Declared and called anyway so the web implementation —
    // which will have a registered view factory and a detached element to clean
    // up — inherits working call sites instead of having to add them.
  }

  // ----------------------------------------------------------------
  // Navigation policy
  // ----------------------------------------------------------------

  /// The order of these checks is the order the two screens ran them in, and it
  /// is not arbitrary: each clause is narrower than "an outbound link", so
  /// every one of them has to get its answer in before the catch-all hands the
  /// URL to the screen.
  NavigationDecision _decideNavigation(NavigationRequest request) {
    final url = request.url;

    // Our own bodyless loads (the error card) and any inlined asset.
    if (url == 'about:blank' || url.startsWith('data:')) {
      return NavigationDecision.navigate;
    }

    // The synthetic base-URL navigation of our own loadHtmlString on macOS
    // WKWebView — see [_expectSyntheticBaseLoad].
    if (_expectSyntheticBaseLoad && _isBareBaseUrl(url)) {
      _expectSyntheticBaseLoad = false;
      return NavigationDecision.navigate;
    }

    // In-page anchor (#fragment) → let the WebView scroll natively. A section
    // jump is movement within the document on screen, not a link out of it.
    if (_isSameDocumentFragment(url)) {
      return NavigationDecision.navigate;
    }

    // Everything else is the screen's decision, not ours.
    onLinkTap(url);
    return NavigationDecision.prevent;
  }

  /// Whether [url] is exactly the configured base URL (modulo a trailing
  /// slash) — the URL WKWebView reports for our own
  /// `loadHtmlString(..., baseUrl:)` navigations on macOS.
  bool _isBareBaseUrl(String url) {
    String norm(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;
    return norm(url) == norm(baseUrl);
  }

  /// Whether [url] is an in-page anchor jump within the loaded document, i.e.
  /// it differs from the base URL only by a `#fragment`. Those should scroll
  /// natively rather than route through external/document navigation.
  bool _isSameDocumentFragment(String url) {
    final reqUri = Uri.tryParse(url);
    if (reqUri == null || !reqUri.hasFragment || reqUri.fragment.isEmpty) {
      return false;
    }
    final baseUri = Uri.tryParse(baseUrl);
    if (baseUri == null) return false;
    String norm(String p) => p.isEmpty ? '/' : p;
    return reqUri.scheme == baseUri.scheme &&
        reqUri.host == baseUri.host &&
        norm(reqUri.path) == norm(baseUri.path);
  }
}
