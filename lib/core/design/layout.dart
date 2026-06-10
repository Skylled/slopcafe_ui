import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Cortado adaptive-layout tokens & helpers for large-screen (tablet / desktop)
/// surfaces.
///
/// The system is deliberately small: one width breakpoint decides the shell's
/// navigation idiom (floating pill tab bar vs side rail), and every scrolling
/// screen centers its content into a readable column by growing its horizontal
/// gutter — list code and paddings otherwise stay exactly as they are on
/// phones.
class AppLayout {
  AppLayout._();

  /// Window width at which the shell switches from the floating bottom tab bar
  /// to the side navigation rail (Material 3's compact/medium boundary).
  static const double railBreakpoint = 600;

  /// Max readable width for general content columns (lists, stats, forms).
  static const double contentMax = 760;

  /// Max width for the Reader's document surface — a touch wider than
  /// [contentMax] since the backend HTML brings its own margins.
  static const double readerMax = 860;

  /// Max width for form-centric columns (Settings, sheets' siblings) — forms
  /// read poorly when their inputs stretch to the full content width.
  static const double formMax = 640;

  /// Max width for modal bottom sheets on wide layouts.
  static const double sheetMax = 560;

  /// Width of the shell's side navigation rail.
  static const double railWidth = 84;

  /// Bottom scroll inset for the three shell tabs when the floating tab bar is
  /// replaced by the rail (nothing floats over the content anymore).
  static const double bottomInsetWide = 28;

  /// The horizontal gutter that centers a content column of at most [max]
  /// inside [width]: the standard mobile screen gutter until the column would
  /// exceed [max], then half the surplus.
  static double gutterFor(
    double width, {
    double max = contentMax,
    double min = AppSpacing.screenH,
  }) => math.max(min, (width - max) / 2);
}

/// `context.isExpandedLayout` — whether the *window* is wide enough for the
/// side-rail idiom. Keyed off the full window width (not local constraints) so
/// the shell and its tabs always agree on which idiom is active.
extension AppLayoutContext on BuildContext {
  bool get isExpandedLayout =>
      MediaQuery.sizeOf(this).width >= AppLayout.railBreakpoint;

  /// Bottom scroll inset for shell tabs: clears the floating tab bar on
  /// compact layouts, shrinks to plain breathing room under the rail.
  double get shellBottomInset =>
      isExpandedLayout ? AppLayout.bottomInsetWide : AppSpacing.bottomInset;
}

/// Provides the centered readable-column gutter for the available width.
/// Wrap a screen's scrollable and use [builder]'s `gutter` as the horizontal
/// padding — on phones it is exactly [AppSpacing.screenH], so compact layouts
/// are untouched.
class AdaptiveGutter extends StatelessWidget {
  const AdaptiveGutter({
    super.key,
    this.maxContent = AppLayout.contentMax,
    required this.builder,
  });

  final double maxContent;
  final Widget Function(BuildContext context, double gutter) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => builder(
        context,
        AppLayout.gutterFor(constraints.maxWidth, max: maxContent),
      ),
    );
  }
}
