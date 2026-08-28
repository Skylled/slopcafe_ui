// Regression guard for the reader-token 401 bug fixed on the `insight`
// branch: a reader-tier token is valid everywhere Insight needs it, but
// `/admin/agents` is operator-only and 401s it by design. Before the fix,
// that 401 flowed through the same global handler as a genuinely rejected
// token, flipping `connectionStateProvider` to `unauthorized` and bouncing
// the reader to Settings on every cold start. See `kProbeRequestExtra`'s doc
// in `api_client.dart` and `AgentsListNotifier.loadNextPage`'s catch clause
// in `agent_provider.dart`.
//
// The real `dioProvider` reads the Base URL/token through
// `SecureStorageService`, a keychain platform channel with no meaningful
// behaviour under `flutter_test` (see `health_and_pagination_test.dart` for
// the same workaround against a different provider), so the tests below run
// against a bare `Dio`. What is NOT faked is the decision that matters: the
// interceptor built below carries the same 401-dispatch contract
// `dioProvider` does — check `kProbeRequestExtra`, then flip
// `connectionStateProvider` — so a future change to `agent_provider.dart`
// that drops the flag from the `/admin/agents` request fails these tests the
// same way it would break the real app.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/api_client.dart';
import 'package:slopcafe_ui/providers/agent_provider.dart';
import 'package:slopcafe_ui/providers/document_provider.dart';

/// Resolves every request with a 200 empty-list body except [path], which is
/// rejected as a 401 — and dispatches that 401 exactly the way `dioProvider`
/// does: through `connectionStateProvider`, unless the request is flagged
/// with [kProbeRequestExtra].
///
/// [containerOf] is a getter rather than a `ProviderContainer` because the
/// container has to override `dioProvider` with the `Dio` this function
/// builds — by the time a request actually reaches `onError` the container
/// exists, so a getter is enough to break the construction cycle.
Dio _dioThat401sOn(String path, ProviderContainer Function() containerOf) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path == path) {
          // The `true` is load-bearing: it is dio's own
          // `callFollowingErrorInterceptor` flag, and without it a reject()
          // thrown from *this* interceptor's onRequest never reaches this
          // same interceptor's onError below — dio treats a plain reject()
          // as final and skips the error-handling chain entirely. See
          // `RequestInterceptorHandler.reject` in package:dio.
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.badResponse,
              response: Response(
                requestOptions: options,
                statusCode: 401,
                data: {
                  'error': 'unauthorized',
                  'message':
                      'operator token or session required — see /openapi.json',
                },
              ),
            ),
            true,
          );
        }
        return handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'agents': <dynamic>[], 'documents': <dynamic>[]},
          ),
        );
      },
      onError: (e, handler) {
        final isProbe = e.requestOptions.extra[kProbeRequestExtra] == true;
        if (e.response?.statusCode == 401 && !isProbe) {
          final apiError = ApiError.fromException(e);
          containerOf()
              .read(connectionStateProvider.notifier)
              .setStatus(ConnectionStatus.unauthorized, apiError.message);
        }
        return handler.next(e);
      },
    ),
  );
  return dio;
}

void main() {
  test(
    'a 401 from /admin/agents does not flip connectionStateProvider to '
    'unauthorized, and degrades the fleet list instead of erroring',
    () async {
      late final ProviderContainer container;
      final dio = _dioThat401sOn('/admin/agents', () => container);
      container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      await container.read(agentsListProvider.notifier).loadNextPage();

      // The regression this test exists for: this 401 must read as "reader
      // tier, no fleet visibility" — not as a rejected token.
      expect(
        container.read(connectionStateProvider).status,
        isNot(ConnectionStatus.unauthorized),
      );

      final agentsState = container.read(agentsListProvider);
      expect(agentsState.agents, isEmpty);
      expect(agentsState.hasError, isFalse);
      expect(agentsState.errorMessage, isNull);
    },
  );

  test(
    'a 401 from /admin/documents still flips connectionStateProvider to '
    'unauthorized — the exclusion is /admin/agents-specific, not a blanket '
    'one',
    () async {
      late final ProviderContainer container;
      final dio = _dioThat401sOn('/admin/documents', () => container);
      container = ProviderContainer(
        overrides: [dioProvider.overrideWithValue(dio)],
      );
      addTearDown(container.dispose);

      await container.read(documentsListProvider.notifier).loadNextPage();

      // A genuinely rejected token must still bounce the operator to
      // Settings — only the agents-list fetch is exempt from the global
      // handler, not every operator-only route.
      expect(
        container.read(connectionStateProvider).status,
        ConnectionStatus.unauthorized,
      );
    },
  );
}
