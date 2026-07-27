/// The shared vocabulary for the **review queue** — the operator-facing
/// consequence of contract 2.0.0's publication gate.
///
/// The gate itself is spelled out in `publication.dart`: a public document with
/// a promoted `published_ver` serves those bytes to everyone, so an agent write
/// lands on `current_ver` and waits. This file answers the two questions that
/// creates for a human: *which documents are waiting*, and *what exactly would
/// change if I approved one*.
///
/// Like its three siblings (`publication.dart`, `links.dart`, `changes.dart`)
/// this module is hermetic — no Flutter imports, no `dio`, no providers — so the
/// rules below are testable without a widget tree or a network.
///
/// **Contract 2.2.0 added the server-side predicate this queue wants**:
/// `GET /admin/documents?visibility=public&publication=pending` (migrations 0011
/// and 0018). The provider no longer walks the corpus — it asks for the queue.
///
/// [reviewQueueFrom] survives that change and is still applied to the result,
/// which is deliberate rather than leftover. The server's `pending` is defined
/// as `published_ver IS NOT current_ver`, and that is **broader** than this
/// screen's question in one specific way: a NULL `published_ver` is distinct
/// from any version number, so a public document that was *never* promoted
/// satisfies the server's predicate. Such a document is not gated at all — by
/// the 2.0.0 serving rule it already serves its head to everyone — so it has no
/// withheld work to review and [DocumentReview.isAwaitingReview] excludes it.
/// (The spec's own wording is ambiguous on whether the backend special-cases
/// this for public documents; the client is correct either way, which is the
/// point of keeping the check.)
///
/// So the division of labour is: the **server narrows the fetch** from the whole
/// corpus to a handful of candidates, and the **client keeps the semantics**.
/// The filter costs one traversal of an already-small list and makes the screen
/// independent of how the backend chooses to read a null pointer.
library;

import '../api/api.dart';
import 'publication.dart';

/// The `?visibility=` filter on `GET /admin/documents` (migration 0011).
///
/// The wire strings are pinned in a test for the same reason [DocumentOrder]'s
/// are: an unrecognised value is a hard `400 bad_request`, never a silent
/// fallback to unfiltered, so a typo here would fail the whole screen rather
/// than quietly widen it.
enum VisibilityFilter {
  public,
  private;

  String get wire => switch (this) {
    VisibilityFilter.public => 'public',
    VisibilityFilter.private => 'private',
  };
}

/// The `?publication=` filter on `GET /admin/documents` (migration 0018).
///
/// `pending` is `published_ver IS NOT current_ver` — the document holds bytes
/// its published pointer does not name. `current` is the complement among
/// non-revoked rows: promoting would be a no-op.
///
/// **Revoked documents match neither value**, because revoke nulls both
/// pointers and the comparison stops being meaningful. That is a filter
/// property, not a client rule, so it does not replace
/// [DocumentReview.isAwaitingReview]'s own `!isRevoked` term — that term exists
/// to keep an unrenderable document out of the queue no matter where the rows
/// came from, including a hand-assembled list or a future caller that does not
/// pass this filter.
enum PublicationFilter {
  pending,
  current;

  String get wire => switch (this) {
    PublicationFilter.pending => 'pending',
    PublicationFilter.current => 'current',
  };
}

/// Which of a queued document's two versions a review pane is showing.
///
/// The pair is the whole point of the screen: [live] is what every reader —
/// including the anonymous internet — is being handed right now, [latest] is
/// what they would be handed if the operator approved. Both resolve to a
/// concrete version number via [DocumentReview.versionFor], and both are read
/// through the *same* pinned byte route (`/d/:id/v/:n/raw`) so that any
/// difference on screen is attributable to the content and never to the route.
enum ReviewSide {
  /// `published_ver` — the bytes the byte path serves today.
  live,

  /// `current_ver` — the document's head, withheld by the gate.
  latest,
}

/// Whether the two versions' retained source bytes are the same.
///
/// Derived from the `*_source_sha256` pair 2.0.0 added to every listing row, so
/// it costs no extra request. Deliberately three-valued rather than a bool: a
/// version written before source retention shipped carries a null hash, and
/// "we cannot tell" must not collapse into either answer.
enum SourceComparison {
  /// Both hashes are present and equal.
  identical,

  /// Both hashes are present and differ.
  differs,

  /// At least one hash is absent — nothing can be concluded.
  unknown,
}

/// The publication gate seen from the review queue's side.
extension DocumentReview on DocumentListing {
  /// Whether this row belongs in the review queue.
  ///
  /// [DocumentPublication.hasUnpublishedWork] is the substance of it — public,
  /// something was promoted, and it isn't the head. The extra `!isRevoked` term
  /// is not redundant defensiveness: a queue entry is a promise that two
  /// versions can be *rendered side by side*, and a revoked document's byte
  /// path is gone (`/d/:id/raw` answers 404/410, and `/links` 404s for the same
  /// reason the Reader gates its links row on this). Queueing one would offer a
  /// review that cannot be performed. Revoke also clears the `current_*` fields,
  /// so in practice `hasUnpublishedWork` is already false here — this states the
  /// intent rather than relying on that.
  bool get isAwaitingReview => !isRevoked && hasUnpublishedWork;

  /// When the work now waiting behind the gate was written.
  ///
  /// `current_version_at` is the last *content* write, which is exactly when the
  /// head moved ahead of the published pointer — i.e. when this document entered
  /// the queue. `updated_at` is the fallback and a deliberately weaker one: it
  /// is the last touch of any kind (retag, rename, visibility, status — and a
  /// promote), so it answers "when did anything happen" rather than "when did
  /// the pending work land". Only rows with a null `current_version_at` fall
  /// back to it, and those have no content clock to offer at all.
  DateTime get pendingSince => currentVersionAt ?? updatedAt;

  /// How many version numbers separate the head from what readers are served.
  ///
  /// Plain arithmetic on the two numbers, and it should be read that way: it
  /// counts version numbers, not review events or authors. Null unless both
  /// numbers are known. Never negative — `published_ver` always names a version
  /// that exists, and versions only count upwards (a restore appends a new head
  /// rather than rewinding), so the gap cannot invert; `clamp` states that
  /// rather than trusting it.
  int? get versionsAhead {
    final head = currentVer;
    final live = publishedVer;
    if (head == null || live == null) return null;
    return (head - live).clamp(0, head);
  }

  /// The version number [side] resolves to, or null when it isn't known.
  int? versionFor(ReviewSide side) =>
      switch (side) { ReviewSide.live => publishedVer, ReviewSide.latest => currentVer };

  /// Whether the published and current versions carry the same source bytes.
  ///
  /// A useful shortcut for the operator: [SourceComparison.identical] means the
  /// pending version was written from byte-identical source, so approving it
  /// moves the pointer without changing what the source says. It is *not* a
  /// promise that the rendered pages match — the two versions can have been run
  /// through different sanitizer releases (`VersionListing.sanitizer_v` differs
  /// per version), and identical source through a newer sanitizer can render
  /// differently. The panes remain the authority on what a reader sees; this
  /// only says whether anyone actually rewrote anything.
  SourceComparison get sourceComparison {
    final live = publishedSourceSha256;
    final head = currentSourceSha256;
    if (live == null || head == null || live.isEmpty || head.isEmpty) {
      return SourceComparison.unknown;
    }
    return live == head ? SourceComparison.identical : SourceComparison.differs;
  }
}

/// Build the review queue out of an arbitrary bag of listing rows.
///
/// Filters to [DocumentReview.isAwaitingReview], de-duplicates on `public_id`,
/// and sorts most-recent-pending-work first.
///
/// Since 2.2.0 the rows handed here are already server-filtered, so this is no
/// longer doing the heavy lifting — but it is not redundant. It still excludes
/// the never-promoted public documents the server's broader `pending` predicate
/// admits (see the library comment), still guarantees the ordering the screen
/// renders, and still holds the line if a caller ever assembles rows some other
/// way. Taking rows rather than a query is what makes it survive a contract
/// change like this one at all.
///
/// **Why newest-first rather than longest-waiting-first.** A queue argues for
/// FIFO, but every list in this app is newest-first and an operator who opens
/// the queue is nearly always reacting to something an agent just did — the
/// burst of writes they want to see is at the top under this order and buried
/// under the backlog under the other. Nothing is starved either way: the queue
/// is exhaustive and the screen states its full length.
///
/// De-duplication is not theoretical. The provider paginates with
/// `updated_since` semantics elsewhere in the app that are inclusive by
/// contract, and a document written *during* the sweep can legitimately be
/// delivered on two pages of an `updated`-ordered walk as its position shifts.
/// Rows are freezed value types, so the first copy seen wins and later ones are
/// dropped rather than merged — they describe the same document, and the sweep
/// re-runs whole rather than patching itself.
List<DocumentListing> reviewQueueFrom(Iterable<DocumentListing> rows) {
  final queue = <DocumentListing>[];
  final seen = <String>{};
  for (final row in rows) {
    if (!row.isAwaitingReview) continue;
    if (!seen.add(row.publicId)) continue;
    queue.add(row);
  }
  queue.sort((a, b) => b.pendingSince.compareTo(a.pendingSince));
  return queue;
}
