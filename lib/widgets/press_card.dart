import 'package:flutter/material.dart';

/// Tactile press feedback: scales the child down slightly while held, like the
/// mockup's `PressCard`. Wrap any tappable card/row. On pointer devices it
/// also shows a click cursor and a whisper of hover lift, so cards read as
/// interactive on desktop.
class PressCard extends StatefulWidget {
  const PressCard({
    super.key,
    required this.child,
    this.onPress,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onPress;
  final BorderRadius? borderRadius;

  @override
  State<PressCard> createState() => _PressCardState();
}

class _PressCardState extends State<PressCard> {
  bool _down = false;
  bool _hover = false;

  void _setDown(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final tappable = widget.onPress != null;
    final scale = _down ? 0.975 : (_hover && tappable ? 1.01 : 1.0);
    return MouseRegion(
      cursor: tappable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onPress,
        onTapDown: (_) => _setDown(true),
        onTapUp: (_) => _setDown(false),
        onTapCancel: () => _setDown(false),
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Drop-in [GestureDetector] for plain tap targets that also shows a click
/// cursor on pointer devices (desktop/web), where a bare GestureDetector gives
/// no affordance at all.
class Tappable extends StatelessWidget {
  const Tappable({super.key, this.onTap, this.behavior, required this.child});

  final VoidCallback? onTap;
  final HitTestBehavior? behavior;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, behavior: behavior, child: child),
    );
  }
}

/// One-shot staggered entrance: fades + rises its child in. [delay] lets callers
/// stagger a list (cap the delay so long lists don't lag).
class RiseIn extends StatefulWidget {
  const RiseIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 10,
  });

  final Widget child;
  final Duration delay;
  final double offset;

  @override
  State<RiseIn> createState() => _RiseInState();
}

class _RiseInState extends State<RiseIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
