import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api.dart';
import '../core/api_client.dart';

class AgentsListState {
  final List<AgentListing> agents;
  final String? nextCursor;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;

  AgentsListState({
    this.agents = const [],
    this.nextCursor,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
  });

  AgentsListState copyWith({
    List<AgentListing>? agents,
    String? Function()? nextCursor,
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
  }) {
    return AgentsListState(
      agents: agents ?? this.agents,
      nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class AgentsListNotifier extends Notifier<AgentsListState> {
  @override
  AgentsListState build() => AgentsListState();

  Future<void> loadNextPage({bool clear = false}) async {
    if (state.isLoading) return;
    if (!clear && state.nextCursor == null && state.agents.isNotEmpty) {
      return; // End of list reached
    }

    state = state.copyWith(isLoading: true, hasError: false);

    try {
      final dio = ref.read(dioProvider);
      final queryParams = <String, dynamic>{'limit': 50};

      if (!clear && state.nextCursor != null) {
        queryParams['cursor'] = state.nextCursor;
      }

      final response = await dio.get(
        '/admin/agents',
        queryParameters: queryParams,
      );
      final parsed = ListAgentsResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      final newAgents = parsed.agents;
      final nextCursor = parsed.nextCursor;
      final currentAgents = clear
          ? <AgentListing>[]
          : List<AgentListing>.from(state.agents);

      final Set<String> existingIds = currentAgents.map((a) => a.id).toSet();
      for (var agent in newAgents) {
        if (!existingIds.contains(agent.id)) {
          currentAgents.add(agent);
        }
      }

      state = AgentsListState(
        agents: currentAgents,
        nextCursor: nextCursor,
        isLoading: false,
        hasError: false,
      );
    } catch (e, stack) {
      dev.log('Failed to fetch agents', error: e, stackTrace: stack);
      state = state.copyWith(
        isLoading: false,
        hasError: true,
        errorMessage: ApiError.describe(e),
      );
    }
  }

  Future<MintAgentKeyResponse> createAgent(String name) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post('/admin/agents', data: {'name': name});
    final mintResponse = MintAgentKeyResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    // Trigger immediate reload to catch the new agent and updated fleet statistics
    await loadNextPage(clear: true);

    return mintResponse;
  }

  Future<RevokeAgentResponse> killAgent(String agentId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.delete('/admin/agents/$agentId');
    final result = RevokeAgentResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    // Remove locally
    final updatedList = state.agents.where((a) => a.id != agentId).toList();
    state = state.copyWith(agents: updatedList);

    return result;
  }
}

final agentsListProvider =
    NotifierProvider<AgentsListNotifier, AgentsListState>(
      AgentsListNotifier.new,
    );

// Fetch all keys for an agent (limit 100 for display purposes)
final agentKeysProvider = FutureProvider.family<ListAgentKeysResponse, String>((
  ref,
  agentId,
) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get(
    '/admin/agents/$agentId/keys',
    queryParameters: {'limit': 100},
  );
  return ListAgentKeysResponse.fromJson(response.data as Map<String, dynamic>);
});

// Helper provider/service class for standalone modifications (keys, OAuth clients)
class AgentManagerService {
  final Ref _ref;
  AgentManagerService(this._ref);

  Future<MintAgentKeyResponse> mintAgentKey(String agentId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('/admin/agents/$agentId/keys');
    return MintAgentKeyResponse.fromJson(response.data as Map<String, dynamic>);
  }

  Future<void> revokeAgentKey(String keyId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete('/admin/keys/$keyId');
  }

  Future<CreateOAuthClientResponse> mintOAuthClient(String agentId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('/admin/agents/$agentId/oauth-clients');
    return CreateOAuthClientResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<CreateUnboundOAuthClientResponse> mintUnboundOAuthClient() async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post('/admin/oauth-clients');
    return CreateUnboundOAuthClientResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  Future<void> deleteOAuthClient(String clientId) async {
    final dio = _ref.read(dioProvider);
    await dio.delete('/admin/oauth-clients/$clientId');
  }
}

final agentManagerServiceProvider = Provider<AgentManagerService>((ref) {
  return AgentManagerService(ref);
});
