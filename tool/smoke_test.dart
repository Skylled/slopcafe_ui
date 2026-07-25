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
import 'package:slopcafe_ui/core/publication.dart';

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
  } else {
    stdout.writeln(
      '\n(skipping authenticated list/search — set OPERATOR_TOKEN to enable)',
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
