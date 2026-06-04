import 'package:flutter/material.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../l10n/l10n.dart';
import 'press_card.dart';

enum PillTone { neutral, clay, honey, red, green, solid }

/// Small rounded status/label chip — the Craft `Pill` primitive.
class Pill extends StatelessWidget {
  const Pill(
    this.label, {
    super.key,
    this.tone = PillTone.neutral,
    this.small = false,
    this.icon,
    this.mono = false,
  });

  final String label;
  final PillTone tone;
  final bool small;
  final IconData? icon;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color fg, Color border) = switch (tone) {
      PillTone.neutral => (c.surface2, c.textDim, c.lineSoft),
      PillTone.clay => (
        c.clay.withValues(alpha: 0.14),
        c.clay,
        c.clay.withValues(alpha: 0.30),
      ),
      PillTone.honey => (
        c.honey.withValues(alpha: 0.15),
        c.honeyD,
        c.honey.withValues(alpha: 0.32),
      ),
      PillTone.red => (
        c.red.withValues(alpha: 0.14),
        c.red,
        c.red.withValues(alpha: 0.30),
      ),
      PillTone.green => (
        c.green.withValues(alpha: 0.15),
        c.green,
        c.green.withValues(alpha: 0.32),
      ),
      PillTone.solid => (c.clay, c.onAccent, c.clay),
    };
    final fontSize = small ? 10.5 : 12.0;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 7 : 10,
        vertical: small ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 1, color: fg),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: (mono ? AppText.monoLabel : AppText.pill).copyWith(
              fontSize: fontSize,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

/// PUBLIC / PRIVATE visibility badge.
class VisBadge extends StatelessWidget {
  const VisBadge(this.visibility, {super.key, this.small = true});
  final String visibility;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final isPublic = visibility == 'public';
    return Pill(
      isPublic ? context.l10n.visibilityPublic : context.l10n.visibilityPrivate,
      tone: isPublic ? PillTone.honey : PillTone.neutral,
      icon: isPublic ? Icons.public : Icons.lock_outline,
      small: small,
    );
  }
}

/// A tag chip tinted by [AppColors.tagTint]. When [onTap] is provided it gains
/// press feedback and is meant to navigate into that tag's collection — the
/// shared affordance used on cards, the Collections list, and the Reader.
class TagChip extends StatelessWidget {
  const TagChip(this.tag, {super.key, this.onTap, this.small = false});

  final String tag;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (bg, fg) = c.tagTint(tag);
    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: small ? 8 : 10,
        vertical: small ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: fg.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sell_outlined, size: small ? 10.5 : 12, color: fg),
          const SizedBox(width: 5),
          Text(
            tag,
            style: AppText.monoLabel.copyWith(
              fontSize: small ? 10.5 : 11.5,
              color: fg,
            ),
          ),
        ],
      ),
    );
    return onTap == null ? chip : PressCard(onPress: onTap, child: chip);
  }
}
