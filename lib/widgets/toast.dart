import 'package:flutter/material.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';

/// Lightweight floating toast, styled to match the Craft `useToast` node.
void showToast(BuildContext context, String message, {bool danger = false}) {
  final c = context.colors;
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(milliseconds: 2400),
      width: null,
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surface3,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            danger ? Icons.warning_amber_rounded : Icons.check,
            size: 16,
            color: danger ? c.red : c.honeyD,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message,
              style: AppText.title.copyWith(fontSize: 13.5, color: c.text),
            ),
          ),
        ],
      ),
    ),
  );
}
