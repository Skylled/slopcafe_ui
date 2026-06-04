import 'package:flutter/material.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';

/// Serif section title with an optional trailing action (e.g. "See all").
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2, right: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(title, style: AppText.headline.copyWith(color: c.text)),
          ),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(
                action!,
                style: AppText.title.copyWith(fontSize: 13.5, color: c.clayD),
              ),
            ),
        ],
      ),
    );
  }
}

/// The faint "·" separator used between inline metadata.
class MetaDot extends StatelessWidget {
  const MetaDot({super.key});
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Text(
        '·',
        style: TextStyle(
          color: context.colors.textFaint.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// Uppercase eyebrow label.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: AppText.label.copyWith(
        fontSize: 12.5,
        letterSpacing: 0.8,
        color: color ?? context.colors.textFaint,
      ),
    );
  }
}
