import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/document_cache.dart';
import '../core/instances.dart';
import '../core/secure_storage.dart';
import 'agent_provider.dart';
import 'changes_provider.dart';
import 'document_provider.dart';
import 'health_provider.dart';
import 'review_provider.dart';

/// The saved deployments and the pointer to the active one.
///
/// On Insight this is a one-element set, seeded by
/// [SecureStorageService.load] and locked there — [SettingsScreen] only ever
/// [edit]s or [signOut]s that single instance, never [add]s or [remove]s a
/// second one. The generic multi-instance machinery below (switching,
/// upserting, the reload-not-invalidate policy) is otherwise unchanged, since
/// it works the same way on a set of one.
///
/// ## What a switch has to do besides swapping credentials
///
/// The Dio interceptor reads the Base URL and token per request, so pointing at
/// another deployment is genuinely just a write. Everything the app is *holding*
/// is the hard part: every list, count, feed and search result on screen belongs
/// to the deployment that answered for it, and none of it means anything against
/// the next one. [switchTo] therefore reloads rather than invalidates.
///
/// The distinction matters. `ref.invalidate` on a `NotifierProvider` a mounted
/// screen is watching rebuilds it at its empty initial state and stops there —
/// the fetch that fills it lives in the screen's `initState`, which has already
/// run. The operator would be left staring at a permanently empty Library. Each
/// notifier's own clear-and-refetch entry point is called instead, which is the
/// same path a pull-to-refresh takes. Only the family providers — which are
/// keyed by a query and rebuilt on next read — are invalidated.
class InstancesNotifier extends AsyncNotifier<InstanceSet> {
  @override
  Future<InstanceSet> build() => SecureStorageService.instance.load();

  SecureStorageService get _storage => SecureStorageService.instance;

  /// Point the app at [id] and rebuild every screen's data against it.
  ///
  /// A no-op when [id] is already active, so a stray tap on the current
  /// instance in the switcher does not throw away good data for a full reload.
  Future<void> switchTo(String id) async {
    final current = state.value;
    if (current != null && current.activeId == id) return;

    await _storage.setActiveInstance(id);
    state = AsyncData(await _storage.load());
    await _resetDerivedState();
  }

  /// Save a new deployment and switch to it. Returns the instance created.
  Future<SlopcafeInstance> add({
    required String baseUrl,
    required String operatorToken,
    String? label,
  }) async {
    final instance = await _storage.addInstance(
      baseUrl: baseUrl,
      operatorToken: operatorToken,
      label: label,
    );
    state = AsyncData(await _storage.load());
    await _resetDerivedState();
    return instance;
  }

  /// Edit a saved deployment in place.
  ///
  /// When the Base URL moves, the instance's id now names a different backend,
  /// so its cache namespace is dropped before anything can read from it — see
  /// [SecureStorageService.updateInstance]. Derived state is only rebuilt when
  /// the edit touched the *active* instance; editing a background one has no
  /// bearing on what is currently on screen.
  Future<void> edit({
    required String id,
    required String baseUrl,
    required String operatorToken,
    String? label,
  }) async {
    final wasActive = state.value?.activeId == id;
    final rehomed = await _storage.updateInstance(
      id: id,
      baseUrl: baseUrl,
      operatorToken: operatorToken,
      label: label,
    );
    if (rehomed) await DocumentCacheManager.deleteNamespace(id);
    state = AsyncData(await _storage.load());
    if (wasActive) await _resetDerivedState();
  }

  /// Forget a deployment, along with the documents cached under it.
  ///
  /// Removing the active instance hands focus to the first one left standing
  /// ([InstanceSet.remove]), so the app is never pointed at nothing while other
  /// instances remain configured.
  Future<void> remove(String id) async {
    final wasActive = state.value?.activeId == id;
    await _storage.removeInstance(id);
    await DocumentCacheManager.deleteNamespace(id);
    state = AsyncData(await _storage.load());
    if (wasActive) await _resetDerivedState();
  }

  /// Forget every deployment — the Settings danger zone.
  Future<void> clearAll() async {
    final ids = state.value?.instances.map((i) => i.id).toList() ?? const [];
    await _storage.clearAll();
    for (final id in ids) {
      await DocumentCacheManager.deleteNamespace(id);
    }
    state = const AsyncData(InstanceSet.empty());
    await _resetDerivedState();
  }

  /// Clear the active instance's operator token, keeping its Base URL —
  /// Insight's "Sign out". The instance is never removed (there is nowhere
  /// left to re-add it from; see `secure_storage.dart`'s seeding note), only
  /// its credential.
  ///
  /// [edit] is not reused here even though the storage write it would do is
  /// identical, because [edit] always ends in [_resetDerivedState]'s full
  /// reload — right when a *replacement* credential should be proven against
  /// the backend immediately, and wrong here: the only credential a reload
  /// could fire requests with is the one just being revoked. An empty Bearer
  /// token still reads as "present" to the Dio interceptor (it is `''`, not
  /// null), so that reload would 401 on `/admin/documents` — which is not
  /// exempt from the global interceptor — and bounce the operator straight
  /// back through the Settings screen they are already standing on. Every
  /// list is still cleared, so a subsequent sign-in starts from a clean slate
  /// rather than the previous session's rows.
  Future<void> signOut() async {
    final id = state.value?.activeId;
    if (id == null) return;
    await _storage.updateInstance(
      id: id,
      baseUrl: kInsightBaseUrl,
      operatorToken: '',
    );
    state = AsyncData(await _storage.load());
    await _resetDerivedState(refetch: false);
  }

  /// Throw away everything the previous deployment put on screen and, unless
  /// [refetch] is false, refetch against the new one. See the class doc for
  /// why a switch reloads rather than invalidates — [refetch] exists only for
  /// [signOut], which wants the clearing half without the doomed-to-401 fetch
  /// half; see its doc for why.
  Future<void> _resetDerivedState({bool refetch = true}) async {
    // A 401 raised by the deployment we just left says nothing about this one.
    ref.read(connectionStateProvider.notifier).reset();

    // Keyed by a query and re-read on demand — invalidation is the right tool.
    ref.invalidate(documentSearchProvider);
    ref.invalidate(agentKeysProvider);

    // Clear before reloading, never instead of it. A reload that fails leaves
    // the old state standing — the correct behaviour for a refresh, and exactly
    // wrong here, because a newly added instance is routinely unreachable or
    // holding a token that is about to be rejected. Without this the shell would
    // keep showing the previous deployment's documents, agents and storage
    // figures under the new deployment's name. See `reset()` on each notifier.
    ref.read(documentsListProvider.notifier).reset();
    ref.read(agentsListProvider.notifier).reset();
    ref.read(healthProvider.notifier).reset();

    // Pushed routes (Changes, Review queue). Touch only the ones already alive:
    // a live notifier may be backing a screen sitting *under* Settings in the
    // navigation stack, which would otherwise come back showing the previous
    // deployment's rows. One that was never opened is left alone — its screen
    // fetches in `initState` when it is first pushed, so waking it here would
    // buy nothing and cost two requests on every switch.
    if (ref.exists(changeFeedProvider)) {
      final notifier = ref.read(changeFeedProvider.notifier)..reset();
      if (refetch) notifier.reload();
    }
    if (ref.exists(reviewQueueProvider)) {
      final notifier = ref.read(reviewQueueProvider.notifier)..reset();
      if (refetch) notifier.reload();
    }

    if (!refetch) return;

    // The home tabs. Awaited so a caller can show a spinner until the shell is
    // actually showing the new deployment rather than the old one's leftovers.
    await Future.wait([
      ref.read(documentsListProvider.notifier).loadNextPage(clear: true),
      ref.read(agentsListProvider.notifier).loadNextPage(clear: true),
      ref.read(healthProvider.notifier).load(),
    ]);
  }
}

final instancesProvider = AsyncNotifierProvider<InstancesNotifier, InstanceSet>(
  InstancesNotifier.new,
);

/// The active deployment, or null before setup. Convenience for the many read
/// sites (headers, switcher chips) that want the current instance and nothing
/// else, so they do not each unwrap the `AsyncValue`.
final activeInstanceProvider = Provider<SlopcafeInstance?>((ref) {
  return ref.watch(instancesProvider).value?.active;
});
