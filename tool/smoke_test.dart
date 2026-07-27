// Live + fixture smoke test for the generated API layer.
//
// Validates that the generated models (lib/api/models.dart) and the ErrorCode
// envelope (lib/api/api_error.dart) correctly handle what the real backend
// sends, focusing on the OpenAPI-3.1 nullability risk (a revoked document has
// null current_ver/current_size/slug) and on contract 2.0.0's publication gate,
// where a listing row carries both current_ver and published_ver and only the
// serving rule says which one a visitor actually receives.
//
//   dart run tool/smoke_test.dart
//
// Public paths (/healthz and an unauthenticated 401) are hit against the live
// backend; the revoked-document and search-hit shapes are validated with
// spec-accurate fixtures (no operator token needed). To additionally exercise
// the authenticated list -> search flow against live data, pass a token:
//
//   OPERATOR_TOKEN=sk_... dart run tool/smoke_test.dart
//   BASE_URL=https://slopcafe.com OPERATOR_TOKEN=sk_... dart run tool/smoke_test.dart
//
// Exits non-zero if any check fails.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/changes.dart';
import 'package:slopcafe_ui/core/links.dart';
import 'package:slopcafe_ui/core/publication.dart';
import 'package:slopcafe_ui/core/review.dart';

int _failures = 0;

void _check(String label, bool ok, [String? detail]) {
  stdout.writeln(
    '${ok ? '  ✓' : '  ✗'} $label${detail != null ? ' — $detail' : ''}',
  );
  if (!ok) _failures++;
}

Future<void> main() async {
  final baseUrl = Platform.environment['BASE_URL'] ?? 'https://slopcafe.com';
  final token = Platform.environment['OPERATOR_TOKEN'];
  final dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      validateStatus: (_) => true, // we assert on status ourselves
    ),
  );

  stdout.writeln('Smoke-testing generated API layer against $baseUrl\n');

  // --- 1. Fixture: a REVOKED document (the OpenAPI-3.1 nullability risk) ------
  stdout.writeln('Revoked-document fixture (nullable fields):');
  // `updated_at` is required from contract 2.0.0 and is the last touch of any
  // kind, so on a revoked document it is the revocation itself — later than the
  // (now null) content write this row no longer has.
  final revokedJson = {
    'public_id': 'pub_revoked_demo',
    'current_ver': null,
    'created_at': '2026-01-02T03:04:05.000Z',
    'updated_at': '2026-02-03T04:05:06.000Z',
    'current_version_at': null,
    'created_by_id': null,
    'created_by_name': null,
    'created_by_kind': 'agent',
    'current_size': null,
    'current_source_sha256': null,
    'published_ver': null,
    'published_source_sha256': null,
    'revoked_at': '2026-02-03T04:05:06.000Z',
    'title': null,
    'description': null,
    'tags': <String>[],
    'slug': null,
    'status': 'active',
    'superseded_by': null,
    'visibility': 'private',
  };
  try {
    final doc = DocumentListing.fromJson(revokedJson);
    _check('parses without throwing', true);
    _check('currentVer is null', doc.currentVer == null);
    _check('currentSize is null', doc.currentSize == null);
    _check('slug is null', doc.slug == null);
    _check('title is null', doc.title == null);
    _check('publishedVer is null', doc.publishedVer == null);
    _check('currentVersionAt is null', doc.currentVersionAt == null);
    _check('isRevoked == true', doc.isRevoked == true);
    _check('createdAt parsed to DateTime', doc.createdAt.year == 2026);
    _check('updatedAt parsed to DateTime', doc.updatedAt.month == 2);
    // Round-trips back to identical snake_case JSON (the offline-cache contract).
    final round = DocumentListing.fromJson(doc.toJson());
    _check(
      'toJson/fromJson round-trip preserves nulls',
      round.currentVer == null && round.slug == null && round.isRevoked,
    );
  } catch (e) {
    _check('parses without throwing', false, '$e');
  }

  // --- 2. Fixture: a SearchHit with null listing fields ----------------------
  stdout.writeln('\nSearch-hit fixture (flat shape + .document view):');
  try {
    final hit = SearchHit.fromJson({
      ...revokedJson,
      'score': 1.5,
      'matched_field': 'title',
      'snippet': 'hello [world]',
    });
    _check('parses without throwing', true);
    _check('score is double', hit.score == 1.5);
    _check(
      '.document view is a DocumentListing',
      hit.document.publicId == 'pub_revoked_demo',
    );
    _check('.document.isRevoked == true', hit.document.isRevoked);
  } catch (e) {
    _check('parses without throwing', false, '$e');
  }

  // --- 3. Fixture: the 2.0.0 publication gate on a listing row ---------------
  //
  // The admin list and search still report `current_ver`, so from 2.0.0 a row
  // alone no longer says what a visitor is served. This checks that the two
  // numbers survive the round-trip and that the serving rule reads them the way
  // the backend does — a public document that has been promoted serves its
  // published version to everyone, while the same numbers on a private document
  // serve current, because there is nobody the gate is holding back.
  stdout.writeln('\nPublication-gate fixture (published_ver vs current_ver):');
  try {
    final promotedJson = {
      ...revokedJson,
      'public_id': 'pub_promoted_demo',
      'revoked_at': null,
      'visibility': 'public',
      'current_ver': 8,
      'published_ver': 4,
      'current_size': 2048,
      'slug': 'promoted-demo',
      'title': 'Promoted demo',
      'created_at': '2026-01-02T03:04:05.000Z',
      'current_version_at': '2026-03-04T05:06:07.000Z',
      'updated_at': '2026-03-09T10:11:12.000Z',
    };
    final promoted = DocumentListing.fromJson(promotedJson);
    _check('parses without throwing', true);
    _check('currentVer == 8', promoted.currentVer == 8);
    _check('publishedVer == 4', promoted.publishedVer == 4);
    _check(
      'updatedAt is after currentVersionAt (retagged since the last write)',
      promoted.updatedAt.isAfter(promoted.currentVersionAt!),
    );
    _check(
      'public + promoted serves the published version',
      promoted.servedVer == 4,
    );
    _check(
      'public + promoted reports unpublished work',
      promoted.hasUnpublishedWork,
    );

    final privateSameNumbers = promoted.copyWith(visibility: 'private');
    _check(
      'private serves current regardless of published_ver',
      privateSameNumbers.servedVer == 8,
    );
    _check(
      'private reports no unpublished work',
      !privateSameNumbers.hasUnpublishedWork,
    );

    final neverPromoted = promoted.copyWith(publishedVer: null);
    _check(
      'public + never promoted serves current',
      neverPromoted.servedVer == 8 && !neverPromoted.hasUnpublishedWork,
    );

    final round = DocumentListing.fromJson(promoted.toJson());
    _check(
      'toJson/fromJson preserves published_ver',
      round.publishedVer == 4 && round.servedVer == 4,
    );
  } catch (e) {
    _check('parses without throwing', false, '$e');
  }

  // --- 3b. Fixture: the link graph on an outbound-link report ----------------
  //
  // The graph resolves each link's target at read time, so the five states are
  // the app's only evidence of link rot. What this pins is the two rules that
  // are easy to get subtly wrong: `redirected` still reaches a document (stale,
  // not dead), and the slug repair applies to a narrower set than "broken" —
  // a name nothing ever claimed has no tombstone to redirect, and a /d/ link
  // has no slug at all.
  stdout.writeln('\nLink-graph fixture (outbound link states):');
  try {
    final graph = DocumentLinksResponse.fromJson({
      'public_id': 'pub_promoted_demo',
      'backlinks': [revokedJson],
      'outbound': [
        {
          'kind': 'slug',
          'value': 'live-target',
          'state': 'live',
          'target_public_id': 'pub_live_target',
          'title': 'A live document',
        },
        {
          'kind': 'slug',
          'value': 'old-name',
          'state': 'redirected',
          'target_public_id': 'pub_forward_target',
          'title': null,
        },
        {'kind': 'slug', 'value': 'dead-name', 'state': 'retired'},
        {'kind': 'public_id', 'value': 'pub_gone', 'state': 'revoked'},
        {'kind': 'slug', 'value': 'never-claimed', 'state': 'missing'},
      ],
    });
    _check('parses without throwing', true);
    _check('backlinks parse as listing rows', graph.backlinks.length == 1);
    _check('outbound preserves authored order', graph.outbound.length == 5);
    _check(
      'nullable target_public_id survives on a broken link',
      graph.outbound[2].targetPublicId == null,
    );
    _check('three dead links are counted as broken', graph.brokenCount == 3);
    _check(
      'a redirect is stale, not broken',
      !graph.outbound[1].isBroken && graph.outbound[1].canOpen,
    );
    _check('a retired slug is repairable', graph.outbound[2].canRepairSlug);
    _check(
      'a missing name is broken but not repairable',
      graph.outbound[4].isBroken && !graph.outbound[4].canRepairSlug,
    );
    _check('a /d/ link is never repairable', !graph.outbound[3].canRepairSlug);
    _check(
      'an unrecognised state degrades to unknown and reads as healthy',
      LinkState.fromWire('a-state-from-the-future') == LinkState.unknown &&
          !LinkState.unknown.isBroken,
    );
  } catch (e) {
    _check('parses without throwing', false, '$e');
  }

  // --- 3c. Fixture: the change feed's kind derivation ------------------------
  //
  // `updated_at` vs `current_version_at` is the only evidence a row carries
  // about WHAT changed, and the contract warns the two are stamped by different
  // statements of one D1 batch — so a pure content write can leave them a
  // millisecond apart in EITHER direction. This pins the tolerance behaviour at
  // the JSON layer (where the timestamps arrive as strings the generator types
  // into DateTime) rather than only in the hermetic unit test.
  stdout.writeln('\nChange-feed fixture (updated_at vs current_version_at):');
  try {
    DocumentListing row(String updatedAt, String? versionAt) =>
        DocumentListing.fromJson({
          'public_id': 'pub_change_demo',
          'created_at': '2026-01-04T10:00:00.000Z',
          'updated_at': updatedAt,
          'current_version_at': versionAt,
          'current_ver': 3,
          'created_by_kind': 'operator',
          'tags': <String>[],
          'status': 'active',
          'visibility': 'public',
        });

    // Retagged eight days after the last write: no version was bumped, so this
    // is precisely the change nothing else in the app can see.
    final reclassified = row(
      '2026-07-20T15:00:00.000Z',
      '2026-07-12T09:00:00.000Z',
    );
    // The same batch, two statements, 40ms apart the "wrong" way.
    final written = row('2026-07-20T15:00:00.000Z', '2026-07-20T15:00:00.040Z');
    final revoked = DocumentListing.fromJson(revokedJson);

    _check('parses without throwing', true);
    _check(
      'a retag long after the write is proven classification-only',
      reclassified.changeKind == ChangeKind.classification &&
          reclassified.isClassificationOnlyChange,
    );
    _check(
      'sub-second batch skew still reads as a content write',
      written.changeKind == ChangeKind.content,
    );
    _check(
      'a revoked row is a revoke, not an unknown',
      revoked.changeKind == ChangeKind.revoked,
    );
    _check(
      'updated_since is emitted as a UTC instant',
      ChangeWindow.day.updatedSince(DateTime.utc(2026, 7, 25, 18, 30))! ==
          '2026-07-24T18:30:00.000Z',
    );
    _check(
      'the all window omits updated_since entirely',
      ChangeWindow.all.updatedSince(DateTime.utc(2026, 7, 25)) == null,
    );
  } catch (e) {
    _check('parses without throwing', false, '$e');
  }

  // --- 4. Live: GET /healthz (public) ----------------------------------------
  stdout.writeln('\nLive GET /healthz (public):');
  try {
    final res = await dio.get('/healthz');
    _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
    final health = HealthzResponse.fromJson(
      Map<String, dynamic>.from(res.data as Map),
    );
    _check('HealthzResponse.ok == true', health.ok == true);
    _check(
      'sanitizerVersion present',
      health.sanitizerVersion.isNotEmpty,
      health.sanitizerVersion,
    );
    _check(
      'storageCapBytes parsed (> 0)',
      health.storageCapBytes > 0,
      '${health.storageCapBytes}',
    );
    _check(
      'd1/r2 nested objects parsed',
      health.r2.bucketReachable == true || health.r2.bucketReachable == false,
    );
  } catch (e) {
    _check('healthz reachable + parses', false, '$e');
  }

  // --- 5. Live: unauthenticated admin call -> ErrorBody envelope -------------
  stdout.writeln('\nLive GET /admin/agents without auth (error envelope):');
  try {
    final res = await dio.get('/admin/agents');
    final err = ApiError.fromResponse(res.statusCode, res.data);
    _check('HTTP 401', res.statusCode == 401, '${res.statusCode}');
    _check(
      'ErrorCode.unauthorized resolved from envelope',
      err.code == ErrorCode.unauthorized,
      'code=${err.code.wire.isEmpty ? "unknown" : err.code.wire}',
    );
    _check('carries a server message', err.message != null, err.message);
  } catch (e) {
    _check('admin/agents reachable', false, '$e');
  }

  // --- 6. Live (optional, authenticated): list -> search ---------------------
  if (token != null && token.isNotEmpty) {
    final auth = Options(headers: {'Authorization': 'Bearer $token'});
    stdout.writeln('\nLive authenticated GET /admin/documents:');
    try {
      final res = await dio.get(
        '/admin/documents',
        queryParameters: {'limit': 50},
        options: auth,
      );
      _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
      final list = ListDocumentsResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      _check('parsed ${list.documents.length} documents', true);
      final revoked = list.documents.where((d) => d.isRevoked).toList();
      _check(
        'revoked docs (if any) parsed with null ver/slug',
        revoked.every((d) => d.currentVer == null && d.slug == null),
        '${revoked.length} revoked',
      );
    } catch (e) {
      _check('list parses', false, '$e');
    }

    stdout.writeln('\nLive authenticated GET /admin/documents/search:');
    try {
      final res = await dio.get(
        '/admin/documents/search',
        queryParameters: {'q': 'a', 'limit': 50},
        options: auth,
      );
      _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
      final hits = SearchDocumentsResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      _check('parsed ${hits.documents.length} search hits', true);
    } catch (e) {
      _check('search parses', false, '$e');
    }

    // The change feed, including the one rule the client's whole pagination
    // design is built around: a cursor carries the ordering that minted it, and
    // replaying it under the other ordering is a hard 400 bad_cursor rather than
    // a silent re-sort. Read-only — a 400 here costs nothing and proves the trap
    // is still armed on the server side.
    stdout.writeln('\nLive authenticated change feed (?order=updated):');
    try {
      final res = await dio.get(
        '/admin/documents',
        queryParameters: {'limit': 5, 'order': DocumentOrder.updated.wire},
        options: auth,
      );
      _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
      final feed = ListDocumentsResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      _check('parsed ${feed.documents.length} changed documents', true);

      final stamps = feed.documents.map((d) => d.updatedAt).toList();
      _check(
        'rows arrive most-recently-changed first',
        List.generate(
          stamps.length - 1 < 0 ? 0 : stamps.length - 1,
          (i) => !stamps[i].isBefore(stamps[i + 1]),
        ).every((ok) => ok),
      );

      // NOT "every row resolves to a kind" — that is a tautology (unknown is
      // defined as a null current_version_at), so it could never fail. The real
      // risk is prod dropping `current_version_at` from live rows, which would
      // silently turn every badge in the feed into nothing at all. Per the
      // contract that field is null only on a revoked document.
      final unclassifiable = feed.documents
          .where((d) => !d.isRevoked && d.currentVersionAt == null)
          .length;
      final kinds = feed.documents.map((d) => d.changeKind).toSet();
      _check(
        'live rows carry current_version_at (only revoked rows may omit it)',
        unclassifiable == 0,
        unclassifiable > 0
            ? '$unclassifiable live rows would badge as unknown'
            : kinds.map((k) => k.name).join(', '),
      );

      // Replay this walk's cursor under the DEFAULT ordering. The contract says
      // this must be rejected; if it ever silently succeeds, the client's
      // separate-state design is guarding against something that no longer
      // exists and the change should be noticed here first.
      final cursor = feed.nextCursor;
      if (cursor == null || cursor.isEmpty) {
        stdout.writeln(
          '  ~ corpus fits in one page; cursor rule not exercised',
        );
      } else {
        final replay = await dio.get(
          '/admin/documents',
          queryParameters: {'limit': 5, 'cursor': cursor},
          options: auth,
        );
        _check(
          'an updated-ordered cursor is REJECTED under the default ordering',
          replay.statusCode == 400 &&
              ApiError.fromResponse(replay.statusCode, replay.data).code ==
                  ErrorCode.badCursor,
          'HTTP ${replay.statusCode}',
        );
      }
    } catch (e) {
      _check('change feed parses', false, '$e');
    }

    // Contract 2.2.0's review-queue filter. Read-only, so safe against prod.
    //
    // The valuable check is the last one. The server defines `pending` as
    // `published_ver IS NOT current_ver`, and NULL is distinct from any version
    // number, so a public document that was NEVER promoted should satisfy it —
    // but such a document is not gated at all (by the 2.0.0 serving rule it
    // already serves its head), so it must not reach the queue. The spec's
    // wording leaves it ambiguous whether the backend special-cases this. Rather
    // than assert one reading, this REPORTS how many rows the client filter
    // drops, which answers the question against live data every time it runs.
    stdout.writeln(
      '\nLive authenticated review queue '
      '(?visibility=public&publication=pending):',
    );
    try {
      final res = await dio.get(
        '/admin/documents',
        queryParameters: {
          'limit': 200,
          'visibility': VisibilityFilter.public.wire,
          'publication': PublicationFilter.pending.wire,
          'order': DocumentOrder.updated.wire,
        },
        options: auth,
      );
      _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
      final page = ListDocumentsResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      _check('parsed ${page.documents.length} candidate rows', true);

      // The filter's own guarantees, asserted rather than assumed.
      _check(
        'every row is public',
        page.documents.every((d) => d.visibility == 'public'),
      );
      _check(
        'no revoked row matches (revoke nulls both pointers)',
        page.documents.every((d) => !d.isRevoked),
      );
      _check(
        'no row is already fully published',
        page.documents.every((d) => d.publishedVer != d.currentVer),
      );

      final queue = reviewQueueFrom(page.documents);
      _check(
        'every queued row has proven withheld work',
        queue.every((d) => d.isAwaitingReview),
      );

      // Does the server's `pending` admit a NEVER-PROMOTED public document?
      //
      // "the client filter dropped nothing" cannot answer this on its own: it
      // is equally consistent with the server excluding such rows and with the
      // corpus simply not containing any. So fetch every public document and
      // find out whether the discriminating case even exists before drawing a
      // conclusion from its absence.
      final allPublicRes = await dio.get(
        '/admin/documents',
        queryParameters: {
          'limit': 200,
          'visibility': VisibilityFilter.public.wire,
        },
        options: auth,
      );
      final allPublic = ListDocumentsResponse.fromJson(
        Map<String, dynamic>.from(allPublicRes.data as Map),
      ).documents;
      final neverPromoted = allPublic
          .where((d) => !d.isRevoked && d.publishedVer == null)
          .toList();
      final pendingIds = page.documents.map((d) => d.publicId).toSet();
      final neverPromotedInPending = neverPromoted
          .where((d) => pendingIds.contains(d.publicId))
          .length;

      stdout.writeln(
        '  ~ ${allPublic.length} public docs; ${neverPromoted.length} never '
        'promoted; client filter keeps ${queue.length} of '
        '${page.documents.length} pending rows',
      );
      if (neverPromoted.isEmpty) {
        // Not a failure — there is simply nothing in the corpus that could tell
        // the two readings apart today. Said out loud so a clean run is never
        // mistaken for evidence that the client filter is redundant.
        stdout.writeln(
          '  ~ INCONCLUSIVE: no never-promoted public document exists, so this '
          'run cannot tell whether the server\'s `pending` would admit one. '
          'The client filter stays either way.',
        );
      } else if (neverPromotedInPending > 0) {
        stdout.writeln(
          '  ~ ANSWERED: the server\'s `pending` DOES admit never-promoted '
          'public docs ($neverPromotedInPending of ${neverPromoted.length} '
          'present in the result). The client filter is LOAD-BEARING — without '
          'it the queue would show ungated documents.',
        );
      } else {
        stdout.writeln(
          '  ~ ANSWERED: the server excludes never-promoted public docs '
          '(${neverPromoted.length} exist, none returned). The client filter is '
          'belt-and-braces here, and still correct.',
        );
      }
      // Whichever way that fell, this must hold: a document the gate is not
      // withholding anything on must never reach the queue.
      _check(
        'no never-promoted public document reaches the queue',
        queue.every((d) => d.publishedVer != null),
      );

      // Gotcha #3: an unrecognised value is a plain 400 bad_request, not a
      // dedicated code and not a silent fallback to unfiltered. If it ever
      // degraded to the latter, the queue would quietly become the whole
      // corpus again and nothing else here would notice.
      final bogus = await dio.get(
        '/admin/documents',
        queryParameters: {'limit': 1, 'publication': 'nonsense'},
        options: auth,
      );
      _check(
        'an unknown publication value is REJECTED, not ignored',
        bogus.statusCode == 400 &&
            ApiError.fromResponse(bogus.statusCode, bogus.data).code ==
                ErrorCode.badRequest,
        'HTTP ${bogus.statusCode}',
      );
    } catch (e) {
      _check('review queue parses', false, '$e');
    }

    // Read-only halves of the link graph. The backfill sweep and the three slug
    // mutators are deliberately NOT exercised here: this script runs against
    // prod, and every one of them writes.
    stdout.writeln('\nLive authenticated GET /admin/links/orphans:');
    try {
      final res = await dio.get('/admin/links/orphans', options: auth);
      _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
      final orphans = OrphanDocumentsResponse.fromJson(
        Map<String, dynamic>.from(res.data as Map),
      );
      _check('parsed ${orphans.documents.length} orphans', true);
      _check(
        'orphan rows are live documents',
        orphans.documents.every((d) => !d.isRevoked),
      );
    } catch (e) {
      _check('orphans parses', false, '$e');
    }

    stdout.writeln('\nLive authenticated GET /d/:id/links:');
    try {
      final listRes = await dio.get(
        '/admin/documents',
        queryParameters: {'limit': 50},
        options: auth,
      );
      final live = ListDocumentsResponse.fromJson(
        Map<String, dynamic>.from(listRes.data as Map),
      ).documents.where((d) => !d.isRevoked).toList();

      if (live.isEmpty) {
        stdout.writeln('  (no live document to probe)');
      } else {
        final res = await dio.get(
          '/d/${live.first.publicId}/links',
          options: auth,
        );
        _check('HTTP 200', res.statusCode == 200, '${res.statusCode}');
        final graph = DocumentLinksResponse.fromJson(
          Map<String, dynamic>.from(res.data as Map),
        );
        _check(
          'graph is for the document we asked about',
          graph.publicId == live.first.publicId,
        );
        _check(
          'parsed ${graph.backlinks.length} backlinks, '
          '${graph.outbound.length} outbound (${graph.brokenCount} broken)',
          true,
        );
        // The forward-compat guarantee, checked against whatever prod actually
        // sends: an unrecognised state would silently read as healthy, so this
        // fails loudly instead if the contract grew one.
        final unknowns = graph.outbound
            .where((l) => l.linkState == LinkState.unknown)
            .map((l) => l.state)
            .toSet();
        _check(
          'every outbound state is one this build knows',
          unknowns.isEmpty,
          unknowns.isEmpty ? null : 'unrecognised: ${unknowns.join(", ")}',
        );
      }
    } catch (e) {
      _check('links parses', false, '$e');
    }
  } else {
    stdout.writeln(
      '\n(skipping authenticated list/search/link-graph — set OPERATOR_TOKEN '
      'to enable)',
    );
  }

  stdout.writeln('');
  if (_failures == 0) {
    stdout.writeln('All smoke checks passed.');
  } else {
    stdout.writeln('$_failures smoke check(s) FAILED.');
    exit(1);
  }
}
