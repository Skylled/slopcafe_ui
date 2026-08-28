import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api.dart';
import '../core/api_client.dart';

/// Best-effort backend health snapshot — the sanitizer version and R2 storage
/// cap/used surfaced on the Operate ("The Pass") stat grid + storage bar.
///
/// This used to live in `OperateScreen`'s local widget state. It was lifted into
/// a provider so a pull-to-refresh on *either* home tab can reload it alongside
/// the document/agent lists: a refresh then behaves "as if the app were opened
/// anew" regardless of which tab the gesture started on. See
/// [refreshFleetData](refresh.dart).
class HealthState {
  final String? sanitizerVersion;
  final int? storageCapBytes;
  final int? storageUsedBytes;
  final int? d1Documents;
  final int? d1Agents;

  const HealthState({
    this.sanitizerVersion,
    this.storageCapBytes,
    this.storageUsedBytes,
    this.d1Documents,
    this.d1Agents,
  });
}

class HealthNotifier extends Notifier<HealthState> {
  @override
  HealthState build() => const HealthState();

  /// Drop everything this notifier is holding, back to its initial state.
  ///
  /// Called when the app is pointed at another deployment: these rows describe
  /// the deployment that served them and mean nothing against the next one. It
  /// is deliberately separate from the reload that follows, because a reload
  /// that *fails* — an unreachable host, a rejected token, exactly the states a
  /// freshly added instance is in — leaves the previous state in place by
  /// design, which is right for a refresh and wrong for a switch. Clearing first
  /// makes the failure show as an empty, erroring screen rather than as the
  /// previous deployment's corpus under the new deployment's name.
  void reset() => state = build();

  /// Fetch `/healthz`. Best-effort: any failure (offline, non-JSON body) leaves
  /// the previous snapshot in place — the UI renders "—" / hides the storage bar
  /// when fields are null.
  Future<void> load() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/healthz');
      final data = res.data;
      if (data is! Map) return;
      final map = Map<String, dynamic>.from(data);
      final health = HealthzResponse.fromJson(map);
      // No canonical "used" field is in the contract; read it opportunistically
      // so the bar fills in if the backend ever exposes one, but never invent it.
      final used = map['storage_used_bytes'] ?? map['storage_bytes_used'];
      state = HealthState(
        sanitizerVersion: health.sanitizerVersion,
        storageCapBytes: health.storageCapBytes,
        storageUsedBytes: used is int ? used : int.tryParse('${used ?? ''}'),
        d1Documents: health.d1.documents,
        d1Agents: health.d1.agents,
      );
    } catch (_) {
      // Health is non-essential; keep whatever we last had.
    }
  }
}

final healthProvider = NotifierProvider<HealthNotifier, HealthState>(
  HealthNotifier.new,
);
