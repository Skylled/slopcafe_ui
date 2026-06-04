import 'package:flutter/material.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';

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
      isPublic ? 'PUBLIC' : 'PRIVATE',
      tone: isPublic ? PillTone.honey : PillTone.neutral,
      icon: isPublic ? Icons.public : Icons.lock_outline,
      small: small,
    );
  }
}

/// Badge for documents whose content is available from the local cache.
class OfflineReadyBadge extends StatelessWidget {
  const OfflineReadyBadge({super.key, this.small = true});
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Pill(
      'OFFLINE READY',
      tone: PillTone.green,
      icon: Icons.offline_pin_outlined,
      small: small,
    );
  }
}
