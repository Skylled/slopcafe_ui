import 'package:flutter/material.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';

/// Small card showing a number + caption (the Library "tickers").
class MiniStat extends StatelessWidget {
  const MiniStat({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: AppText.featured.copyWith(fontSize: 30, color: c.text),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppText.small.copyWith(fontSize: 11, color: c.textFaint),
          ),
        ],
      ),
    );
  }
}

/// Labelled metric tile for the Operate stat grid.
class OpStat extends StatelessWidget {
  const OpStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.sub,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? sub;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.label.copyWith(
                    fontSize: 10.5,
                    color: c.textFaint,
                  ),
                ),
              ),
              Icon(icon, size: 15, color: c.clayD),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            value,
            style: (mono ? AppText.mono : AppText.featured).copyWith(
              fontSize: mono ? 19 : 28,
              fontWeight: mono ? FontWeight.w700 : FontWeight.w400,
              color: c.text,
              height: 1.0,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 5),
            Text(
              sub!,
              style: AppText.small.copyWith(fontSize: 11.5, color: c.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}
