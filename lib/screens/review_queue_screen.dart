import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../core/review.dart';
import '../l10n/l10n.dart';
import '../providers/review_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/doc_feed_card.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import 'document_list_screen.dart';
import 'review_screen.dart';

/// The review queue — every public document whose head is being withheld from
/// readers by contract 2.0.0's publication gate.
///
/// A pushed screen reading its own sweep (see [reviewQueueProvider]) rather than
/// a filter over the shared document list, for a reason that is easy to miss:
/// the shared list is paginated and the app only ever holds the pages the
/// operator happened to scroll. Filtering it would produce a queue that is a
/// function of how far somebody scrolled the Library, and that is worse than no
/// queue at all — it would say "you're all caught up" while holding work back.
/// The contract offers no server-side predicate for this (see the `review.dart`
/// library comment), so completeness has to be bought with a full sweep.
class ReviewQueueScreen extends ConsumerStatefulWidget {
  const ReviewQueueScreen({super.key});

  @override
  ConsumerState<ReviewQueueScreen> createState() => _ReviewQueueScreenState();
}

class _ReviewQueueScreenState extends ConsumerState<ReviewQueueScreen> {
  @override
  void initState() {
    super.initState();
    // The queue is a live view — always sweep afresh on open rather than showing
    // whatever a previous visit left in the provider. A version published since
    // then would still be sitting in that list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The callback belongs to the binding, not this element, so it still fires
      // if the route was popped within the frame — and `ref.read` on a disposed
      // consumer throws rather than no-opping.
      if (!mounted) return;
      ref.read(reviewQueueProvider.notifier).reload();
    });
  }

  Future<void> _reload() => ref.read(reviewQueueProvider.notifier).reload();

  Future<void> _openReview(DocumentListing doc) async {
    await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => ReviewScreen(doc: doc)));
    // No re-sweep on return: the review screen resolves its own row through the
    // provider when it publishes, so the queue is already correct and a sweep
    // here would only cost the operator a wait between reviews.
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(reviewQueueProvider);
    final topInset = MediaQuery.paddingOf(context).top + 12;
    final docs = state.documents;

    return Scaffold(
      backgroundColor: c.bg,
      body: AdaptiveGutter(
        builder: (context, gutter) => RefreshIndicator(
          onRefresh: _reload,
          color: c.clay,
          backgroundColor: c.surface,
          child: ListView(
            // Keeps the list draggable when its content is shorter than the
            // viewport, which is exactly the empty and error states — neither
            // of which carries any other retry affordance. Under clamping
            // physics a short list refuses the drag and the RefreshIndicator
            // never sees it.
            //
            // Redundant today, deliberately kept: ScrollView already defaults
            // to these physics for a vertical list with no controller, and the
            // day this one acquires a controller `primary` goes false and takes
            // the default with it. Same line, same reason, on all three pushed
            // worklists.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              gutter,
              topInset,
              gutter,
              AppSpacing.bottomInset,
            ),
            children: [
              // An explicit refresh beside the title, because the
              // [RefreshIndicator] above takes a drag and Flutter's desktop/web
              // scroll behaviour will not start one from a mouse — so
              // pull-to-refresh is touch-only. The shell's side rail has the
              // same action for the same reason, but a pushed route covers the
              // rail. It matters most on this screen: the queue is a live
              // sweep, and the operator's own work in the Review screen is what
              // empties it, so "ask again" is the commonest thing they want.
              Row(
                children: [
                  Expanded(
                    child: BackHeader(l10n.reviewQueue, eyebrow: l10n.thePass),
                  ),
                  AppIconButton(
                    Icons.refresh,
                    tooltip: l10n.refresh,
                    onPressed: state.isLoading ? null : _reload,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Always visible, in the spirit of the orphans screen's "rebuild
              // the graph first": this states what the queue *is*, and without
              // it a list of documents that look perfectly healthy on every
              // other surface has no obvious reason to exist.
              _note(c, l10n.reviewQueueNote),
              const SizedBox(height: 14),
              // Just the count now. It used to be paired with "N scanned",
              // which existed to contextualise "0 waiting" against the size of
              // the corpus it was drawn from. Since 2.2.0 the server returns
              // the queue itself rather than everything, so there is no corpus
              // figure to report and none is needed: "nothing waiting" is now
              // the server's own answer, not an inference from a sweep.
              if (docs.isNotEmpty || state.hasLoaded)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 12),
                  child: Text(
                    l10n.reviewQueueCount(docs.length),
                    overflow: TextOverflow.ellipsis,
                    style: AppText.small.copyWith(
                      color: c.textFaint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              // A sweep that stopped at the page backstop is not an answer. Say
              // so loudly rather than letting a truncated queue read as "all
              // caught up".
              if (state.hasLoaded && !state.isComplete && !state.isLoading) ...[
                _note(c, l10n.reviewQueueIncomplete, danger: true),
                const SizedBox(height: 12),
              ],
              if (docs.isEmpty && !state.hasError && !state.hasLoaded)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Center(
                    child: CircularProgressIndicator(color: c.clay),
                  ),
                )
              else if (docs.isEmpty && state.hasError)
                _tile(
                  c,
                  Icons.cloud_off,
                  l10n.reviewQueueLoadFailed,
                  detail: state.errorMessage,
                  danger: true,
                )
              else if (state.isEmptyResult)
                _tile(c, Icons.done_all, l10n.reviewQueueEmpty)
              else ...[
                for (var i = 0; i < docs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RiseIn(
                      delay: Duration(milliseconds: (i * 40).clamp(0, 300)),
                      child: _ReviewRow(
                        doc: docs[i],
                        onOpen: _openReview,
                        onTagTap: (t) =>
                            DocumentListScreen.openForTag(context, t),
                      ),
                    ),
                  ),
                // Only ever seen on a queue long enough to paginate, which the
                // server-side filter makes rare — the first page holds 200
                // pending documents. Kept because the rows above are already
                // usable while a second page is in flight.
                if (state.isLoading) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.clay,
                      ),
                    ),
                  ),
                ],
                // A failure after rows are on screen keeps the rows and appends
                // the error, rather than replacing a partial answer with none.
                if (state.hasError) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage ?? l10n.reviewQueueLoadFailed,
                    style: AppText.small.copyWith(color: c.red),
                  ),
                ],
              ],
              // Outside every branch on purpose, and the empty state is where it
              // matters most: an operator who sees "nothing waiting" and knows a
              // public document of theirs changes constantly needs to be told
              // that a document nobody ever published isn't gated at all.
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  l10n.reviewQueueFootnote,
                  style: AppText.small.copyWith(
                    color: c.textFaint,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _note(AppColors c, String text, {bool danger = false}) {
    final fg = danger ? c.red : c.honeyD;
    final tint = danger ? c.red : c.honey;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.12),
        border: Border.all(color: tint.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            danger ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    AppColors c,
    IconData icon,
    String text, {
    String? detail,
    bool danger = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 18),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        boxShadow: c.shadow,
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: danger ? c.red : c.textFaint),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppText.titleSerif.copyWith(
                color: danger ? c.red : c.text,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: AppText.small.copyWith(color: c.textFaint),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A queue row: the shared document plate, with the pending change stated above
/// it — the same idiom as the change feed's rows.
///
/// The meta line leads with the two version numbers because they are the whole
/// entry: `v4 → v8` says what is served and what would be, and nothing else on
/// the card can. The card's own `NotLiveBadge` is redundant here (every row in
/// this list has one by definition) but is left alone rather than special-cased
/// out — it is the same marker the operator followed in from the Library, and
/// suppressing it only on this screen would break that thread.
class _ReviewRow extends StatelessWidget {
  const _ReviewRow({
    required this.doc,
    required this.onOpen,
    required this.onTagTap,
  });

  final DocumentListing doc;
  final void Function(DocumentListing) onOpen;
  final void Function(String) onTagTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final ahead = doc.versionsAhead;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              // No leading icon: the label's own "→" is the arrow, and a
              // Pill icon beside it renders as a doubled one.
              Pill(
                l10n.reviewVersionGap('${doc.publishedVer}', '${doc.currentVer}'),
                tone: PillTone.honey,
                small: true,
                mono: true,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  ahead == null
                      ? l10n.reviewPendingSince(relTime(l10n, doc.pendingSince))
                      : l10n.reviewPendingSinceAhead(
                          ahead,
                          relTime(l10n, doc.pendingSince),
                        ),
                  overflow: TextOverflow.ellipsis,
                  style: AppText.small.copyWith(color: c.textFaint),
                ),
              ),
            ],
          ),
        ),
        DocFeedCard(doc: doc, onOpen: onOpen, onTagTap: onTagTap),
      ],
    );
  }
}
