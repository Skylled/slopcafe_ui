import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/api_client.dart';
import '../core/changes.dart';

/// One walk of the corpus change feed: the rows fetched so far, the cursor that
/// continues *this* walk, and the window that defined it.
///
/// Deliberately a separate state object from `DocumentsListState` rather than a
/// mode on it. Two reasons, and the first is a correctness one:
///
///  1. **A cursor carries the ordering that minted it.** Mixing the two walks in
///     one `nextCursor` field would put a `400 bad_cursor` one careless mode
///     flip away. Two state objects make that error unreachable — there is no
///     field a `created`-ordered cursor and an `updated`-ordered cursor can both
///     be written to.
///  2. The feed is a **worklist**, not the corpus browse. It never feeds the
///     Library, Collections or the tag lists, and it must never be written to
///     the offline document cache: `documents_list.json` is the newest-created
///     page the app falls back to when offline, and overwriting it with a
///     recently-*changed* slice would quietly corrupt what "offline" shows.
class ChangeFeedState {
  const ChangeFeedState({
    this.documents = const [],
    this.window = ChangeWindow.week,
    this.windowSince,
    this.nextCursor,
    this.isLoading = false,
    this.hasLoaded = false,
    this.hasError = false,
    this.errorMessage,
  });

  /// Rows accumulated across this walk, most-recently-changed first.
  final List<DocumentListing> documents;

  /// The window preset this walk was started under.
  final ChangeWindow window;

  /// The **resolved** `updated_since` instant for this walk, pinned once when
  /// the walk started (null for [ChangeWindow.all], which sends no parameter).
  ///
  /// Pinned rather than recomputed per page, and that is load-bearing. The feed
  /// is ordered most-recently-changed **first**, so a walk moves *towards* the
  /// window's lower bound as it pages. Re-resolving `now - 24h` on page 2 would
  /// raise that bound by however long the operator took to tap Load more, and
  /// silently filter out the rows nearest the boundary — precisely the ones the
  /// later pages exist to deliver. The server does not encode filters in the
  /// cursor, so nothing would reject it: the walk would just quietly end short
  /// of its own stated window.
  final String? windowSince;

  /// Cursor continuing this walk, or null at the end of the feed.
  final String? nextCursor;

  final bool isLoading;

  /// Whether a walk has ever completed successfully. Distinguishes "no results"
  /// from "not asked yet" — without it the untouched initial state reads as an
  /// empty feed and the screen flashes "nothing changed" before its first fetch
  /// has even started.
  final bool hasLoaded;

  final bool hasError;
  final String? errorMessage;

  /// Whether another page can be requested.
  bool get hasMore => nextCursor != null && nextCursor!.isNotEmpty;

  /// True only once a walk has actually completed with nothing in it — an empty
  /// list that is loading, errored, or never ran is not an empty feed.
  bool get isEmptyResult =>
      hasLoaded && documents.isEmpty && !isLoading && !hasError;
}

/// Walks `GET /admin/documents?order=updated` — the corpus change feed.
///
/// Every page sends `order` explicitly, including the ones that also send a
/// `cursor`: the contract rejects a cursor replayed under a different ordering
/// with a hard `400 bad_cursor`, so the ordering is part of the pagination
/// state, not a one-off starting parameter.
class ChangeFeedNotifier extends Notifier<ChangeFeedState> {
  /// Monotonic id of the newest request. Every in-flight fetch captures the
  /// value it was issued under and refuses to write state unless it is still
  /// the current one.
  ///
  /// This is why [reload] is **not** gated on `isLoading` the way the sibling
  /// `DocumentsListNotifier.loadNextPage` is. Blocking would be the wrong
  /// behaviour here: tapping a different window while a page is in flight must
  /// switch the feed immediately, not be swallowed. Superseding gives that, but
  /// only if the abandoned request can no longer commit — otherwise a slow page
  /// from the old walk lands afterwards and appends its rows onto the new
  /// walk's list, restores the old `window`, and leaves a cursor minted under
  /// one window paired with another window's `updated_since`.
  int _generation = 0;

  @override
  ChangeFeedState build() => const ChangeFeedState();

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

  /// Restart the walk under [window] (default: re-run the current window).
  ///
  /// Always drops the cursor and re-pins the window instant: both were minted
  /// under the previous walk, and a change-feed page only means anything
  /// relative to the walk that produced it.
  Future<void> reload({ChangeWindow? window}) {
    final next = window ?? state.window;
    final generation = ++_generation;
    // Resolved ONCE here, then replayed verbatim on every page of this walk.
    final since = next.updatedSince(DateTime.now());
    // A same-window reload (pull-to-refresh) keeps the rows on screen under the
    // refresh spinner; switching windows clears them, because rows fetched under
    // the old window do not belong to the new one and showing them beneath a
    // freshly-moved selector would misreport what the screen is claiming. Either
    // way the fetch runs with `clear: true` and replaces the list wholesale on
    // success — this only governs what is visible in the meantime.
    final sameWindow = next == state.window;
    state = ChangeFeedState(
      documents: sameWindow ? state.documents : const [],
      window: next,
      windowSince: since,
      isLoading: true,
      hasLoaded: sameWindow && state.hasLoaded,
    );
    return _fetch(clear: true, generation: generation);
  }

  /// Fetch the next page of the current walk. No-op at the end of the feed or
  /// while a fetch is already in flight.
  Future<void> loadMore() {
    if (state.isLoading || !state.hasMore) return Future.value();
    final generation = ++_generation;
    state = ChangeFeedState(
      documents: state.documents,
      window: state.window,
      windowSince: state.windowSince,
      nextCursor: state.nextCursor,
      isLoading: true,
      hasLoaded: state.hasLoaded,
    );
    return _fetch(clear: false, generation: generation);
  }

  Future<void> _fetch({required bool clear, required int generation}) async {
    // Everything this fetch needs is captured before the await, so a superseded
    // request can never read the *new* walk's state on completion.
    final window = state.window;
    final since = state.windowSince;
    final cursor = clear ? null : state.nextCursor;
    final existing = clear ? const <DocumentListing>[] : state.documents;
    final hadLoaded = state.hasLoaded;

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/admin/documents',
        queryParameters: {
          'limit': 100,
          // `order` rides along with `cursor` on every page, not just the
          // first — see the class doc.
          'order': DocumentOrder.updated.wire,
          'updated_since': ?since,
          'cursor': ?cursor,
        },
      );
      if (generation != _generation) return; // superseded mid-flight

      final parsed = ListDocumentsResponse.fromJson(
        response.data as Map<String, dynamic>,
      );

      final rows = List<DocumentListing>.from(existing);
      // `updated_since` is an INCLUSIVE window and the feed re-delivers the
      // boundary row by design, so de-duplicate on public_id rather than
      // trusting the pages to be disjoint.
      final seen = rows.map((d) => d.publicId).toSet();
      for (final doc in parsed.documents) {
        if (seen.add(doc.publicId)) rows.add(doc);
      }

      state = ChangeFeedState(
        documents: rows,
        window: window,
        windowSince: since,
        nextCursor: parsed.nextCursor,
        isLoading: false,
        hasLoaded: true,
      );

      ref
          .read(connectionStateProvider.notifier)
          .setStatus(ConnectionStatus.connected);
    } catch (e, stack) {
      dev.log('Change feed fetch failed', error: e, stackTrace: stack);
      if (generation != _generation) return; // superseded mid-flight
      // No offline fallback, unlike the document list: the feed's whole claim is
      // "this is what moved recently", and the cached listing cannot answer that
      // — it is a snapshot with no record of when anything changed relative to
      // the window. Better an honest error than a stale list presented as news.
      state = ChangeFeedState(
        documents: existing,
        window: window,
        windowSince: since,
        nextCursor: cursor,
        isLoading: false,
        hasLoaded: clear ? false : hadLoaded,
        hasError: true,
        errorMessage: ApiError.describe(e),
      );
    }
  }
}

final changeFeedProvider =
    NotifierProvider<ChangeFeedNotifier, ChangeFeedState>(
      ChangeFeedNotifier.new,
    );
