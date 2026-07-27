// Unit tests for the review queue — the operator-facing side of contract
// 2.0.0's publication gate.
//
// The queue exists because the gate is silent: a public document whose head sits
// behind `published_ver` looks entirely healthy on every listing surface, and
// nothing in the contract offers a server-side way to ask for the set of them.
// That makes three things the client's own responsibility, and all three are
// pinned here: which rows belong in the queue, what order they come in, and what
// the two versions on a row actually resolve to.
//
// Hermetic throughout — rows are built as `DocumentListing` values, the same way
// `publication_gate_test.dart` and `change_feed_test.dart` build theirs. What is
// under test is the derivation, not HTTP.

import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/review.dart';

/// A listing row with the fields the queue reasons about under our control.
///
/// `updatedAt` deliberately runs later than `currentVersionAt` by default:
/// promoting or retagging touches the row without writing a version, which is
/// the ordinary shape of a document with something waiting behind the gate — and
/// it is what makes the two clocks distinguishable in the ordering tests below.
DocumentListing _row({
  String publicId = 'abcdefghijklmnopqrstuv',
  String visibility = 'public',
  int? currentVer = 8,
  int? publishedVer = 4,
  DateTime? currentVersionAt,
  /// Set for a row with no `current_version_at` at all. A separate flag rather
  /// than passing null to [currentVersionAt], because that parameter defaults to
  /// a stamp and `??` cannot tell "unspecified" from "deliberately absent".
  bool noContentClock = false,
  DateTime? updatedAt,
  DateTime? revokedAt,
  String? currentSha,
  String? publishedSha,
}) => DocumentListing(
  publicId: publicId,
  createdAt: DateTime(2026, 5, 1),
  currentVersionAt: noContentClock
      ? null
      : (currentVersionAt ?? DateTime(2026, 6, 2)),
  updatedAt: updatedAt ?? DateTime(2026, 6, 9),
  revokedAt: revokedAt,
  createdByKind: 'agent',
  createdByName: 'test agent',
  tags: const [],
  status: 'active',
  visibility: visibility,
  currentVer: currentVer,
  publishedVer: publishedVer,
  currentSourceSha256: currentSha,
  publishedSourceSha256: publishedSha,
  title: 'Test document',
);

void main() {
  group('queue admission', () {
    test('a public document behind its head is awaiting review', () {
      expect(_row().isAwaitingReview, isTrue);
    });

    // A private document always serves `current_ver`, so its readers — such as
    // they are — already have the head. There is nothing withheld to approve,
    // even though a promote may well have staged a choice for later.
    test('a private document is never queued, whatever its numbers say', () {
      expect(_row(visibility: 'private').isAwaitingReview, isFalse);
    });

    // A null `published_ver` means the gate was never closed: the document
    // serves its head to everyone. Queueing it would invent work.
    test('a never-promoted public document is not queued', () {
      expect(_row(publishedVer: null).isAwaitingReview, isFalse);
    });

    test('a fully-published document is not queued', () {
      expect(_row(currentVer: 8, publishedVer: 8).isAwaitingReview, isFalse);
    });

    // The load-bearing exclusion. A queue entry promises two renderable
    // versions, and a revoked document's byte path is gone — the review it
    // offered could not be performed. Revoke also clears the current_* fields in
    // practice, so this row is doubly excluded; the assertion pins the intent
    // rather than the coincidence.
    test('a revoked document is never queued', () {
      final revoked = _row(revokedAt: DateTime(2026, 6, 10));
      expect(revoked.isAwaitingReview, isFalse);
    });

    test('a revoked document is excluded even with intact version numbers', () {
      // Constructed to defeat the incidental exclusion: both versions present
      // and diverging, public, and revoked. Only the explicit !isRevoked term
      // keeps this out of the queue.
      final row = _row(
        revokedAt: DateTime(2026, 6, 10),
        currentVer: 8,
        publishedVer: 4,
      );
      expect(row.hasUnpublishedWorkForTest, isTrue);
      expect(row.isAwaitingReview, isFalse);
    });
  });

  group('version resolution', () {
    test('live resolves to published_ver and latest to current_ver', () {
      final row = _row(currentVer: 8, publishedVer: 4);
      expect(row.versionFor(ReviewSide.live), 4);
      expect(row.versionFor(ReviewSide.latest), 8);
    });

    test('versionsAhead is the gap between the two numbers', () {
      expect(_row(currentVer: 8, publishedVer: 4).versionsAhead, 4);
      expect(_row(currentVer: 5, publishedVer: 4).versionsAhead, 1);
    });

    test('versionsAhead is null when either number is unknown', () {
      expect(_row(currentVer: null).versionsAhead, isNull);
      expect(_row(publishedVer: null).versionsAhead, isNull);
    });

    // Versions only count upwards — a restore appends a new head rather than
    // rewinding — so an inverted pair should be impossible. If one ever arrives,
    // reporting "-3 versions ahead" is worse than reporting none.
    test('versionsAhead never reports a negative gap', () {
      expect(_row(currentVer: 4, publishedVer: 8).versionsAhead, 0);
    });
  });

  group('pendingSince', () {
    // The content clock, not the touch clock. `current_version_at` is when the
    // head moved ahead of the pointer, i.e. when the document entered the queue;
    // `updated_at` also moves on a retag or a promote and would misdate it.
    test('prefers current_version_at over updated_at', () {
      final row = _row(
        currentVersionAt: DateTime(2026, 6, 2),
        updatedAt: DateTime(2026, 6, 9),
      );
      expect(row.pendingSince, DateTime(2026, 6, 2));
    });

    test('falls back to updated_at when there is no content clock', () {
      final row = _row(
        noContentClock: true,
        updatedAt: DateTime(2026, 6, 9),
      );
      expect(row.pendingSince, DateTime(2026, 6, 9));
    });
  });

  group('source comparison', () {
    test('matching hashes report identical', () {
      final row = _row(currentSha: 'abc123', publishedSha: 'abc123');
      expect(row.sourceComparison, SourceComparison.identical);
    });

    test('differing hashes report differs', () {
      final row = _row(currentSha: 'abc123', publishedSha: 'def456');
      expect(row.sourceComparison, SourceComparison.differs);
    });

    // A version written before source retention shipped carries no hash. "We
    // cannot tell" must not collapse into either answer — reporting `differs`
    // would put a spurious caution on the screen, and `identical` would tell the
    // operator they need not read the diff.
    test('a missing hash on either side reports unknown', () {
      expect(
        _row(currentSha: null, publishedSha: 'abc123').sourceComparison,
        SourceComparison.unknown,
      );
      expect(
        _row(currentSha: 'abc123', publishedSha: null).sourceComparison,
        SourceComparison.unknown,
      );
      expect(
        _row(currentSha: '', publishedSha: 'abc123').sourceComparison,
        SourceComparison.unknown,
      );
    });
  });

  group('reviewQueueFrom', () {
    test('keeps only the rows awaiting review', () {
      final rows = [
        _row(publicId: 'aaaaaaaaaaaaaaaaaaaaaa'),
        _row(publicId: 'bbbbbbbbbbbbbbbbbbbbbb', visibility: 'private'),
        _row(publicId: 'cccccccccccccccccccccc', publishedVer: null),
        _row(publicId: 'dddddddddddddddddddddd', currentVer: 3, publishedVer: 3),
      ];
      final queue = reviewQueueFrom(rows);
      expect(queue.map((d) => d.publicId), ['aaaaaaaaaaaaaaaaaaaaaa']);
    });

    test('orders by most recent pending work first', () {
      final rows = [
        _row(
          publicId: 'oldddddddddddddddddddd',
          currentVersionAt: DateTime(2026, 1, 1),
        ),
        _row(
          publicId: 'newwwwwwwwwwwwwwwwwwww',
          currentVersionAt: DateTime(2026, 7, 1),
        ),
        _row(
          publicId: 'midddddddddddddddddddd',
          currentVersionAt: DateTime(2026, 4, 1),
        ),
      ];
      expect(reviewQueueFrom(rows).map((d) => d.publicId), [
        'newwwwwwwwwwwwwwwwwwww',
        'midddddddddddddddddddd',
        'oldddddddddddddddddddd',
      ]);
    });

    // A document written during the sweep can legitimately be delivered twice by
    // an `updated`-ordered walk as its position shifts under the cursor. The
    // queue must not then show it twice.
    test('de-duplicates on public_id, first copy wins', () {
      final rows = [
        _row(publicId: 'aaaaaaaaaaaaaaaaaaaaaa', currentVer: 8),
        _row(publicId: 'aaaaaaaaaaaaaaaaaaaaaa', currentVer: 9),
      ];
      final queue = reviewQueueFrom(rows);
      expect(queue, hasLength(1));
      expect(queue.single.currentVer, 8);
    });

    test('an empty corpus yields an empty queue', () {
      expect(reviewQueueFrom(const <DocumentListing>[]), isEmpty);
    });
  });
}

/// Exposes the underlying gate predicate so the revoke test can assert that the
/// exclusion comes from [DocumentReview.isAwaitingReview]'s own `!isRevoked`
/// term rather than from the row failing the gate check for unrelated reasons.
extension on DocumentListing {
  bool get hasUnpublishedWorkForTest =>
      visibility == 'public' &&
      publishedVer != null &&
      currentVer != null &&
      publishedVer != currentVer;
}
