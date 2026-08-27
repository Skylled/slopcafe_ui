import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/api_client.dart';
import '../core/changes.dart';
import '../core/review.dart';

/// The documents the publication gate is holding back, read straight from the
/// server.
///
/// Since contract **2.2.0** this is a filtered query rather than a corpus sweep:
/// `GET /admin/documents?visibility=public&publication=pending` returns the
/// candidates directly (migrations 0011 and 0018), so the number of rows crossing
/// the wire is proportional to the *queue*, not to the corpus behind it.
///
/// A separate state object from both `DocumentsListState` and `ChangeFeedState`,
/// for the change feed's two reasons — an `updated`-ordered cursor must never
/// meet the `created`-ordered one, and a gate-filtered slice must never be
/// written to `documents_list.json`, which is the newest-*created* page the app
/// falls back to offline — plus its own third: this walk carries filters those
/// two do not, and the server does not encode filters in the cursor, so a cursor
/// swapped between them would silently return the wrong population rather than
/// erroring.
class ReviewQueueState {
  const ReviewQueueState({
    this.documents = const [],
    this.isLoading = false,
    this.hasLoaded = false,
    this.isComplete = false,
    this.hasError = false,
    this.errorMessage,
  });

  /// The queue, newest pending work first.
  final List<DocumentListing> documents;

  final bool isLoading;

  /// Whether a walk has ever finished. Distinguishes "nothing is waiting" from
  /// "we haven't asked yet" — without it the untouched initial state renders as
  /// an empty queue before the first request has left.
  final bool hasLoaded;

  /// Whether the last walk actually reached the end of the queue.
  ///
  /// Now that the server does the filtering this should be unreachable — it
  /// takes more pending documents than any operator could work through to trip
  /// the page backstop. It is kept anyway, and the screen still warns when it
  /// fires: the cost is nothing while it holds, and a review queue that
  /// truncates in silence reads as "you're all caught up" while hiding work
  /// somebody is accountable for. Cheap insurance against a future where the
  /// filter behaves differently than it does today.
  final bool isComplete;

  final bool hasError;
  final String? errorMessage;

  /// True only once a walk has completed with nothing waiting.
  bool get isEmptyResult =>
      hasLoaded && documents.isEmpty && !isLoading && !hasError;
}

/// Reads the review queue via the 2.2.0 publication filter.
///
/// The result is still passed through [reviewQueueFrom] rather than rendered
/// raw. The server's `pending` is `published_ver IS NOT current_ver`, which also
/// admits a public document that was **never** promoted — a document that is not
/// gated at all, since by the 2.0.0 serving rule it already serves its head. The
/// client filter drops those, guarantees the ordering, and keeps the screen
/// correct regardless of how the backend reads a null pointer. See the
/// `review.dart` library comment.
class ReviewQueueNotifier extends Notifier<ReviewQueueState> {
  /// Maximum pages one walk will request — a runaway-cursor backstop, not a
  /// real limit. At the page size below it allows 10,000 documents *already
  /// awaiting review*, which is far past the point where a queue is a worklist.
  static const int _maxPages = 50;

  /// Rows per page. The contract's maximum: the filtered result is small, so
  /// this is very often a single request.
  static const int _pageSize = 200;

  /// Monotonic id of the newest walk. A walk captures the value it started under
  /// and re-checks it after every await, so a pull-to-refresh mid-walk supersedes
  /// the old one instead of interleaving pages with it. Still a loop of awaits,
  /// so the loop breaks on a generation change rather than merely declining to
  /// write at the end.
  int _generation = 0;

  @override
  ReviewQueueState build() => const ReviewQueueState();

  /// Drop everything this notifier is holding, back to its initial state.
  ///
  /// Called when the app is pointed at another deployment: these rows describe
  /// the deployment that served them and mean nothing against the next one. It
  /// is deliberately separate from the reload that follows, because a reload
  /// that *fails* — an unreachable host, a rejected token, exactly the states a
  /// freshly added instance is in — leaves the previous state in place by
  /// design, which is right for a refresh and wrong for a switch. Clearing first
  /// makes the failure show as an empty, erroring screen rather than as the
  /// previous deployment's corpus under the new deployment's name.
  void reset() => state = build();

  /// Re-read the queue from the beginning.
  ///
  /// Rows already on screen stay under the spinner — refreshing a queue the
  /// operator is reading should not blank it — and are replaced wholesale as the
  /// new walk's pages land.
  Future<void> reload() async {
    final generation = ++_generation;
    state = ReviewQueueState(
      documents: state.documents,
      isLoading: true,
      hasLoaded: state.hasLoaded,
    );

    final dio = ref.read(dioProvider);
    final rows = <DocumentListing>[];
    String? cursor;
    var pages = 0;

    try {
      do {
        final response = await dio.get(
          '/admin/documents',
          queryParameters: {
            'limit': _pageSize,
            // The two filters that make this a query instead of a sweep.
            // `visibility=public` is not optional decoration: `publication=pending`
            // on its own also matches private drafts that were never published,
            // which are not gated and have no reader to withhold anything from.
            'visibility': VisibilityFilter.public.wire,
            'publication': PublicationFilter.pending.wire,
            // Ordering rides along with the cursor on every page, not just the
            // first — the contract rejects a cursor replayed under a different
            // ordering outright rather than silently re-sorting.
            'order': DocumentOrder.updated.wire,
            'cursor': ?cursor,
          },
        );
        if (generation != _generation) return; // superseded mid-walk

        final parsed = ListDocumentsResponse.fromJson(
          response.data as Map<String, dynamic>,
        );
        rows.addAll(parsed.documents);
        pages++;
        cursor = (parsed.nextCursor?.isNotEmpty ?? false)
            ? parsed.nextCursor
            : null;

        state = ReviewQueueState(
          documents: reviewQueueFrom(rows),
          isLoading: cursor != null && pages < _maxPages,
          hasLoaded: true,
          isComplete: cursor == null,
        );
      } while (cursor != null && pages < _maxPages);

      ref
          .read(connectionStateProvider.notifier)
          .setStatus(ConnectionStatus.connected);
    } catch (e, stack) {
      dev.log('Review queue fetch failed', error: e, stackTrace: stack);
      if (generation != _generation) return; // superseded mid-walk
      // No offline fallback, matching the change feed: the queue's claim is
      // "these are waiting *right now*", and a cached listing cannot support it
      // — a stale queue would have the operator approving against version
      // numbers that have since moved. Rows already fetched are kept, but
      // `isComplete` stays false so a failed walk is never called exhaustive.
      state = ReviewQueueState(
        documents: reviewQueueFrom(rows),
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
  /// than the version that was requested, so the row is re-evaluated against what
  /// the backend actually pointed at: promoting v6 of a document whose head is v8
  /// moves the pointer without catching it up, and the row still belongs here.
  ///
  /// A local edit rather than a re-read. Cheaper than a round trip, and it avoids
  /// reshuffling the queue under an operator working through it — a promote
  /// stamps `updated_at`, so a re-read would jump the row they just handled to
  /// the top before removing it.
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
