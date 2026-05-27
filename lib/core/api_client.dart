import 'dart:developer' as dev;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_storage.dart';

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

  ApiConnectionState({
    required this.status,
    this.errorMessage,
  });

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

/// State notifier to track connection/auth errors globally.
class ConnectionStateNotifier extends StateNotifier<ApiConnectionState> {
  ConnectionStateNotifier() : super(ApiConnectionState(status: ConnectionStatus.initial));

  void setStatus(ConnectionStatus status, [String? errorMessage]) {
    state = ApiConnectionState(status: status, errorMessage: errorMessage);
  }

  void reset() {
    state = ApiConnectionState(status: ConnectionStatus.initial);
  }
}

final connectionStateProvider = StateNotifierProvider<ConnectionStateNotifier, ApiConnectionState>((ref) {
  return ConnectionStateNotifier();
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio();
  
  // Custom Interceptor for Auth & Logging
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final storage = SecureStorageService.instance;
      final baseUrl = await storage.getBaseUrl();
      final token = await storage.getOperatorToken();

      if (baseUrl != null) {
        options.baseUrl = baseUrl;
      }

      // In the spec, health GET / is unauthenticated, but authenticated probe GET /admin/agents is auth.
      // So if the path contains '/admin', we attach the token.
      final isAuthRequired = options.path.contains('/admin') || options.path.startsWith('admin');

      if (isAuthRequired && token != null) {
        options.headers['Authorization'] = 'Bearer $token';
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

      // Trigger unauthorized connection state on 401
      if (e.response?.statusCode == 401) {
        ref.read(connectionStateProvider.notifier).setStatus(
          ConnectionStatus.unauthorized,
          'Operator token rejected. Please verify your credentials.',
        );
      }

      return handler.next(e);
    },
  ));

  return dio;
});
