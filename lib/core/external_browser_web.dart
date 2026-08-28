/// The browser implementation of the external-browser seam.
///
/// In a browser, "open this somewhere that is not the app" is a new tab, and
/// `url_launcher` already has an endorsed web implementation that does exactly
/// that. Using it rather than reaching for `window.open` here is deliberate:
/// the plugin carries two behaviours worth inheriting rather than re-deriving.
///
///  * It opens with **`noopener,noreferrer`**. Without `noopener` the new tab
///    keeps a live `window.opener` handle back into this app and can navigate
///    it somewhere else — reverse tabnabbing, and the URL being opened came
///    from an agent-authored document, which is precisely the source that
///    should never get a handle on the operator console. (The implicit
///    `noopener` browsers apply to `<a target="_blank">` does **not** apply to
///    `window.open`.)
///  * It special-cases Safari, which needs `mailto:` / `tel:` / `sms:` on the
///    `_top` target rather than a new tab or it strands a blank one. That is
///    why this file does **not** pass `webOnlyWindowName: '_blank'` — doing so
///    overrides the quirk handling to say something the plugin already says
///    better by default (unset means a new tab).
///
/// ## What `opened` can and cannot mean here
///
/// `url_launcher_web` returns true for any scheme it is willing to launch and
/// documents why it cannot do better: `window.open` with `noopener` returns
/// null **by specification**, so a blocked popup is indistinguishable from a
/// successful one. So [ExternalBrowserOutcome.opened] means *the browser was
/// asked*, and the Reader's toast ("Opening in browser…") is a statement about
/// the request rather than about a painted page.
///
/// That gap is not theoretical. Browsers only allow a programmatic new tab
/// under a user activation, and the Reader's external-link path asks *after*
/// awaiting a confirmation sheet — Chromium and Firefox keep the activation
/// alive for a few seconds and let it through, Safari is stricter about
/// anything outside the original task. Nothing here can detect that, which is
/// the reason the accompanying prose is careful; the "Open in browser" action
/// in the more-sheet has no such gap because it does not await anything first.
///
/// ## The scheme gate
///
/// `canLaunchUrl` on the web answers true only for `http`, `https`, `mailto`,
/// `tel` and `sms`, so anything else comes back
/// [ExternalBrowserOutcome.unsupported] rather than being handed to the
/// browser. It is the second such gate — `document_renderer_web.dart` already
/// filters a document's links to `http`/`https`/`mailto`/`tel` before reporting
/// them — and both are kept: this one also covers the Reader's own
/// operator-facing URLs, and neither is expensive.
library;

import 'package:url_launcher/url_launcher.dart';

import 'external_browser.dart';

/// Opens [url] in a new browser tab.
Future<ExternalBrowserOutcome> openInExternalBrowser(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) return ExternalBrowserOutcome.unsupported;
  try {
    if (!await canLaunchUrl(uri)) return ExternalBrowserOutcome.unsupported;
    return await launchUrl(uri)
        ? ExternalBrowserOutcome.opened
        : ExternalBrowserOutcome.failed;
  } catch (_) {
    // See the seam's contract: a navigation gesture must not be able to throw.
    return ExternalBrowserOutcome.failed;
  }
}
