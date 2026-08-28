import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api.dart';
import 'http_adapter.dart';
import 'secure_storage.dart';

/// Slopcafe API Client.
///
/// Canonical HTTP API Reference:
/// - Title: Slopcafe HTTP API reference
/// - Slug: slopcafe-http-api
/// - URL: https://slopcafe.com/s/slopcafe-http-api
///
/// Refer to the above Slopcafe document for the most up-to-date and complete contract
/// regarding request/response shapes, headers, status codes, and error codes.
/// Keep this client and the app's models synchronized with that reference.

/// Enum representing the connection state of the Operator app.
enum ConnectionStatus {
  initial,
  connecting,
  connected,
  unauthorized, // 401 error
  disconnected, // Network error
}

class ApiConnectionState {
  final ConnectionStatus status;
  final String? errorMessage;

  ApiConnectionState({required this.status, this.errorMessage});

  ApiConnectionState copyWith({
    ConnectionStatus? status,
    String? errorMessage,
  }) {
    return ApiConnectionState(
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Notifier to track connection/auth errors globally.
class ConnectionStateNotifier extends Notifier<ApiConnectionState> {
  @override
  ApiConnectionState build() =>
      ApiConnectionState(status: ConnectionStatus.initial);

  void setStatus(ConnectionStatus status, [String? errorMessage]) {
    state = ApiConnectionState(status: status, errorMessage: errorMessage);
  }

  void reset() {
    state = ApiConnectionState(status: ConnectionStatus.initial);
  }
}

final connectionStateProvider =
    NotifierProvider<ConnectionStateNotifier, ApiConnectionState>(
      ConnectionStateNotifier.new,
    );

/// Marks a request whose 401 is a *result* rather than an app-wide auth failure.
///
/// Settings' connection test deliberately fires credentials that may be wrong —
/// that is the whole point of a test — and reports the outcome in its own result
/// panel. Letting that 401 flip [connectionStateProvider] would raise the global
/// "token rejected" banner and have [AppShell] push a *second* Settings screen
/// on top of the one the operator is typing in. Requests carrying this flag are
/// exempt; every other 401 is still handled globally.
const String kProbeRequestExtra = 'slopcafe.probe';

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio();

  // Transport-level platform differences, all of which are browser-only — see
  // `http_adapter.dart`. A no-op on native.
  applyPlatformHttpAdapter(dio);

  // Custom Interceptor for Auth & Logging
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final storage = SecureStorageService.instance;
        final baseUrl = await storage.getBaseUrl();
        final token = await storage.getOperatorToken();

        if (baseUrl != null) {
          options.baseUrl = baseUrl;
        }

        // In the spec, health GET / is unauthenticated, but authenticated probe GET /admin/agents is auth.
        // So if the path contains '/admin' or '/d/', we attach the token.
        final isAuthRequired =
            options.path.contains('/admin') ||
            options.path.startsWith('admin') ||
            options.path.contains('/d/') ||
            options.path.startsWith('d/');

        // Never overwrite a token the caller supplied. Settings' auth probe
        // sets its own so it can test the credentials *typed into the form*
        // rather than the ones already saved — which is the only way to prove a
        // second deployment before committing it, and would otherwise send the
        // active instance's token to a URL it means nothing to (a guaranteed
        // 401 on every "Test Connection" for a new instance). Same principle as
        // the Accept header below: an explicit caller knows better.
        final hasAuth = options.headers.keys.any(
          (key) => key.trim().toLowerCase() == 'authorization',
        );
        if (isAuthRequired && token != null && !hasAuth) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        // `dart:io` sends no Accept header at all unless one is set explicitly,
        // and Cloudflare strips the ETag from the response to a request that
        // arrives without one. That header is how every version-resolution path
        // in the app learns which version it is holding (see
        // `lib/core/publication.dart`), so its absence doesn't fail loudly — it
        // silently degrades reader caching, revalidation and the published-vs-
        // current comparison. `*/*` is the neutral value: it constrains nothing
        // about what the server may return, it only keeps the validator intact.
        // A caller that set its own Accept (a byte path asking for HTML, say)
        // knows better than this interceptor and is never overridden.
        //
        // ON THE WEB THIS IS A NO-OP, AND IT IS STILL THE RIGHT CODE. XHR
        // already sends `Accept: */*` when the author sets none, so the browser
        // was never the platform with the problem; setting it here just names
        // the value the browser was going to send anyway. It is also free:
        // `Accept` is CORS-safelisted, so writing it does not add a preflight,
        // and XHR replaces the default rather than appending to it, so there is
        // no doubled header. Deleting it would fix nothing and break native.
        //
        // What DOES take the ETag away in a browser is a different mechanism
        // entirely, and the resemblance is a trap: a cross-origin response
        // exposes only seven safelisted headers to script, and everything else
        // reads back as null — no error, no console line. `etag` and
        // `x-doc-current-version` have to be named in the deployment's
        // `Access-Control-Expose-Headers` (they are — `CORS_EXPOSED_RESPONSE_HEADERS`
        // in the agent-web-host repo's `src/cors.ts`, which says the same thing
        // from the other side). So if version resolution ever goes quiet on the
        // web, the answer is over there in the deployment's CORS config, and no
        // amount of tightening this header will help.
        final hasAccept = options.headers.keys.any(
          (key) => key.trim().toLowerCase() == 'accept',
        );
        if (!hasAccept) {
          options.headers['Accept'] = '*/*';
        }

        // Redacted developer logging
        if (kDebugMode) {
          final headersRedacted = Map<String, dynamic>.from(options.headers);
          if (headersRedacted.containsKey('Authorization')) {
            headersRedacted['Authorization'] = 'Bearer [REDACTED]';
          }
          dev.log(
            'API REQUEST: ${options.method} ${options.baseUrl}${options.path}\nHeaders: $headersRedacted\nData: ${options.data}',
            name: 'SlopcafeApiClient',
          );
        }

        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          dev.log(
            'API RESPONSE: ${response.statusCode} ${response.requestOptions.path}\nData: ${response.data}',
            name: 'SlopcafeApiClient',
          );
        }
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        if (kDebugMode) {
          dev.log(
            'API ERROR: ${e.response?.statusCode} ${e.requestOptions.path}\nMessage: ${e.message}\nResponse: ${e.response?.data}',
            name: 'SlopcafeApiClient',
            error: e,
          );
        }

        // Trigger unauthorized connection state on 401. No app copy lives in
        // this context-less service — the UI layer renders the localized
        // `tokenRejectedDetail` fallback. We do forward the backend's own
        // `ErrorBody.message` (server-supplied detail, parsed via the typed
        // envelope) when present; `errorMessage` stays null otherwise.
        final isProbe = e.requestOptions.extra[kProbeRequestExtra] == true;
        if (e.response?.statusCode == 401 && !isProbe) {
          final apiError = ApiError.fromException(e);
          ref
              .read(connectionStateProvider.notifier)
              .setStatus(ConnectionStatus.unauthorized, apiError.message);
        }

        return handler.next(e);
      },
    ),
  );

  return dio;
});
