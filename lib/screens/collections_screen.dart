import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../l10n/l10n.dart';
import '../providers/document_provider.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import 'document_list_screen.dart';

/// Collections — browse the full tag list. Each row opens that tag's
/// collection via [DocumentListScreen]. Tag counts are computed client-side
/// from the loaded documents, matching the Library's Collections carousel.
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final docState = ref.watch(documentsListProvider);

    final live = docState.documents.where((d) => !d.isRevoked).toList();
    final tagCounts = <String, int>{};
    for (final d in live) {
      for (final t in d.tags) {
        tagCounts[t] = (tagCounts[t] ?? 0) + 1;
      }
    }
    final tags =
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
          BackHeader(
            context.l10n.collectionsTitle,
            eyebrow: context.l10n.browseByTag,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 14),
            child: Text(
              context.l10n.collectionCount(tags.length),
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ),
          if (tags.isEmpty)
            _empty(context, c)
          else
            for (var i = 0; i < tags.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 11),
                child: RiseIn(
                  delay: Duration(milliseconds: (i * 30).clamp(0, 300)),
                  child: _CollectionRow(
                    tag: tags[i],
                    count: tagCounts[tags[i]] ?? 0,
                    onTap: () =>
                        DocumentListScreen.openForTag(context, tags[i]),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, AppColors c) {
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
            Icon(Icons.sell_outlined, size: 30, color: c.textFaint),
            const SizedBox(height: 12),
            Text(
              context.l10n.noCollectionsYet,
              style: AppText.titleSerif.copyWith(color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionRow extends StatelessWidget {
  const _CollectionRow({
    required this.tag,
    required this.count,
    required this.onTap,
  });
  final String tag;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = c.tagTint(tag);
    return PressCard(
      onPress: onTap,
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
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Icon(Icons.sell_outlined, size: 20, color: fg),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titleCase(tag),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.documentCount(count),
                    style: AppText.small.copyWith(
                      fontSize: 12.5,
                      color: c.textFaint,
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
