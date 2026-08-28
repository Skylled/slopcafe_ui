// The browser HTTP adapter, checked in a real browser.
//
//     flutter test --platform chrome test/http_adapter_browser_test.dart
//
// `flutter test` on its own SKIPS this file — `@TestOn('browser')` keeps it out
// of the VM suite, which cannot compile it: the whole subject is a class that
// only exists behind `dart:js_interop`.
//
// Two properties, one loud and one quiet.
//
// The loud one is why the seam exists: dio's browser adapter warns, per
// request, that a request will trigger a CORS preflight, and for this app that
// is every request (they all carry `Authorization`). Preflight is the designed
// behaviour of this pairing, the deployment answers `OPTIONS`, and the console
// was filling with a warning about a thing working correctly.
//
// The quiet one is `withCredentials`, and it is here because constructing the
// adapter by hand moved that default from dio's hands into ours. It must stay
// false: the deployment deliberately never sends
// `Access-Control-Allow-Credentials` (`src/cors.ts` in agent-web-host treats
// that as its one hard rule), so a credentialed request would be refused by the
// browser outright — and "credentials" here means the operator's ambient cookie
// session riding along beside the bearer token this app sends deliberately.
// Nothing in the app reads that field, so nothing but this test would notice it
// changing.

@TestOn('browser')
library;

import 'package:dio/browser.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/http_adapter_web.dart';

void main() {
  test('installs the browser adapter with the preflight warning off', () {
    final dio = Dio();
    applyPlatformHttpAdapter(dio);

    final adapter = dio.httpClientAdapter;
    expect(
      adapter,
      isA<BrowserHttpClientAdapter>(),
      reason: 'The seam did not install an adapter it configured itself, so '
          'whatever defaults dio picked are the ones in force.',
    );

    final browser = adapter as BrowserHttpClientAdapter;
    expect(
      browser.enableCORSWarning,
      isFalse,
      reason: 'The per-request CORS preflight warning is back on. Every '
          'request this app makes carries Authorization, so this is one log '
          'line and one stack trace per request, about behaviour that is '
          'correct.',
    );
    expect(
      browser.withCredentials,
      isFalse,
      reason: 'withCredentials is on. The deployment never sends '
          'Access-Control-Allow-Credentials, so every cross-origin request '
          'would now fail — and the reason it never sends it is that ambient '
          'cookie authority is exactly what this app must not acquire.',
    );
  });
}
