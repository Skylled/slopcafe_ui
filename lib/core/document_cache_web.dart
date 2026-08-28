/// The browser implementation of the document-cache seam.
///
/// Two stores, chosen separately because the two things being cached are not
/// the same kind of thing:
///
///  * **Document bodies → an in-memory LRU.** Rendered HTML is the big, hot,
///    disposable half. Keeping it in a map recovers the thing that actually
///    matters minute to minute — reopening a document you just closed repaints
///    instantly instead of refetching — and costs nothing at rest.
///  * **The default document list → `sessionStorage`.** Small, and the *only*
///    thing that revives two features which were dead code in a browser: the
///    Library's offline banner (`docState.isOffline` is set only when a cached
///    list comes back) and the offline search fallback. Both hang off
///    [getCachedDocumentList] returning something.
///
/// ## Why not IndexedDB
///
/// It is the obvious answer and it was refused on purpose, so do not "upgrade"
/// to it without re-arguing this. Persisting document *bytes* at rest would
/// mean writing private documents into a per-origin store shared by every
/// human who uses that browser profile — a materially worse trade than the app
/// makes on a phone, where the cache sits in a per-app sandbox. And the payoff
/// it promises is not deliverable anyway: Safari evicts all script-writable
/// storage after seven days of no interaction, so "switch back next week and
/// find it intact" is a promise that browser will not keep.
///
/// `sessionStorage` is the narrow exception rather than a contradiction: it
/// holds listing *metadata* (titles, slugs, tags — not bodies), it is scoped to
/// the tab, and the browser drops it when that tab closes.
///
/// ## What this implementation genuinely does not deliver
///
/// **A body cache does not survive a page reload.** On io the cache is files,
/// so the app can be killed and reopened offline and still render. Here a
/// refresh empties the body LRU; the document list survives within the tab.
/// That is a real reduction and it is stated rather than hidden — every method
/// still answers honestly (a miss is a miss), so the Reader simply refetches,
/// which is what it does on a cold io cache too.
library;

import 'dart:collection';
import 'dart:convert';

import 'package:web/web.dart' as web;

import '../api/api.dart';
import 'secure_storage.dart';

/// One cached body, and the version it is.
///
/// Version and HTML travel together because every read in the Reader is
/// version-qualified: a body whose number is not known is not usable as a
/// conditional-GET validator, and a body filed under the wrong number is worse
/// than none (see the Reader's `_loadHtmlIntoWebview`).
class _CachedBody {
  const _CachedBody(this.version, this.html);

  final int version;
  final String html;
}

/// The offline document cache — rendered HTML by `public_id`, plus the default
/// document list. Browser half of the seam; see `document_cache.dart` for the
/// contract, and `document_cache_io.dart` for the file-backed half.
class DocumentCacheManager {
  /// The namespace used when no instance is active. Only reachable in the
  /// window before first-run setup completes, where nothing is cached anyway.
  /// Same literal as the io side — the two namespaces never meet, but a reader
  /// comparing the files should not have to wonder.
  static const String _unscopedNamespace = 'default';

  /// Key prefix for everything this app writes to `sessionStorage`, mirroring
  /// the io side's `slopcafe_doc_cache/<instance-id>/` directory layout so the
  /// two are legible as the same scheme. Storage keys are flat, so the slashes
  /// are punctuation rather than structure — which is exactly why
  /// [deleteNamespace] has to scan rather than delete a directory.
  static const String _storageRoot = 'slopcafe_doc_cache/';

  /// Bounds on the body LRU: entries, and total characters held.
  ///
  /// A tab that renders documents already carries the Flutter engine, the
  /// canvas and every decoded image, so the cache gets a budget rather than
  /// free rein. 4Mi characters is roughly 8MB of UTF-16 and comfortably more
  /// than an operator opens in a session; the entry count is the second bound
  /// so a corpus of tiny documents cannot grow the map without limit either.
  static const int _maxCachedBodies = 32;
  static const int _maxCachedChars = 4 * 1024 * 1024;

  /// Bodies, most-recently-used **last**.
  ///
  /// A `LinkedHashMap` iterates in insertion order, so "move to the end on
  /// touch, evict from the front" is a complete LRU with no extra bookkeeping.
  /// The key is `<namespace>/<public_id>` — the namespace is part of the key
  /// rather than a nested map because an id means nothing without the
  /// deployment it came from (see the seam's contract).
  static final LinkedHashMap<String, _CachedBody> _bodies =
      LinkedHashMap<String, _CachedBody>();

  /// Running total of [_bodies] body lengths, so a write does not have to sum
  /// the map.
  static int _cachedChars = 0;

  /// The active instance's cache namespace.
  /// The active instance's cache namespace, or null when it cannot be
  /// resolved — in which case the caller caches nothing.
  ///
  /// The read can genuinely fail here in a way it cannot on io:
  /// `flutter_secure_storage_web` decrypts through WebCrypto, which does not
  /// exist outside a secure context, and it raises an `UnsupportedError` —
  /// an `Error`, so the plugin's own `on Exception` catch does not hold it.
  /// Falling back to [_unscopedNamespace] there would be worse than caching
  /// nothing: it would file one deployment's documents under a shared name.
  /// The io side reaches the same outcome by a different route (its per-method
  /// `try` swallows the throw and the method no-ops).
  static Future<String?> _namespace() async {
    try {
      return await SecureStorageService.instance.getActiveInstanceId() ??
          _unscopedNamespace;
    } catch (_) {
      return null;
    }
  }

  /// `sessionStorage`, or null when the browser refuses it.
  ///
  /// Reading the property itself throws `SecurityError` when storage is
  /// blocked for the origin (Safari's "block all cookies", a third-party
  /// context, some enterprise policies), which is why this is a method with a
  /// try rather than a field. Null means "no list cache here" and every caller
  /// degrades to a network read, exactly as it would on a cold cache.
  static web.Storage? _sessionStorage() {
    try {
      return web.window.sessionStorage;
    } catch (_) {
      return null;
    }
  }

  /// The `sessionStorage` key holding [namespace]'s document list.
  static String _listKey(String namespace) =>
      '$_storageRoot$namespace/documents_list';

  /// The body-LRU key for [publicId] under the active instance, or null when
  /// the namespace could not be resolved.
  static Future<String?> _bodyKey(String publicId) async {
    final namespace = await _namespace();
    return namespace == null ? null : '$namespace/$publicId';
  }

  // ---- Namespace eviction ---------------------------------------------------

  /// Drop every cached entry for one instance — called when that instance is
  /// removed, or when its Base URL is edited to point somewhere else and its id
  /// therefore names a different deployment.
  ///
  /// **The one method here with correctness weight rather than performance
  /// weight**, and therefore the one that must never be a stub: leaving these
  /// entries behind would serve a *different* deployment's documents under
  /// this instance's identity. Storage keys are flat, so "delete the
  /// namespace" is a real prefix scan — collected first and removed after,
  /// because `Storage.key(i)` reindexes as items are removed and deleting mid
  /// walk skips entries.
  ///
  /// The trailing slash in the prefix is load-bearing: instance ids are
  /// host-derived slugs, so `example-com` is a prefix of `example-com-2`.
  static Future<void> deleteNamespace(String instanceId) async {
    _dropBodiesWithPrefix('$instanceId/');

    final storage = _sessionStorage();
    if (storage == null) return;
    try {
      final prefix = '$_storageRoot$instanceId/';
      final doomed = <String>[];
      for (var i = 0; i < storage.length; i++) {
        final key = storage.key(i);
        if (key != null && key.startsWith(prefix)) doomed.add(key);
      }
      for (final key in doomed) {
        storage.removeItem(key);
      }
    } catch (_) {
      // Fail silently: an un-evicted cache is stale, not broken — every read
      // is version-keyed and revalidated.
    }
  }

  // ---- Document bodies ------------------------------------------------------

  /// Load cached HTML for a specific document ID and version.
  /// Returns null if there is no cache hit.
  static Future<String?> getCachedHtml(String publicId, int version) async {
    final key = await _bodyKey(publicId);
    if (key == null) return null;
    final entry = _touch(key);
    if (entry == null || entry.version != version) return null;
    return entry.html;
  }

  /// Hold HTML for a document, clobbering any other cached version of it to
  /// avoid stale cache — the same all-or-one rule the io side gets by deleting
  /// the document's other files before it writes.
  static Future<void> saveCachedHtml(
    String publicId,
    int version,
    String html,
  ) async {
    final key = await _bodyKey(publicId);
    if (key == null) return;
    _drop(key);

    // A single body larger than the whole budget is not cached at all, rather
    // than admitted and then immediately evicted along with everything it
    // pushed out. The document still renders; it just refetches next time.
    if (html.length > _maxCachedChars) return;

    _bodies[key] = _CachedBody(version, html);
    _cachedChars += html.length;

    while (_bodies.length > _maxCachedBodies ||
        (_cachedChars > _maxCachedChars && _bodies.length > 1)) {
      _drop(_bodies.keys.first);
    }
  }

  /// Evict the cached body for a given document publicId.
  static Future<void> deleteCachedDoc(String publicId) async {
    final key = await _bodyKey(publicId);
    if (key != null) _drop(key);
  }

  /// Check if a specific version of a document is cached offline.
  static Future<bool> isCached(String publicId, int version) async {
    final entry = _entryFor(await _bodyKey(publicId));
    return entry != null && entry.version == version;
  }

  /// The version number of the cached body for a document, or null if none.
  ///
  /// There is at most one, because [saveCachedHtml] replaces rather than
  /// accumulates — which is also why the io side's directory scan collapses to
  /// a map lookup here.
  static Future<int?> getCachedVersion(String publicId) async =>
      _entryFor(await _bodyKey(publicId))?.version;

  static _CachedBody? _entryFor(String? key) =>
      key == null ? null : _bodies[key];

  /// Move an entry to the recent end and return it (null when absent).
  /// Does not touch [_cachedChars]: the same bytes are still held.
  static _CachedBody? _touch(String key) {
    final entry = _bodies.remove(key);
    if (entry == null) return null;
    return _bodies[key] = entry;
  }

  static void _drop(String key) {
    final removed = _bodies.remove(key);
    if (removed != null) _cachedChars -= removed.html.length;
  }

  static void _dropBodiesWithPrefix(String prefix) {
    for (final key in _bodies.keys.where((k) => k.startsWith(prefix)).toList()) {
      _drop(key);
    }
  }

  // ---- The document list ----------------------------------------------------

  /// Save the default/unfiltered list of documents for this session.
  static Future<void> saveCachedDocumentList(
    List<DocumentListing> documents,
  ) async {
    final storage = _sessionStorage();
    final namespace = await _namespace();
    if (storage == null || namespace == null) return;
    try {
      final jsonList = documents.map((d) => d.toJson()).toList();
      storage.setItem(_listKey(namespace), json.encode(jsonList));
    } catch (_) {
      // Fail silently if cache writing fails. `setItem` throws on quota
      // exhaustion and leaves the previous value in place, so a failed write
      // degrades to a staler list rather than to none — the same outcome a
      // failed file write has on io.
    }
  }

  /// Load this session's cached list of documents.
  static Future<List<DocumentListing>?> getCachedDocumentList() async {
    final storage = _sessionStorage();
    final namespace = await _namespace();
    if (storage == null || namespace == null) return null;
    try {
      final raw = storage.getItem(_listKey(namespace));
      if (raw == null || raw.isEmpty) return null;
      final List<dynamic> jsonList = json.decode(raw);
      return jsonList.map((j) => DocumentListing.fromJson(j)).toList();
    } catch (_) {
      // Fail silently if cache reading fails — including the deliberate case
      // where a list written by an older build no longer parses against a
      // re-pinned contract (a newly required field). A failed parse reads as
      // "nothing cached" and the caller fetches.
    }
    return null;
  }
}
