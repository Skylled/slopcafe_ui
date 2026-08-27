import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/api_client.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/instances.dart';
import '../l10n/l10n.dart';
import '../providers/instances_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/cafe_logo.dart';
import '../widgets/instance_switcher.dart';
import '../widgets/section_header.dart';
import '../widgets/sheets.dart';
import '../widgets/toast.dart';

/// The Pass — operator connection setup, and the manager for every saved
/// Slopcafe deployment.
///
/// Pushed route (its own Scaffold + AppBar titled "Connection"), or the
/// first-run destination when nothing is configured yet ([firstRun]).
///
/// Two things share the screen. The **instance list** is the set of saved
/// deployments: tap one to switch, or use its menu to edit or forget it. The
/// **form** below composes a new instance, or edits the one selected from that
/// list. The double-probe connection test (`GET /healthz`, then
/// `GET /admin/agents?limit=1` with a Bearer token) is unchanged, and still runs
/// against whatever is typed in the form rather than against what is saved — so
/// a new deployment can be proven before it is committed.
///
/// The quick switcher in the shell ([showInstanceSwitcher]) covers the frequent
/// case; this screen is where the set itself is curated.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.firstRun = false});

  /// True when this is the first-launch gate rather than a pushed route: there
  /// is no instance list to show, no route to pop back to, and saving hands off
  /// to `RootGate`, which swaps in the shell as soon as an instance exists.
  final bool firstRun;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testingConnection = false;
  bool _saving = false;
  String? _testResult;
  bool _resultIsError = false;

  /// The instance the form is editing, or null when it is composing a new one.
  /// This is the screen's one mode bit: it decides the form's header, its
  /// primary button, and whether saving upserts or appends.
  String? _editingId;

  @override
  void dispose() {
    _labelController.dispose();
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// Load [instance] into the form for editing.
  void _beginEdit(SlopcafeInstance instance) {
    setState(() {
      _editingId = instance.id;
      _labelController.text = instance.label;
      _urlController.text = instance.baseUrl;
      _tokenController.text = instance.operatorToken;
      // A probe result describes the credentials that were on screen when it
      // ran, so it is stale the moment the form is repopulated.
      _testResult = null;
      _resultIsError = false;
    });
  }

  /// Return the form to compose-a-new-instance mode.
  void _resetForm() {
    setState(() {
      _editingId = null;
      _labelController.clear();
      _urlController.clear();
      _tokenController.clear();
      _testResult = null;
      _resultIsError = false;
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    setState(() {
      _testingConnection = true;
      _testResult = null;
      _resultIsError = false;
    });

    final dio = ref.read(dioProvider);
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    try {
      // Both probes address `url` absolutely and carry their own token, so the
      // test proves the credentials *in the form* rather than the ones already
      // saved — which is what lets a second deployment be verified before it is
      // committed, while some other instance is still the active one.
      final probeOptions = Options(extra: const {kProbeRequestExtra: true});

      // 1. Health Probe (unauthenticated).
      final healthResponse = await dio.get(
        '$url/healthz',
        options: probeOptions,
      );

      // 2. Auth Probe (Bearer token).
      final authResponse = await dio.get(
        '$url/admin/agents?limit=1',
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          extra: const {kProbeRequestExtra: true},
        ),
      );

      if (healthResponse.statusCode == 200 && authResponse.statusCode == 200) {
        final health = HealthzResponse.fromJson(
          healthResponse.data as Map<String, dynamic>,
        );
        setState(() {
          _resultIsError = false;
          _testResult = l10n.connectionSuccessResult(
            health.sanitizerVersion,
            '${health.storageCapBytes}',
          );
        });
        ref
            .read(connectionStateProvider.notifier)
            .setStatus(ConnectionStatus.connected);
      } else {
        setState(() {
          _resultIsError = true;
          _testResult = l10n.connectionProbeFailed;
        });
      }
    } catch (e) {
      setState(() {
        _resultIsError = true;
        _testResult = l10n.connectionFailed(ApiError.describe(e));
      });
    } finally {
      if (mounted) {
        setState(() {
          _testingConnection = false;
        });
      }
    }
  }

  /// Commit the form — as an edit to [_editingId], or as a new instance.
  ///
  /// Either path reloads the fleet against the affected deployment (see
  /// [InstancesNotifier]), so this awaits real network work and holds the
  /// buttons disabled while it runs.
  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final notifier = ref.read(instancesProvider.notifier);
    final editingId = _editingId;

    setState(() => _saving = true);
    String label;
    try {
      if (editingId != null) {
        await notifier.edit(
          id: editingId,
          baseUrl: _urlController.text,
          operatorToken: _tokenController.text,
          label: _labelController.text,
        );
        label =
            ref.read(instancesProvider).value?.byId(editingId)?.label ??
            _labelController.text;
      } else {
        final added = await notifier.add(
          baseUrl: _urlController.text,
          operatorToken: _tokenController.text,
          label: _labelController.text,
        );
        label = added.label;
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;

    showToast(
      context,
      editingId != null
          ? l10n.instanceUpdated(label)
          : l10n.instanceAdded(label),
    );

    if (widget.firstRun) {
      // `RootGate` watches the same provider and swaps in the shell on its own
      // as soon as an instance exists — there is nothing to pop back to here.
      return;
    }
    if (editingId != null) {
      _resetForm();
    } else {
      navigator.maybePop();
    }
  }

  Future<void> _switchTo(SlopcafeInstance instance) async {
    final l10n = context.l10n;
    setState(() => _saving = true);
    try {
      await ref.read(instancesProvider.notifier).switchTo(instance.id);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    showToast(context, l10n.switchedToInstance(instance.label));
  }

  Future<void> _removeInstance(SlopcafeInstance instance) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      context,
      title: l10n.removeInstanceTitle,
      body: Text(l10n.removeInstanceBody(instance.label)),
      cta: l10n.removeInstance,
      danger: true,
    );
    if (!confirmed || !mounted) return;

    await ref.read(instancesProvider.notifier).remove(instance.id);
    if (_editingId == instance.id) _resetForm();
    if (!mounted) return;
    showToast(context, l10n.instanceRemoved(instance.label));
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    await ref.read(instancesProvider.notifier).clearAll();
    if (!mounted) return;
    _resetForm();
    showToast(context, l10n.secureStorageCleared);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final connectionState = ref.watch(connectionStateProvider);
    final isUnauthorized =
        connectionState.status == ConnectionStatus.unauthorized;
    final set = ref.watch(instancesProvider).value;
    final instances = set?.instances ?? const <SlopcafeInstance>[];
    final activeId = set?.activeId;
    final editing = _editingId == null ? null : set?.byId(_editingId!);
    final busy = _testingConnection || _saving;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        // First run is the root: there is no route underneath to go back to.
        leading: widget.firstRun ? null : const BackButton(),
        automaticallyImplyLeading: false,
        title: Text(l10n.connectionTitle),
      ),
      body: Form(
        key: _formKey,
        child: AdaptiveGutter(
          maxContent: AppLayout.formMax,
          builder: (context, gutter) => ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              AppSpacing.lg,
              gutter,
              AppSpacing.bottomInset,
            ),
            children: [
              if (isUnauthorized) ...[
                _UnauthorizedBanner(
                  message:
                      connectionState.errorMessage ?? l10n.tokenRejectedDetail,
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
              _IntroCard(),
              const SizedBox(height: AppSpacing.xxl),

              // ---- Saved instances -------------------------------------
              // Hidden on first run, where the list is necessarily empty and a
              // header over nothing is just noise.
              if (instances.isNotEmpty) ...[
                SectionHeader(l10n.instancesSection),
                for (final instance in instances) ...[
                  InstanceRow(
                    instance: instance,
                    active: instance.id == activeId,
                    onTap: busy ? null : () => _switchTo(instance),
                    trailing: _InstanceMenu(
                      enabled: !busy,
                      onEdit: () => _beginEdit(instance),
                      onRemove: () => _removeInstance(instance),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                const SizedBox(height: AppSpacing.xl),
              ] else if (!widget.firstRun) ...[
                Text(
                  l10n.noInstancesYet,
                  style: AppText.body.copyWith(color: c.textDim),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              // ---- Add / edit form -------------------------------------
              Row(
                children: [
                  Expanded(
                    child: SectionHeader(
                      editing != null
                          ? l10n.editInstanceSection(editing.label)
                          : instances.isEmpty
                          ? l10n.credentialsSection
                          : l10n.addInstanceSection,
                    ),
                  ),
                  if (editing != null)
                    TextButton(
                      onPressed: busy ? null : _resetForm,
                      child: Text(l10n.cancelEdit),
                    ),
                ],
              ),
              _FieldLabel(l10n.instanceLabelLabel),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _labelController,
                autocorrect: false,
                style: AppText.body.copyWith(color: c.text),
                decoration: InputDecoration(
                  hintText: l10n.instanceLabelHint,
                  prefixIcon: const Icon(Icons.badge_outlined),
                ),
                // Deliberately not required: a blank name falls back to the
                // host, which is a better default than refusing the save.
              ),
              const SizedBox(height: AppSpacing.lg),
              _FieldLabel(l10n.baseUrlLabel),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _urlController,
                keyboardType: TextInputType.url,
                autocorrect: false,
                style: AppText.body.copyWith(color: c.text),
                decoration: InputDecoration(
                  hintText: l10n.baseUrlHint,
                  prefixIcon: const Icon(Icons.link),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.baseUrlRequired;
                  }
                  if (!value.startsWith('http://') &&
                      !value.startsWith('https://')) {
                    return l10n.baseUrlInvalidScheme;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              _FieldLabel(l10n.operatorTokenLabel),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _tokenController,
                obscureText: _obscureToken,
                autocorrect: false,
                enableSuggestions: false,
                style: AppText.mono.copyWith(color: c.text),
                decoration: InputDecoration(
                  hintText: l10n.operatorTokenHint,
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? l10n.showToken : l10n.hideToken,
                    icon: Icon(
                      _obscureToken
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: c.textDim,
                    ),
                    onPressed: () =>
                        setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.operatorTokenRequired;
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      _testingConnection
                          ? l10n.testingConnection
                          : l10n.testConnection,
                      variant: AppBtnVariant.outline,
                      icon: Icons.bolt,
                      expand: true,
                      onPressed: busy ? null : _testConnection,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      _saving
                          ? l10n.switchingInstance
                          : editing != null
                          ? l10n.saveInstanceButton
                          : instances.isEmpty
                          ? l10n.saveAndContinue
                          : l10n.addInstanceButton,
                      variant: AppBtnVariant.primary,
                      icon: Icons.check,
                      expand: true,
                      onPressed: busy ? null : _saveSettings,
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: AppSpacing.xl),
                _ResultPanel(text: _testResult!, isError: _resultIsError),
              ],
              const SizedBox(height: AppSpacing.xxl),
              Divider(color: c.lineSoft, height: 1),
              const SizedBox(height: AppSpacing.xl),
              _DangerCard(onClear: _clearAll),
            ],
          ),
        ),
      ),
    );
  }
}

/// Warm welcome card that frames what this screen configures.
class _IntroCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadii.card),
        border: Border.all(color: c.lineSoft),
        boxShadow: c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: c.clay.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                  border: Border.all(color: c.clay.withValues(alpha: 0.22)),
                ),
                child: const CafeLogo(size: 24),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(context.l10n.thePass, color: c.clayD),
                    const SizedBox(height: 4),
                    Text(
                      context.l10n.openTheLine,
                      style: AppText.headline.copyWith(color: c.text),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.l10n.connectionIntroBody,
            style: AppText.body.copyWith(color: c.textDim),
          ),
        ],
      ),
    );
  }
}

/// Small uppercase label above an input field.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Text(
      text.toUpperCase(),
      style: AppText.label.copyWith(color: c.textDim),
    );
  }
}

/// Banner shown when the global connection state is `unauthorized` (401).
class _UnauthorizedBanner extends StatelessWidget {
  const _UnauthorizedBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: c.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, color: c.red, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.tokenRejectedHeading,
                  style: AppText.titleSm.copyWith(color: c.red),
                ),
                const SizedBox(height: 3),
                Text(message, style: AppText.small.copyWith(color: c.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Mono panel that renders the result of the connection test.
class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.text, required this.isError});
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = isError ? c.red : c.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                size: 15,
                color: accent,
              ),
              const SizedBox(width: 7),
              Text(
                (isError ? context.l10n.probeFailed : context.l10n.probeResult)
                    .toUpperCase(),
                style: AppText.monoLabel.copyWith(color: accent),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(text, style: AppText.mono.copyWith(color: c.text)),
        ],
      ),
    );
  }
}

/// Destructive zone: clears all locally-stored secure credentials.
class _DangerCard extends StatelessWidget {
  const _DangerCard({required this.onClear});
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: c.red.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.clearSecureStorageTitle,
            style: AppText.title.copyWith(color: c.text),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.clearSecureStorageBody,
            style: AppText.small.copyWith(color: c.textDim),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            context.l10n.clearSecureStorageButton,
            variant: AppBtnVariant.danger,
            icon: Icons.delete_outline,
            onPressed: onClear,
          ),
        ],
      ),
    );
  }
}

/// The per-instance overflow menu in the Settings list: edit, or forget.
///
/// Switching is the row tap, so the menu carries only the two actions that are
/// not the common case — which keeps a mis-aimed tap on a busy list from
/// forgetting a deployment.
class _InstanceMenu extends StatelessWidget {
  const _InstanceMenu({
    required this.enabled,
    required this.onEdit,
    required this.onRemove,
  });

  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return PopupMenuButton<_InstanceAction>(
      enabled: enabled,
      tooltip: '',
      icon: Icon(Icons.more_horiz, size: 20, color: c.textDim),
      onSelected: (action) => switch (action) {
        _InstanceAction.edit => onEdit(),
        _InstanceAction.remove => onRemove(),
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _InstanceAction.edit,
          child: Text(l10n.editInstance),
        ),
        PopupMenuItem(
          value: _InstanceAction.remove,
          child: Text(
            l10n.removeInstance,
            style: AppText.body.copyWith(color: c.red),
          ),
        ),
      ],
    );
  }
}

enum _InstanceAction { edit, remove }
