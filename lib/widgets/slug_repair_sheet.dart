import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/links_provider.dart';
import 'app_button.dart';
import 'sheets.dart';
import 'toast.dart';

/// Repair a retired slug: point it at a live document, drop that redirect, or
/// release the name entirely.
///
/// Unlike [showDeprecateSheet], this sheet owns its own writes rather than
/// returning a decision for the caller to act on. It offers three different
/// mutations against two endpoints, and it is reached from two unrelated places
/// — a broken outbound link in the Reader's link report, and the manual entry
/// in Operate — so handing the POSTs back to the caller would duplicate the
/// error mapping at both sites.
///
/// [initialSlug] pre-fills the name when the caller already knows it (every
/// path except the manual one). The sheet still shows the field: the contract
/// exposes no way to browse retired slugs, so typing one is a first-class way
/// in rather than a fallback.
Future<void> showSlugRepairSheet(
  BuildContext context, {
  String? initialSlug,
}) {
  return showAppSheet<void>(
    context,
    builder: (_) => _SlugRepairSheet(host: context, initialSlug: initialSlug),
  );
}

class _SlugRepairSheet extends ConsumerStatefulWidget {
  const _SlugRepairSheet({required this.host, this.initialSlug});
  final BuildContext host;
  final String? initialSlug;

  @override
  ConsumerState<_SlugRepairSheet> createState() => _SlugRepairSheetState();
}

class _SlugRepairSheetState extends ConsumerState<_SlugRepairSheet> {
  late final _slugController = TextEditingController(
    text: widget.initialSlug ?? '',
  );
  final _targetController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _slugController.dispose();
    _targetController.dispose();
    super.dispose();
  }

  String get _slug => _slugController.text.trim();
  String get _target => _targetController.text.trim();

  /// Maps the two failures these routes have their own codes for, so the
  /// operator is told which precondition they missed rather than that
  /// something went wrong. `not_found` here never means "no such document" —
  /// on a slug route it means the name isn't retired.
  String _describeFailure(Object error, AppLocalizations l10n) {
    return switch (ApiError.fromException(error).code) {
      ErrorCode.notFound => l10n.slugNotRetiredToast,
      ErrorCode.badTarget => l10n.slugBadTargetToast,
      _ => l10n.failedSlugUpdate(ApiError.describe(error)),
    };
  }

  /// Runs [action] with the sheet's busy/error plumbing, then reports [success]
  /// on the host and closes. The toast goes to the host context because this
  /// sheet is gone by the time it renders.
  Future<void> _run(
    Future<String> Function(LinkGraphService service) action,
  ) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final message = await action(ref.read(linkGraphServiceProvider));
      if (widget.host.mounted) showToast(widget.host, message);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showToast(context, _describeFailure(e, l10n), danger: true);
    }
  }

  Future<void> _setRedirect() {
    final l10n = context.l10n;
    return _run((service) async {
      final result = await service.setSlugRedirect(_slug, _target);
      return l10n.slugRedirectSet(result.slug, result.redirectTo);
    });
  }

  Future<void> _clearRedirect() {
    final l10n = context.l10n;
    return _run((service) async {
      final result = await service.clearSlugRedirect(_slug);
      return l10n.slugRedirectCleared(result.slug);
    });
  }

  Future<void> _release() async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: l10n.slugReleaseTitle,
      body: Text(l10n.slugReleaseBody),
      cta: l10n.slugReleaseCta,
    );
    if (!confirmed || !mounted) return;
    await _run((service) async {
      final result = await service.releaseSlug(_slug);
      return l10n.slugReleasedToast(result.slug);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final hasSlug = _slug.isNotEmpty;
    final canAct = hasSlug && !_busy;

    return AppSheet(
      title: l10n.slugTombstones,
      subtitle: l10n.linkGraph,
      icon: Icons.link_off,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.slugTombstoneBody,
            style: AppText.body.copyWith(fontSize: 14.5, color: c.textDim),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.slugLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _slugController,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            style: AppText.mono.copyWith(fontSize: 14, color: c.text),
            decoration: InputDecoration(hintText: l10n.slugLabel.toLowerCase()),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.slugTombstoneLookupNote,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: 18),
          Text(
            l10n.slugRedirectLabel,
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _targetController,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            style: AppText.mono.copyWith(fontSize: 14, color: c.text),
            decoration: InputDecoration(hintText: l10n.supersededByHint),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.slugRedirectNote,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: 18),
          AppButton(
            l10n.slugSetRedirect,
            variant: AppBtnVariant.primary,
            icon: Icons.subdirectory_arrow_right,
            expand: true,
            onPressed: (canAct && _target.isNotEmpty) ? _setRedirect : null,
          ),
          const SizedBox(height: 10),
          AppButton(
            l10n.slugClearRedirect,
            variant: AppBtnVariant.outline,
            icon: Icons.link_off,
            expand: true,
            onPressed: canAct ? _clearRedirect : null,
          ),
          const SizedBox(height: 10),
          AppButton(
            l10n.slugRelease,
            variant: AppBtnVariant.danger,
            icon: Icons.delete_outline,
            expand: true,
            onPressed: canAct ? _release : null,
          ),
        ],
      ),
    );
  }
}
