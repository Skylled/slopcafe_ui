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

  const HealthState({
    this.sanitizerVersion,
    this.storageCapBytes,
    this.storageUsedBytes,
  });
}

class HealthNotifier extends Notifier<HealthState> {
  @override
  HealthState build() => const HealthState();

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
      );
    } catch (_) {
      // Health is non-essential; keep whatever we last had.
    }
  }
}

final healthProvider = NotifierProvider<HealthNotifier, HealthState>(
  HealthNotifier.new,
);
