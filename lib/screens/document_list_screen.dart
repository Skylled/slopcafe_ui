import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../l10n/l10n.dart';
import '../api/api.dart';
import '../providers/document_provider.dart';
import '../widgets/doc_feed_card.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import 'reader_screen.dart';

/// A pushed browse screen rendering documents as text-forward [DocFeedCard]s.
///
/// Powers both "Recently plated → See all" (newest-first) and a single tag's
/// collection ([tag] set). Documents are read straight from the shared
/// [documentsListProvider] and filtered client-side, so the listing stays
/// consistent with the Library's tag counts and works offline.
class DocumentListScreen extends ConsumerWidget {
  const DocumentListScreen({
    super.key,
    required this.title,
    this.eyebrow,
    this.tag,
    this.limit,
  });

  final String title;
  final String? eyebrow;

  /// When set, only documents carrying this tag are shown.
  final String? tag;

  /// Optional cap on the number of (newest-first) documents shown.
  final int? limit;

  /// Push a screen browsing every document carrying [tag]. The shared tag-tap
  /// affordance used by cards, the Collections list, and the Reader.
  static void openForTag(BuildContext context, String tag) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DocumentListScreen(
          title: titleCase(tag),
          eyebrow: context.l10n.collectionEyebrow,
          tag: tag,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final docState = ref.watch(documentsListProvider);

    final live = docState.documents.where((d) => !d.isRevoked).where((d) {
      return tag == null || d.tags.contains(tag);
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final docs = limit != null ? live.take(limit!).toList() : live;

    final topInset = MediaQuery.paddingOf(context).top + 12;

    void openDoc(DocumentListing doc) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: AdaptiveGutter(
        builder: (context, gutter) => ListView(
          padding: EdgeInsets.fromLTRB(
            gutter,
            topInset,
            gutter,
            AppSpacing.bottomInset,
          ),
          children: [
            BackHeader(title, eyebrow: eyebrow),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 14),
              child: Text(
                context.l10n.documentCount(docs.length),
                style: AppText.small.copyWith(color: c.textFaint),
              ),
            ),
            if (docs.isEmpty)
              _empty(context, c)
            else
              for (var i = 0; i < docs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: RiseIn(
                    delay: Duration(milliseconds: (i * 40).clamp(0, 300)),
                    child: DocFeedCard(
                      doc: docs[i],
                      onOpen: openDoc,
                      onTagTap: (t) =>
                          DocumentListScreen.openForTag(context, t),
                    ),
                  ),
                ),
          ],
        ),
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
            Icon(Icons.coffee_outlined, size: 30, color: c.textFaint),
            const SizedBox(height: 12),
            Text(
              context.l10n.nothingPlatedHere,
              style: AppText.titleSerif.copyWith(color: c.text),
            ),
          ],
        ),
      ),
    );
  }
}
