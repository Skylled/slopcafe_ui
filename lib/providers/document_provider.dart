import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api.dart';
import '../core/api_client.dart';
import '../core/document_cache.dart';

class DocumentsListState {
  final List<DocumentListing> documents;
  final String? nextCursor;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;
  final Set<String> aggregatedTags;
  final bool isOffline;

  DocumentsListState({
    this.documents = const [],
    this.nextCursor,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
    this.aggregatedTags = const {},
    this.isOffline = false,
  });

  /// Whether another page can be requested.
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  DocumentsListState copyWith({
    List<DocumentListing>? documents,
    String? Function()? nextCursor,
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
    Set<String>? aggregatedTags,
    bool? isOffline,
  }) {
    return DocumentsListState(
      documents: documents ?? this.documents,
      nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      aggregatedTags: aggregatedTags ?? this.aggregatedTags,
      isOffline: isOffline ?? this.isOffline,
    );
  }
}

class DocumentsListNotifier extends Notifier<DocumentsListState> {
  @override
  DocumentsListState build() => DocumentsListState();

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

  Future<void> loadNextPage({
    String? tag,
    String? slug,
    bool clear = false,
  }) async {
    if (state.isLoading) return;
    if (!clear && state.nextCursor == null && state.documents.isNotEmpty) {
      // End of pages reached
      return;
    }

    state = state.copyWith(isLoading: true, hasError: false);

    try {
      final dio = ref.read(dioProvider);
      final queryParams = <String, dynamic>{'limit': 50};

      if (!clear && state.nextCursor != null) {
        queryParams['cursor'] = state.nextCursor;
      }
      if (tag != null && tag.isNotEmpty) {
        queryParams['tag'] = tag;
      }
      if (slug != null && slug.isNotEmpty) {
        queryParams['slug'] = slug;
      }

      final response = await dio.get(
        '/admin/documents',
        queryParameters: queryParams,
      );
      final parsed = ListDocumentsResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      final newDocs = parsed.documents;
      final nextCursor = parsed.nextCursor;
      final currentDocs = clear
          ? <DocumentListing>[]
          : List<DocumentListing>.from(state.documents);

      final Set<String> existingIds = currentDocs
          .map((d) => d.publicId)
          .toSet();
      for (var doc in newDocs) {
        if (!existingIds.contains(doc.publicId)) {
          currentDocs.add(doc);
        }
      }

      // Aggregate tags from all retrieved documents to assist client-side filtering suggestions
      final Set<String> allTags = clear
          ? <String>{}
          : Set<String>.from(state.aggregatedTags);
      for (var doc in newDocs) {
        allTags.addAll(doc.tags);
      }

      state = DocumentsListState(
        documents: currentDocs,
        nextCursor: nextCursor,
        isLoading: false,
        hasError: false,
        aggregatedTags: allTags,
        isOffline: false,
      );

      // A successful authenticated fetch means we're connected — surface it so
      // the Library status pill reads "Live" (the symmetric complement to the
      // dio interceptor flipping to `unauthorized` on a 401).
      ref
          .read(connectionStateProvider.notifier)
          .setStatus(ConnectionStatus.connected);

      // Save to local cache only if they are not filtering (canonical default list)
      if (tag == null && (slug == null || slug.isEmpty)) {
        await DocumentCacheManager.saveCachedDocumentList(currentDocs);
      }
    } catch (e, stack) {
      dev.log('Failed to fetch documents', error: e, stackTrace: stack);

      // Load offline cache fallback
      final cachedList = await DocumentCacheManager.getCachedDocumentList();
      if (cachedList != null && cachedList.isNotEmpty) {
        if (clear || state.documents.isEmpty) {
          final Set<String> allTags = {};
          for (var doc in cachedList) {
            allTags.addAll(doc.tags);
          }
          state = DocumentsListState(
            documents: cachedList,
            nextCursor: null,
            isLoading: false,
            hasError: false,
            aggregatedTags: allTags,
            isOffline: true,
          );
          return;
        }
      }

      state = state.copyWith(
        isLoading: false,
        hasError: true,
        errorMessage: ApiError.describe(e),
      );
    }
  }

  void revokeDocumentLocally(String publicId, DateTime revokedAt) {
    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        // On revoke the backend clears ver/size/slug; mirror that locally.
        return doc.copyWith(
          currentSize: null,
          currentVer: null,
          slug: null,
          revokedAt: revokedAt,
        );
      }
      return doc;
    }).toList();

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: state.aggregatedTags,
      isOffline: state.isOffline,
    );
    DocumentCacheManager.saveCachedDocumentList(updatedDocs);
  }

  Future<DocumentListing> updateVisibility(
    String publicId,
    String visibility,
  ) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/visibility',
      data: {'visibility': visibility},
    );
    final returnedVisibility = SetDocumentVisibilityResponse.fromJson(
      response.data as Map<String, dynamic>,
    ).visibility;

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return doc.copyWith(visibility: returnedVisibility);
      }
      return doc;
    }).toList();

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: state.aggregatedTags,
      isOffline: state.isOffline,
    );
    await DocumentCacheManager.saveCachedDocumentList(updatedDocs);

    return state.documents.firstWhere((d) => d.publicId == publicId);
  }

  Future<DocumentListing> updateSlug(String publicId, String slug) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/slug',
      data: {'slug': slug},
    );
    final returnedSlug = SetDocumentSlugResponse.fromJson(
      response.data as Map<String, dynamic>,
    ).slug;

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return doc.copyWith(slug: returnedSlug);
      }
      return doc;
    }).toList();

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: state.aggregatedTags,
      isOffline: state.isOffline,
    );
    await DocumentCacheManager.saveCachedDocumentList(updatedDocs);

    return state.documents.firstWhere((d) => d.publicId == publicId);
  }

  Future<DocumentListing> updateTags(String publicId, List<String> tags) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/tags',
      data: {'tags': tags},
    );
    final returnedTags = SetDocumentTagsResponse.fromJson(
      response.data as Map<String, dynamic>,
    ).tags;

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return doc.copyWith(tags: returnedTags);
      }
      return doc;
    }).toList();

    final Set<String> allTags = Set<String>.from(state.aggregatedTags)
      ..addAll(returnedTags);

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: allTags,
      isOffline: state.isOffline,
    );
    await DocumentCacheManager.saveCachedDocumentList(updatedDocs);

    return state.documents.firstWhere((d) => d.publicId == publicId);
  }

  /// Set a live document's lifecycle status via
  /// `POST /admin/documents/:id/status` — no version bump, like the
  /// visibility/slug/tags mutators above. `'deprecated'` may carry a
  /// [supersededBy] replacement public_id (full-replace per call: omitting it
  /// clears any stored pointer); the backend force-clears the pointer on
  /// `'active'`. The response is canonical for both fields.
  Future<DocumentListing> updateStatus(
    String publicId,
    String status, {
    String? supersededBy,
  }) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/status',
      data: {
        'status': status,
        if (supersededBy != null && supersededBy.isNotEmpty)
          'superseded_by': supersededBy,
      },
    );
    final returned = SetDocumentStatusResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return doc.copyWith(
          status: returned.status,
          supersededBy: returned.supersededBy,
        );
      }
      return doc;
    }).toList();

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: state.aggregatedTags,
      isOffline: state.isOffline,
    );
    await DocumentCacheManager.saveCachedDocumentList(updatedDocs);

    return state.documents.firstWhere((d) => d.publicId == publicId);
  }

  /// Re-fetch the canonical metadata record for a single document from
  /// `GET /admin/documents/:id` and replace it in the in-memory list and the
  /// offline cache, so every surface that reads the documents provider (the
  /// Library, Search, and especially the Reader's chrome) sees the fresh
  /// version, title, tags, size and visibility. Returns the refreshed listing.
  ///
  /// This is the metadata counterpart to the Reader re-fetching the rendered
  /// HTML body on refresh: without it the body updated but the version, tags,
  /// title, etc. stayed pinned to whatever was loaded when the list was first
  /// fetched — stale on screen and stale again after leaving and reopening.
  Future<DocumentListing> refreshDocument(String publicId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get('/admin/documents/$publicId');
    final fresh = DocumentListing.fromJson(
      response.data as Map<String, dynamic>,
    );

    final existingIndex = state.documents.indexWhere(
      (d) => d.publicId == publicId,
    );

    // Idempotent: when the freshly fetched record is value-equal to the one we
    // already hold — or the document isn't in the loaded list at all — leave
    // provider state and the offline cache untouched. Rebuilding every listener
    // and rewriting disk for an unchanged record would defeat the "no new
    // version → no-op" contract. Callers still receive the canonical listing.
    // (DocumentListing is a freezed value type, so `==` compares every field.)
    if (existingIndex == -1 || state.documents[existingIndex] == fresh) {
      return fresh;
    }

    final updatedDocs = List<DocumentListing>.from(state.documents)
      ..[existingIndex] = fresh;

    final Set<String> allTags = Set<String>.from(state.aggregatedTags)
      ..addAll(fresh.tags);

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: allTags,
      isOffline: state.isOffline,
    );
    await DocumentCacheManager.saveCachedDocumentList(updatedDocs);

    return fresh;
  }

  /// Resolve a raw addressed name — a `/d/<public_id>` or `/s/<slug>` — to the
  /// listing row the Reader needs to open it.
  ///
  /// This is the shared landing point for every *late-bound* reference into the
  /// corpus: a link tapped inside the Reader's WebView, an outbound edge in the
  /// link graph, and an inbound web link from outside the app entirely
  /// (`lib/core/deep_link.dart`). All three arrive holding a name rather than a
  /// document, which is precisely what the link graph's late-binding rule says
  /// they must.
  ///
  /// Resolution walks three tiers, cheapest first:
  ///
  /// 1. The already-loaded list — free, and the common case for a corpus the
  ///    operator has been browsing.
  /// 2. `GET /admin/documents?slug=` / `GET /admin/documents/:id` — the
  ///    canonical record. Note this is the *admin* surface, so a **private**
  ///    target resolves too: a link that would 404 for an anonymous visitor
  ///    still opens for the operator, which is the whole point of resolving
  ///    here rather than handing the URL to a browser.
  /// 3. For a `public_id` only, a synthesised placeholder row.
  ///
  /// That third tier is not a fallback for tidiness. A `public_id` is an
  /// immutable capability, so a lookup failing on one means we could not *ask*
  /// — offline, or a token the deployment rejected — far more often than it
  /// means the document is gone. Opening the Reader on a placeholder lets its
  /// own byte-path fetch produce the real answer, including the offline-cached
  /// body it may already hold and the honest "revoked"/"not found" page when
  /// the server does reply. Returning null there would dead-end a link that
  /// works. A `slug` gets no such placeholder, because a name that resolved to
  /// nothing is a name with nothing behind it — there is no id to fetch bytes
  /// with, so there would be nothing for the Reader to do.
  ///
  /// The placeholder's `updatedAt` borrows the same synthesised "now" as
  /// `createdAt`: a record we invented has never been touched, and claiming any
  /// other timestamp would be a fabrication the chrome would then display.
  ///
  /// Returns null when nothing could be resolved, and never throws — every
  /// caller is a navigation gesture, and a network blip should cost the tap,
  /// not the screen.
  Future<DocumentListing?> resolveListing({
    String? publicId,
    String? slug,
  }) async {
    if (publicId != null) {
      for (final doc in state.documents) {
        if (doc.publicId == publicId) return doc;
      }
    }
    if (slug != null) {
      for (final doc in state.documents) {
        if (doc.slug == slug) return doc;
      }
    }

    final dio = ref.read(dioProvider);

    if (slug != null) {
      try {
        final response = await dio.get(
          '/admin/documents',
          queryParameters: {'slug': slug},
        );
        final docs = ListDocumentsResponse.fromJson(
          response.data as Map<String, dynamic>,
        ).documents;
        if (docs.isNotEmpty) return docs.first;
      } catch (_) {
        // Fall through to the public_id tiers below.
      }
    }

    if (publicId != null) {
      try {
        final response = await dio.get('/admin/documents/$publicId');
        if (response.statusCode == 200) {
          return DocumentListing.fromJson(
            response.data as Map<String, dynamic>,
          );
        }
      } catch (_) {
        // Fall through to the placeholder below.
      }

      final now = DateTime.now();
      return DocumentListing(
        publicId: publicId,
        createdAt: now,
        updatedAt: now,
        createdByKind: 'agent',
        tags: [],
        status: 'active',
        title: publicId,
        visibility: 'private',
      );
    }

    return null;
  }

  /// Author a brand-new document as the operator principal via
  /// `POST /admin/documents` (the new authoring surface).
  ///
  /// [content] + [format] (`'markdown'` | `'html'`) are the only contract-
  /// required fields. The rest are optional — pass null/empty to let the backend
  /// derive the title from the first `<h1>`, leave description/tags/slug unset,
  /// and birth the document at the deployment's default visibility (so only send
  /// [visibility] when the operator explicitly picks one).
  ///
  /// Returns the backend's [WriteResponse] (the new `publicId`/`url`/`version`
  /// plus the sanitizer report — `stripped` / `willNotRender`) and reloads the
  /// canonical first page so the new document shows up immediately (this also
  /// refreshes the offline cache and flips the connection pill to "Live", just
  /// like [loadNextPage]'s success path).
  Future<WriteResponse> authorDocument({
    required String content,
    required String format,
    String? title,
    String? description,
    List<String>? tags,
    String? slug,
    String? visibility,
  }) async {
    final dio = ref.read(dioProvider);
    final body = <String, dynamic>{'content': content, 'format': format};
    if (title != null && title.isNotEmpty) body['title'] = title;
    if (description != null && description.isNotEmpty) {
      body['description'] = description;
    }
    if (tags != null && tags.isNotEmpty) body['tags'] = tags;
    if (slug != null && slug.isNotEmpty) body['slug'] = slug;
    if (visibility != null && visibility.isNotEmpty) {
      body['visibility'] = visibility;
    }

    final response = await dio.post('/admin/documents', data: body);
    final write = WriteResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    await loadNextPage(clear: true);
    return write;
  }

  /// List a document's version history via `GET /admin/documents/:id/versions`
  /// — newest first, capped at the 200 most recent versions, with no cursor.
  ///
  /// Deliberately uncached and never folded into [DocumentsListState]: the
  /// history is a live view that a promote or a restore invalidates the moment
  /// it happens, and it is only ever read by a screen that is already open. Its
  /// `current_ver` (and each row's `isCurrent` / `isPublished`) is the canonical
  /// answer to "what is live, and what is being served" at the instant of the
  /// call, so callers should re-fetch rather than hold on to it.
  Future<ListVersionsResponse> fetchVersions(String publicId) async {
    final dio = ref.read(dioProvider);
    final response = await dio.get('/admin/documents/$publicId/versions');
    return ListVersionsResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Move the publication pointer to [version] via
  /// `POST /admin/documents/:id/promote` — the operator-only way to change what
  /// the HTML byte path serves for a public document (`GET /d/:id/raw` and
  /// `GET /s/:slug` serve `published_ver` whenever the document is public and a
  /// version has been promoted; everything else keeps serving `current_ver`).
  ///
  /// Promote is NOT a write: it bumps no version, re-runs no sanitizer, and
  /// triggers no FTS/vector resync — it only repoints an existing version. It is
  /// therefore idempotent (promoting the version that is already published is a
  /// no-op) and it is allowed on a private document, which stages the choice
  /// before the door opens: nothing is served differently until visibility flips
  /// to public, at which point the staged version is what visitors get.
  ///
  /// The response is canonical for `published_ver`, so mirror it onto the row in
  /// state and the offline cache the same way the visibility/slug/tags/status
  /// mutators mirror theirs.
  ///
  /// It returns the [PromoteResponse] rather than a [DocumentListing] because a
  /// promoted document need not be in [state.documents] at all — Search opens
  /// the Reader on a listing synthesised from a [SearchHit], the in-WebView link
  /// handler can hand it a placeholder, and a tag filter or an unpaged tail
  /// simply leaves the row out. Reading the answer back out of the loaded list
  /// would make a successful promote look like a failure in exactly those cases,
  /// and reporting "couldn't publish" over a pointer that really did move is the
  /// one lie the publication gate cannot afford. Every caller already holds the
  /// listing it is displaying, so folding `published_ver` onto that is both
  /// cheaper and always possible.
  Future<PromoteResponse> promoteVersion(String publicId, int version) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/promote',
      data: {'version': version},
    );
    final promoted = PromoteResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return doc.copyWith(publishedVer: promoted.publishedVer);
      }
      return doc;
    }).toList();

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: state.aggregatedTags,
      isOffline: state.isOffline,
    );
    await DocumentCacheManager.saveCachedDocumentList(updatedDocs);

    return promoted;
  }

  /// Restore an older version via the operator route
  /// `POST /admin/documents/:id/restore`.
  ///
  /// Restore is mandatorily restore-as-new: the backend re-writes the chosen
  /// version's retained source as a BRAND-NEW version on top of the history and
  /// never rewinds `current_ver`, so the returned [RestoreResponse.version] is
  /// the new head and nothing is ever lost. Because it re-runs the current
  /// sanitizer over old source, the response carries a fresh sanitizer report —
  /// `modified` / `stripped` / `willNotRender` — which is exactly why this
  /// returns the typed response rather than a bare version number: a restore can
  /// come back materially different from what the operator was looking at, and
  /// the caller has to be able to say so.
  ///
  /// A caller must check [VersionListing.sourcePresent] before offering this: a
  /// pre-0008 version predates source retention, has no source to re-write, and
  /// cannot be restored.
  ///
  /// Restore DOES bump `current_ver`, so reload the canonical first page to pick
  /// up the new head, size and timestamps everywhere the listing is shown.
  Future<RestoreResponse> restoreVersion(String publicId, int version) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/restore',
      data: {'version': version},
    );
    final restored = RestoreResponse.fromJson(
      response.data as Map<String, dynamic>,
    );

    await loadNextPage(clear: true);
    return restored;
  }

  /// Walks `POST /admin/vectors/backfill` to completion, populating the semantic
  /// search index. [VectorBackfillMode.missing] embeds only documents whose
  /// vectors are absent (cheap, incremental); [VectorBackfillMode.rebuild]
  /// re-embeds the entire live corpus (expensive — after an embedding model /
  /// chunk-size change, or to repair a suspected-stale index). The endpoint is
  /// cursor-paginated and idempotent/resumable, so this loops over every page
  /// and returns the summed totals. Touches no document state — vectors are a
  /// search-side index, not part of the listing.
  Future<BackfillSummary> backfillVectors(VectorBackfillMode mode) async {
    final dio = ref.read(dioProvider);
    var scanned = 0, embedded = 0, vectors = 0, skipped = 0, pages = 0;
    String? cursor;
    // Pull the largest page the contract allows to minimise round-trips; the
    // page cap is a defensive backstop against a pathological non-advancing
    // cursor (200 docs/page × 1000 pages = 200k docs).
    do {
      final response = await dio.post(
        '/admin/vectors/backfill',
        queryParameters: {
          'mode': mode.wire,
          'limit': 200,
          'cursor': ?cursor,
        },
      );
      final page = BackfillResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      scanned += page.scanned;
      embedded += page.embedded;
      vectors += page.vectors;
      skipped += page.skipped;
      pages++;
      cursor = (page.nextCursor?.isNotEmpty ?? false) ? page.nextCursor : null;
    } while (cursor != null && pages < 1000);

    return BackfillSummary(
      mode: mode,
      scanned: scanned,
      embedded: embedded,
      vectors: vectors,
      skipped: skipped,
      pages: pages,
    );
  }
}

final documentsListProvider =
    NotifierProvider<DocumentsListNotifier, DocumentsListState>(
      DocumentsListNotifier.new,
    );

/// Ranking mode for `GET /admin/documents/search` (the `mode` query param).
///
/// [hybrid] (the server default) fuses the BM25 keyword leg and the vector
/// (Vectorize/Workers-AI) semantic leg via Reciprocal Rank Fusion — best
/// recall. [keyword] is FTS-only (a deterministic exact-match escape hatch).
/// [semantic] is vector-only (pure concept match). Server-side the query embed
/// is best-effort: `hybrid`/`semantic` silently fall back to the keyword leg
/// when embedding is briefly unavailable, so they never fail on that account.
enum SearchMode {
  hybrid('hybrid'),
  keyword('keyword'),
  semantic('semantic');

  const SearchMode(this.wire);

  /// The on-the-wire `mode` value sent to the backend.
  final String wire;
}

class SearchQueryParams {
  final String query;
  final String? tag;
  final String? slug;
  final SearchMode mode;

  SearchQueryParams({
    required this.query,
    this.tag,
    this.slug,
    this.mode = SearchMode.hybrid,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQueryParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          tag == other.tag &&
          slug == other.slug &&
          mode == other.mode;

  @override
  int get hashCode =>
      query.hashCode ^ tag.hashCode ^ slug.hashCode ^ mode.hashCode;
}

final documentSearchProvider =
    FutureProvider.family<List<SearchHit>, SearchQueryParams>((
      ref,
      params,
    ) async {
      if (params.query.trim().isEmpty) return const [];

      final dio = ref.read(dioProvider);
      // `mode` selects the ranking leg (hybrid | keyword | semantic). Sent
      // explicitly; the backend default is hybrid either way.
      final queryParams = <String, dynamic>{
        'q': params.query,
        'limit': 50,
        'mode': params.mode.wire,
      };
      if (params.tag != null && params.tag!.isNotEmpty) {
        queryParams['tag'] = params.tag;
      }
      if (params.slug != null && params.slug!.isNotEmpty) {
        queryParams['slug'] = params.slug;
      }

      try {
        final response = await dio.get(
          '/admin/documents/search',
          queryParameters: queryParams,
        );
        return SearchDocumentsResponse.fromJson(
          response.data as Map<String, dynamic>,
        ).documents;
      } catch (e, stack) {
        dev.log(
          'Search online query failed, attempting local search fallback',
          error: e,
          stackTrace: stack,
        );

        // Fall back to local search over cached document list
        final cachedList = await DocumentCacheManager.getCachedDocumentList();
        if (cachedList != null) {
          final queryLower = params.query.toLowerCase();
          final List<SearchHit> localHits = [];
          for (var doc in cachedList) {
            // Apply tag/slug filters if present
            if (params.tag != null &&
                params.tag!.isNotEmpty &&
                !doc.tags.contains(params.tag)) {
              continue;
            }
            if (params.slug != null &&
                params.slug!.isNotEmpty &&
                doc.slug != params.slug) {
              continue;
            }

            bool match = false;
            String matchedField = '';
            String snippet = '';

            if (doc.title != null &&
                doc.title!.toLowerCase().contains(queryLower)) {
              match = true;
              matchedField = 'title';
              snippet = doc.title!;
            } else if (doc.description != null &&
                doc.description!.toLowerCase().contains(queryLower)) {
              match = true;
              matchedField = 'description';
              snippet = doc.description!;
            } else if (doc.slug != null &&
                doc.slug!.toLowerCase().contains(queryLower)) {
              match = true;
              matchedField = 'slug';
              snippet = doc.slug!;
            } else if (doc.tags.any(
              (t) => t.toLowerCase().contains(queryLower),
            )) {
              match = true;
              matchedField = 'tags';
              snippet = doc.tags.join(', ');
            }

            if (match) {
              final int matchIdx = snippet.toLowerCase().indexOf(queryLower);
              String highlightedSnippet = snippet;
              if (matchIdx != -1) {
                final prefix = snippet.substring(0, matchIdx);
                final matchText = snippet.substring(
                  matchIdx,
                  matchIdx + queryLower.length,
                );
                final suffix = snippet.substring(matchIdx + queryLower.length);
                highlightedSnippet = '$prefix[$matchText]$suffix';
              }
              localHits.add(
                SearchHit.fromDocument(
                  doc,
                  score: 1.0,
                  matchedField: matchedField,
                  snippet: highlightedSnippet,
                ),
              );
            }
          }
          return localHits;
        }
        rethrow;
      }
    });

/// Mode for `POST /admin/vectors/backfill`. [missing] embeds only documents
/// whose vectors are absent (cheap, incremental — the backend default);
/// [rebuild] re-embeds every live document (expensive in compute and real cost
/// — use after an embedding-model / chunk-size change, or to repair a
/// suspected-stale index).
enum VectorBackfillMode {
  missing('missing'),
  rebuild('rebuild');

  const VectorBackfillMode(this.wire);

  /// The on-the-wire `mode` value.
  final String wire;
}

/// Aggregate of a (possibly multi-page) vector backfill run — the per-page
/// `BackfillResponse` counts summed across the whole walk.
class BackfillSummary {
  const BackfillSummary({
    required this.mode,
    required this.scanned,
    required this.embedded,
    required this.vectors,
    required this.skipped,
    required this.pages,
  });

  final VectorBackfillMode mode;

  /// Live documents scanned across all pages.
  final int scanned;

  /// Documents (re-)embedded.
  final int embedded;

  /// Chunk vectors upserted.
  final int vectors;

  /// Documents skipped (already had vectors, `missing` mode).
  final int skipped;

  /// Number of backfill pages walked.
  final int pages;

  /// Heuristic flag: fewer chunk vectors than documents embedded suggests some
  /// embeds silently failed mid-run (the contract calls out `vectors ≪
  /// embedded` as a transient Vectorize/Workers-AI failure worth re-running).
  bool get suspectPartialFailure => embedded > 0 && vectors < embedded;
}
