import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
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

  Future<int> restoreVersion(String publicId, int version) async {
    final dio = ref.read(dioProvider);
    final response = await dio.post(
      '/d/$publicId/restore',
      data: FormData.fromMap({'version': version}),
      options: Options(contentType: Headers.formUrlEncodedContentType),
    );

    int newVer = version + 1;
    if (response.data is Map) {
      newVer =
          response.data['version'] as int? ??
          (response.data['new_version'] as int? ?? (version + 1));
    } else if (response.data is int) {
      newVer = response.data as int;
    } else if (response.data is String) {
      newVer = int.tryParse(response.data.toString()) ?? (version + 1);
    }

    await loadNextPage(clear: true);
    return newVer;
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
