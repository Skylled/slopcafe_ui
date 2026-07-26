import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/changes.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../l10n/l10n.dart';
import '../providers/changes_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/doc_feed_card.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import 'document_list_screen.dart';
import 'reader_screen.dart';

/// The corpus change feed — `GET /admin/documents?order=updated`, windowed by
/// `?updated_since=`.
///
/// A pushed screen reading its own walk (see [changeFeedProvider]) rather than a
/// mode on the shared document list, so the two orderings can never trade
/// cursors. Renders the same [DocFeedCard]s as every other document list, with
/// one addition the other lists have no use for: a per-row badge naming *what
/// kind* of change happened, since "this moved" is only actionable once the
/// operator knows whether the bytes changed or only the filing did.
class ChangesScreen extends ConsumerStatefulWidget {
  const ChangesScreen({super.key});

  @override
  ConsumerState<ChangesScreen> createState() => _ChangesScreenState();
}

class _ChangesScreenState extends ConsumerState<ChangesScreen> {
  @override
  void initState() {
    super.initState();
    // The feed is a live view — always start a fresh walk on open rather than
    // showing whatever a previous visit left in the provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The callback is owned by the binding, not this element, so it still runs
      // if the route was popped within the frame — and `ref.read` on a disposed
      // consumer throws rather than no-opping. Same guard as library_screen.
      if (!mounted) return;
      ref.read(changeFeedProvider.notifier).reload();
    });
  }

  Future<void> _reload() => ref.read(changeFeedProvider.notifier).reload();

  void _setWindow(ChangeWindow w) {
    if (w == ref.read(changeFeedProvider).window) return;
    // Changing the window restarts the walk: the held cursor was minted under
    // the old one and means nothing under the new.
    ref.read(changeFeedProvider.notifier).reload(window: w);
  }

  void _open(DocumentListing doc) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(changeFeedProvider);
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
            // Without this the list refuses drags whenever the content is
            // shorter than the viewport (clamping physics), which would make
            // pull-to-refresh unreachable in exactly the two states that need it
            // — the error tile and the empty result, neither of which carries
            // any other retry affordance.
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              gutter,
              topInset,
              gutter,
              AppSpacing.bottomInset,
            ),
            children: [
              BackHeader(l10n.changeFeed, eyebrow: l10n.thePass),
              const SizedBox(height: 8),
              _WindowSegmented(value: state.window, onChanged: _setWindow),
              const SizedBox(height: 14),
              // Always visible: the reason this screen exists is exactly the
              // class of change no other surface in the app can report.
              _note(c, l10n.changeFeedNote),
              const SizedBox(height: 14),
              if (docs.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 12),
                  child: Text(
                    l10n.changeFeedCount(docs.length),
                    style: AppText.small.copyWith(color: c.textFaint),
                  ),
                ),
              // `!hasLoaded` covers the frames between the screen mounting and
              // its first fetch starting — without it the untouched initial
              // state would flash "nothing changed" before anything was asked.
              if (docs.isEmpty &&
                  !state.hasError &&
                  (state.isLoading || !state.hasLoaded))
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
                  l10n.changeFeedLoadFailed,
                  detail: state.errorMessage,
                  danger: true,
                )
              else if (state.isEmptyResult)
                _tile(c, Icons.done_all, l10n.changeFeedEmpty)
              else ...[
                for (var i = 0; i < docs.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RiseIn(
                      delay: Duration(milliseconds: (i * 40).clamp(0, 300)),
                      child: _ChangeRow(
                        doc: docs[i],
                        onOpen: _open,
                        onTagTap: (t) =>
                            DocumentListScreen.openForTag(context, t),
                      ),
                    ),
                  ),
                if (state.hasMore) ...[
                  const SizedBox(height: 2),
                  AppButton(
                    l10n.changeFeedMore,
                    icon: Icons.expand_more,
                    expand: true,
                    onPressed: state.isLoading
                        ? null
                        : () =>
                              ref.read(changeFeedProvider.notifier).loadMore(),
                  ),
                ],
                // A failure *after* rows are already on screen keeps the rows
                // and says so, rather than replacing a partial answer with an
                // error tile.
                if (state.hasError) ...[
                  const SizedBox(height: 12),
                  Text(
                    state.errorMessage ?? l10n.changeFeedLoadFailed,
                    style: AppText.small.copyWith(color: c.red),
                  ),
                ],
              ],
              // Outside every branch on purpose. The empty result is where this
              // caveat matters MOST: an operator who picks a short window, sees
              // "nothing changed", and knows perfectly well they retagged
              // something last month needs to be told that pre-migration
              // reclassifications report their write time instead.
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  l10n.changeFeedBackfillNote,
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

  Widget _note(AppColors c, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.honey.withValues(alpha: 0.12),
        border: Border.all(color: c.honey.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: c.honeyD),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.honeyD,
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

/// A change-feed row: the shared document plate, with the change itself stated
/// above it.
class _ChangeRow extends StatelessWidget {
  const _ChangeRow({
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              if (ChangeKindBadge.showsFor(doc)) ...[
                ChangeKindBadge(doc: doc),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Text(
                  l10n.changedRelative(relTime(l10n, doc.updatedAt)),
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

/// The window selector — the same segmented idiom as Search's mode selector and
/// Operate's status filter.
class _WindowSegmented extends StatelessWidget {
  const _WindowSegmented({required this.value, required this.onChanged});

  final ChangeWindow value;
  final ValueChanged<ChangeWindow> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    String label(ChangeWindow w) => switch (w) {
      ChangeWindow.day => l10n.changeWindowDay,
      ChangeWindow.week => l10n.changeWindowWeek,
      ChangeWindow.month => l10n.changeWindowMonth,
      ChangeWindow.all => l10n.changeWindowAll,
    };

    Widget seg(ChangeWindow w) {
      final active = w == value;
      return Expanded(
        child: Tappable(
          onTap: () => onChanged(w),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: active ? c.clay : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Center(
              child: Text(
                label(w),
                style: AppText.small.copyWith(
                  fontWeight: FontWeight.w700,
                  color: active ? c.surface : c.textDim,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(children: [for (final w in ChangeWindow.values) seg(w)]),
    );
  }
}
