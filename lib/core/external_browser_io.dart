/// The native implementation of the external-browser seam — macOS, iOS and
/// Android.
///
/// A move rather than a rewrite: the platform branching below is the ladder
/// `reader_screen.dart` ran, in the same order, with the same outcomes. What
/// stayed behind in the Reader is everything that needs a `BuildContext` — the
/// clipboard fallback and the toasts — because those are decisions about a
/// human, not about a platform.
library;

import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import 'external_browser.dart';

/// Hands [url] to the platform's browser.
///
/// The ladder, and why it is not just `launchUrl` everywhere:
///
///  * **Android · iOS** — `url_launcher` with
///    `LaunchMode.externalApplication`, so the URL leaves the app entirely
///    rather than opening an in-app web view. A document link is content the
///    app has deliberately refused to render itself; showing it in a chrome-less
///    embedded view would hand it back the framing it was denied.
///    `canLaunchUrl` first: on recent Android/iOS it answers false unless the
///    scheme is declared in the manifest / `Info.plist`, and a false there is
///    [ExternalBrowserOutcome.unsupported] — there is no handler, not a
///    failure.
///  * **macOS** — `open(1)`. `url_launcher_macos` would also work, but this
///    path has shipped and the web port is not the moment to re-test the
///    desktop one.
///  * **Anything else** — `unsupported`. The app targets macOS, iOS, Android
///    and the web, so on io this is the "ran somewhere unplanned" branch.
///
/// The one deliberate change from the pre-seam code: the macOS branch now
/// **checks `open`'s exit code**. It previously reported success unconditionally
/// and toasted "Opening in browser…" even when nothing opened; a non-zero exit
/// now falls through to the Reader's clipboard fallback, which is the honest
/// answer and a strictly more useful one.
Future<ExternalBrowserOutcome> openInExternalBrowser(String url) async {
  final uri = Uri.tryParse(url);
  try {
    if (uri != null && (Platform.isAndroid || Platform.isIOS)) {
      if (!await canLaunchUrl(uri)) return ExternalBrowserOutcome.unsupported;
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return ExternalBrowserOutcome.opened;
    }

    if (Platform.isMacOS) {
      // Deliberately the raw string, not `uri`: `open` takes what the document
      // actually asked for, and a URL this app could not parse is one macOS
      // may still resolve.
      final result = await Process.run('open', [url]);
      return result.exitCode == 0
          ? ExternalBrowserOutcome.opened
          : ExternalBrowserOutcome.failed;
    }

    return ExternalBrowserOutcome.unsupported;
  } catch (_) {
    // Nothing here may throw into a navigation gesture — see the seam's
    // contract. `launchUrl` throws a PlatformException rather than returning
    // false on several platforms, and `Process.run` throws when the binary is
    // missing.
    return ExternalBrowserOutcome.failed;
  }
}
