/// The one place the HTTP client's *transport* differs by platform.
///
/// [applyPlatformHttpAdapter] is called once, on the [Dio] built in
/// `api_client.dart`, and is a no-op everywhere except the browser. It exists
/// because the browser transport is not a client we configure so much as one we
/// borrow: `XMLHttpRequest` comes with the page's origin, its cookie jar and
/// its CORS rules already attached, and dio's adapter has opinions about all
/// three that only make sense to state on that platform.
///
/// A conditional export rather than a `kIsWeb` branch, for the ordinary reason:
/// the web implementation names `BrowserHttpClientAdapter`, which is only
/// reachable through `package:dio/browser.dart`, which pulls in `dart:js_interop`
/// and does not compile off the web. Same shape as `document_cache.dart` and the
/// renderer seam next door.
library;

export 'http_adapter_io.dart'
    if (dart.library.js_interop) 'http_adapter_web.dart';
