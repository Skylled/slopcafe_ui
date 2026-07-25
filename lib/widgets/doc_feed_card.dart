import 'package:flutter/material.dart';

import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../core/publication.dart';
import '../l10n/l10n.dart';
import '../api/api.dart';
import 'pill.dart';
import 'press_card.dart';
import 'section_header.dart';

/// A text-forward document card — the Cortado "plate". No cover art: the title is
/// the star, with a visibility marker pinned top-right. [featured] only gives a
/// larger, hero-weight treatment (used by the Library's "Today's Special" slot);
/// the "special" labeling itself is owned by the homepage, not this widget. Used
/// across the browse/list screens (Collections, Recently plated → See all). Tags
/// are tappable when [onTagTap] is provided.
class DocFeedCard extends StatelessWidget {
  const DocFeedCard({
    super.key,
    required this.doc,
    required this.onOpen,
    this.onTagTap,
    this.featured = false,
  });

  final DocumentListing doc;
  final void Function(DocumentListing) onOpen;
  final void Function(String tag)? onTagTap;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final isRevoked = doc.isRevoked;
    final isPublic = doc.visibility == 'public';
    final titleStyle = featured
        ? AppText.featured
        : AppText.titleSerif.copyWith(fontSize: 21, height: 1.18);

    return PressCard(
      onPress: () => onOpen(doc),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(featured ? 18 : 16),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: featured ? c.line : c.lineSoft),
          borderRadius: BorderRadius.circular(AppRadii.card),
          boxShadow: c.shadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    doc.title ?? l10n.untitled,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: titleStyle.copyWith(
                      color: isRevoked ? c.textFaint : c.text,
                      decoration: isRevoked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Visibility marker pinned to the top-right, optically aligned
                // with the title's first line.
                if (isRevoked)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Pill(
                      l10n.revokedUpper,
                      tone: PillTone.red,
                      icon: Icons.block,
                      small: true,
                    ),
                  )
                else ...[
                  if (doc.status == 'deprecated')
                    const Padding(
                      padding: EdgeInsets.only(top: 2, right: 6),
                      child: DeprecatedBadge(),
                    ),
                  Padding(
                    padding: EdgeInsets.only(top: featured ? 6 : 4),
                    child: Icon(
                      isPublic ? Icons.public : Icons.lock_outline,
                      size: 15,
                      color: c.textFaint,
                    ),
                  ),
                ],
              ],
            ),
            if (!isRevoked &&
                doc.description != null &&
                doc.description!.trim().isNotEmpty) ...[
              SizedBox(height: featured ? 10 : 8),
              Text(
                doc.description!.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: AppText.body.copyWith(color: c.textDim),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Flexible(
                  child: Text(
                    doc.createdByName ?? l10n.unknownAgent,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.small.copyWith(
                      color: c.textDim,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (doc.currentVer != null) ...[
                  const MetaDot(),
                  Text(
                    l10n.versionLabel('${doc.currentVer}'),
                    style: AppText.monoLabel.copyWith(color: c.textFaint),
                  ),
                  // The version this row names is the document's head, which
                  // since contract 2.0.0 is not necessarily what a reader is
                  // served, so the marker sits with the number it qualifies
                  // rather than up in the status corner. A revoked document
                  // serves nobody, so the publication gate is moot there — the
                  // same reason the DEPRECATED badge stays off a revoked card.
                  if (!isRevoked && doc.hasUnpublishedWork) ...[
                    const SizedBox(width: 6),
                    const NotLiveBadge(),
                  ],
                ],
                const MetaDot(),
                Text(
                  relTime(l10n, doc.createdAt),
                  style: AppText.small.copyWith(color: c.textFaint),
                ),
              ],
            ),
            if (doc.tags.isNotEmpty) ...[
              SizedBox(height: featured ? 14 : 12),
              // Single line: tags overflow into a horizontal scroll rather than
              // wrapping, keeping every card a predictable height.
              SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  itemCount: doc.tags.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 7),
                  itemBuilder: (context, i) {
                    final t = doc.tags[i];
                    return TagChip(
                      t,
                      onTap: onTagTap == null ? null : () => onTagTap!(t),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// NOT LIVE marker — contract 2.0.0's publication gate, seen from a listing row.
///
/// Render it only where [DocumentPublication.hasUnpublishedWork] holds: the
/// document is public, a version has been promoted, and it is not the current
/// one, so everybody reading the document — the anonymous internet included —
/// is served older bytes than the version the row names. The listing is the
/// reliable place to say this: every row already carries `visibility` and
/// `published_ver`, so the state is known without probing each document.
///
/// It is deliberately the same honey [Pill] as [DeprecatedBadge]. Both are
/// cautions about a document's state rather than the red of a revoked kill, and
/// they have to read as siblings on the surfaces where they land together.
class NotLiveBadge extends StatelessWidget {
  const NotLiveBadge({super.key, this.small = true});
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Pill(
      context.l10n.notLiveBadge,
      tone: PillTone.honey,
      icon: Icons.pending_outlined,
      small: small,
    );
  }
}
