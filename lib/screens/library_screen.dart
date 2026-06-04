import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../models/document.dart';
import '../providers/agent_provider.dart';
import '../providers/document_provider.dart';
import '../widgets/doc_feed_card.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import '../widgets/stat.dart';
import 'collections_screen.dart';
import 'document_list_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// Library — "The Café" home tab.
///
/// Greets the operator, surfaces fleet/menu tickers, a featured "Today's
/// Special" document, tag-based collections, and a recently-plated list. All
/// data binds to the unchanged document/agent/connection providers; offline
/// awareness mirrors the old DocumentsScreen (cache-backed list + per-doc
/// "OFFLINE READY" badge derived from [DocumentCacheManager.getCachedVersion]).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    // Trigger the initial loads for both lists when they're empty. Provider
    // mutation must happen after the first frame, never during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(documentsListProvider).documents.isEmpty) {
        ref.read(documentsListProvider.notifier).loadNextPage(clear: true);
      }
      if (ref.read(agentsListProvider).agents.isEmpty) {
        ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
      }
    });
  }

  void _openDoc(DocumentListing doc) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final docState = ref.watch(documentsListProvider);
    final agentState = ref.watch(agentsListProvider);

    // Live = non-revoked documents (mirrors mockup's `DOCS.filter(!revokedAt)`).
    final live = docState.documents.where((d) => !d.isRevoked).toList();
    final publicCount = live.where((d) => d.visibility == 'public').length;

    // Featured: newest non-revoked public doc, falling back to the first doc.
    final DocumentListing? featured = _pickFeatured(live, docState.documents);

    // Recently plated: non-revoked docs, newest first, capped at 7.
    final recent = [...live]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final recentTop = recent.take(7).toList();

    // Tag counts from the aggregated tag set, scoped to live documents.
    final tagCounts = <String, int>{};
    for (final d in live) {
      for (final t in d.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    final collections =
        docState.aggregatedTags.where((t) => (tagCounts[t] ?? 0) > 0).toList()
          ..sort((a, b) => (tagCounts[b] ?? 0).compareTo(tagCounts[a] ?? 0));

    final topInset = MediaQuery.paddingOf(context).top + 12;

    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          topInset,
          AppSpacing.screenH,
          AppSpacing.bottomInset,
        ),
        children: [
          _header(c),
          const SizedBox(height: 18),
          if (docState.isOffline) ...[
            _offlineBanner(c),
            const SizedBox(height: 14),
          ],
          _tickers(c, live.length, agentState.agents.length, publicCount),
          const SizedBox(height: 26),
          if (featured != null) ...[
            RiseIn(
              child: DocFeedCard(
                doc: featured,
                featured: true,
                onOpen: _openDoc,
                onTagTap: (t) => DocumentListScreen.openForTag(context, t),
              ),
            ),
            const SizedBox(height: 26),
          ],
          if (collections.isNotEmpty) ...[
            SectionHeader(
              'Collections',
              action: 'All',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CollectionsScreen()),
              ),
            ),
            _collections(c, collections, tagCounts),
            const SizedBox(height: 26),
          ],
          SectionHeader(
            'Recently plated',
            action: 'See all',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const DocumentListScreen(
                  title: 'Recently plated',
                  eyebrow: 'Most recent first',
                ),
              ),
            ),
          ),
          _recentlyPlated(c, recentTop, docState.isLoading),
        ],
      ),
    );
  }

  DocumentListing? _pickFeatured(
    List<DocumentListing> live,
    List<DocumentListing> all,
  ) {
    if (live.isEmpty) {
      return all.isEmpty ? null : all.first;
    }
    final publics = live.where((d) => d.visibility == 'public').toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (publics.isNotEmpty) return publics.first;
    return live.first;
  }

  // ---- Header: greeting + "The Café" + connection-status pill ----
  Widget _header(AppColors c) {
    final conn = ref.watch(connectionStateProvider);
    final (String label, Color dot, Color textColor) = switch (conn.status) {
      ConnectionStatus.connected => ('Live', c.green, c.textDim),
      ConnectionStatus.unauthorized => ('Token rejected', c.red, c.red),
      ConnectionStatus.disconnected => ('Disconnected', c.textFaint, c.textDim),
      ConnectionStatus.connecting => ('Connecting', c.honey, c.textDim),
      ConnectionStatus.initial => ('Connect', c.textFaint, c.textDim),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${greeting()}, Operator',
                style: AppText.titleSm.copyWith(
                  fontSize: 13.5,
                  color: c.textFaint,
                ),
              ),
              const SizedBox(height: 3),
              Text('The Café', style: AppText.display.copyWith(color: c.text)),
            ],
          ),
        ),
        const SizedBox(width: 12),
        PressCard(
          onPress: _openSettings,
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 7, 12, 7),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              boxShadow: c.shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: dot,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: dot.withValues(alpha: 0.20),
                        blurRadius: 0,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(label, style: AppText.pill.copyWith(color: textColor)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _offlineBanner(AppColors c) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: c.honey.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: c.honey.withValues(alpha: 0.32)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: c.honeyD),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              'Offline — showing cached documents.',
              style: AppText.small.copyWith(
                color: c.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Three MiniStat tickers ----
  Widget _tickers(AppColors c, int liveDocs, int agents, int publicDocs) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: MiniStat(value: '$liveDocs', label: 'on the menu'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniStat(value: '$agents', label: 'cooks on the line'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniStat(value: '$publicDocs', label: 'public plates'),
          ),
        ],
      ),
    );
  }

  // ---- Collections horizontal carousel ----
  Widget _collections(AppColors c, List<String> tags, Map<String, int> counts) {
    return SizedBox(
      height: 132,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        itemCount: tags.length,
        separatorBuilder: (_, _) => const SizedBox(width: 11),
        itemBuilder: (context, i) {
          final tag = tags[i];
          final count = counts[tag] ?? 0;
          final (bg, fg) = c.tagTint(tag);
          return RiseIn(
            delay: Duration(milliseconds: (i * 30).clamp(0, 300)),
            child: PressCard(
              onPress: () => DocumentListScreen.openForTag(context, tag),
              child: Container(
                width: 132,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.lineSoft),
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  boxShadow: c.shadow,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(Icons.sell_outlined, size: 18, color: fg),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      titleCase(tag),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.title.copyWith(color: c.text),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count document${count == 1 ? '' : 's'}',
                      style: AppText.small.copyWith(
                        fontSize: 12.5,
                        color: c.textFaint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ---- Recently plated card-list ----
  Widget _recentlyPlated(
    AppColors c,
    List<DocumentListing> docs,
    bool isLoading,
  ) {
    if (docs.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.lineSoft),
          borderRadius: BorderRadius.circular(AppRadii.xxl),
          boxShadow: c.shadow,
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.coffee_outlined, size: 30, color: c.textFaint),
                    const SizedBox(height: 12),
                    Text(
                      'Nothing plated yet.',
                      style: AppText.titleSerif.copyWith(color: c.text),
                    ),
                  ],
                ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xxl),
        boxShadow: c.shadow,
      ),
      child: Column(
        children: [
          for (var i = 0; i < docs.length; i++)
            RiseIn(
              delay: Duration(milliseconds: (i * 40).clamp(0, 300)),
              child: _DocRow(
                doc: docs[i],
                onOpen: _openDoc,
                isLast: i == docs.length - 1,
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Recently-plated document row
// ============================================================
class _DocRow extends StatelessWidget {
  const _DocRow({
    required this.doc,
    required this.onOpen,
    required this.isLast,
  });

  final DocumentListing doc;
  final void Function(DocumentListing) onOpen;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final firstTag = doc.tags.isNotEmpty ? doc.tags.first : null;
    final (tintBg, tintFg) = c.tagTint(firstTag);
    final isPublic = doc.visibility == 'public';

    return PressCard(
      onPress: () => onOpen(doc),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        decoration: BoxDecoration(
          border: isLast ? null : Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        child: Row(
          children: [
            // Tagged tile with a tag/doc icon.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tintBg,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Icon(
                firstTag != null
                    ? Icons.sell_outlined
                    : Icons.description_outlined,
                size: 20,
                color: tintFg,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    doc.title ?? '[Untitled]',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSerif.copyWith(color: c.text),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          firstTag ?? 'untagged',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small.copyWith(
                            fontSize: 12.5,
                            color: tintFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const MetaDot(),
                      Text(
                        'v${doc.currentVer ?? '—'}',
                        style: AppText.monoLabel.copyWith(color: c.textFaint),
                      ),
                      const MetaDot(),
                      Text(
                        relTime(doc.createdAt),
                        style: AppText.small.copyWith(
                          fontSize: 12.5,
                          color: c.textFaint,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              isPublic ? Icons.public : Icons.lock_outline,
              size: isPublic ? 15 : 14,
              color: c.textFaint,
            ),
          ],
        ),
      ),
    );
  }
}
