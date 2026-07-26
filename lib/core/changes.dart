/// The shared vocabulary for contract 2.0.0's **corpus change feed** (migration
/// 0017) — the hermetic sibling of `publication.dart` and `links.dart`, with no
/// Flutter imports so it can be unit-tested without a widget binding.
///
/// The feed is `GET /admin/documents` under `?order=updated`, optionally
/// windowed by `?updated_since=`. It exists because **classification edits never
/// write a version**: retagging, renaming, flipping visibility, changing
/// lifecycle status, publishing (promote) and revoking all stamp `updated_at`
/// while leaving `current_ver` — and therefore every version-based check the app
/// makes — completely unmoved. Walking the default `created` ordering can never
/// discover them: a document authored a year ago and retagged this morning sits
/// a year deep in that list.
///
/// Two rules from the contract are load-bearing enough to restate here, because
/// getting either wrong is a hard error rather than a degraded result:
///
///  * **A cursor encodes the ordering that minted it.** Replaying an
///    `order=updated` cursor under the default ordering (or the reverse) is a
///    `400 bad_cursor`, never a silent re-sort. `order` must therefore be sent
///    back alongside every `cursor`, and changing the ordering must drop the
///    cursor and restart the walk. The app keeps the feed's pagination in its
///    own state object ([ChangeFeedState]) precisely so the two walks can never
///    share a cursor field by accident.
///  * **`updated_since` is inclusive** (`updated_at >= value`), deliberately, so
///    a resuming consumer re-delivers the row on the boundary rather than
///    skipping one that shares a millisecond with it. Anything reading the feed
///    has to be idempotent per row.
library;

import '../api/api.dart';

/// Sort field for the two document list surfaces (`?order=`).
///
/// [created] is the server default and what every browse surface in the app
/// uses. [updated] turns the same endpoint into the change feed.
enum DocumentOrder {
  created('created'),
  updated('updated');

  const DocumentOrder(this.wire);

  /// The on-the-wire `order` value.
  final String wire;
}

/// What kind of change last touched a document, derived from the row alone.
///
/// See [DocumentChange.changeKind] for the derivation and why three of these
/// four are *proven* rather than guessed.
enum ChangeKind {
  /// The document was revoked. Dominates every other reading: revoke stamps
  /// `updated_at` and clears the `current_*` fields, so nothing else about the
  /// row can be compared afterwards.
  revoked,

  /// The last touch was a content write — a new version (authored, updated or
  /// restored). `updated_at` and `current_version_at` agree.
  content,

  /// The last touch was a **classification** edit: tags, slug, visibility,
  /// lifecycle status, or a publish (promote). None of these bump a version, so
  /// this is the class of change the feed exists to surface at all.
  classification,

  /// The row does not say. `current_version_at` is null on a document that has
  /// no current version to have been written, leaving nothing to compare
  /// `updated_at` against.
  unknown,
}

/// Change-feed reading of a listing row.
extension DocumentChange on DocumentListing {
  /// How far apart `updated_at` and `current_version_at` may sit while still
  /// describing the same event.
  ///
  /// The contract is explicit that these two columns are "stamped by different
  /// statements of one D1 batch, so a pure content write can leave them a
  /// millisecond apart **either way**", and that they should be compared "for
  /// meaning, not an exact inequality". Two seconds is far above that batch skew
  /// and far below any interval a human operator could retag a document in, so
  /// it separates the two cases without ever having to guess between them.
  ///
  /// **The tolerance is what absorbs the skew; the comparison itself is
  /// deliberately one-sided** ([changeKind] tests `updatedAt - currentVersionAt
  /// > tolerance`, not the absolute difference). Do not "fix" this into
  /// `.abs()`. The two are not interchangeable, and only the signed form is
  /// sound: a classification edit is by definition something that happened
  /// *after* the last write, so only `updated_at` running **ahead** is evidence
  /// of one. `current_version_at` ahead of `updated_at` by more than the
  /// tolerance is an anomaly no ordinary operation produces, and reading it as a
  /// reclassification would assert something the row does not show. Both
  /// directions of *sub-tolerance* skew already land on `content` either way —
  /// which is exactly why a test built on ±40ms cannot tell the two forms apart
  /// (see `test/change_feed_test.dart`, which pins the sign with drift *beyond*
  /// the tolerance instead).
  static const Duration writeSkewTolerance = Duration(seconds: 2);

  /// What last changed about this document.
  ///
  /// Three of the four answers are **proven by the row**, not inferred:
  ///
  ///  * [ChangeKind.revoked] — `revoked_at` is set. Nothing else needs checking.
  ///  * [ChangeKind.classification] — `updated_at` is more than
  ///    [writeSkewTolerance] *after* `current_version_at`. Something stamped
  ///    `updated_at` after the current version's bytes were written, and a
  ///    content write always stamps both; therefore the later touch was
  ///    necessarily not a content write. This is a deduction, not a heuristic.
  ///  * [ChangeKind.content] — everything else with a known write time: the two
  ///    agree within the tolerance, so the last touch *was* the write. This also
  ///    absorbs the anomalous case of `current_version_at` running ahead of
  ///    `updated_at`, which is the safe place for it to land (see
  ///    [writeSkewTolerance] on why the comparison is signed).
  ///  * [ChangeKind.unknown] — `current_version_at` is null, so there is nothing
  ///    to compare.
  ///
  /// The one case this cannot resolve is a classification edit made in the same
  /// couple of seconds as the write it followed; it reads as [content]. That
  /// direction is the safe one — under-reporting a reclassification the operator
  /// just made themselves is invisible, whereas labelling an ordinary write
  /// "reclassified" would send them looking for an edit nobody made.
  ChangeKind get changeKind {
    if (isRevoked) return ChangeKind.revoked;
    final writtenAt = currentVersionAt;
    if (writtenAt == null) return ChangeKind.unknown;
    final drift = updatedAt.difference(writtenAt);
    if (drift > writeSkewTolerance) return ChangeKind.classification;
    return ChangeKind.content;
  }

  /// Whether this row's last change was one that left no version behind — the
  /// documents a version-based sync would silently miss entirely.
  bool get isClassificationOnlyChange =>
      changeKind == ChangeKind.classification;
}

/// A preset `updated_since` window.
///
/// Presets rather than a persisted "since you last looked" watermark: this is an
/// operator console driven by a human asking "what moved recently", not a
/// headless consumer resuming a sync. A stored watermark would buy nothing here
/// and would import the feed's inclusive-boundary/idempotency obligations into
/// app state for a question a fixed window already answers.
enum ChangeWindow {
  day(Duration(days: 1)),
  week(Duration(days: 7)),
  month(Duration(days: 30)),

  /// No `updated_since` at all — walk the whole corpus in `updated` order.
  all(null);

  const ChangeWindow(this.span);

  /// How far back this window reaches, or null for "everything".
  final Duration? span;

  /// The `updated_since` query value for this window as of [now], or null when
  /// the parameter should be omitted entirely.
  ///
  /// Emitted as a UTC ISO-8601 instant — one of the three shapes the contract
  /// accepts, and the only one with no ambiguity about the caller's offset.
  String? updatedSince(DateTime now) {
    final span = this.span;
    if (span == null) return null;
    return now.toUtc().subtract(span).toIso8601String();
  }
}
