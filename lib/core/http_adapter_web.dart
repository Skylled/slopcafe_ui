/// The browser side of the HTTP-adapter seam.
///
/// Dio picks `BrowserHttpClientAdapter` on its own here, so this file is not
/// about *choosing* the transport — it is about turning off one thing that
/// adapter does by default, and re-stating the setting that must never change.
///
/// ## The noise
///
/// The adapter logs a warning, per request, whenever a request is not a CORS
/// "simple request" and will therefore be preceded by a preflight `OPTIONS`.
/// For this app that is **every request**: they all carry `Authorization`,
/// which is not on the CORS safelist, and the reads carry `If-None-Match` on
/// top of it. In a debug session the browser console fills with
///
///     🔔 Dio: This request is not a CORS "simple request" and will trigger a
///     preflight (OPTIONS) request: the request header "Authorization" is not
///     on the CORS safelist. …
///
/// once per document opened, plus a stack trace each time. The warning is not
/// wrong; it is just not news. Preflight is the *designed* behaviour of this
/// pairing — the deployment answers `OPTIONS` and advertises `authorization`,
/// `if-none-match` and the rest in `Access-Control-Allow-Headers` (see
/// `src/cors.ts` in the agent-web-host repo, which caps the preflight cache at
/// Chromium's two-hour ceiling precisely because our GETs always preflight).
///
/// Silencing it costs nothing diagnostically, and that is worth being precise
/// about rather than assuming: `enableCORSWarning` gates only the per-request
/// log. When a request actually fails, the adapter still appends the same CORS
/// explanation to the `DioException`'s message, unconditionally. So a genuinely
/// misconfigured deployment — one whose `CORS_ALLOWED_ORIGINS` does not include
/// this app's origin — still reports itself, at the moment it breaks, where the
/// app's own error handling will surface it. What is gone is the log line on
/// the requests that were always going to work.
///
/// ## The setting that must not move
///
/// Constructing the adapter by hand means this file now owns its configuration,
/// including the one that used to be someone else's default. **`withCredentials`
/// stays false.** It is dio's default, it is not written below, and it is not an
/// oversight:
///
///   * The deployment deliberately never emits `Access-Control-Allow-Credentials`
///     (`src/cors.ts` documents that as its one hard rule and has a test
///     scanning for the header name), so a credentialed cross-origin request
///     would be rejected by the browser outright — every request would fail.
///   * Credentials here means the *browser's* ambient authority — cookies for
///     the deployment's origin, i.e. an operator's console session. This app
///     authenticates with a bearer token it holds itself and sends explicitly.
///     Attaching an ambient session on top would hand every request a second,
///     invisible identity, which is exactly the CSRF-shaped thing the backend's
///     cookie/CSRF pairing is built to prevent.
///
/// If a future change needs per-request credentials, dio takes
/// `Options.extra['withCredentials']` — but read the backend's CORS rule first,
/// because the answer there is "no".
library;

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Installs the browser adapter with its per-request CORS preflight warning
/// off. See the library doc for why the warning is noise here and what is
/// deliberately left at its default.
///
/// `enableCORSWarning` arrived in `dio_web_adapter` 2.2.1 (reached through
/// dio's own `package:dio/browser.dart` re-export). If a dio bump ever drops
/// or renames it this stops compiling, which is the failure mode to want: the
/// alternative — a flag that silently stops applying — would restore the noise
/// with nobody the wiser.
void applyPlatformHttpAdapter(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(enableCORSWarning: false);
}
