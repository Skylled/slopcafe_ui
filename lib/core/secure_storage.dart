import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'instances.dart';

/// Persistence for the saved set of Slopcafe deployments — see
/// `lib/core/instances.dart` for the value model this reads and writes.
///
/// The whole set lives under a single [_keyInstances] entry as JSON rather than
/// one keychain entry per field. That is deliberate: a switch has to move the
/// Base URL and the operator token together, and a multi-key write is not
/// atomic. One key means the app can never come up holding one deployment's URL
/// and another's token.
class SecureStorageService {
  SecureStorageService._internal();
  static final SecureStorageService instance = SecureStorageService._internal();

  // flutter_secure_storage 10 dropped the EncryptedSharedPreferences-backed
  // Android implementation (Jetpack Security was deprecated by Google). The
  // plugin now uses custom ciphers by default and transparently migrates any
  // values written by earlier versions on first access, so Android needs no
  // options here.
  //
  // macOS: force the legacy file-based keychain instead of the default data
  // protection keychain (usesDataProtectionKeychain defaults to true). The data
  // protection keychain requires the keychain-access-groups / application-
  // identifier entitlement even when the app is unsandboxed, which an ad-hoc
  // signed build (no Apple Developer team) cannot satisfy — every write fails
  // with errSecMissingEntitlement (-34018). mOptions is macOS-only, so iOS and
  // Android behaviour is unchanged.
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  /// The saved set, as JSON. See the class doc for why it is one key.
  static const String _keyInstances = 'slopcafe_instances';

  // ---- Legacy single-deployment keys (read once, then migrated away) --------
  static const String _legacyKeyBaseUrl = 'slopcafe_base_url';
  static const String _legacyKeyOperatorToken = 'slopcafe_operator_token';
  static const String _legacyKeyUnboundOAuthClientIds =
      'slopcafe_unbound_oauth_client_ids';

  /// In-memory copy of the persisted set.
  ///
  /// Every outbound request asks for the active Base URL and token from the Dio
  /// interceptor, which previously meant two keychain round-trips per request.
  /// This service is the only writer, so caching the parsed set here is safe and
  /// keeps a switch — which is what invalidates it — the only thing that pays
  /// for a read.
  InstanceSet? _cached;

  /// Load the saved set, migrating a pre-multi-instance install on first call.
  Future<InstanceSet> load() async {
    final cached = _cached;
    if (cached != null) return cached;

    final raw = await _storage.read(key: _keyInstances);
    if (raw != null && raw.isNotEmpty) {
      try {
        return _cached = InstanceSet.fromJson(json.decode(raw));
      } catch (_) {
        // Unparseable JSON reads as "nothing saved" rather than throwing on
        // every launch — InstanceSet.fromJson is tolerant for the same reason.
        return _cached = const InstanceSet.empty();
      }
    }

    return _cached = await _migrateLegacy();
  }

  /// Persist [set] and refresh the in-memory copy.
  Future<void> save(InstanceSet set) async {
    _cached = set;
    await _storage.write(key: _keyInstances, value: json.encode(set.toJson()));
  }

  /// Promote a pre-multi-instance install: the one configured deployment becomes
  /// the first saved instance, and its unbound OAuth client ids come with it
  /// (they were only ever this deployment's).
  ///
  /// Only a *complete* pair migrates. A half-configured install (a Base URL with
  /// no token) is one the old `RootGate` already treated as unconfigured and
  /// routed to setup, so nothing that was reachable before is lost.
  Future<InstanceSet> _migrateLegacy() async {
    final url = await _storage.read(key: _legacyKeyBaseUrl);
    final token = await _storage.read(key: _legacyKeyOperatorToken);
    if (url == null || url.isEmpty || token == null || token.isEmpty) {
      return const InstanceSet.empty();
    }

    final rawIds = await _storage.read(key: _legacyKeyUnboundOAuthClientIds);
    final clientIds = _splitIds(rawIds);

    final baseUrl = normalizeBaseUrl(url);
    final migrated = SlopcafeInstance(
      id: newInstanceId(baseUrl, taken: const <String>[]),
      label: defaultLabelFor(baseUrl),
      baseUrl: baseUrl,
      operatorToken: token,
      unboundOAuthClientIds: clientIds,
    );
    final set = InstanceSet(
      instances: [migrated],
      activeId: migrated.id,
    );

    await save(set);
    await _storage.delete(key: _legacyKeyBaseUrl);
    await _storage.delete(key: _legacyKeyOperatorToken);
    await _storage.delete(key: _legacyKeyUnboundOAuthClientIds);
    return set;
  }

  // ---- Active-instance conveniences ----------------------------------------
  //
  // The call sites that only ever want "where am I pointed right now" — the Dio
  // interceptor, the Reader, the Review split view, the document action sheet —
  // read through these and stay unaware that a set exists at all.

  Future<String?> getBaseUrl() async => (await load()).active?.baseUrl;

  Future<String?> getOperatorToken() async =>
      (await load()).active?.operatorToken;

  /// The active instance's id, which is also its offline-cache namespace.
  /// See `document_cache.dart`.
  Future<String?> getActiveInstanceId() async => (await load()).activeId;

  // ---- Mutations -----------------------------------------------------------

  /// Save a brand-new instance for [baseUrl] and make it active. Returns it.
  Future<SlopcafeInstance> addInstance({
    required String baseUrl,
    required String operatorToken,
    String? label,
  }) async {
    final set = await load();
    final url = normalizeBaseUrl(baseUrl);
    final trimmedLabel = label?.trim();
    final instance = SlopcafeInstance(
      id: newInstanceId(url, taken: set.instances.map((i) => i.id)),
      label: trimmedLabel == null || trimmedLabel.isEmpty
          ? defaultLabelFor(url)
          : trimmedLabel,
      baseUrl: url,
      operatorToken: operatorToken.trim(),
    );
    await save(set.upsert(instance));
    return instance;
  }

  /// Edit an existing instance in place, keeping its id (and therefore its cache
  /// namespace and its unbound client ids).
  ///
  /// Returns true when the Base URL actually changed — the id now names a
  /// different deployment, so the caller must drop that namespace's cached
  /// documents. See the id note in `instances.dart`.
  Future<bool> updateInstance({
    required String id,
    required String baseUrl,
    required String operatorToken,
    String? label,
  }) async {
    final set = await load();
    final existing = set.byId(id);
    if (existing == null) return false;

    final url = normalizeBaseUrl(baseUrl);
    final trimmedLabel = label?.trim();
    final rehomed = url != existing.baseUrl;
    await save(
      set.upsert(
        existing.copyWith(
          label: trimmedLabel == null || trimmedLabel.isEmpty
              ? defaultLabelFor(url)
              : trimmedLabel,
          baseUrl: url,
          operatorToken: operatorToken.trim(),
          // The old deployment's client ids do not describe the new one.
          unboundOAuthClientIds: rehomed ? const [] : null,
        ),
      ),
    );
    return rehomed;
  }

  Future<void> removeInstance(String id) async {
    final set = await load();
    await save(set.remove(id));
  }

  Future<void> setActiveInstance(String id) async {
    final set = await load();
    await save(set.activate(id));
  }

  // ---- Unbound OAuth client ids (scoped to the active instance) -------------

  Future<List<String>> getUnboundOAuthClientIds() async =>
      (await load()).active?.unboundOAuthClientIds ?? const [];

  Future<void> addUnboundOAuthClientId(String clientId) async {
    await _mutateUnboundIds((ids) {
      if (ids.contains(clientId)) return null;
      return [...ids, clientId];
    });
  }

  Future<void> removeUnboundOAuthClientId(String clientId) async {
    await _mutateUnboundIds((ids) {
      if (!ids.contains(clientId)) return null;
      return ids.where((id) => id != clientId).toList();
    });
  }

  /// Apply [change] to the active instance's client ids. A null return means
  /// "no change", which skips the write entirely.
  Future<void> _mutateUnboundIds(
    List<String>? Function(List<String> ids) change,
  ) async {
    final set = await load();
    final active = set.active;
    if (active == null) return;
    final next = change(active.unboundOAuthClientIds);
    if (next == null) return;
    await save(set.upsert(active.copyWith(unboundOAuthClientIds: next)));
  }

  // ---- Teardown ------------------------------------------------------------

  /// Forget every instance, including any legacy keys an install still carries
  /// because it never opened a screen that triggered the migration.
  Future<void> clearAll() async {
    _cached = const InstanceSet.empty();
    await _storage.delete(key: _keyInstances);
    await _storage.delete(key: _legacyKeyBaseUrl);
    await _storage.delete(key: _legacyKeyOperatorToken);
    await _storage.delete(key: _legacyKeyUnboundOAuthClientIds);
  }

  static List<String> _splitIds(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}
