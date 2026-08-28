/// The shared vocabulary for **multiple Slopcafe deployments** — the saved set
/// of instances the operator app can point at, and the one that is currently
/// active.
///
/// This is the sixth hermetic core module, beside `publication.dart`,
/// `links.dart`, `changes.dart`, `review.dart` and `deep_link.dart`: no Flutter
/// imports, no `dart:io`, no plugin channels. Everything here is a value type
/// or a pure function over one, so the whole switching model is unit-testable
/// without a keychain, a device or a backend. The persistence lives in
/// `lib/core/secure_storage.dart`, the reset-on-switch orchestration in
/// `lib/providers/instances_provider.dart`, and the UI in `SettingsScreen` —
/// on the generic app, alongside the shell's quick switcher; on Insight,
/// which locks every instance but [kInsightBaseUrl] out of reach, alone.
///
/// ## Why an instance is more than a URL + token pair
///
/// The app derives state from whichever deployment it is talking to, and that
/// state is *not* interchangeable between deployments:
///
///   - **Unbound OAuth client ids** are issued by one backend's `/admin` API and
///     are meaningless to another, so they hang off the instance rather than
///     sitting in one global list (which is where they lived when there could
///     only ever be one deployment).
///   - **The offline document cache** is keyed by `public_id`, and public ids
///     are per-deployment. Two instances can hand out the same id for entirely
///     different documents, so the cache is namespaced by [SlopcafeInstance.id]
///     (see `document_cache.dart`). Without that, switching instances would
///     serve one deployment's bytes under the other's name — a silent, and
///     therefore nasty, kind of wrong.
///
/// ## Why ids are derived from the host and never change afterwards
///
/// [newInstanceId] slugifies the base URL's host (and port) rather than minting
/// an opaque token. Two properties fall out of that, and both are wanted:
///
///   - The id is filesystem-safe, so it can *be* the cache namespace directly,
///     and a stray cache directory is legible to whoever is looking at it.
///   - Re-adding a deployment that was removed earlier lands on the same id, so
///     it lands on the same cache namespace.
///
/// The id is assigned once, at creation, and is immutable from then on: editing
/// an instance's Base URL leaves its id alone. The name can therefore drift
/// from the URL it was derived from, which is fine — ids are opaque to
/// everything except the cache. What is *not* fine is keeping cached bytes
/// across such an edit, since the id now names a different deployment; the
/// storage layer drops that namespace when the URL changes.
library;

/// The one Slopcafe deployment the Insight build talks to.
///
/// Insight is a read-only fork of the generic operator app (see the project
/// CLAUDE.md): the Base URL field is gone from Settings, and
/// [SecureStorageService.load] seeds a single instance pointed here whenever
/// nothing is persisted yet, so the app is never configurable against any
/// other deployment. Everything downstream — [InstanceSet], the switch/edit
/// machinery this library still exposes — is unchanged and still works on a
/// one-element set; only the UI that let an operator add a second element was
/// removed.
const String kInsightBaseUrl = 'https://insight-slopcafe.skylled.workers.dev';

/// One saved deployment: where it is, how to authenticate to it, and the
/// deployment-scoped state that would be nonsense to share with another.
class SlopcafeInstance {
  const SlopcafeInstance({
    required this.id,
    required this.label,
    required this.baseUrl,
    required this.operatorToken,
    this.unboundOAuthClientIds = const [],
  });

  /// Stable, filesystem-safe identity. Minted by [newInstanceId] at creation
  /// and never rewritten — see the library doc.
  final String id;

  /// Operator-facing name. Seeded from the host by [defaultLabelFor]; free text
  /// afterwards, so a fork and its upstream can be told apart at a glance.
  final String label;

  /// Normalised (no trailing slash) deployment origin.
  final String baseUrl;

  final String operatorToken;

  /// OAuth client ids this deployment issued that are not yet bound to an
  /// agent. Deployment-scoped: see the library doc.
  final List<String> unboundOAuthClientIds;

  /// The host this instance's Base URL points at, lowercased, or `''` when the
  /// URL does not parse. Used to route an inbound web link to the instance that
  /// can actually resolve it.
  String get host => hostOf(baseUrl);

  SlopcafeInstance copyWith({
    String? label,
    String? baseUrl,
    String? operatorToken,
    List<String>? unboundOAuthClientIds,
  }) {
    return SlopcafeInstance(
      id: id,
      label: label ?? this.label,
      baseUrl: baseUrl ?? this.baseUrl,
      operatorToken: operatorToken ?? this.operatorToken,
      unboundOAuthClientIds:
          unboundOAuthClientIds ?? this.unboundOAuthClientIds,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'base_url': baseUrl,
    'operator_token': operatorToken,
    'unbound_oauth_client_ids': unboundOAuthClientIds,
  };

  /// Tolerant of a malformed record: anything unreadable becomes null rather
  /// than throwing, so one corrupt entry cannot lock the operator out of every
  /// other instance they have saved.
  static SlopcafeInstance? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final baseUrl = raw['base_url'];
    final token = raw['operator_token'];
    if (id is! String || id.isEmpty) return null;
    if (baseUrl is! String || baseUrl.isEmpty) return null;
    if (token is! String) return null;
    final label = raw['label'];
    final ids = raw['unbound_oauth_client_ids'];
    return SlopcafeInstance(
      id: id,
      label: label is String && label.isNotEmpty
          ? label
          : defaultLabelFor(baseUrl),
      baseUrl: baseUrl,
      operatorToken: token,
      unboundOAuthClientIds: ids is List
          ? ids.whereType<String>().where((s) => s.isNotEmpty).toList()
          : const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlopcafeInstance &&
      other.id == id &&
      other.label == label &&
      other.baseUrl == baseUrl &&
      other.operatorToken == operatorToken &&
      _listEquals(other.unboundOAuthClientIds, unboundOAuthClientIds);

  @override
  int get hashCode => Object.hash(
    id,
    label,
    baseUrl,
    operatorToken,
    Object.hashAll(unboundOAuthClientIds),
  );

  @override
  String toString() => 'SlopcafeInstance($id, $label, $baseUrl)';
}

/// Every saved instance plus the pointer to the active one.
///
/// Immutable: each mutator returns a new set, so the notifier that owns it can
/// treat a switch the same way it treats any other state transition.
class InstanceSet {
  const InstanceSet({required this.instances, this.activeId});

  const InstanceSet.empty() : instances = const [], activeId = null;

  final List<SlopcafeInstance> instances;

  /// The [SlopcafeInstance.id] of the active instance, or null when nothing is
  /// configured. Always either null or present in [instances] — [_resolve]
  /// enforces that on every construction path.
  final String? activeId;

  bool get isEmpty => instances.isEmpty;
  bool get isNotEmpty => instances.isNotEmpty;

  /// The instance every request, cache read and screen currently answers to.
  SlopcafeInstance? get active {
    final id = activeId;
    if (id == null) return null;
    for (final i in instances) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// True once there is an active instance with a token — the condition
  /// `RootGate` uses to decide between the shell and first-run setup.
  bool get isConfigured {
    final a = active;
    return a != null && a.baseUrl.isNotEmpty && a.operatorToken.isNotEmpty;
  }

  SlopcafeInstance? byId(String id) {
    for (final i in instances) {
      if (i.id == id) return i;
    }
    return null;
  }

  /// The instance whose Base URL points at [host], or null. Case-insensitive.
  ///
  /// This is what lets an inbound web link land on the deployment that can
  /// actually resolve it rather than on whichever one happens to be active —
  /// see `AppShell._openDeepLink`.
  SlopcafeInstance? byHost(String host) {
    final needle = host.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final i in instances) {
      if (i.host == needle) return i;
    }
    return null;
  }

  /// Add [instance], or replace the existing entry with the same id in place.
  /// A newly added instance becomes active; updating one does not steal focus.
  InstanceSet upsert(SlopcafeInstance instance) {
    final existing = instances.indexWhere((i) => i.id == instance.id);
    if (existing >= 0) {
      final next = [...instances];
      next[existing] = instance;
      return _resolve(next, activeId);
    }
    return _resolve([...instances, instance], instance.id);
  }

  /// Drop [id]. When it was the active instance, focus falls to the first
  /// remaining one so the app is never left pointing at nothing while
  /// instances are still configured.
  InstanceSet remove(String id) {
    final next = instances.where((i) => i.id != id).toList();
    return _resolve(next, activeId == id ? null : activeId);
  }

  /// Point the app at [id]. Unknown ids are ignored rather than blanking the
  /// active pointer.
  InstanceSet activate(String id) {
    if (byId(id) == null) return this;
    return _resolve(instances, id);
  }

  /// Guarantees the invariant [activeId] depends on: it names a real member, or
  /// it is null because there are no members at all.
  static InstanceSet _resolve(List<SlopcafeInstance> list, String? wanted) {
    if (list.isEmpty) return const InstanceSet.empty();
    final valid = wanted != null && list.any((i) => i.id == wanted);
    return InstanceSet(
      instances: List.unmodifiable(list),
      activeId: valid ? wanted : list.first.id,
    );
  }

  Map<String, dynamic> toJson() => {
    'active_id': activeId,
    'instances': instances.map((i) => i.toJson()).toList(),
  };

  /// Tolerant by design — see [SlopcafeInstance.fromJson]. A record that will
  /// not parse is dropped; a set that will not parse reads as empty, which
  /// routes the operator to first-run setup rather than to a crash loop.
  static InstanceSet fromJson(Object? raw) {
    if (raw is! Map) return const InstanceSet.empty();
    final list = raw['instances'];
    if (list is! List) return const InstanceSet.empty();
    final parsed = <SlopcafeInstance>[];
    final seen = <String>{};
    for (final entry in list) {
      final instance = SlopcafeInstance.fromJson(entry);
      if (instance == null) continue;
      if (!seen.add(instance.id)) continue;
      parsed.add(instance);
    }
    final active = raw['active_id'];
    return _resolve(parsed, active is String ? active : null);
  }

  @override
  bool operator ==(Object other) =>
      other is InstanceSet &&
      other.activeId == activeId &&
      _listEquals(other.instances, instances);

  @override
  int get hashCode => Object.hash(activeId, Object.hashAll(instances));
}

/// Strip the trailing slash and surrounding whitespace from a Base URL so the
/// same deployment typed two ways is stored one way.
///
/// Lifted out of the old `saveConnectionDetails` unchanged in behaviour, and
/// made pure so it can be tested and reused by the migration path.
String normalizeBaseUrl(String raw) {
  var url = raw.trim();
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return url;
}

/// The host of [baseUrl], lowercased, or `''` when it does not parse.
String hostOf(String baseUrl) {
  final uri = Uri.tryParse(normalizeBaseUrl(baseUrl));
  return (uri?.host ?? '').toLowerCase();
}

/// The name a freshly added instance carries until the operator renames it:
/// its host, without a `www.` prefix. Falls back to the raw URL when the host
/// is unreadable, which is still more use than a blank row.
String defaultLabelFor(String baseUrl) {
  final host = hostOf(baseUrl);
  if (host.isEmpty) return normalizeBaseUrl(baseUrl);
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Mint the immutable id for a new instance at [baseUrl], avoiding collisions
/// with [taken].
///
/// The slug is host + port with every non-alphanumeric run folded to a single
/// `-`, which keeps it usable as a directory name on every platform the app
/// ships to. A collision (the same host saved twice, under two tokens) gets a
/// numeric suffix rather than being merged — those really are two instances.
String newInstanceId(String baseUrl, {required Iterable<String> taken}) {
  final uri = Uri.tryParse(normalizeBaseUrl(baseUrl));
  final host = (uri?.host ?? '').toLowerCase();
  final port = uri != null && uri.hasPort ? '-${uri.port}' : '';
  var slug = '$host$port'
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) slug = 'instance';

  final used = taken.toSet();
  if (!used.contains(slug)) return slug;
  for (var n = 2; ; n++) {
    final candidate = '$slug-$n';
    if (!used.contains(candidate)) return candidate;
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
