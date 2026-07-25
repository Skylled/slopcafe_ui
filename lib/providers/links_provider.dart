import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/api.dart';
import '../core/api_client.dart';

/// The link graph and the slug tombstones that repair it.
///
/// A standalone service rather than a notifier, in the shape of
/// [AgentManagerService]: none of these calls owns app state. The graph is a
/// live view that every write invalidates — the backend re-extracts a
/// document's links in the same batch as the write itself — so a cached
/// neighborhood would be wrong the moment it mattered, and each surface that
/// needs one fetches it per open.
///
/// The slug mutators are grouped here rather than with the document writes
/// because they operate on a name's *tombstone*, not on a document: the slug
/// they take has, by definition, no live document behind it. They are reachable
/// from the broken-link report for the same reason — that report is the only
/// place the app ever learns a retired slug's name.
class LinkGraphService {
  final Ref _ref;
  LinkGraphService(this._ref);

  /// A document's link-graph neighborhood via `GET /d/:public_id/links`.
  ///
  /// Uncached and never folded into document state, like
  /// `DocumentsListNotifier.fetchVersions`: `backlinks` describes *other*
  /// documents' current versions and `outbound` resolves its targets at read
  /// time, so both answers age the instant anything in the corpus is written,
  /// renamed or revoked.
  ///
  /// Auth is any authenticated reader, never public — backlink rows are
  /// listing rows for other documents, including private ones.
  Future<DocumentLinksResponse> fetchLinks(String publicId) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/d/$publicId/links');
    return DocumentLinksResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Live documents that no live document links to, via
  /// `GET /admin/links/orphans` — newest first, capped at 200, deliberately
  /// uncursored (the contract frames it as a curation worklist, not a browse
  /// surface).
  ///
  /// An orphan is a librarian's signal, not an error: a document only ever
  /// shared by URL is a perfectly good orphan. It is only meaningful after
  /// [backfillLinks] has run at least once — before that every pre-backfill
  /// document reads as an orphan, because there are no graph rows to say
  /// otherwise.
  Future<OrphanDocumentsResponse> fetchOrphans() async {
    final dio = _ref.read(dioProvider);
    final response = await dio.get('/admin/links/orphans');
    return OrphanDocumentsResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Walks `POST /admin/links/backfill` to completion, re-extracting every live
  /// document's on-platform links from its stored render into the table behind
  /// [fetchLinks] and [fetchOrphans].
  ///
  /// Always rebuild semantics — extraction is cheap and deterministic, so there
  /// is no incremental mode to choose and no expensive-option warning to give.
  /// The write path keeps the graph current from here on; this sweep exists for
  /// the corpus published before the graph shipped, and for reconciliation.
  /// Idempotent and resumable, so a failed run is re-run rather than repaired.
  Future<LinksBackfillSummary> backfillLinks() async {
    final dio = _ref.read(dioProvider);
    var scanned = 0, updated = 0, links = 0, pages = 0;
    String? cursor;
    // Largest page the contract allows, to minimise round-trips; the page cap
    // is a defensive backstop against a pathological non-advancing cursor,
    // matching `backfillVectors`.
    do {
      final response = await dio.post(
        '/admin/links/backfill',
        queryParameters: {'limit': 200, 'cursor': ?cursor},
      );
      final page = LinksBackfillResponse.fromJson(
        response.data as Map<String, dynamic>,
      );
      scanned += page.scanned;
      updated += page.updated;
      // Per-page, not a running table total — the spec is explicit ("Total link
      // rows stored across this page"), where the prose reference's "total rows
      // stored" reads either way. Summing is therefore correct; taking the last
      // page's value would report one page of a multi-page sweep.
      links += page.links;
      pages++;
      cursor = (page.nextCursor?.isNotEmpty ?? false) ? page.nextCursor : null;
    } while (cursor != null && pages < 1000);

    return LinksBackfillSummary(
      scanned: scanned,
      updated: updated,
      links: links,
      pages: pages,
    );
  }

  /// Point a retired [slug] at a live document via
  /// `POST /admin/slugs/:slug/redirect`, so `/s/:slug` forwards loudly instead
  /// of answering 410.
  ///
  /// The slug must ALREADY be retired — a live slug serves its own document —
  /// so this answers `404 not_found` for a name that was never claimed, and
  /// `422 bad_target` when the target is unknown, revoked or malformed. It
  /// overwrites any existing redirect, including the automatic forward a rename
  /// leaves behind.
  Future<SetSlugRedirectResponse> setSlugRedirect(
    String slug,
    String targetPublicId,
  ) async {
    final dio = _ref.read(dioProvider);
    // The body is modelled inline in the spec rather than in
    // `components.schemas`, so the generator emits no request class and the map
    // is built by hand — the same shape as the promote/restore writes.
    final response = await dio.post(
      '/admin/slugs/${_encodeSlug(slug)}/redirect',
      data: {'target_public_id': targetPublicId},
    );
    return SetSlugRedirectResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Drop a retired slug's redirect via `DELETE /admin/slugs/:slug/redirect`,
  /// reverting `/s/:slug` to a plain 410 tombstone.
  ///
  /// The slug stays retired and therefore still unclaimable; only the
  /// forwarding target is removed. Use [releaseSlug] to return the name itself.
  Future<ClearSlugRedirectResponse> clearSlugRedirect(String slug) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.delete(
      '/admin/slugs/${_encodeSlug(slug)}/redirect',
    );
    return ClearSlugRedirectResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Force-release a retired slug via `DELETE /admin/slugs/:slug`, deleting its
  /// tombstone and returning the name to the pool for a future publish.
  ///
  /// The contract's escape hatch for "I revoked by mistake" and "I really do
  /// want to repurpose this name". This is the ONLY path that un-retires a
  /// slug, and it is distinct from [clearSlugRedirect], which keeps it retired.
  /// Worth confirming destructively at the call site: once released, a later
  /// publish may claim the name, and every link still addressing it will then
  /// silently reach a different document than its author meant.
  Future<ReleaseSlugTombstoneResponse> releaseSlug(String slug) async {
    final dio = _ref.read(dioProvider);
    final response = await dio.delete('/admin/slugs/${_encodeSlug(slug)}');
    return ReleaseSlugTombstoneResponse.fromJson(
      response.data as Map<String, dynamic>,
    );
  }

  /// Percent-encodes a slug for a path segment.
  ///
  /// A slug that reaches these routes from the link graph always matches the
  /// backend's charset, but one typed into the manual repair sheet need not —
  /// and a stray `/` or `?` there would silently address a different route
  /// instead of earning the `400 bad_slug` the operator should see.
  String _encodeSlug(String slug) => Uri.encodeComponent(slug);
}

final linkGraphServiceProvider = Provider<LinkGraphService>((ref) {
  return LinkGraphService(ref);
});

/// Aggregate of a (possibly multi-page) link-graph backfill run.
class LinksBackfillSummary {
  const LinksBackfillSummary({
    required this.scanned,
    required this.updated,
    required this.links,
    required this.pages,
  });

  /// Live documents scanned across all pages.
  final int scanned;

  /// Documents whose link rows were rewritten.
  final int updated;

  /// Total link rows stored across the whole sweep.
  final int links;

  /// Number of backfill pages walked.
  final int pages;

  /// Documents scanned but not updated — the contract's stated cause is a
  /// render that couldn't be fetched, and the stated remedy is to re-run.
  int get unreadable => scanned - updated;

  /// Whether any document was skipped for an unfetchable render, so the run
  /// should be repeated before its results are trusted.
  bool get hasUnreadable => unreadable > 0;
}
