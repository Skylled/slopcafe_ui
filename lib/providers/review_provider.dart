import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/api_client.dart';
import '../core/changes.dart';
import '../core/review.dart';

/// One sweep of the corpus looking for documents held behind the publication
/// gate: public, promoted, and no longer serving their head.
///
/// A separate state object from both `DocumentsListState` and `ChangeFeedState`,
/// for the same two reasons the change feed is separate from the document list,
/// plus a third of its own:
///
///  1. **A cursor carries the ordering that minted it.** This walk is
///     `order=updated`, so its cursor and the `created`-ordered one the shared
///     document list holds must never meet — replaying one under the other
///     ordering is a hard `400 bad_cursor`. Separate state makes that
///     unreachable by construction rather than by discipline.
///  2. **It must never reach the offline cache.** `documents_list.json` is the
///     newest-*created* page the app falls back to when offline; writing a
///     gate-filtered slice into it would quietly corrupt what "offline" shows.
///  3. **It is a sweep, not a page.** The change feed hands the operator a
///     Load-more button because a change feed has a natural "that's enough"
///     point. A review queue does not: a queue that stops early is a queue that
///     silently hides work an operator is accountable for publishing, so this
///     one runs to exhaustion and reports how far it got.
class ReviewQueueState {
  const ReviewQueueState({
    this.documents = const [],
    this.scanned = 0,
    this.isLoading = false,
    this.hasLoaded = false,
    this.isComplete = false,
    this.hasError = false,
    this.errorMessage,
  });

  /// The queue itself — rows passing [DocumentReview.isAwaitingReview], newest
  /// pending work first. Grows as the sweep pages, so the screen can show real
  /// results while the tail of the corpus is still being walked.
  final List<DocumentListing> documents;

  /// How many corpus rows this sweep has examined. Shown on the screen: the
  /// queue's length only means something next to the size of the corpus it was
  /// drawn from, and "0 waiting" out of 4 scanned is a very different statement
  /// from "0 waiting" out of 4000.
  final int scanned;

  final bool isLoading;

  /// Whether a sweep has ever finished. Distinguishes "nothing is waiting" from
  /// "we haven't looked yet" — without it the untouched initial state renders as
  /// an empty queue before the first request has left.
  final bool hasLoaded;

  /// Whether the last sweep actually reached the end of the corpus.
  ///
  /// False when the page backstop tripped, and the screen says so out loud. A
  /// review queue that quietly truncates is worse than no queue at all: it reads
  /// as "you're all caught up" while holding work back.
  final bool isComplete;

  final bool hasError;
  final String? errorMessage;

  /// True only once a sweep has completed with nothing waiting.
  bool get isEmptyResult =>
      hasLoaded && documents.isEmpty && !isLoading && !hasError;
}

/// Sweeps `GET /admin/documents?order=updated` and filters the result down to
/// the documents awaiting publication.
///
/// The filter is client-side because the contract offers no server-side one:
/// the list endpoint takes `tag`, `slug`, `status`, `order` and `updated_since`,
/// and none of those can express "public and `published_ver != current_ver`".
/// See the `review.dart` library comment.
///
/// `order=updated` rather than the default `created`, for two reasons. The
/// interesting rows — documents an agent has just rewritten — are the ones this
/// ordering puts on the first page, so the queue fills with useful entries
/// immediately instead of after a full walk. And the queue's own sort key
/// ([DocumentReview.pendingSince]) tracks the same clock, so rows arrive in
/// roughly their final order and the list stops reshuffling under the operator
/// as pages land.
///
/// No `updated_since` window. The queue is a statement about the *whole* corpus
/// — a document rewritten last year and never approved is still waiting — so
/// narrowing the walk would trade completeness for speed on the one surface that
/// cannot afford it.
class ReviewQueueNotifier extends Notifier<ReviewQueueState> {
  /// Maximum pages one sweep will request. At the 200-row page size below that
  /// is 200k documents — a backstop against a pathological non-advancing cursor
  /// rather than a real limit, and the same shape of guard
  /// `DocumentsListNotifier.backfillVectors` uses on its own walk. Tripping it
  /// clears [ReviewQueueState.isComplete] instead of passing a partial sweep off
  /// as a finished one.
  static const int _maxPages = 1000;

  /// Rows per page. The contract's maximum — a sweep is round-trip bound, and
  /// every page is a request the operator waits on.
  static const int _pageSize = 200;

  /// Monotonic id of the newest sweep. A sweep captures the value it started
  /// under and re-checks it after every await, so a pull-to-refresh mid-walk
  /// supersedes the old sweep instead of interleaving pages with it.
  ///
  /// This matters more here than on a single-request feed: a sweep is a *loop*
  /// of awaits, so an abandoned one has many chances to commit. Every one of
  /// them is gated, and the loop itself breaks on a generation change rather
  /// than merely declining to write at the end.
  int _generation = 0;

  @override
  ReviewQueueState build() => const ReviewQueueState();

  /// Walk the corpus from the beginning.
  ///
  /// Rows already on screen are kept underneath the spinner — a refresh of a
  /// queue the operator is reading should not blank it — and are replaced
  /// wholesale as the new sweep's pages land.
  Future<void> reload() async {
    final generation = ++_generation;
    state = ReviewQueueState(
      documents: state.documents,
      scanned: 0,
      isLoading: true,
      hasLoaded: state.hasLoaded,
    );

    final dio = ref.read(dioProvider);
    final rows = <DocumentListing>[];
    String? cursor;
    var pages = 0;
    var scanned = 0;

    try {
      do {
        final response = await dio.get(
          '/admin/documents',
          queryParameters: {
            'limit': _pageSize,
            // `order` rides along with `cursor` on every page, not just the
            // first: the contract rejects a cursor replayed under a different
            // ordering outright rather than silently re-sorting.
            'order': DocumentOrder.updated.wire,
            'cursor': ?cursor,
          },
        );
        if (generation != _generation) return; // superseded mid-sweep

        final parsed = ListDocumentsResponse.fromJson(
          response.data as Map<String, dynamic>,
        );
        rows.addAll(parsed.documents);
        scanned += parsed.documents.length;
        pages++;
        cursor = (parsed.nextCursor?.isNotEmpty ?? false)
            ? parsed.nextCursor
            : null;

        // Publish progress after every page. The filter is cheap and the sweep
        // is not, so an operator with a large corpus sees the queue fill rather
        // than watching a spinner for the whole walk.
        state = ReviewQueueState(
          documents: reviewQueueFrom(rows),
          scanned: scanned,
          isLoading: cursor != null && pages < _maxPages,
          hasLoaded: true,
          isComplete: cursor == null,
        );
      } while (cursor != null && pages < _maxPages);

      ref
          .read(connectionStateProvider.notifier)
          .setStatus(ConnectionStatus.connected);
    } catch (e, stack) {
      dev.log('Review queue sweep failed', error: e, stackTrace: stack);
      if (generation != _generation) return; // superseded mid-sweep
      // No offline fallback, matching the change feed and for the same reason:
      // the queue's claim is "these documents are waiting *right now*", and the
      // cached listing cannot support it. A stale queue presented as current
      // would have the operator approving versions against numbers that have
      // since moved. Rows already swept are kept — a sweep that failed on page 9
      // still found everything on pages 1-8 — but `isComplete` stays false, so
      // the screen never calls a failed sweep exhaustive.
      state = ReviewQueueState(
        documents: reviewQueueFrom(rows),
        scanned: scanned,
        isLoading: false,
        hasLoaded: state.hasLoaded || rows.isNotEmpty,
        hasError: true,
        errorMessage: ApiError.describe(e),
      );
    }
  }

  /// Drop a document from the queue after its pending version was published.
  ///
  /// Called with the canonical `published_ver` from the [PromoteResponse] rather
  /// than the version that was requested, so the row is re-evaluated against
  /// what the backend actually pointed at. It leaves the queue only if that
  /// genuinely closed the gap: promoting v6 of a document whose head is v8 moves
  /// the pointer without catching it up, and the row belongs in the queue
  /// afterwards exactly as much as it did before.
  ///
  /// A local edit rather than a re-sweep. The sweep is the expensive part of
  /// this provider and the operator has just told us what changed, so paying for
  /// a full corpus walk to learn one row's new `published_ver` would be a poor
  /// trade — and it would reshuffle the queue under them mid-review, since a
  /// promote stamps `updated_at`.
  void resolve(String publicId, int publishedVer) {
    var touched = false;
    final next = <DocumentListing>[];
    for (final doc in state.documents) {
      if (doc.publicId != publicId) {
        next.add(doc);
        continue;
      }
      touched = true;
      final updated = doc.copyWith(publishedVer: publishedVer);
      if (updated.isAwaitingReview) next.add(updated);
    }
    if (!touched) return;
    state = ReviewQueueState(
      documents: next,
      scanned: state.scanned,
      isLoading: state.isLoading,
      hasLoaded: state.hasLoaded,
      isComplete: state.isComplete,
      hasError: state.hasError,
      errorMessage: state.errorMessage,
    );
  }
}

final reviewQueueProvider =
    NotifierProvider<ReviewQueueNotifier, ReviewQueueState>(
      ReviewQueueNotifier.new,
    );
