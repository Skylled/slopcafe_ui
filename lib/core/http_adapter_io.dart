/// The native side of the HTTP-adapter seam: nothing to do.
///
/// macOS, iOS and Android keep dio's default `IOHttpClientAdapter`. Everything
/// this seam exists to configure — CORS, cookies, the browser's own request
/// headers — is a property of a browsing context, and none of it applies to a
/// `dart:io` socket. The function is here so the caller does not have to know
/// that, and so the web file has something to be the other half of.
library;

import 'package:dio/dio.dart';

/// See the library doc: deliberately empty on this platform.
void applyPlatformHttpAdapter(Dio dio) {}
