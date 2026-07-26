// Unit + render tests for the corpus change feed
// (GET /admin/documents?order=updated&updated_since=…).
//
// The feed exists for one reason: a classification edit — retag, rename,
// visibility flip, status change, publish — stamps `updated_at` and writes NO
// new version, so every version-based check in the app is blind to it. Two
// things carry the feature, and both are quiet failures rather than loud ones:
//
//   - THE CHANGE-KIND DERIVATION. `updated_at` vs `current_version_at` is the
//     only evidence a row carries about WHAT changed. The contract is explicit
//     that the two columns are stamped by different statements of one D1 batch
//     and can land a millisecond apart EITHER WAY on a pure content write. Two
//     independent things therefore have to be right, and a test that only
//     exercises millisecond skew pins just the first: the TOLERANCE (which
//     absorbs the batch skew in both directions) and the SIGN (only `updated_at`
//     running AHEAD proves a classification edit). Get the tolerance wrong and
//     ordinary writes are badged "RECLASSIFIED"; get the sign wrong and so are
//     anomalous rows the badge has no evidence about.
//   - THE WINDOW. `updated_since` is INCLUSIVE by contract, and the value is a
//     UTC instant — a local-time stamp would silently shift the window by the
//     machine's offset.
//
// Everything here is hermetic: rows are built as `DocumentListing` values
// directly, because what is under test is the vocabulary, not HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/changes.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/widgets/pill.dart';

DocumentListing _row({
  required DateTime updatedAt,
  DateTime? currentVersionAt,
  DateTime? revokedAt,
  int? currentVer = 3,
}) => DocumentListing(
  publicId: 'AAAAAAAAAAAAAAAAAAAAAA',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: updatedAt,
  currentVersionAt: currentVersionAt,
  revokedAt: revokedAt,
  currentVer: currentVer,
  createdByKind: 'operator',
  tags: const ['notes'],
  status: 'active',
  visibility: 'public',
  title: 'A document',
);

Widget _harness(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('DocumentOrder', () {
    test('sends the wire values the contract enumerates', () {
      // A typo here is a 400 bad_request, not a silent fallback.
      expect(DocumentOrder.created.wire, 'created');
      expect(DocumentOrder.updated.wire, 'updated');
    });
  });

  group('changeKind', () {
    test('a revoke dominates, even with the timestamps of a content write', () {
      // Revoke clears the current_* fields and stamps updated_at, so nothing
      // else about the row is comparable afterwards.
      final doc = _row(
        updatedAt: DateTime.utc(2026, 7, 20, 12),
        currentVersionAt: DateTime.utc(2026, 7, 20, 12),
        revokedAt: DateTime.utc(2026, 7, 20, 12),
        currentVer: null,
      );
      expect(doc.changeKind, ChangeKind.revoked);
      expect(doc.isClassificationOnlyChange, isFalse);
    });

    test('identical timestamps read as a content write', () {
      final at = DateTime.utc(2026, 7, 20, 12);
      expect(
        _row(updatedAt: at, currentVersionAt: at).changeKind,
        ChangeKind.content,
      );
    });

    test(
      'sub-second batch skew reads as a content write in EITHER direction',
      () {
        // The contract: the two columns are "stamped by different statements of
        // one D1 batch, so a pure content write can leave them a millisecond
        // apart either way". Note this pair alone does NOT pin the sign of the
        // comparison — ±40ms is 50x inside the tolerance, so it passes under a
        // signed test, an absolute-difference test and a sign-inverted one
        // alike. The sign is pinned by the test below.
        final base = DateTime.utc(2026, 7, 20, 12);
        expect(
          _row(
            updatedAt: base.add(const Duration(milliseconds: 40)),
            currentVersionAt: base,
          ).changeKind,
          ChangeKind.content,
        );
        expect(
          _row(
            updatedAt: base,
            currentVersionAt: base.add(const Duration(milliseconds: 40)),
          ).changeKind,
          ChangeKind.content,
        );
      },
    );

    test(
      'the comparison is SIGNED: a backwards drift is never a reclassification',
      () {
        // The discriminating input, and the reason it has to exist: swapping the
        // implementation to `drift.abs() > writeSkewTolerance` — which an earlier
        // draft of this module's own doc comment wrongly prescribed — leaves every
        // other test in this file green while flipping this row's badge.
        //
        // Only `updated_at` running AHEAD of the write proves a classification
        // edit, because a classification edit is by definition something that
        // happened after the last write. `current_version_at` ahead of
        // `updated_at` is an anomaly no ordinary operation produces, and calling
        // it a reclassification would assert something the row does not show.
        final base = DateTime.utc(2026, 7, 20, 12);
        expect(
          _row(
            updatedAt: base,
            currentVersionAt: base.add(const Duration(hours: 1)),
          ).changeKind,
          ChangeKind.content,
        );
      },
    );

    test('updated_at well ahead of the write proves a classification edit', () {
      // A content write always stamps BOTH columns, so anything that moved
      // updated_at after the current version's bytes were written was
      // necessarily not a content write. This is a deduction, not a guess.
      final doc = _row(
        updatedAt: DateTime.utc(2026, 7, 20, 15),
        currentVersionAt: DateTime.utc(2026, 7, 12, 9),
      );
      expect(doc.changeKind, ChangeKind.classification);
      expect(doc.isClassificationOnlyChange, isTrue);
    });

    test('the tolerance boundary resolves to content, not classification', () {
      // The safe direction: under-reporting a reclassification made seconds
      // after a write is invisible, whereas calling an ordinary write a
      // reclassification sends the operator hunting for a phantom edit.
      final base = DateTime.utc(2026, 7, 20, 12);
      expect(
        _row(
          updatedAt: base.add(DocumentChange.writeSkewTolerance),
          currentVersionAt: base,
        ).changeKind,
        ChangeKind.content,
      );
      expect(
        _row(
          updatedAt: base.add(
            DocumentChange.writeSkewTolerance + const Duration(seconds: 1),
          ),
          currentVersionAt: base,
        ).changeKind,
        ChangeKind.classification,
      );
    });

    test('a null current_version_at is unknown, never a guess', () {
      final doc = _row(
        updatedAt: DateTime.utc(2026, 7, 20),
        currentVersionAt: null,
      );
      expect(doc.changeKind, ChangeKind.unknown);
      expect(doc.isClassificationOnlyChange, isFalse);
    });
  });

  group('ChangeWindow', () {
    final now = DateTime.utc(2026, 7, 25, 18, 30);

    test('all omits updated_since entirely', () {
      // Not a very old timestamp — the parameter must be absent, or the walk
      // silently stops being "the whole corpus".
      expect(ChangeWindow.all.span, isNull);
      expect(ChangeWindow.all.updatedSince(now), isNull);
    });

    test('presets subtract their span', () {
      expect(
        ChangeWindow.day.updatedSince(now),
        DateTime.utc(2026, 7, 24, 18, 30).toIso8601String(),
      );
      expect(
        ChangeWindow.week.updatedSince(now),
        DateTime.utc(2026, 7, 18, 18, 30).toIso8601String(),
      );
      expect(
        ChangeWindow.month.updatedSince(now),
        DateTime.utc(2026, 6, 25, 18, 30).toIso8601String(),
      );
    });

    test('emits a UTC instant regardless of the caller\'s local offset', () {
      // A local-time stamp would shift the window by the machine's offset —
      // silently wrong rather than rejected, since the server parses it fine.
      final local = DateTime.utc(2026, 7, 25, 18, 30).toLocal();
      final since = ChangeWindow.day.updatedSince(local)!;
      expect(since, endsWith('Z'));
      expect(DateTime.parse(since).isUtc, isTrue);
      expect(DateTime.parse(since), DateTime.utc(2026, 7, 24, 18, 30));
    });
  });

  group('ChangeKindBadge', () {
    testWidgets('badges a reclassification and an ordinary write differently', (
      tester,
    ) async {
      await tester.pumpWidget(
        _harness(
          Column(
            children: [
              ChangeKindBadge(
                doc: _row(
                  updatedAt: DateTime.utc(2026, 7, 20, 15),
                  currentVersionAt: DateTime.utc(2026, 7, 12),
                ),
              ),
              ChangeKindBadge(
                doc: _row(
                  updatedAt: DateTime.utc(2026, 7, 20, 15),
                  currentVersionAt: DateTime.utc(2026, 7, 20, 15),
                ),
              ),
            ],
          ),
        ),
      );
      expect(find.text('RECLASSIFIED'), findsOneWidget);
      // Not "REWRITTEN": a first authoring lands on ChangeKind.content too, and
      // its own current_ver of 1 would contradict the stronger word.
      expect(find.text('NEW VERSION'), findsOneWidget);
    });

    testWidgets(
      'renders NOTHING for a revoked row, which the card already marks',
      (tester) async {
        // The kind is correct in the model; repeating it here would print the
        // identical red REVOKED pill twice in one row block, since every surface
        // showing a revoked document already carries one.
        final doc = _row(
          updatedAt: DateTime.utc(2026, 7, 20),
          currentVersionAt: null,
          revokedAt: DateTime.utc(2026, 7, 20),
          currentVer: null,
        );
        expect(doc.changeKind, ChangeKind.revoked);
        expect(ChangeKindBadge.showsFor(doc), isFalse);
        await tester.pumpWidget(_harness(ChangeKindBadge(doc: doc)));
        expect(find.byType(Pill), findsNothing);
      },
    );

    testWidgets('renders NOTHING when the row does not say', (tester) async {
      // An "UNKNOWN" pill would dress the absence of information up as a
      // finding. The row's timestamp still reports when it changed.
      final doc = _row(
        updatedAt: DateTime.utc(2026, 7, 20),
        currentVersionAt: null,
      );
      expect(ChangeKindBadge.showsFor(doc), isFalse);
      await tester.pumpWidget(_harness(ChangeKindBadge(doc: doc)));
      expect(find.byType(Pill), findsNothing);
    });
  });
}
