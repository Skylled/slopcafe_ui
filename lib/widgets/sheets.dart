import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../l10n/l10n.dart';
import 'app_button.dart';
import 'toast.dart';
import 'press_card.dart';

/// Presents [builder] as a rounded-top modal bottom sheet. The builder should
/// return an [AppSheet] (or any widget) — the sheet handles scrolling and the
/// keyboard inset itself. On wide layouts the sheet is capped at
/// [AppLayout.sheetMax] and centered rather than stretching across the window.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: const Color(0x66241E18),
    constraints: const BoxConstraints(maxWidth: AppLayout.sheetMax),
    builder: builder,
  );
}

/// Standard Cortado bottom-sheet shell: grab handle, sticky header (eyebrow
/// subtitle, serif title, optional leading badge, close button) and a scrollable
/// body. Resizes above the keyboard.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.emoji,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final String? emoji;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final maxH = MediaQuery.sizeOf(context).height * 0.86;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: maxH),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadii.sheet),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: c.surface3,
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  Row(
                    children: [
                      if (emoji != null || icon != null) ...[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(AppRadii.md),
                          ),
                          alignment: Alignment.center,
                          child: emoji != null
                              ? Text(
                                  emoji!,
                                  style: const TextStyle(fontSize: 20),
                                )
                              : Icon(icon, size: 20, color: c.clayD),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (subtitle != null)
                              Text(
                                subtitle!.toUpperCase(),
                                style: AppText.label.copyWith(
                                  fontSize: 11.5,
                                  color: c.textFaint,
                                ),
                              ),
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppText.headline.copyWith(
                                fontSize: 23,
                                color: c.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CircleClose(onTap: () => Navigator.of(context).pop()),
                    ],
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleClose extends StatelessWidget {
  const _CircleClose({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface2,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.close, size: 16, color: c.textDim),
        ),
      ),
    );
  }
}

/// Tappable list row used inside sheets (more-menu, agent actions).
class SheetActionRow extends StatelessWidget {
  const SheetActionRow({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.danger = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final color = danger ? c.red : c.text;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 19, color: danger ? c.red : c.textDim),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: AppText.body.copyWith(
                  fontSize: 16,
                  fontWeight: danger ? FontWeight.w700 : FontWeight.w500,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A read-only field with a copy-to-clipboard button. Secrets render in red.
class CopyField extends StatefulWidget {
  const CopyField({
    super.key,
    required this.label,
    required this.value,
    this.secret = false,
  });
  final String label;
  final String value;
  final bool secret;

  @override
  State<CopyField> createState() => _CopyFieldState();
}

class _CopyFieldState extends State<CopyField> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
          decoration: BoxDecoration(
            color: c.surface2,
            border: Border.all(color: c.lineSoft),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    widget.value,
                    style: AppText.mono.copyWith(
                      fontWeight: FontWeight.w700,
                      color: widget.secret ? c.red : c.text,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.value));
                    if (!context.mounted) return;
                    setState(() => _copied = true);
                    Future.delayed(const Duration(milliseconds: 1400), () {
                      if (mounted) setState(() => _copied = false);
                    });
                  },
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: Icon(
                      _copied ? Icons.check : Icons.copy_outlined,
                      size: 15,
                      color: _copied ? c.honeyD : c.textDim,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class SecretField {
  const SecretField(this.label, this.value, {this.secret = false});
  final String label;
  final String value;
  final bool secret;
}

/// One-shot secret reveal sheet: a danger warning, copyable fields, a
/// "stored it" acknowledgement, and a dismiss button gated on the checkbox.
class SecretSheet extends StatefulWidget {
  const SecretSheet({
    super.key,
    required this.title,
    required this.fields,
    this.note,
  });
  final String title;
  final List<SecretField> fields;
  final String? note;

  @override
  State<SecretSheet> createState() => _SecretSheetState();
}

class _SecretSheetState extends State<SecretSheet> {
  bool _stored = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: widget.title,
      subtitle: l10n.shownOnce,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
              color: c.red.withValues(alpha: 0.09),
              border: Border.all(color: c.red.withValues(alpha: 0.26)),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 17, color: c.red),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    l10n.secretWarning,
                    style: AppText.small.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (var i = 0; i < widget.fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 13),
            CopyField(
              label: widget.fields[i].label,
              value: widget.fields[i].value,
              secret: widget.fields[i].secret,
            ),
          ],
          if (widget.note != null) ...[
            const SizedBox(height: 13),
            Text(
              widget.note!,
              style: AppText.small.copyWith(
                fontStyle: FontStyle.italic,
                color: c.textFaint,
              ),
            ),
          ],
          const SizedBox(height: 18),
          _Check(
            value: _stored,
            onChanged: (v) => setState(() => _stored = v),
            label: l10n.secretStoredAck,
          ),
          const SizedBox(height: 16),
          AppButton(
            l10n.dismissPurgeSecret,
            variant: AppBtnVariant.danger,
            icon: Icons.check,
            expand: true,
            onPressed: _stored ? () => Navigator.of(context).pop() : null,
          ),
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final ValueChanged<bool> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tappable(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: value ? c.clay : c.surface2,
              border: Border.all(color: value ? c.clay : c.line),
              borderRadius: BorderRadius.circular(7),
            ),
            child: value
                ? Icon(Icons.check, size: 14, color: c.onAccent)
                : null,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              label,
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.textDim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Deprecate-document sheet: explains the lifecycle state and takes an
/// optional `superseded_by` replacement public_id. Returns the trimmed target
/// (`''` = deprecate with no successor) when confirmed, or null on cancel.
/// The caller owns the actual `POST …/status` call, like [showConfirmSheet].
Future<String?> showDeprecateSheet(
  BuildContext context, {
  String? initialTarget,
}) {
  return showAppSheet<String?>(
    context,
    builder: (_) => _DeprecateSheet(initialTarget: initialTarget),
  );
}

class _DeprecateSheet extends StatefulWidget {
  const _DeprecateSheet({this.initialTarget});
  final String? initialTarget;

  @override
  State<_DeprecateSheet> createState() => _DeprecateSheetState();
}

class _DeprecateSheetState extends State<_DeprecateSheet> {
  late final _controller = TextEditingController(
    text: widget.initialTarget ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: l10n.markDeprecated,
      subtitle: l10n.documentProperties,
      icon: Icons.history_toggle_off,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.markDeprecatedBody,
            style: AppText.body.copyWith(fontSize: 14.5, color: c.textDim),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.supersededByLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            style: AppText.mono.copyWith(fontSize: 14, color: c.text),
            decoration: InputDecoration(hintText: l10n.supersededByHint),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.supersededByNote,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  l10n.cancel,
                  variant: AppBtnVariant.outline,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AppButton(
                  l10n.markDeprecated,
                  variant: AppBtnVariant.warm,
                  icon: Icons.history_toggle_off,
                  expand: true,
                  onPressed: () =>
                      Navigator.of(context).pop(_controller.text.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows a destructive-confirmation sheet. Returns `true` when confirmed. When
/// [confirmWord] is set, the CTA stays disabled until it is typed exactly.
Future<bool> showConfirmSheet(
  BuildContext context, {
  required String title,
  required Widget body,
  String? confirmWord,
  required String cta,
  bool danger = true,
}) async {
  final result = await showAppSheet<bool>(
    context,
    builder: (_) => _ConfirmSheet(
      title: title,
      body: body,
      confirmWord: confirmWord,
      cta: cta,
      danger: danger,
    ),
  );
  return result ?? false;
}

class _ConfirmSheet extends StatefulWidget {
  const _ConfirmSheet({
    required this.title,
    required this.body,
    required this.confirmWord,
    required this.cta,
    required this.danger,
  });
  final String title;
  final Widget body;
  final String? confirmWord;
  final String cta;
  final bool danger;

  @override
  State<_ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<_ConfirmSheet> {
  final _controller = TextEditingController();
  bool get _ok =>
      widget.confirmWord == null ||
      _controller.text.trim() == widget.confirmWord;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return AppSheet(
      title: widget.title,
      subtitle: l10n.confirmAction,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefaultTextStyle.merge(
            style: AppText.body.copyWith(fontSize: 14.5, color: c.textDim),
            child: widget.body,
          ),
          if (widget.confirmWord != null) ...[
            const SizedBox(height: 16),
            Text.rich(
              TextSpan(
                style: AppText.small.copyWith(color: c.textDim),
                children: [
                  TextSpan(text: l10n.typeToConfirmPrefix),
                  TextSpan(
                    text: widget.confirmWord,
                    style: AppText.mono.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.red,
                    ),
                  ),
                  TextSpan(text: l10n.typeToConfirmSuffix),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              style: AppText.mono.copyWith(fontSize: 14, color: c.text),
              decoration: InputDecoration(hintText: widget.confirmWord),
            ),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  l10n.cancel,
                  variant: AppBtnVariant.outline,
                  expand: true,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: AppButton(
                  widget.cta,
                  variant: widget.danger
                      ? AppBtnVariant.danger
                      : AppBtnVariant.primary,
                  icon: widget.danger ? Icons.delete_outline : Icons.check,
                  expand: true,
                  onPressed: _ok ? () => Navigator.of(context).pop(true) : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Convenience: present a [SecretSheet].
Future<void> showSecretSheet(
  BuildContext context, {
  required String title,
  required List<SecretField> fields,
  String? note,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => SecretSheet(title: title, fields: fields, note: note),
  );
}

/// Re-export so callers can pop with a toast in one import.
void sheetToast(BuildContext context, String message, {bool danger = false}) =>
    showToast(context, message, danger: danger);
