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

/// Header for a pushed browse screen: a circular back button beside a serif
/// title with an optional uppercase eyebrow. Mirrors the Library display type.
class BackHeader extends StatelessWidget {
  const BackHeader(this.title, {super.key, this.eyebrow});
  final String title;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _CircleBack(onTap: () => Navigator.of(context).maybePop()),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (eyebrow != null) ...[
                Eyebrow(eyebrow!),
                const SizedBox(height: 3),
              ],
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.display.copyWith(fontSize: 30, color: c.text),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleBack extends StatelessWidget {
  const _CircleBack({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: c.shadow),
      child: Material(
        color: c.surface,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.chevron_left, size: 22, color: c.clayD),
          ),
        ),
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
