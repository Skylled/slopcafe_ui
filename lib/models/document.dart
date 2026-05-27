class DocumentListing {
  final String publicId;
  final int? currentVer;
  final DateTime createdAt;
  final String? createdById;
  final String? createdByName;
  final int? currentSize;
  final DateTime? revokedAt;
  final String? title;
  final String? description;
  final List<String> tags;
  final String? slug;

  DocumentListing({
    required this.publicId,
    this.currentVer,
    required this.createdAt,
    this.createdById,
    this.createdByName,
    this.currentSize,
    this.revokedAt,
    this.title,
    this.description,
    required this.tags,
    this.slug,
  });

  bool get isRevoked => revokedAt != null;

  factory DocumentListing.fromJson(Map<String, dynamic> json) {
    return DocumentListing(
      publicId: json['public_id'] as String,
      currentVer: json['current_ver'] as int?,
      createdAt: DateTime.parse(json['created_at'] as String),
      createdById: json['created_by_id'] as String?,
      createdByName: json['created_by_name'] as String?,
      currentSize: json['current_size'] as int?,
      revokedAt: json['revoked_at'] != null
          ? DateTime.parse(json['revoked_at'] as String)
          : null,
      title: json['title'] as String?,
      description: json['description'] as String?,
      tags: List<String>.from(json['tags'] ?? const []),
      slug: json['slug'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'public_id': publicId,
      'current_ver': currentVer,
      'created_at': createdAt.toIso8601String(),
      'created_by_id': createdById,
      'created_by_name': createdByName,
      'current_size': currentSize,
      'revoked_at': revokedAt?.toIso8601String(),
      'title': title,
      'description': description,
      'tags': tags,
      'slug': slug,
    };
  }
}

class SearchHit {
  final DocumentListing document;
  final double score;
  final String matchedField;
  final String snippet;

  SearchHit({
    required this.document,
    required this.score,
    required this.matchedField,
    required this.snippet,
  });

  factory SearchHit.fromJson(Map<String, dynamic> json) {
    return SearchHit(
      document: DocumentListing.fromJson(json),
      score: (json['score'] as num).toDouble(),
      matchedField: json['matched_field'] as String,
      snippet: json['snippet'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...document.toJson(),
      'score': score,
      'matched_field': matchedField,
      'snippet': snippet,
    };
  }
}
