import 'package:flutter/material.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';

enum AppBtnVariant { normal, primary, warm, ghost, danger, outline }

/// The Cortado `Btn` primitive — a labelled, optionally-iconed button with the
/// design's variant set. Use [expand] to fill the available width.
class AppButton extends StatelessWidget {
  const AppButton(
    this.label, {
    super.key,
    this.onPressed,
    this.variant = AppBtnVariant.normal,
    this.icon,
    this.small = false,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppBtnVariant variant;
  final IconData? icon;
  final bool small;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final disabled = onPressed == null;
    final (Color bg, Color fg, Color border) = switch (variant) {
      AppBtnVariant.normal => (c.surface2, c.text, c.line),
      AppBtnVariant.primary => (c.clay, c.onAccent, c.clay),
      AppBtnVariant.warm => (c.honey, c.onAccent, c.honey),
      AppBtnVariant.ghost => (
        Colors.transparent,
        c.textDim,
        Colors.transparent,
      ),
      AppBtnVariant.danger => (
        c.red.withValues(alpha: 0.14),
        c.red,
        c.red.withValues(alpha: 0.35),
      ),
      AppBtnVariant.outline => (Colors.transparent, c.text, c.line),
    };
    final fontSize = small ? 13.0 : 14.0;
    final child = Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: bg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.md),
          side: BorderSide(color: border),
        ),
        child: InkWell(
          onTap: disabled ? null : onPressed,
          borderRadius: BorderRadius.circular(AppRadii.md),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? 12 : 16,
              vertical: small ? 7 : 10,
            ),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: small ? 15 : 17, color: fg),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(
                      fontSize: fontSize,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: child) : child;
  }
}

/// Square icon button (the Cortado `IconBtn`) with an optional active state.
class AppIconButton extends StatelessWidget {
  const AppIconButton(
    this.icon, {
    super.key,
    this.onPressed,
    this.active = false,
    this.tooltip,
    this.size = 18,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final bool active;
  final String? tooltip;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = color ?? (active ? c.clay : c.textDim);
    final btn = Material(
      color: active ? c.clay.withValues(alpha: 0.14) : Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.sm + 2),
        side: BorderSide(
          color: active ? c.clay.withValues(alpha: 0.30) : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppRadii.sm + 2),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: size, color: fg),
        ),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
