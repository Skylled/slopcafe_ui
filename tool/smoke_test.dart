// Live + fixture smoke test for the generated API layer.
//
// Validates that the generated models (lib/api/models.dart) and the ErrorCode
// envelope (lib/api/api_error.dart) correctly handle what the real backend
// sends, focusing on the OpenAPI-3.1 nullability risk (a revoked document has
// null current_ver/current_size/slug).
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
  final revokedJson = {
    'public_id': 'pub_revoked_demo',
    'current_ver': null,
    'created_at': '2026-01-02T03:04:05.000Z',
    'created_by_id': null,
    'created_by_name': null,
    'created_by_kind': 'agent',
    'current_size': null,
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
    _check('isRevoked == true', doc.isRevoked == true);
    _check('createdAt parsed to DateTime', doc.createdAt.year == 2026);
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

  // --- 3. Live: GET /healthz (public) ----------------------------------------
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

  // --- 4. Live: unauthenticated admin call -> ErrorBody envelope -------------
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

  // --- 5. Live (optional, authenticated): list -> search ---------------------
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
