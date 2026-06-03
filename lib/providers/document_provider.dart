import 'dart:developer' as dev;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/document.dart';

class DocumentsListState {
  final List<DocumentListing> documents;
  final String? nextCursor;
  final bool isLoading;
  final bool hasError;
  final String? errorMessage;
  final Set<String> aggregatedTags;

  DocumentsListState({
    this.documents = const [],
    this.nextCursor,
    this.isLoading = false,
    this.hasError = false,
    this.errorMessage,
    this.aggregatedTags = const {},
  });

  DocumentsListState copyWith({
    List<DocumentListing>? documents,
    String? Function()? nextCursor,
    bool? isLoading,
    bool? hasError,
    String? errorMessage,
    Set<String>? aggregatedTags,
  }) {
    return DocumentsListState(
      documents: documents ?? this.documents,
      nextCursor: nextCursor != null ? nextCursor() : this.nextCursor,
      isLoading: isLoading ?? this.isLoading,
      hasError: hasError ?? this.hasError,
      errorMessage: errorMessage ?? this.errorMessage,
      aggregatedTags: aggregatedTags ?? this.aggregatedTags,
    );
  }
}

class DocumentsListNotifier extends StateNotifier<DocumentsListState> {
  final Ref _ref;

  DocumentsListNotifier(this._ref) : super(DocumentsListState());

  Future<void> loadNextPage({String? tag, String? slug, bool clear = false}) async {
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

      final response = await dio.get('/admin/documents', queryParameters: queryParams);
      final data = response.data as Map<String, dynamic>;
      final List<dynamic> docsJson = data['documents'] ?? [];
      final nextCursor = data['next_cursor'] as String?;

      final newDocs = docsJson.map((j) => DocumentListing.fromJson(j)).toList();
      final currentDocs = clear ? <DocumentListing>[] : List<DocumentListing>.from(state.documents);

      final Set<String> existingIds = currentDocs.map((d) => d.publicId).toSet();
      for (var doc in newDocs) {
        if (!existingIds.contains(doc.publicId)) {
          currentDocs.add(doc);
        }
      }

      // Aggregate tags from all retrieved documents to assist client-side filtering suggestions
      final Set<String> allTags = clear ? <String>{} : Set<String>.from(state.aggregatedTags);
      for (var doc in newDocs) {
        allTags.addAll(doc.tags);
      }

      state = DocumentsListState(
        documents: currentDocs,
        nextCursor: nextCursor,
        isLoading: false,
        hasError: false,
        aggregatedTags: allTags,
      );
    } catch (e, stack) {
      dev.log('Failed to fetch documents', error: e, stackTrace: stack);
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
          currentVer: null,  // ver is null when revoked
          description: doc.description,
          slug: null,        // slug is cleared when revoked
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
    );
  }

  Future<DocumentListing> updateVisibility(String publicId, String visibility) async {
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
    );

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
    );

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

    final Set<String> allTags = Set<String>.from(state.aggregatedTags)..addAll(returnedTags);

    state = DocumentsListState(
      documents: updatedDocs,
      nextCursor: state.nextCursor,
      isLoading: state.isLoading,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
      aggregatedTags: allTags,
    );

    return state.documents.firstWhere((d) => d.publicId == publicId);
  }

  Future<int> restoreVersion(String publicId, int version) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.post(
      '/d/$publicId/restore',
      data: FormData.fromMap({'version': version}),
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
      ),
    );
    
    int newVer = version + 1;
    if (response.data is Map) {
      newVer = response.data['version'] as int? ?? 
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

  SearchQueryParams({
    required this.query,
    this.tag,
    this.slug,
  });

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
    FutureProvider.family<List<SearchHit>, SearchQueryParams>((ref, params) async {
  if (params.query.trim().isEmpty) return const [];

  final dio = ref.read(dioProvider);
  final queryParams = <String, dynamic>{
    'q': params.query,
    'limit': 50,
  };
  if (params.tag != null && params.tag!.isNotEmpty) {
    queryParams['tag'] = params.tag;
  }
  if (params.slug != null && params.slug!.isNotEmpty) {
    queryParams['slug'] = params.slug;
  }

  final response = await dio.get('/admin/documents/search', queryParameters: queryParams);
  final data = response.data as Map<String, dynamic>;
  final List<dynamic> hitsJson = data['documents'] ?? [];

  return hitsJson.map((j) => SearchHit.fromJson(j)).toList();
});

final documentDetailHtmlProvider =
    FutureProvider.family<String, String>((ref, publicId) async {
  final dio = ref.read(dioProvider);
  // The raw HTML endpoint does not require auth, but can be reached
  // directly through the public URL structure on the backend.
  final response = await dio.get('/d/$publicId/raw');
  return response.data as String;
});

class MarkdownDetailResponse {
  final String markdown;
  final String sanitizerVersion;
  final String converterVersion;

  MarkdownDetailResponse({
    required this.markdown,
    required this.sanitizerVersion,
    required this.converterVersion,
  });
}

final documentDetailTextProvider =
    FutureProvider.family<MarkdownDetailResponse, String>((ref, publicId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/d/$publicId/text');
  
  final markdown = response.data as String;
  final sanitizerVersion = response.headers.value('x-sanitizer-version') ?? 'unknown';
  final converterVersion = response.headers.value('x-converter-version') ?? 'unknown';

  return MarkdownDetailResponse(
    markdown: markdown,
    sanitizerVersion: sanitizerVersion,
    converterVersion: converterVersion,
  );
});

class ReadSourceOkResponse {
  final String source;
  final String sourceFormat;
  final int versionNo;
  final String sanitizerVersion;
  final List<String> stripped;
  final List<String> willNotRender;
  final bool unsanitized;
  final String? title;
  final String? description;
  final List<String> tags;
  final String? slug;

  ReadSourceOkResponse({
    required this.source,
    required this.sourceFormat,
    required this.versionNo,
    required this.sanitizerVersion,
    required this.stripped,
    required this.willNotRender,
    required this.unsanitized,
    this.title,
    this.description,
    required this.tags,
    this.slug,
  });

  factory ReadSourceOkResponse.fromJson(Map<String, dynamic> json) {
    return ReadSourceOkResponse(
      source: json['source'] as String,
      sourceFormat: json['source_format'] as String,
      versionNo: json['version_no'] as int,
      sanitizerVersion: json['sanitizer_v'] as String,
      stripped: List<String>.from(json['stripped'] ?? const []),
      willNotRender: List<String>.from(json['will_not_render'] ?? const []),
      unsanitized: json['unsanitized'] as bool? ?? false,
      title: json['title'] as String?,
      description: json['description'] as String?,
      tags: List<String>.from(json['tags'] ?? const []),
      slug: json['slug'] as String?,
    );
  }
}

final documentDetailSourceProvider =
    FutureProvider.family<ReadSourceOkResponse, String>((ref, publicId) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/d/$publicId/source');
  return ReadSourceOkResponse.fromJson(response.data as Map<String, dynamic>);
});

final documentDetailHistoryRawProvider =
    FutureProvider.family<String, ({String publicId, int version})>((ref, arg) async {
  final dio = ref.read(dioProvider);
  final response = await dio.get('/d/${arg.publicId}/v/${arg.version}/raw');
  return response.data as String;
});
