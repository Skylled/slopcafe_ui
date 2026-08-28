import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../core/instances.dart';
import '../core/publication.dart';
import '../api/api.dart';
import '../core/secure_storage.dart';
import '../l10n/l10n.dart';
import '../providers/agent_provider.dart';
import '../providers/document_provider.dart';
import '../providers/health_provider.dart';
import '../providers/instances_provider.dart';
import '../providers/links_provider.dart';
import '../providers/refresh.dart';
import '../widgets/app_button.dart';
import '../widgets/doc_feed_card.dart';
import '../widgets/instance_switcher.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sheets.dart';
import '../widgets/slug_repair_sheet.dart';
import '../widgets/stat.dart';
import '../widgets/toast.dart';
import 'changes_screen.dart';
import 'compose_screen.dart';
import 'orphans_screen.dart';
import 'reader_screen.dart';
import 'review_queue_screen.dart';

/// Operate — "The Pass" (back of house). The single most feature-dense screen:
/// fleet/document statistics, R2 storage, an agent kitchen (mint/keys/OAuth/kill)
/// and an admin document list (visibility/slug/tags/publish/revoke).
///
/// Ported from the legacy `agents_screen`, `agent_detail_screen`,
/// `documents_screen` and `document_detail_screen`. All API/cache/confirm wiring
/// is preserved against the unchanged providers; only the presentation is reskinned.
class OperateScreen extends ConsumerStatefulWidget {
  const OperateScreen({super.key});

  @override
  ConsumerState<OperateScreen> createState() => _OperateScreenState();
}

enum _OpSeg { kitchen, docs }

/// Lifecycle filter for the admin document list. Client-side, like the
/// include-revoked toggle: it filters the loaded pages of the shared documents
/// provider rather than re-querying with the server's `status` param.
enum _DocStatusFilter { all, active, deprecated }

class _OperateScreenState extends ConsumerState<OperateScreen> {
  _OpSeg _seg = _OpSeg.kitchen;
  bool _includeRevoked = false;
  _DocStatusFilter _statusFilter = _DocStatusFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(agentsListProvider).agents.isEmpty) {
        ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
      }
      if (ref.read(documentsListProvider).documents.isEmpty) {
        ref.read(documentsListProvider.notifier).loadNextPage(clear: true);
      }
      // Best-effort /healthz metrics (sanitizer version + R2 storage). Held in a
      // provider so a pull-to-refresh from either home tab reloads it too.
      ref.read(healthProvider.notifier).load();
    });
  }

  // -------------------------------------------------------------------------
  // Kitchen: mint agent (name -> createAgent -> one-shot secret).
  // -------------------------------------------------------------------------
  Future<void> _showNewAgentSheet() async {
    final l10n = context.l10n;
    await showAppSheet<void>(
      context,
      builder: (sheetCtx) => _NewAgentSheet(
        onSubmit: (name) async {
          final mint = await ref
              .read(agentsListProvider.notifier)
              .createAgent(name);
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          if (!mounted) return;
          await showSecretSheet(
            context,
            title: l10n.agentHiredTitle,
            fields: [
              SecretField(l10n.agentIdLabel, mint.agentId),
              SecretField(l10n.plaintextBearerKeyLabel, mint.key, secret: true),
            ],
            note: mint.note.isEmpty ? null : mint.note,
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Kitchen: unbound OAuth clients (mint + list/delete from local store).
  // -------------------------------------------------------------------------
  Future<void> _showUnboundClientsSheet() async {
    await showAppSheet<void>(
      context,
      builder: (_) => _UnboundClientsSheet(ref: ref, host: context),
    );
  }

  // -------------------------------------------------------------------------
  // Kitchen: per-agent management sheet.
  // -------------------------------------------------------------------------
  Future<void> _openAgentSheet(AgentListing agent) async {
    await showAppSheet<void>(
      context,
      builder: (_) => _AgentSheet(ref: ref, host: context, agent: agent),
    );
  }

  // -------------------------------------------------------------------------
  // Documents: per-row admin actions sheet.
  // -------------------------------------------------------------------------
  Future<void> _openDocActions(DocumentListing doc) async {
    await showAppSheet<void>(
      context,
      builder: (_) => _DocActionsSheet(ref: ref, host: context, doc: doc),
    );
  }

  // -------------------------------------------------------------------------
  // Documents: manage the semantic-search vector index (POST /admin/vectors/
  // backfill). Two modes — index-new (cheap) and rebuild (expensive) — each
  // gated by its own confirmation step inside the sheet.
  // -------------------------------------------------------------------------
  Future<void> _openBackfill() async {
    await showAppSheet<void>(
      context,
      builder: (_) => _BackfillSheet(ref: ref, host: context),
    );
  }

  // -------------------------------------------------------------------------
  // Documents: the link graph — its rebuild sweep (POST /admin/links/backfill),
  // the orphan worklist (GET /admin/links/orphans) and the slug tombstones that
  // repair the link rot it reports. One entry rather than three, because they
  // are one subsystem and only the first is an action on its own.
  // -------------------------------------------------------------------------
  Future<void> _openLinkGraph() async {
    await showAppSheet<void>(
      context,
      builder: (_) => _LinkGraphSheet(ref: ref, host: context),
    );
  }

  // -------------------------------------------------------------------------
  // Documents: the corpus change feed (GET /admin/documents?order=updated).
  // A pushed screen rather than a sheet — it is a browse/triage surface with its
  // own pagination, and it reads its own walk so its `updated`-ordered cursor
  // can never meet the `created`-ordered one the shared document list holds.
  // -------------------------------------------------------------------------
  void _openChanges() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangesScreen()));
  }

  // -------------------------------------------------------------------------
  // Documents: the review queue — public documents the 2.0.0 publication gate
  // is holding back, and the two-pane comparison that decides each one.
  //
  // A pushed screen for the same reason the change feed is one: it is a triage
  // surface with its own corpus sweep, not an action menu. It sweeps rather than
  // filtering the shared document list because the contract has no server-side
  // predicate for "public and published_ver != current_ver", and a queue built
  // from whatever pages happen to be loaded would under-report silently.
  // -------------------------------------------------------------------------
  void _openReviewQueue() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReviewQueueScreen()));
  }

  // -------------------------------------------------------------------------
  // Documents: author a new document (POST /admin/documents). The compose
  // screen reloads the list itself and pops the WriteResponse; we surface the
  // outcome (including any sanitizer adjustments) here.
  // -------------------------------------------------------------------------
  Future<void> _openCompose() async {
    final l10n = context.l10n;
    final write = await Navigator.of(context).push<WriteResponse>(
      MaterialPageRoute(builder: (_) => const ComposeScreen()),
    );
    if (write == null || !mounted) return;
    final adjusted = write.stripped.length + write.willNotRender.length;
    showToast(
      context,
      adjusted > 0
          ? l10n.documentPublishedSanitized(write.version, adjusted)
          : l10n.documentPublished(write.version),
    );
  }

  void _openReader(DocumentListing doc) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final agentsState = ref.watch(agentsListProvider);
    final docsState = ref.watch(documentsListProvider);
    final health = ref.watch(healthProvider);
    final activeInstance = ref.watch(activeInstanceProvider);

    final agents = agentsState.agents;
    final docs = docsState.documents;

    final liveDocs = docs.where((d) => !d.isRevoked).length;
    final publicDocs = docs
        .where((d) => !d.isRevoked && d.visibility == 'public')
        .length;
    final activeAgents = agents.where((a) => a.activeKeys > 0).length;
    final activeKeys = agents.fold<int>(0, (s, a) => s + a.activeKeys);
    final mintedKeys = agents.fold<int>(0, (s, a) => s + a.totalKeys);

    return Scaffold(
      backgroundColor: c.bg,
      body: RefreshIndicator(
        onRefresh: () => refreshFleetData(ref),
        color: c.clay,
        backgroundColor: c.surface,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = AppLayout.gutterFor(constraints.maxWidth);
            // Lay the four stat tiles in one row when the content column can
            // give each a comfortable cell; otherwise keep the phone 2x2 grid.
            final statsAcross = constraints.maxWidth - 2 * gutter >= 640;
            final stats = [
              OpStat(
                icon: Icons.description_outlined,
                label: l10n.liveDocuments,
                value: '${health.d1Documents ?? liveDocs}',
                sub: l10n.publicCountSub(publicDocs),
              ),
              OpStat(
                icon: Icons.person_outline,
                label: l10n.activeAgents,
                value: '$activeAgents',
                sub: l10n.ofCountSub(health.d1Agents ?? agents.length),
              ),
              OpStat(
                icon: Icons.key_outlined,
                label: l10n.activeKeys,
                value: '$activeKeys',
                sub: l10n.mintedSub(mintedKeys),
              ),
              OpStat(
                icon: Icons.shield_outlined,
                label: l10n.sanitizer,
                value: health.sanitizerVersion ?? '—',
                sub: health.sanitizerVersion != null
                    ? l10n.allGreen
                    : l10n.unavailable,
                mono: true,
              ),
            ];

            return ListView(
              // AlwaysScrollable so the pull-to-refresh gesture works even
              // when the content is short enough to fit without scrolling.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                gutter,
                MediaQuery.paddingOf(context).top + 12,
                gutter,
                context.shellBottomInset,
              ),
              children: [
                // ---- Header ----
                // The instance chip rides the Operate title because this is the
                // operator's tab: every destructive action on the screen below
                // lands on whichever deployment the chip names, so the answer to
                // "which one am I about to act on" belongs in the same glance as
                // the title. On expanded layouts the side rail already carries a
                // switcher, so the chip stands down rather than offering two.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(l10n.backOfHouse),
                          const SizedBox(height: 3),
                          Text(
                            l10n.thePass,
                            style: AppText.display.copyWith(color: c.text),
                          ),
                        ],
                      ),
                    ),
                    if (!context.isExpandedLayout && activeInstance != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, left: 8),
                        child: _InstanceChip(instance: activeInstance),
                      ),
                  ],
                ),
                const SizedBox(height: 18),

                // ---- Stat grid (2x2, or 4-across on wide columns) ----
                if (statsAcross)
                  _statRow(stats)
                else ...[
                  _statRow(stats.sublist(0, 2)),
                  const SizedBox(height: 11),
                  _statRow(stats.sublist(2)),
                ],
                const SizedBox(height: 12),

                // ---- R2 storage bar (hidden gracefully if cap unknown) ----
                if (health.storageCapBytes != null) _buildStorageBar(c, health),
                if (health.storageCapBytes != null) const SizedBox(height: 22),
                if (health.storageCapBytes == null) const SizedBox(height: 10),

                // ---- Segmented control ----
                _Segmented(
                  value: _seg,
                  onChanged: (v) => setState(() => _seg = v),
                ),
                const SizedBox(height: 16),

                // ---- Content ----
                if (_seg == _OpSeg.kitchen)
                  _buildKitchen(c, agentsState)
                else
                  _buildDocuments(c, docsState),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One stat row: equal-width cells, stretched to the tallest tile.
  Widget _statRow(List<Widget> cells) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cells.length; i++) ...[
            if (i > 0) const SizedBox(width: 11),
            Expanded(child: cells[i]),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Storage bar
  // -------------------------------------------------------------------------
  Widget _buildStorageBar(AppColors c, HealthState health) {
    final cap = health.storageCapBytes!;
    final used = health.storageUsedBytes;
    final pct = (used != null && cap > 0) ? (used / cap).clamp(0.0, 1.0) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl + 1),
        boxShadow: c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 15, color: c.honeyD),
                  const SizedBox(width: 7),
                  Text(
                    context.l10n.r2Storage,
                    style: AppText.titleSm.copyWith(color: c.text),
                  ),
                ],
              ),
              Text(
                used != null
                    ? '${fmtBytes(used)} / ${fmtBytes(cap)}'
                    : context.l10n.storageCapLabel(fmtBytes(cap)),
                style: AppText.mono.copyWith(color: c.textDim),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 10,
              color: c.surface3,
              child: pct == null
                  ? null
                  : FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c.clay, c.honey]),
                        ),
                      ),
                    ),
            ),
          ),
          if (pct == null) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.usageUnavailable,
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Kitchen tab
  // -------------------------------------------------------------------------
  Widget _buildKitchen(AppColors c, AgentsListState state) {
    final l10n = context.l10n;
    final agents = state.agents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: count + new agent.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.agentCount(agents.length),
                style: AppText.label.copyWith(
                  fontSize: 12.5,
                  color: c.textFaint,
                  letterSpacing: 0.6,
                ),
              ),
              Tappable(
                onTap: _showNewAgentSheet,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: c.clayD),
                    const SizedBox(width: 6),
                    Text(
                      l10n.newAgent,
                      style: AppText.title.copyWith(
                        fontSize: 13.5,
                        color: c.clayD,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Manage unbound OAuth clients entry.
        PressCard(
          onPress: _showUnboundClientsSheet,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: c.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.unboundOAuthClients,
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.unboundOAuthSubtitle,
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),

        // Agent list / empty / error.
        if (agents.isEmpty && state.isLoading)
          _loadingTile(c)
        else if (agents.isEmpty && state.hasError)
          _errorTile(
            c,
            l10n.couldNotLoadFleet,
            state.errorMessage,
            () =>
                ref.read(agentsListProvider.notifier).loadNextPage(clear: true),
          )
        else if (agents.isEmpty)
          _emptyTile(c, Icons.person_outline, l10n.noAgentsYet)
        else
          ...List.generate(agents.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RiseIn(
                delay: Duration(milliseconds: (i * 30).clamp(0, 250)),
                child: _AgentRow(
                  agent: agents[i],
                  onPress: () => _openAgentSheet(agents[i]),
                ),
              ),
            );
          }),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Documents tab
  // -------------------------------------------------------------------------
  Widget _buildDocuments(AppColors c, DocumentsListState state) {
    final l10n = context.l10n;
    final all = state.documents;
    final docs = all.where((d) {
      if (!_includeRevoked && d.isRevoked) return false;
      return switch (_statusFilter) {
        _DocStatusFilter.all => true,
        _DocStatusFilter.active => d.status == 'active',
        _DocStatusFilter.deprecated => d.status == 'deprecated',
      };
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppButton(
          l10n.authorDocument,
          variant: AppBtnVariant.primary,
          icon: Icons.edit_note,
          expand: true,
          onPressed: _openCompose,
        ),
        const SizedBox(height: 10),
        // The publication gate's worklist. First among the four entries because
        // it is the only one with a backlog: the other three are maintenance the
        // operator chooses to run, this one is work waiting on them.
        //
        // Deliberately carries no pending count. The honest number needs a full
        // corpus sweep, and the only figure available here is a lower bound over
        // whatever pages the shared list happens to hold — which would sit a few
        // pixels above the very rows whose NOT LIVE badges contradict it. The
        // queue screen is the surface that can claim a number.
        PressCard(
          onPress: _openReviewQueue,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.rate_review_outlined, size: 18, color: c.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.reviewQueue,
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.reviewQueueSubtitle,
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Semantic-search index management (vector backfill).
        PressCard(
          onPress: _openBackfill,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.travel_explore, size: 18, color: c.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.searchIndex,
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.searchIndexSubtitle,
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // The corpus change feed (order=updated) — the only surface that reports
        // classification-only edits, which write no version.
        PressCard(
          onPress: _openChanges,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.history, size: 18, color: c.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.changeFeed,
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.changeFeedSubtitle,
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Link-graph maintenance: rebuild, orphans, retired names.
        PressCard(
          onPress: _openLinkGraph,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.account_tree_outlined, size: 18, color: c.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.linkGraph,
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.linkGraphSubtitle,
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.allDocuments,
                style: AppText.label.copyWith(
                  fontSize: 12.5,
                  color: c.textFaint,
                  letterSpacing: 0.6,
                ),
              ),
              Tappable(
                onTap: () => setState(() => _includeRevoked = !_includeRevoked),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _includeRevoked
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _includeRevoked ? c.clayD : c.textFaint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.includeRevoked,
                      style: AppText.title.copyWith(
                        fontSize: 13,
                        color: _includeRevoked ? c.clayD : c.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _StatusFilterSegmented(
            value: _statusFilter,
            onChanged: (v) => setState(() => _statusFilter = v),
          ),
        ),

        if (docs.isEmpty && state.isLoading)
          _loadingTile(c)
        else if (docs.isEmpty && state.hasError)
          _errorTile(
            c,
            l10n.couldNotLoadDocuments,
            state.errorMessage,
            () => ref
                .read(documentsListProvider.notifier)
                .loadNextPage(clear: true),
          )
        else if (docs.isEmpty)
          _emptyTile(c, Icons.description_outlined, l10n.noDocuments)
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.xl + 2),
              boxShadow: c.shadow,
            ),
            child: Column(
              children: List.generate(docs.length, (i) {
                return _AdminDocRow(
                  doc: docs[i],
                  last: i == docs.length - 1,
                  onOpen: () => _openReader(docs[i]),
                  onMore: () => _openDocActions(docs[i]),
                );
              }),
            ),
          ),
        if (state.hasMore) ...[
          const SizedBox(height: 12),
          AppButton(
            l10n.changeFeedMore,
            icon: Icons.expand_more,
            expand: true,
            onPressed: state.isLoading
                ? null
                : () => ref
                    .read(documentsListProvider.notifier)
                    .loadNextPage(),
          ),
        ],
        if (state.isLoading && docs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: c.clay,
              ),
            ),
          ),
        ],
        if (state.hasError && docs.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            state.errorMessage ?? l10n.couldNotLoadDocuments,
            style: AppText.small.copyWith(color: c.red),
          ),
        ],
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Shared state tiles
  // -------------------------------------------------------------------------
  Widget _loadingTile(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: c.clay),
        ),
      ),
    );
  }

  Widget _emptyTile(AppColors c, IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: c.textFaint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.textDim),
          ),
        ],
      ),
    );
  }

  Widget _errorTile(
    AppColors c,
    String title,
    String? detail,
    VoidCallback onRetry,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 38, color: c.red),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.titleSm.copyWith(color: c.text),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            context.l10n.retry,
            variant: AppBtnVariant.outline,
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Segmented control (port of the mockup `MSeg`).
// ===========================================================================
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final _OpSeg value;
  final ValueChanged<_OpSeg> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(_OpSeg v, String label) {
      final active = v == value;
      return Expanded(
        child: Tappable(
          onTap: () => onChanged(v),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active ? c.shadow : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppText.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? c.text : c.textFaint,
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
        borderRadius: BorderRadius.circular(AppRadii.md + 1),
      ),
      child: Row(
        children: [
          seg(_OpSeg.kitchen, context.l10n.segKitchen),
          const SizedBox(width: 3),
          seg(_OpSeg.docs, context.l10n.segDocuments),
        ],
      ),
    );
  }
}

/// Three-way lifecycle filter (All / Active / Deprecated) for the admin
/// document list — same segmented styling as [_Segmented], typed to
/// [_DocStatusFilter].
class _StatusFilterSegmented extends StatelessWidget {
  const _StatusFilterSegmented({required this.value, required this.onChanged});
  final _DocStatusFilter value;
  final ValueChanged<_DocStatusFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    Widget seg(_DocStatusFilter v, String label) {
      final active = v == value;
      return Expanded(
        child: Tappable(
          onTap: () => onChanged(v),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active ? c.shadow : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppText.body.copyWith(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? c.text : c.textFaint,
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
        borderRadius: BorderRadius.circular(AppRadii.md + 1),
      ),
      child: Row(
        children: [
          seg(_DocStatusFilter.all, l10n.statusFilterAll),
          const SizedBox(width: 3),
          seg(_DocStatusFilter.active, l10n.statusFilterActive),
          const SizedBox(width: 3),
          seg(_DocStatusFilter.deprecated, l10n.statusFilterDeprecated),
        ],
      ),
    );
  }
}

// ===========================================================================
// Agent row (PressCard).
// ===========================================================================
class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.onPress});
  final AgentListing agent;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = c.accentForId(agent.id);
    final online = agent.activeKeys > 0;

    return PressCard(
      onPress: onPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.lineSoft),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: c.shadow,
        ),
        child: Row(
          children: [
            // Decorative accent tile (not data).
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadii.md + 1),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.person_outline, size: 21, color: accent),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    agent.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.monoLabel.copyWith(color: c.textFaint),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Pill(
                        '${agent.activeKeys}/${agent.totalKeys}',
                        tone: PillTone.clay,
                        small: true,
                        icon: Icons.key_outlined,
                      ),
                      const SizedBox(width: 7),
                      Pill(
                        '${agent.liveDocs}',
                        tone: PillTone.neutral,
                        small: true,
                        icon: Icons.description_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: online ? c.green : c.line,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Admin document row (inside the bordered list card).
// ===========================================================================
class _AdminDocRow extends StatelessWidget {
  const _AdminDocRow({
    required this.doc,
    required this.last,
    required this.onOpen,
    required this.onMore,
  });
  final DocumentListing doc;
  final bool last;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final revoked = doc.isRevoked;
    final (tintBg, tintFg) = c.tagTint(
      doc.tags.isEmpty ? null : doc.tags.first,
    );

    return Opacity(
      opacity: revoked ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Tappable(
                onTap: revoked ? null : onOpen,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: tintBg,
                        borderRadius: BorderRadius.circular(AppRadii.sm + 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: tintFg,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title ?? l10n.untitled,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                              decoration: revoked
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            revoked
                                ? l10n.revokedLower
                                : '${l10n.versionLabel('${doc.currentVer ?? 1}')} · ${fmtBytes(doc.currentSize)}',
                            style: AppText.monoLabel.copyWith(
                              fontSize: 11,
                              color: c.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (revoked)
              Pill(l10n.revokedBadge, tone: PillTone.red, small: true)
            else ...[
              if (doc.status == 'deprecated') ...[
                const DeprecatedBadge(),
                const SizedBox(width: 6),
              ],
              // The subtitle above names the head, which since contract 2.0.0 is
              // no longer what a reader of a public document is served: the byte
              // path hands out `published_ver` once anything has been promoted.
              // The listing row carries both numbers, so proven divergence is a
              // pure function of the row and needs no per-document probing. The
              // marker is the shared [NotLiveBadge] so this row reads identically
              // to the same document on the Library, Search and feed surfaces.
              if (doc.hasUnpublishedWork) ...[
                const NotLiveBadge(),
                const SizedBox(width: 6),
              ],
              Icon(
                doc.visibility == 'public' ? Icons.public : Icons.lock_outline,
                size: 14,
                color: c.textFaint,
              ),
              const SizedBox(width: 4),
              AppIconButton(
                Icons.more_horiz,
                size: 18,
                onPressed: onMore,
                tooltip: l10n.documentActionsTooltip,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// New-agent sheet (name input -> createAgent).
// ===========================================================================
class _NewAgentSheet extends StatefulWidget {
  const _NewAgentSheet({required this.onSubmit});
  final Future<void> Function(String name) onSubmit;

  @override
  State<_NewAgentSheet> createState() => _NewAgentSheetState();
}

class _NewAgentSheetState extends State<_NewAgentSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = context.l10n;
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = l10n.nameRequired);
      return;
    }
    if (name.length > 200) {
      setState(() => _error = l10n.nameTooLong);
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(name);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showToast(
          context,
          l10n.failedHireAgent(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: l10n.hireAgentTitle,
      subtitle: l10n.newProfile,
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.hireAgentBody,
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.agentNameLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            enabled: !_submitting,
            autofocus: true,
            style: AppText.body.copyWith(color: c.text),
            decoration: InputDecoration(hintText: l10n.agentNameHint),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppText.small.copyWith(color: c.red)),
          ],
          const SizedBox(height: 18),
          AppButton(
            _submitting ? l10n.hiring : l10n.hireAgent,
            variant: AppBtnVariant.primary,
            icon: Icons.add,
            expand: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Unbound OAuth clients sheet (mint + list/delete from secure storage).
// ===========================================================================
class _UnboundClientsSheet extends StatefulWidget {
  const _UnboundClientsSheet({required this.ref, required this.host});
  final WidgetRef ref;
  final BuildContext host;

  @override
  State<_UnboundClientsSheet> createState() => _UnboundClientsSheetState();
}

class _UnboundClientsSheetState extends State<_UnboundClientsSheet> {
  List<String> _ids = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await SecureStorageService.instance.getUnboundOAuthClientIds();
    if (mounted) {
      setState(() {
        _ids = ids;
        _loading = false;
      });
    }
  }

  Future<void> _mint() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final res = await widget.ref
          .read(agentManagerServiceProvider)
          .mintUnboundOAuthClient();
      await SecureStorageService.instance.addUnboundOAuthClientId(res.clientId);
      await _load();
      if (!widget.host.mounted) return;
      await showSecretSheet(
        widget.host,
        title: l10n.oauthClientCreated,
        fields: [
          SecretField(l10n.clientIdLabel, res.clientId),
          SecretField(l10n.clientSecretLabel, res.clientSecret, secret: true),
          SecretField(l10n.mcpUrlLabel, res.mcpUrl),
        ],
        note: res.note.isEmpty ? null : res.note,
      );
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedMintUnbound(ApiError.describe(e)),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String clientId) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.deleteUnboundTitle,
      body: Text(l10n.deleteUnboundBody(clientId)),
      cta: l10n.deleteClient,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await widget.ref
          .read(agentManagerServiceProvider)
          .deleteOAuthClient(clientId);
      await SecureStorageService.instance.removeUnboundOAuthClientId(clientId);
      await _load();
      if (widget.host.mounted) {
        showToast(widget.host, l10n.unboundClientDeleted);
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedDeleteClient(ApiError.describe(e)),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: l10n.unboundOAuthClients,
      subtitle: l10n.globalConnections,
      icon: Icons.link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.unboundClientsBody,
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 16),
          AppButton(
            _busy ? l10n.working : l10n.mintUnboundClient,
            variant: AppBtnVariant.primary,
            icon: Icons.add,
            expand: true,
            onPressed: _busy ? null : _mint,
          ),
          const SizedBox(height: 20),
          Text(
            l10n.mintedOnThisDevice,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 10),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.clay,
                  ),
                ),
              ),
            )
          else if (_ids.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                l10n.noUnboundClients,
                style: AppText.small.copyWith(
                  fontStyle: FontStyle.italic,
                  color: c.textFaint,
                ),
              ),
            )
          else
            for (final id in _ids)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                decoration: BoxDecoration(
                  color: c.surface2,
                  border: Border.all(color: c.lineSoft),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: c.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.mono.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                    ),
                    AppIconButton(
                      Icons.delete_outline,
                      size: 17,
                      color: c.red,
                      onPressed: _busy ? null : () => _delete(id),
                      tooltip: l10n.deleteClient,
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Agent management sheet (keys, mint key, OAuth client, kill agent).
// ===========================================================================
class _AgentSheet extends ConsumerStatefulWidget {
  const _AgentSheet({
    required this.ref,
    required this.host,
    required this.agent,
  });
  final WidgetRef ref;
  final BuildContext host;
  final AgentListing agent;

  @override
  ConsumerState<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends ConsumerState<_AgentSheet> {
  bool _oauthBusy = false;
  // OAuth discovery state, mirroring agent_detail_screen.
  bool _knowsOAuthExistence = false;
  String? _existingClientId;
  String? _oAuthHint;

  AgentListing get agent => widget.agent;

  Future<void> _mintKey() async {
    final l10n = context.l10n;
    try {
      final res = await widget.ref
          .read(agentManagerServiceProvider)
          .mintAgentKey(agent.id);
      widget.ref.invalidate(agentKeysProvider(agent.id));
      if (!widget.host.mounted) return;
      await showSecretSheet(
        widget.host,
        title: l10n.bearerKeyMinted,
        fields: [SecretField(l10n.keyPlaintextLabel, res.key, secret: true)],
        note: res.note.isEmpty ? null : res.note,
      );
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedMintKey(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  Future<void> _revokeKey(AgentKey key) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.revokeKeyTitle,
      body: Text(l10n.revokeKeyBody(key.keyPrefix)),
      cta: l10n.revokeKeyTitle,
    );
    if (!confirmed) return;
    try {
      await widget.ref.read(agentManagerServiceProvider).revokeAgentKey(key.id);
      widget.ref.invalidate(agentKeysProvider(agent.id));
      if (widget.host.mounted) {
        showToast(widget.host, l10n.keyRevoked(key.keyPrefix));
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedRevokeKey(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  Future<void> _mintOAuth() async {
    final l10n = context.l10n;
    setState(() => _oauthBusy = true);
    try {
      final res = await widget.ref
          .read(agentManagerServiceProvider)
          .mintOAuthClient(agent.id);
      if (mounted) {
        setState(() {
          _knowsOAuthExistence = true;
          _existingClientId = res.clientId;
          _oAuthHint = null;
        });
      }
      if (widget.host.mounted) {
        await showSecretSheet(
          widget.host,
          title: l10n.oauthClientCreated,
          fields: [
            SecretField(l10n.clientIdLabel, res.clientId),
            SecretField(l10n.clientSecretLabel, res.clientSecret, secret: true),
            SecretField(l10n.mcpUrlLabel, res.mcpUrl),
          ],
          note: res.note.isEmpty ? null : res.note,
        );
      }
    } on DioException catch (e) {
      final apiError = ApiError.fromException(e);
      if (apiError.code == ErrorCode.clientExists) {
        if (mounted) {
          setState(() {
            _knowsOAuthExistence = true;
            _existingClientId = apiError.clientId;
            _oAuthHint = apiError.hint;
          });
          showToast(context, l10n.oauthAlreadyExists);
        }
      } else {
        if (mounted) {
          showToast(
            context,
            l10n.failedMintOAuth(ApiError.describe(e)),
            danger: true,
          );
        }
      }
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
    }
  }

  Future<void> _deleteOAuth(String clientId) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.deleteOAuthTitle,
      body: Text(l10n.deleteOAuthBody(clientId)),
      cta: l10n.deleteClient,
    );
    if (!confirmed) return;
    setState(() => _oauthBusy = true);
    try {
      await widget.ref
          .read(agentManagerServiceProvider)
          .deleteOAuthClient(clientId);
      if (mounted) {
        setState(() {
          _knowsOAuthExistence = false;
          _existingClientId = null;
          _oAuthHint = null;
        });
      }
      if (widget.host.mounted) {
        showToast(widget.host, l10n.oauthClientDeleted);
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedDeleteOAuth(ApiError.describe(e)),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
    }
  }

  Future<void> _killAgent() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.killAgentTitle,
      body: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: l10n.cascadingDestruction,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w700,
                color: c.red,
              ),
            ),
            TextSpan(text: l10n.killAgentBody),
          ],
        ),
      ),
      confirmWord: agent.name,
      cta: l10n.killProfile,
    );
    if (!confirmed) return;
    try {
      final res = await widget.ref
          .read(agentsListProvider.notifier)
          .killAgent(agent.id);
      if (widget.host.mounted) {
        showToast(
          widget.host,
          l10n.agentKilled(res.keysRevoked, res.oauthClientsDeleted),
          danger: true,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedKillAgent(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final keysAsync = ref.watch(agentKeysProvider(agent.id));

    return AppSheet(
      title: agent.name,
      subtitle: l10n.agentProfile,
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity line.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    agent.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono.copyWith(color: c.textDim),
                  ),
                ),
                Pill(
                  l10n.docsCountShort(agent.liveDocs),
                  tone: PillTone.neutral,
                  small: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mint key + OAuth client buttons.
          Row(
            children: [
              Expanded(
                child: AppButton(
                  l10n.mintKey,
                  variant: AppBtnVariant.primary,
                  icon: Icons.add,
                  small: true,
                  expand: true,
                  onPressed: _mintKey,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  _oauthBusy ? l10n.working : l10n.oauthClientButton,
                  variant: AppBtnVariant.outline,
                  icon: Icons.link,
                  small: true,
                  expand: true,
                  onPressed: _oauthBusy ? null : _mintOAuth,
                ),
              ),
            ],
          ),

          // OAuth existence card (after a 409 or successful mint).
          if (_knowsOAuthExistence && _existingClientId != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border.all(color: c.lineSoft),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 16, color: c.green),
                      const SizedBox(width: 7),
                      Text(
                        l10n.oauthClientRegistered,
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _existingClientId!,
                    style: AppText.monoLabel.copyWith(color: c.textDim),
                  ),
                  if (_oAuthHint != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _oAuthHint!,
                      style: AppText.small.copyWith(
                        fontStyle: FontStyle.italic,
                        color: c.textFaint,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppButton(
                    l10n.deleteOAuthClientButton,
                    variant: AppBtnVariant.danger,
                    icon: Icons.link_off,
                    small: true,
                    expand: true,
                    onPressed: _oauthBusy
                        ? null
                        : () => _deleteOAuth(_existingClientId!),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            l10n.apiKeysLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 10),

          keysAsync.when(
            data: (result) {
              // A key is surfaced as live only while it still authenticates
              // (neither revoked nor expired — `isActive`). Lapsed-but-un-revoked
              // short-lived publish credentials fall into the inert audit below
              // alongside revoked keys, so the operator never sees a dead key as
              // a live, revocable one.
              final active = result.keys.where((k) => k.isActive).toList();
              final inert = result.keys.where((k) => !k.isActive).toList();
              if (active.isEmpty && inert.isEmpty) {
                return Text(
                  l10n.noKeys,
                  style: AppText.small.copyWith(
                    fontStyle: FontStyle.italic,
                    color: c.textFaint,
                  ),
                );
              }
              return Column(
                children: [
                  for (final k in active)
                    _KeyRow(keyItem: k, onRevoke: () => _revokeKey(k)),
                  if (inert.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        l10n.inactiveAudit(inert.length),
                        style: AppText.label.copyWith(
                          fontSize: 10.5,
                          color: c.textFaint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final k in inert) _KeyRow(keyItem: k),
                  ],
                ],
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.clay,
                  ),
                ),
              ),
            ),
            error: (e, _) => Text(
              l10n.errorFetchingKeys(ApiError.describe(e)),
              style: AppText.small.copyWith(color: c.red),
            ),
          ),

          const SizedBox(height: 20),
          AppButton(
            l10n.killAgentTitle,
            variant: AppBtnVariant.danger,
            icon: Icons.delete_outline,
            expand: true,
            onPressed: _killAgent,
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.keyItem, this.onRevoke});
  final AgentKey keyItem;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final revoked = keyItem.isRevoked;
    // Expired-but-not-revoked: lapsed past its TTL, no longer authenticates.
    final expired = !revoked && keyItem.expired;
    final inactive = !keyItem.isActive; // revoked OR expired — an inert key.
    // Active short-lived credential with a future expiry worth flagging.
    final expiresSoon = !inactive && keyItem.expiresAt != null;
    final String subLabel;
    if (revoked) {
      subLabel = l10n.keyRevokedOn(fmtDate(keyItem.revokedAt));
    } else if (expired) {
      subLabel = l10n.keyExpiredOn(fmtDate(keyItem.expiresAt));
    } else if (expiresSoon) {
      subLabel = l10n.keyExpiresOn(fmtDate(keyItem.expiresAt));
    } else {
      subLabel = l10n.keyMintedOn(fmtDate(keyItem.createdAt));
    }
    return Opacity(
      opacity: inactive ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Icon(
              Icons.key_outlined,
              size: 16,
              color: inactive ? c.textFaint : c.clayD,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    keyItem.keyPrefix,
                    style: AppText.mono.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      decoration: inactive ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    subLabel,
                    style: AppText.small.copyWith(
                      fontSize: 11,
                      color: c.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (revoked)
              Pill(l10n.revokedUpper, tone: PillTone.red, small: true)
            else if (expired)
              Pill(l10n.expiredUpper, tone: PillTone.neutral, small: true)
            else
              Tappable(
                onTap: onRevoke,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    l10n.revoke,
                    style: AppText.title.copyWith(fontSize: 13, color: c.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Document admin actions sheet (visibility / publish / slug / tags / copy /
// revoke).
// ===========================================================================
class _DocActionsSheet extends StatefulWidget {
  const _DocActionsSheet({
    required this.ref,
    required this.host,
    required this.doc,
  });
  final WidgetRef ref;
  final BuildContext host;
  final DocumentListing doc;

  @override
  State<_DocActionsSheet> createState() => _DocActionsSheetState();
}

class _DocActionsSheetState extends State<_DocActionsSheet> {
  late DocumentListing _doc = widget.doc;
  bool _busy = false;

  Future<String?> _baseUrl() => SecureStorageService.instance.getBaseUrl();

  Future<void> _toggleVisibility() async {
    final l10n = context.l10n;
    final next = _doc.visibility == 'public' ? 'private' : 'public';
    final confirmed = await showConfirmSheet(
      widget.host,
      title: next == 'public' ? l10n.makePublic : l10n.makePrivate,
      body: Text(next == 'public' ? l10n.makePublicBody : l10n.makePrivateBody),
      cta: next == 'public' ? l10n.makePublic : l10n.makePrivate,
      danger: false,
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.ref
          .read(documentsListProvider.notifier)
          .updateVisibility(_doc.publicId, next);
      if (mounted) setState(() => _doc = updated);
      if (widget.host.mounted) {
        showToast(widget.host, l10n.visibilitySet(next.toUpperCase()));
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedUpdateVisibility(ApiError.describe(e)),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Toggle lifecycle status. Deprecating routes through the deprecate sheet
  /// (optional superseded_by target); re-activating is a plain confirm — the
  /// backend force-clears the pointer on 'active'.
  Future<void> _toggleStatus() async {
    final l10n = context.l10n;
    final deprecating = _doc.status != 'deprecated';
    String? supersededBy;
    if (deprecating) {
      final target = await showDeprecateSheet(
        widget.host,
        initialTarget: _doc.supersededBy,
      );
      if (target == null) return;
      supersededBy = target.isEmpty ? null : target;
    } else {
      final confirmed = await showConfirmSheet(
        widget.host,
        title: l10n.markActive,
        body: Text(l10n.markActiveBody),
        cta: l10n.markActive,
        danger: false,
      );
      if (!confirmed) return;
    }
    setState(() => _busy = true);
    try {
      final next = deprecating ? 'deprecated' : 'active';
      final updated = await widget.ref
          .read(documentsListProvider.notifier)
          .updateStatus(_doc.publicId, next, supersededBy: supersededBy);
      if (mounted) setState(() => _doc = updated);
      if (widget.host.mounted) {
        showToast(widget.host, l10n.statusSet(next.toUpperCase()));
      }
    } catch (e) {
      if (mounted) {
        showToast(
          context,
          l10n.failedUpdateStatus(ApiError.describe(e)),
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Promote the head to the publication pointer via `POST /admin/documents/:id/
  /// promote` — the operator-only way to move what the HTML byte path serves.
  ///
  /// The Pass publishes the CURRENT version and nothing else. Picking an
  /// arbitrary version out of the history is a different intent (a rollback),
  /// it needs the history's dates, authors and `source_present` to be made
  /// safely, and the Reader already owns that surface; here the two numbers on
  /// the row have already said exactly what would change, so an intermediate
  /// list would be a picker with one sane answer in it. Publishing the head
  /// also costs no extra request, which keeps this sheet instant.
  ///
  /// Promote is not a write — it bumps no version and re-runs no sanitizer — but
  /// it is what the anonymous internet reads, so it is confirmed like one.
  Future<void> _publishCurrent() async {
    final l10n = context.l10n;
    final c = context.colors;
    final version = _doc.currentVer;
    if (version == null) return;

    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.publishVersionTitle(version),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.publishVersionBody(version)),
          // Promote is legal on a private document and worth doing — it stages
          // the choice before the door opens, and the later flip to public keeps
          // it — but nothing about that document is being read by anyone yet, so
          // the sentence above is qualified rather than left to imply it is live.
          if (!_doc.isPublic) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline, size: 15, color: c.textFaint),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.makePrivateBody)),
              ],
            ),
          ],
        ],
      ),
      cta: l10n.publishAction,
      danger: false,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final promoted = await widget.ref
          .read(documentsListProvider.notifier)
          .promoteVersion(_doc.publicId, version);
      // The response is canonical for `published_ver`, so fold it onto the
      // listing this sheet is showing — that copy always exists, whereas the row
      // in the loaded list may not.
      if (mounted) {
        setState(
          () => _doc = _doc.copyWith(publishedVer: promoted.publishedVer),
        );
      }
      if (widget.host.mounted) {
        // Report what the backend actually pointed at rather than what we asked
        // for.
        showToast(widget.host, l10n.publishedToast(promoted.publishedVer));
      }
    } catch (e) {
      if (mounted) {
        // The head we read off the row can be gone by the time we promote it —
        // a restore or a revoke elsewhere rewrites the history under us — and
        // "that version no longer exists" tells the operator to reopen the list
        // in a way that a generic failure does not.
        final code = ApiError.fromException(e).code;
        showToast(
          context,
          code == ErrorCode.versionNotFound
              ? l10n.versionNotFoundToast
              : l10n.publishFailedToast,
          danger: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSlugAndTags() async {
    await showAppSheet<void>(
      widget.host,
      builder: (_) => _EditSlugTagsSheet(
        doc: _doc,
        ref: widget.ref,
        host: widget.host,
        onUpdated: (updated) {
          if (mounted) setState(() => _doc = updated);
        },
      ),
    );
  }

  Future<void> _copySlugUrl() async {
    final l10n = context.l10n;
    final base = await _baseUrl();
    if (base == null || _doc.slug == null) {
      if (widget.host.mounted) {
        showToast(widget.host, l10n.noSlugUrl, danger: true);
      }
      return;
    }
    final url = '$base/s/${_doc.slug}';
    await _copy(url, l10n.slugUrlCopied);
  }

  Future<void> _copy(String value, String msg) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (widget.host.mounted) showToast(widget.host, msg);
  }

  // Revoke uses the exact dio DELETE + local revoke from document_detail_screen.
  Future<void> _revoke() async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.revokeDocumentTitle,
      body: Text(l10n.revokeDocumentBodyShort),
      confirmWord: l10n.revokeConfirmWord,
      cta: l10n.revokePermanently,
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final dio = widget.ref.read(dioProvider);
      final response = await dio.delete('/d/${_doc.publicId}');
      final revoke = RevokeResponse.fromJson(
        response.data as Map<String, dynamic>,
      );

      final now = DateTime.now();
      widget.ref
          .read(documentsListProvider.notifier)
          .revokeDocumentLocally(_doc.publicId, now);

      if (widget.host.mounted) {
        showToast(
          widget.host,
          l10n.documentRevokedPurged(revoke.r2ObjectsPurged),
          danger: true,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(
          context,
          l10n.revocationFailed(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final isPublic = _doc.visibility == 'public';
    final isDeprecated = _doc.status == 'deprecated';
    final currentVer = _doc.currentVer;
    final publishedVer = _doc.publishedVer;
    final servedVer = _doc.servedVer;
    final holdingBack = _doc.hasUnpublishedWork;

    // Promote is only worth offering where it would move something: there has
    // to be a head to point at, and it must not already be the published one
    // (the backend accepts that happily, but it is a no-op dressed up as a
    // decision). Private documents keep the action — promoting one stages the
    // choice before the door opens, and the later flip to public keeps it.
    final canPublish = currentVer != null && publishedVer != currentVer;

    // `hasUnpublishedWork` already proves both numbers are present; restating
    // the null checks here is what lets Dart promote them to non-null.
    final String? unpublishedNote =
        (holdingBack && currentVer != null && publishedVer != null)
        ? l10n.unpublishedWorkNote(currentVer, publishedVer)
        : null;

    return AppSheet(
      title: _doc.title ?? l10n.untitled,
      subtitle: l10n.documentActions,
      icon: Icons.description_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VisBadge(_doc.visibility),
              const SizedBox(width: 8),
              if (isDeprecated) ...[
                const DeprecatedBadge(),
                const SizedBox(width: 8),
              ],
              // The head. A public document that is serving its head says so
              // once, in the pill beside this one, rather than twice.
              if (currentVer != null && (!isPublic || holdingBack))
                Pill(
                  l10n.versionLabel('$currentVer'),
                  tone: PillTone.neutral,
                  small: true,
                ),
              // What a reader is actually handed. Only public documents serve
              // anything, so a private one gets no claim about being live —
              // even when a version has already been staged for it. Honey while
              // the gate holds newer work back, matching the row's marker.
              if (isPublic && servedVer != null) ...[
                if (holdingBack) const SizedBox(width: 8),
                Pill(
                  l10n.liveVersionLabel('$servedVer'),
                  tone: holdingBack ? PillTone.honey : PillTone.neutral,
                  small: true,
                ),
              ],
            ],
          ),
          // Says out loud what the two pills only imply: the newest version is
          // sitting behind the publication gate and every reader — including
          // the anonymous internet — is being handed the older published one.
          if (unpublishedNote != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.pending_outlined, size: 14, color: c.honeyD),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    unpublishedNote,
                    style: AppText.small.copyWith(color: c.honeyD),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.clay,
                  ),
                ),
              ),
            ),
          // Publication leads: it is the only action in this sheet that changes
          // what a reader is handed, and it is what the row's NOT LIVE marker
          // sent the operator in here to do.
          if (canPublish) ...[
            SheetActionRow(
              icon: Icons.publish_outlined,
              label: l10n.publishAction,
              onTap: _busy ? null : _publishCurrent,
            ),
            Divider(color: c.lineSoft, height: 16),
          ],
          SheetActionRow(
            icon: isPublic ? Icons.lock_outline : Icons.public,
            label: isPublic ? l10n.makePrivate : l10n.makePublic,
            onTap: _busy ? null : _toggleVisibility,
          ),
          SheetActionRow(
            icon: isDeprecated ? Icons.task_alt : Icons.history_toggle_off,
            label: isDeprecated ? l10n.markActive : l10n.markDeprecated,
            onTap: _busy ? null : _toggleStatus,
          ),
          SheetActionRow(
            icon: Icons.sell_outlined,
            label: l10n.editSlugTags,
            onTap: _busy ? null : _editSlugAndTags,
          ),
          SheetActionRow(
            icon: Icons.link,
            label: l10n.copySlugUrl,
            onTap: _busy ? null : _copySlugUrl,
          ),
          Divider(color: c.lineSoft, height: 16),
          SheetActionRow(
            icon: Icons.delete_outline,
            label: l10n.revokeDocumentTitle,
            danger: true,
            onTap: _busy ? null : _revoke,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Vector backfill sheet (semantic-search index): index-new vs rebuild.
// ===========================================================================
class _BackfillSheet extends StatefulWidget {
  const _BackfillSheet({required this.ref, required this.host});
  final WidgetRef ref;
  final BuildContext host;

  @override
  State<_BackfillSheet> createState() => _BackfillSheetState();
}

class _BackfillSheetState extends State<_BackfillSheet> {
  bool _busy = false;
  VectorBackfillMode? _running;

  Future<void> _run(VectorBackfillMode mode) async {
    final l10n = context.l10n;
    final rebuild = mode == VectorBackfillMode.rebuild;

    // Confirmation step (required for both modes; rebuild gets the danger CTA).
    final confirmed = await showConfirmSheet(
      widget.host,
      title: rebuild ? l10n.rebuildIndexTitle : l10n.indexNewTitle,
      body: Text(
        rebuild ? l10n.rebuildIndexConfirmBody : l10n.indexNewConfirmBody,
      ),
      cta: rebuild ? l10n.rebuildIndexCta : l10n.indexNewCta,
      danger: rebuild,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _running = mode;
    });
    try {
      final summary = await widget.ref
          .read(documentsListProvider.notifier)
          .backfillVectors(mode);
      if (widget.host.mounted) {
        final String msg;
        final bool danger;
        if (summary.suspectPartialFailure) {
          msg = l10n.backfillPartial(summary.embedded, summary.vectors);
          danger = true;
        } else if (summary.embedded == 0) {
          msg = l10n.backfillUpToDate;
          danger = false;
        } else {
          msg = l10n.backfillDone(
            summary.embedded,
            summary.vectors,
            summary.skipped,
          );
          danger = false;
        }
        showToast(widget.host, msg, danger: danger);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _running = null;
        });
        showToast(
          context,
          l10n.backfillFailed(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: l10n.searchIndex,
      subtitle: l10n.semanticSearch,
      icon: Icons.travel_explore,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.backfillBody,
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 18),
          if (_busy)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border.all(color: c.lineSoft),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: c.clay,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _running == VectorBackfillMode.rebuild
                          ? l10n.rebuildingIndex
                          : l10n.indexingNew,
                      style: AppText.small.copyWith(color: c.textDim),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _BackfillOption(
              icon: Icons.auto_fix_high,
              title: l10n.indexNewTitle,
              body: l10n.indexNewOptionBody,
              onTap: () => _run(VectorBackfillMode.missing),
            ),
            const SizedBox(height: 10),
            _BackfillOption(
              icon: Icons.refresh,
              title: l10n.rebuildIndexTitle,
              body: l10n.rebuildIndexOptionBody,
              danger: true,
              onTap: () => _run(VectorBackfillMode.rebuild),
            ),
          ],
        ],
      ),
    );
  }
}

class _BackfillOption extends StatelessWidget {
  const _BackfillOption({
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = danger ? c.red : c.clayD;
    return PressCard(
      onPress: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(
            color: danger ? c.red.withValues(alpha: 0.30) : c.lineSoft,
          ),
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 19, color: accent),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.titleSm.copyWith(color: c.text)),
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: AppText.small.copyWith(
                      color: c.textFaint,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 20, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Link-graph sheet: rebuild the graph, browse orphans, repair retired names.
// ===========================================================================
class _LinkGraphSheet extends StatefulWidget {
  const _LinkGraphSheet({required this.ref, required this.host});
  final WidgetRef ref;
  final BuildContext host;

  @override
  State<_LinkGraphSheet> createState() => _LinkGraphSheetState();
}

class _LinkGraphSheetState extends State<_LinkGraphSheet> {
  bool _busy = false;

  /// The backfill has only one mode and is cheap, deterministic and idempotent,
  /// so unlike the vector rebuild there is no expensive option to warn about —
  /// but it still confirms, because it rewrites rows across the whole corpus
  /// and a sweep nobody asked for is its own kind of surprise.
  Future<void> _rebuild() async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.linkBackfillTitle,
      body: Text(l10n.linkBackfillConfirmBody),
      cta: l10n.linkBackfillCta,
      danger: false,
    );
    if (!confirmed || !mounted) return;

    setState(() => _busy = true);
    try {
      final summary = await widget.ref
          .read(linkGraphServiceProvider)
          .backfillLinks();
      if (widget.host.mounted) {
        showToast(
          widget.host,
          summary.hasUnreadable
              ? l10n.linkBackfillPartial(summary.unreadable)
              : l10n.linkBackfillDone(summary.updated, summary.links),
          danger: summary.hasUnreadable,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(
          context,
          l10n.linkBackfillFailed(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  void _openOrphans() {
    Navigator.of(context).pop();
    Navigator.of(
      widget.host,
    ).push(MaterialPageRoute(builder: (_) => const OrphansScreen()));
  }

  void _openSlugTombstones() {
    Navigator.of(context).pop();
    showSlugRepairSheet(widget.host);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: l10n.linkGraph,
      subtitle: l10n.backOfHouse,
      icon: Icons.account_tree_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.linkGraphBody,
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 18),
          if (_busy)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border.all(color: c.lineSoft),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: c.clay,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      l10n.linkBackfillRunning,
                      style: AppText.small.copyWith(color: c.textDim),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            _BackfillOption(
              icon: Icons.refresh,
              title: l10n.linkBackfillTitle,
              body: l10n.linkBackfillOptionBody,
              onTap: _rebuild,
            ),
            const SizedBox(height: 10),
            _BackfillOption(
              icon: Icons.filter_drama_outlined,
              title: l10n.orphansTitle,
              body: l10n.orphansSubtitle,
              onTap: _openOrphans,
            ),
            const SizedBox(height: 10),
            _BackfillOption(
              icon: Icons.link_off,
              title: l10n.slugTombstones,
              body: l10n.slugTombstonesSubtitle,
              onTap: _openSlugTombstones,
            ),
          ],
        ],
      ),
    );
  }
}

// ===========================================================================
// Edit slug & tags sheet.
// ===========================================================================
class _EditSlugTagsSheet extends StatefulWidget {
  const _EditSlugTagsSheet({
    required this.doc,
    required this.ref,
    required this.host,
    required this.onUpdated,
  });
  final DocumentListing doc;
  final WidgetRef ref;
  final BuildContext host;
  final ValueChanged<DocumentListing> onUpdated;

  @override
  State<_EditSlugTagsSheet> createState() => _EditSlugTagsSheetState();
}

class _EditSlugTagsSheetState extends State<_EditSlugTagsSheet> {
  late final TextEditingController _slug = TextEditingController(
    text: widget.doc.slug ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.doc.tags.join(', '),
  );
  bool _busy = false;

  @override
  void dispose() {
    _slug.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final notifier = widget.ref.read(documentsListProvider.notifier);
    final newSlug = _slug.text.trim();
    final newTags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    try {
      DocumentListing updated = await notifier.updateSlug(
        widget.doc.publicId,
        newSlug,
      );
      updated = await notifier.updateTags(widget.doc.publicId, newTags);
      widget.onUpdated(updated);
      if (widget.host.mounted) {
        showToast(widget.host, l10n.slugTagsUpdated);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(
          context,
          l10n.failedUpdate(ApiError.describe(e)),
          danger: true,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: l10n.editSlugTags,
      subtitle: l10n.documentMetadata,
      icon: Icons.sell_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.slugLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _slug,
            enabled: !_busy,
            style: AppText.body.copyWith(color: c.text),
            decoration: InputDecoration(hintText: l10n.slugHint),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.slugRetiredNote,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.tagsLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tags,
            enabled: !_busy,
            style: AppText.body.copyWith(color: c.text),
            decoration: InputDecoration(hintText: l10n.tagsHint),
          ),
          const SizedBox(height: 18),
          AppButton(
            _busy ? l10n.saving : l10n.saveChanges,
            variant: AppBtnVariant.primary,
            icon: Icons.check,
            expand: true,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// The compact-layout entry point to the instance quick switcher, shown beside
/// the Operate title.
///
/// Named rather than iconic: an icon would say that switching is possible
/// without saying what is currently selected, and the second half is the part
/// worth a permanent slot on the screen where documents get revoked.
class _InstanceChip extends StatelessWidget {
  const _InstanceChip({required this.instance});

  final SlopcafeInstance instance;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tappable(
      onTap: () => showInstanceSwitcher(context),
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.clay.withValues(alpha: 0.10),
          border: Border.all(color: c.clay.withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.swap_horiz, size: 14, color: c.clayD),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                instance.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label.copyWith(color: c.clayD),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
