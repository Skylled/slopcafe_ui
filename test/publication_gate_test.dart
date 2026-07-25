// Unit + render tests for contract 2.0.0's publication gate.
//
// From 2.0.0 the backend serves the HTML byte path (GET /d/:id/raw, GET
// /s/:slug) by the rule
//
//     served = (visibility == 'public' && published_ver != null)
//         ? published_ver
//         : current_ver
//
// so the version this app wrote is no longer necessarily the version anyone
// reading the document receives. Two things have to hold for that not to become
// a silent lie: version resolution off a response's headers has to answer
// "which version is CURRENT" and "which version was SERVED" separately, and the
// listing surfaces have to say out loud when those two numbers disagree.
//
// Everything here is hermetic — the header cases build a dio [Headers]/[Response]
// directly rather than going over the wire, because what is under test is the
// resolver, not HTTP.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/publication.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/widgets/doc_feed_card.dart';

Headers _headers(Map<String, String> values) => Headers.fromMap({
  for (final entry in values.entries) entry.key: [entry.value],
});

/// A 304 carries no body, so the only thing it can tell us is what its headers
/// say — which is exactly why the resolver has to work off a [Response] that
/// never had one.
Response<void> _notModified(Map<String, String> values) => Response<void>(
  requestOptions: RequestOptions(path: '/d/abcdefghijklmnopqrstuv/raw'),
  statusCode: 304,
  headers: _headers(values),
);

/// A listing row with the publication fields under our control. `updatedAt` is
/// later than `currentVersionAt` throughout: promoting or retagging a document
/// touches the row without writing a new version, which is the ordinary shape
/// of a document that has something sitting behind the gate.
DocumentListing _listing({
  required String visibility,
  int? currentVer,
  int? publishedVer,
}) => DocumentListing(
  publicId: 'abcdefghijklmnopqrstuv',
  createdAt: DateTime(2026, 5, 1),
  currentVersionAt: DateTime(2026, 6, 2),
  updatedAt: DateTime(2026, 6, 9),
  createdByKind: 'agent',
  createdByName: 'test agent',
  tags: const [],
  status: 'active',
  visibility: visibility,
  currentVer: currentVer,
  publishedVer: publishedVer,
  title: 'Test document',
);

Widget _harness(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('preflight resolution', () {
    // The whole point of x-doc-current-version: on a promoted public document
    // the ETag names the OLDER, published version, and a write built from it
    // would either fail confusingly or — worse, against a server that compares
    // loosely — clobber the newer head. The header wins.
    test('current-version header beats the ETag it disagrees with', () {
      final headers = _headers({'ETag': '"v4"', 'x-doc-current-version': '7'});

      expect(resolveCurrentVersion(headers), 7);
      expect(ifMatchFor(headers), 'v7');
      // The served version is the other number, and stays the other number.
      expect(resolveServedVersion(headers), 4);
    });

    // The ETag fallback is correct behaviour, not an error path: the header is
    // absent for an anonymous caller and on any pre-2.0.0 server, and in both
    // of those the ETag *is* the current version. This must not throw and must
    // not return null.
    test('falls back to the ETag when the header is absent', () {
      final headers = _headers({'ETag': '"v5"'});

      expect(resolveCurrentVersion(headers), 5);
      expect(ifMatchFor(headers), 'v5');
      expect(resolveServedVersion(headers), 5);
    });

    // A conditional request that validates still tells us where the head is,
    // so the resolver has to read a 304's headers as readily as a 200's —
    // otherwise every cache hit silently loses the version.
    test('reads the current-version header off a 304', () {
      final response = _notModified({
        'ETag': 'W/"v4"',
        'x-doc-current-version': '7',
      });

      expect(response.statusCode, 304);
      expect(resolveCurrentVersion(response.headers), 7);
      expect(ifMatchFor(response.headers), 'v7');
      expect(resolveServedVersion(response.headers), 4);
    });

    // Cloudflare weakens the ETag whenever it gzips the body, which it does
    // routinely for HTML, so the strong form does not survive the edge and
    // nothing may depend on it.
    test('parses a weak ETag', () {
      expect(parseVersionTag('W/"v7"'), 7);
      expect(resolveServedVersion(_headers({'ETag': 'W/"v7"'})), 7);
      // The If-Match we emit is normalised back to the strong form: the value
      // we send is ours, and it should not depend on the edge's compression.
      expect(ifMatchFor(_headers({'ETag': 'W/"v7"'})), 'v7');
    });

    test('parses every shape the byte path can hand us', () {
      expect(parseVersionTag('"v7"'), 7);
      expect(parseVersionTag('v7'), 7);
      expect(parseVersionTag('7'), 7);
      expect(parseVersionTag('W/"v7"'), 7);
      expect(parseVersionTag('  "v7" '), 7);
    });

    // A wrong version is worse than no version: no version degrades to a
    // visible unknown, while a salvaged one silently mislabels the document or
    // sends an If-Match that overwrites somebody's work.
    test('returns null rather than guessing at a malformed value', () {
      expect(parseVersionTag(null), isNull);
      expect(parseVersionTag(''), isNull);
      expect(parseVersionTag('   '), isNull);
      expect(parseVersionTag('version 7'), isNull);
      expect(parseVersionTag('v'), isNull);
      expect(parseVersionTag('v7-gzip'), isNull);
      expect(parseVersionTag('"v7'), isNull);
      expect(parseVersionTag('vv7'), isNull);
    });

    test('no resolvable version means no If-Match at all', () {
      final headers = _headers({'Content-Type': 'text/html'});

      expect(resolveCurrentVersion(headers), isNull);
      expect(resolveServedVersion(headers), isNull);
      expect(ifMatchFor(headers), isNull);
    });
  });

  group('the serving rule on a listing row', () {
    // The display case: the admin list reports current_ver, so the row names a
    // version nobody is being served. The UI must not present /raw's bytes as
    // current.
    test('public + promoted serves the published version', () {
      final doc = _listing(
        visibility: 'public',
        currentVer: 8,
        publishedVer: 4,
      );

      expect(doc.isPublic, isTrue);
      expect(doc.servedVer, 4);
      expect(doc.hasUnpublishedWork, isTrue);
    });

    // Private documents always serve current: there is no anonymous reader for
    // the gate to hold fresh bytes back from, so the same two numbers mean
    // nothing is being withheld.
    test('private serves current whatever published_ver says', () {
      final doc = _listing(
        visibility: 'private',
        currentVer: 8,
        publishedVer: 4,
      );

      expect(doc.isPublic, isFalse);
      expect(doc.servedVer, 8);
      expect(doc.hasUnpublishedWork, isFalse);
    });

    // A null published_ver means nothing was ever promoted, so the gate was
    // never closed and the rule falls through to current.
    test('public + never promoted serves current', () {
      final doc = _listing(
        visibility: 'public',
        currentVer: 8,
        publishedVer: null,
      );

      expect(doc.servedVer, 8);
      expect(doc.hasUnpublishedWork, isFalse);
    });

    // hasUnpublishedWork reports PROVEN divergence. Equal numbers are the
    // published-and-current case, and a missing current_ver (a revoked
    // document) leaves nothing to compare against — badging either would put
    // "unpublished changes" on a document that has none.
    test('reports no unpublished work without proven divergence', () {
      expect(
        _listing(
          visibility: 'public',
          currentVer: 4,
          publishedVer: 4,
        ).hasUnpublishedWork,
        isFalse,
      );
      expect(
        _listing(
          visibility: 'public',
          currentVer: null,
          publishedVer: 4,
        ).hasUnpublishedWork,
        isFalse,
      );
      expect(
        _listing(
          visibility: 'public',
          currentVer: null,
          publishedVer: 4,
        ).servedVer,
        4,
      );
    });

    // A search hit is the same row in a different envelope, and the offline
    // fallback rebuilds one from a listing, so the two numbers have to survive
    // both directions or the gate silently opens on the search screen.
    test('a search hit carries the gate through .document', () {
      final hit = SearchHit.fromDocument(
        _listing(visibility: 'public', currentVer: 8, publishedVer: 4),
        score: 1.5,
        matchedField: 'title',
        snippet: 'hello [world]',
      );

      expect(hit.publishedVer, 4);
      expect(hit.document.servedVer, 4);
      expect(hit.document.hasUnpublishedWork, isTrue);
    });
  });

  group('the gate as the operator sees it', () {
    testWidgets('a listing row with unpublished work is marked NOT LIVE', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          DocFeedCard(
            doc: _listing(visibility: 'public', currentVer: 8, publishedVer: 4),
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotLiveBadge), findsOneWidget);
      expect(find.text('NOT LIVE'), findsOneWidget);
      // The row still names the head — the badge qualifies that number, it does
      // not replace it.
      expect(find.text('v8'), findsOneWidget);
    });

    testWidgets('a fully published row carries no marker', (tester) async {
      await tester.pumpWidget(
        _harness(
          DocFeedCard(
            doc: _listing(visibility: 'public', currentVer: 8, publishedVer: 8),
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotLiveBadge), findsNothing);
    });

    testWidgets('a private row carries no marker', (tester) async {
      await tester.pumpWidget(
        _harness(
          DocFeedCard(
            doc: _listing(
              visibility: 'private',
              currentVer: 8,
              publishedVer: 4,
            ),
            onOpen: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NotLiveBadge), findsNothing);
    });
  });
}
