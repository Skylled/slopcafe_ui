import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/instances.dart';
import '../l10n/l10n.dart';
import '../providers/instances_provider.dart';
import '../screens/settings_screen.dart';
import 'pill.dart';
import 'press_card.dart';
import 'sheets.dart';
import 'toast.dart';

/// The quick switcher — the one-tap path between saved deployments.
///
/// Settings owns adding, editing and removing instances; this owns the thing the
/// operator does dozens of times a day, and it is deliberately reachable without
/// entering Settings at all. It is opened from the side rail's logo on desktop
/// and from the Operate header's chip on phones (see `app_shell.dart` and
/// `operate_screen.dart`), so both idioms reach it from the surface the operator
/// is already looking at.
Future<void> showInstanceSwitcher(BuildContext context) {
  return showAppSheet<void>(
    context,
    builder: (_) => const _InstanceSwitcherSheet(),
  );
}

class _InstanceSwitcherSheet extends ConsumerStatefulWidget {
  const _InstanceSwitcherSheet();

  @override
  ConsumerState<_InstanceSwitcherSheet> createState() =>
      _InstanceSwitcherSheetState();
}

class _InstanceSwitcherSheetState
    extends ConsumerState<_InstanceSwitcherSheet> {
  /// The instance a switch is in flight for, so its row can show the spinner
  /// while the fleet reloads. A switch awaits real network work, and the sheet
  /// stays open through it — closing on tap would drop the operator back onto a
  /// shell still showing the previous deployment's rows.
  String? _switchingTo;

  Future<void> _switch(SlopcafeInstance instance) async {
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    setState(() => _switchingTo = instance.id);
    try {
      await ref.read(instancesProvider.notifier).switchTo(instance.id);
    } finally {
      if (mounted) setState(() => _switchingTo = null);
    }
    if (!mounted) return;
    navigator.pop();
    showToast(context, l10n.switchedToInstance(instance.label));
  }

  void _openSettings() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final set = ref.watch(instancesProvider).value;
    final instances = set?.instances ?? const <SlopcafeInstance>[];
    final activeId = set?.activeId;

    return AppSheet(
      title: l10n.instanceSwitcherTitle,
      subtitle: l10n.instanceSwitcherSubtitle,
      icon: Icons.swap_horiz,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final instance in instances) ...[
            InstanceRow(
              instance: instance,
              active: instance.id == activeId,
              busy: _switchingTo == instance.id,
              // A switch already in flight disables every row, so two taps in
              // quick succession cannot race two fleet reloads against each
              // other.
              onTap: _switchingTo != null ? null : () => _switch(instance),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.xs),
          SheetActionRow(
            icon: Icons.settings_outlined,
            label: l10n.connectionTitle,
            onTap: _switchingTo != null ? null : _openSettings,
          ),
        ],
      ),
    );
  }
}

/// One saved deployment, as a selectable card.
///
/// Shared by the quick switcher and the Settings instance list so the two never
/// drift on what an instance looks like. [trailing] is where Settings hangs its
/// edit/remove menu; the switcher leaves it null.
class InstanceRow extends StatelessWidget {
  const InstanceRow({
    super.key,
    required this.instance,
    required this.active,
    this.busy = false,
    this.onTap,
    this.trailing,
  });

  final SlopcafeInstance instance;
  final bool active;
  final bool busy;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    return PressCard(
      onPress: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          // The active instance is tinted rather than merely ticked: on a
          // surface whose whole job is "which deployment am I about to act
          // on", that answer should survive a glance.
          color: active ? c.clay.withValues(alpha: 0.08) : c.surface,
          border: Border.all(
            color: active ? c.clay.withValues(alpha: 0.34) : c.lineSoft,
          ),
          borderRadius: BorderRadius.circular(AppRadii.card),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: busy
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.clay,
                      ),
                    )
                  : Icon(
                      active
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      size: 20,
                      color: active ? c.clay : c.textFaint,
                    ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          instance.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.title.copyWith(
                            color: active ? c.clayD : c.text,
                          ),
                        ),
                      ),
                      if (active) ...[
                        const SizedBox(width: AppSpacing.sm),
                        Pill(
                          l10n.instanceActive,
                          tone: PillTone.clay,
                          small: true,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    instance.baseUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono.copyWith(
                      fontSize: 12,
                      color: c.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
