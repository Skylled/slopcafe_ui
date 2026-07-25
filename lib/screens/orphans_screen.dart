import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../l10n/l10n.dart';
import '../providers/links_provider.dart';
import '../widgets/doc_feed_card.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import 'document_list_screen.dart';
import 'reader_screen.dart';

/// The orphan worklist — live documents that no live document links to,
/// from `GET /admin/links/orphans`.
///
/// A pushed screen rather than a sheet because it renders the same
/// [DocFeedCard]s as every other document list and wants the room. It reads its
/// own endpoint rather than filtering [documentsListProvider]: orphanhood is a
/// property of the link graph, not of any field on a listing row, so there is
/// nothing to compute client-side.
///
/// Deliberately uncursored, matching the contract — the response is capped at
/// 200 and framed as a curation worklist, not a browse surface.
class OrphansScreen extends ConsumerStatefulWidget {
  const OrphansScreen({super.key});

  @override
  ConsumerState<OrphansScreen> createState() => _OrphansScreenState();
}

class _OrphansScreenState extends ConsumerState<OrphansScreen> {
  late Future<OrphanDocumentsResponse> _orphans;

  @override
  void initState() {
    super.initState();
    _orphans = ref.read(linkGraphServiceProvider).fetchOrphans();
  }

  Future<void> _reload() async {
    final next = ref.read(linkGraphServiceProvider).fetchOrphans();
    setState(() => _orphans = next);
    await next.catchError((_) => const OrphanDocumentsResponse(documents: []));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final topInset = MediaQuery.paddingOf(context).top + 12;

    return Scaffold(
      backgroundColor: c.bg,
      body: AdaptiveGutter(
        builder: (context, gutter) => RefreshIndicator(
          onRefresh: _reload,
          color: c.clay,
          backgroundColor: c.surface,
          child: FutureBuilder<OrphanDocumentsResponse>(
            future: _orphans,
            builder: (context, snapshot) {
              final loading =
                  snapshot.connectionState != ConnectionState.done;
              final docs = snapshot.data?.documents ?? const <DocumentListing>[];

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  gutter,
                  topInset,
                  gutter,
                  AppSpacing.bottomInset,
                ),
                children: [
                  BackHeader(l10n.orphansTitle, eyebrow: l10n.linkGraph),
                  const SizedBox(height: 8),
                  if (!loading && snapshot.hasError)
                    _tile(c, Icons.cloud_off, l10n.orphansLoadFailed,
                        danger: true)
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 2, bottom: 12),
                      child: Text(
                        loading ? '' : l10n.orphansCount(docs.length),
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ),
                    // The caveat stays visible whatever the result: the client
                    // cannot tell a genuine orphan from a document the graph
                    // simply has no rows for yet, and a pre-backfill corpus
                    // reports every document here.
                    _note(c, l10n.orphansNote),
                    const SizedBox(height: 14),
                    if (loading)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: CircularProgressIndicator(color: c.clay),
                        ),
                      )
                    else if (docs.isEmpty)
                      _tile(c, Icons.done_all, l10n.orphansEmpty)
                    else ...[
                      for (var i = 0; i < docs.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RiseIn(
                            delay: Duration(
                              milliseconds: (i * 40).clamp(0, 300),
                            ),
                            child: DocFeedCard(
                              doc: docs[i],
                              onOpen: (doc) => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ReaderScreen(doc: doc),
                                ),
                              ),
                              onTagTap: (t) =>
                                  DocumentListScreen.openForTag(context, t),
                            ),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          l10n.orphansHint,
                          style: AppText.small.copyWith(
                            color: c.textFaint,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
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
          ],
        ),
      ),
    );
  }
}
