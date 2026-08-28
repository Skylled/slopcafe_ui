/// The platform seam for the offline document cache.
///
/// `DocumentCacheManager` is the app's only cache of document bytes and of the
/// default document list. On macOS · iOS · Android it is files in a temp
/// directory ([document_cache_io.dart]); in a browser it is an in-memory LRU
/// plus `sessionStorage` ([document_cache_web.dart]). Every call site — the
/// Reader's version-first body cache, the documents provider's offline list
/// fallback and its local search, the instance switcher's namespace eviction —
/// talks to this file and never learns which one it got.
///
/// ## Why this file exists at all
///
/// The io implementation reaches for `dart:io` and `path_provider`, and on the
/// web neither works: `dart:io` compiles to a *throwing stub* and
/// `path_provider` has no web implementation, so `getTemporaryDirectory()`
/// raises `MissingPluginException`. Every method here already swallows its own
/// errors, so the browser build did not crash — it silently cached nothing,
/// which is worse than either working or failing. Two things went with it: the
/// Library's offline banner (`docState.isOffline`, set only when a cached list
/// comes back) and the offline search fallback both became unreachable code in
/// a browser. This seam turns an accidental no-op into a deliberate
/// implementation.
///
/// ## A conditional *export*, unlike the renderer seam
///
/// `lib/core/document_view/document_renderer.dart` uses a conditional **import**
/// and it is worth knowing why this one differs rather than assuming an
/// inconsistency. That seam declares an abstract class with a redirecting
/// factory (`factory DocumentRenderer(...) = DocumentRendererImpl;`), which
/// needs the implementation's name resolvable in *its own* library scope — and
/// an `export` directive puts no name in scope. Nothing here needs that:
/// `DocumentCacheManager` is a static-method class, so callers only need the
/// name **exported**, and re-exporting one of two identically-shaped
/// declarations is exactly what a conditional export is for.
///
/// The condition is `dart.library.js_interop` rather than the older
/// `dart.library.html`: it is true on both web compilers (dart2js and
/// dart2wasm) and false everywhere else.
///
/// ## The contract both implementations owe
///
/// * **Every entry is namespaced by the active instance id.** A `public_id` is
///   a fact about *one* deployment, so two saved deployments can legitimately
///   mint the same id for different documents. A flat cache would serve one
///   deployment's bytes under the other's name — silently, and only for the ids
///   that happened to collide. The namespace is
///   `SecureStorageService.getActiveInstanceId()` (see `instances.dart`).
/// * **[DocumentCacheManager.deleteNamespace] really deletes.** It is the one
///   method with correctness weight rather than performance weight: it is what
///   runs when an instance is removed, or when its Base URL is edited so that
///   its id now names a *different* deployment. A stub there leaves one
///   deployment's documents readable under another's identity. Both
///   implementations do a real scan.
/// * **Nothing throws.** Every method fails silently to null / false / no-op.
///   A cache is an optimisation; a failure to read or write one must cost a
///   round trip, never a screen. (This is also why the accidental web no-op was
///   invisible for so long — the honest way to keep that property is to make
///   the no-op deliberate and documented, which is what the web file does for
///   the parts it genuinely cannot deliver.)
///
/// Where the two implementations legitimately differ — durability across a
/// reload, and what is written to disk at rest — is documented in
/// `document_cache_web.dart`, which is the side that had a choice to make.
library;

export 'document_cache_io.dart'
    if (dart.library.js_interop) 'document_cache_web.dart';
