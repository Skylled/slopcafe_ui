import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/document.dart';
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

class DocumentsListNotifier extends StateNotifier<DocumentsListState> {
  final Ref _ref;

  DocumentsListNotifier(this._ref) : super(DocumentsListState());

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
      final dio = _ref.read(dioProvider);
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
      final data = response.data as Map<String, dynamic>;
      final List<dynamic> docsJson = data['documents'] ?? [];
      final nextCursor = data['next_cursor'] as String?;

      final newDocs = docsJson.map((j) => DocumentListing.fromJson(j)).toList();
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
      _ref
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
        errorMessage: e.toString(),
      );
    }
  }

  void revokeDocumentLocally(String publicId, DateTime revokedAt) {
    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return DocumentListing(
          publicId: doc.publicId,
          createdAt: doc.createdAt,
          tags: doc.tags,
          createdById: doc.createdById,
          createdByName: doc.createdByName,
          currentSize: null, // bytes is null when revoked
          currentVer: null, // ver is null when revoked
          description: doc.description,
          slug: null, // slug is cleared when revoked
          title: doc.title,
          revokedAt: revokedAt,
          visibility: doc.visibility,
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
    final dio = _ref.read(dioProvider);
    await dio.post(
      '/admin/documents/$publicId/visibility',
      data: {'visibility': visibility},
    );

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return DocumentListing(
          publicId: doc.publicId,
          createdAt: doc.createdAt,
          tags: doc.tags,
          createdById: doc.createdById,
          createdByName: doc.createdByName,
          currentSize: doc.currentSize,
          currentVer: doc.currentVer,
          description: doc.description,
          slug: doc.slug,
          title: doc.title,
          revokedAt: doc.revokedAt,
          visibility: visibility,
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

  Future<DocumentListing> updateSlug(String publicId, String slug) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/slug',
      data: {'slug': slug},
    );
    final data = response.data as Map<String, dynamic>;
    final returnedSlug = data['slug'] as String?;

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return DocumentListing(
          publicId: doc.publicId,
          createdAt: doc.createdAt,
          tags: doc.tags,
          createdById: doc.createdById,
          createdByName: doc.createdByName,
          currentSize: doc.currentSize,
          currentVer: doc.currentVer,
          description: doc.description,
          slug: returnedSlug,
          title: doc.title,
          revokedAt: doc.revokedAt,
          visibility: doc.visibility,
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

  Future<DocumentListing> updateTags(String publicId, List<String> tags) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(
      '/admin/documents/$publicId/tags',
      data: {'tags': tags},
    );
    final data = response.data as Map<String, dynamic>;
    final returnedTags = List<String>.from(data['tags'] ?? const []);

    final updatedDocs = state.documents.map((doc) {
      if (doc.publicId == publicId) {
        return DocumentListing(
          publicId: doc.publicId,
          createdAt: doc.createdAt,
          tags: returnedTags,
          createdById: doc.createdById,
          createdByName: doc.createdByName,
          currentSize: doc.currentSize,
          currentVer: doc.currentVer,
          description: doc.description,
          slug: doc.slug,
          title: doc.title,
          revokedAt: doc.revokedAt,
          visibility: doc.visibility,
        );
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

  Future<int> restoreVersion(String publicId, int version) async {
    final dio = _ref.read(dioProvider);
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
}

final documentsListProvider =
    StateNotifierProvider<DocumentsListNotifier, DocumentsListState>((ref) {
      return DocumentsListNotifier(ref);
    });

class SearchQueryParams {
  final String query;
  final String? tag;
  final String? slug;

  SearchQueryParams({required this.query, this.tag, this.slug});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchQueryParams &&
          runtimeType == other.runtimeType &&
          query == other.query &&
          tag == other.tag &&
          slug == other.slug;

  @override
  int get hashCode => query.hashCode ^ tag.hashCode ^ slug.hashCode;
}

final documentSearchProvider =
    FutureProvider.family<List<SearchHit>, SearchQueryParams>((
      ref,
      params,
    ) async {
      if (params.query.trim().isEmpty) return const [];

      final dio = ref.read(dioProvider);
      final queryParams = <String, dynamic>{'q': params.query, 'limit': 50};
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
        final data = response.data as Map<String, dynamic>;
        final List<dynamic> hitsJson = data['documents'] ?? [];

        return hitsJson.map((j) => SearchHit.fromJson(j)).toList();
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
                SearchHit(
                  document: doc,
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
