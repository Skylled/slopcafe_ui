/// The platform seam for handing a URL to the outside world.
///
/// One caller today — the Reader, for a link a rendered document asked to
/// follow and for its own "Open in browser" action — and one job: get [url] in
/// front of the human, in something that is not this app, and say honestly
/// whether that worked.
///
/// ## Why this file exists
///
/// The logic it replaces lived in `reader_screen.dart` and branched on
/// `Platform.isAndroid` / `isIOS` / `isMacOS`. Under dart2js `dart:io` is not
/// absent, it is a *throwing stub*, so in a browser the first of those reads
/// raised `UnsupportedError`, the whole handler unwound, and the app reported
/// failure — "URL copied instead" — on the one platform that **is** a browser.
/// It degraded quietly rather than loudly (the throw is inside an async
/// handler, not a build) which is exactly why it survived: nothing on screen
/// and nothing in the console said the branch had never run.
///
/// This is a conditional **export**, unlike `document_view/`'s conditional
/// import: that seam has an abstract class with a redirecting factory, which
/// needs the implementation's name in its own scope, and `export` puts no name
/// there. A bare top-level function needs only to be re-exported.
///
/// ## The contract both implementations owe
///
/// * **Never throw.** Every failure comes back as an [ExternalBrowserOutcome].
///   The call site is a navigation gesture; a mis-typed scheme or a missing
///   handler must cost the tap, not the screen.
/// * **Distinguish "this platform cannot" from "this platform tried and
///   failed".** The two have different remedies and the Reader says different
///   things about them, which is the whole reason this returns an enum rather
///   than a bool.
/// * **Do not claim success that was not observed.** `opened` means the
///   platform accepted the URL, not that a page painted — see the note on
///   `external_browser_web.dart`, where the browser genuinely refuses to tell
///   us more than that.
///
/// What is deliberately *not* here: the clipboard fallback and the toast. Those
/// need a `BuildContext` and a localized string, so they stay in the Reader,
/// which is also the only place that knows whether the URL is worth showing a
/// human at all.
library;

export 'external_browser_io.dart'
    if (dart.library.js_interop) 'external_browser_web.dart';

/// What became of a request to open a URL outside the app.
enum ExternalBrowserOutcome {
  /// The platform accepted the URL. On io that means a browser was launched;
  /// on the web it means the tab was requested (see that file — a popup
  /// blocker can still swallow it, and the browser will not say so).
  opened,

  /// This platform has no way to open that URL: no installed handler for the
  /// scheme, or a scheme the web implementation is not allowed to launch. The
  /// URL is fine; there is simply nowhere to send it.
  unsupported,

  /// The platform had a way and it did not work.
  failed,
}
