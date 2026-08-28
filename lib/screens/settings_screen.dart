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
import '../widgets/section_header.dart';
import '../widgets/toast.dart';

/// The Pass — operator connection setup for Insight's one hardcoded
/// deployment ([kInsightBaseUrl]).
///
/// Pushed route (its own Scaffold + AppBar titled "Connection"), or the
/// first-run destination when no token is saved yet ([firstRun]).
///
/// Insight is a read-only fork of the generic operator app (see the project
/// CLAUDE.md) and this screen is where that shows up most: there is no Base
/// URL field and no saved-instance list to manage — [SlopcafeInstance] and
/// [InstanceSet] underneath still model a set of deployments, seeded by
/// [SecureStorageService.load] to exactly one, but nothing here lets an
/// operator add a second. The form is just a token, tested against
/// [kInsightBaseUrl] with a reader-safe probe (`GET /d?limit=1` — *not*
/// `/admin/agents`, which 401s a valid reader token) and saved with
/// [InstancesNotifier.edit]. Signing out ([InstancesNotifier.signOut]) clears
/// the token without discarding the instance, so there is always something to
/// sign back into.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.firstRun = false});

  /// True when this is the first-launch gate rather than a pushed route:
  /// there is no route to pop back to, and saving hands off to `RootGate`,
  /// which swaps in the shell as soon as the hardcoded instance has a token.
  final bool firstRun;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testingConnection = false;
  bool _saving = false;
  String? _testResult;
  bool _resultIsError = false;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
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
    final token = _tokenController.text.trim();

    try {
      // Both probes carry their own token and address the hardcoded instance
      // absolutely, so the test proves the credential *typed into the form*
      // rather than whatever is already saved.
      final probeOptions = Options(extra: const {kProbeRequestExtra: true});

      // 1. Health probe (unauthenticated).
      final healthResponse = await dio.get(
        '$kInsightBaseUrl/healthz',
        options: probeOptions,
      );

      // 2. Auth probe. Deliberately `GET /d?limit=1`, not `/admin/agents`:
      // `/admin/agents` is operator-only and 401s a valid reader-tier token,
      // which is exactly the credential this build expects an operator to
      // hand a reader — that would fail Test Connection for a token that
      // works everywhere else. `/d` is reader-OK and still proves the token
      // is accepted at all, which is everything this probe needs to show.
      final authResponse = await dio.get(
        '$kInsightBaseUrl/d',
        queryParameters: const {'limit': 1},
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

  /// Save the typed token onto the hardcoded instance.
  ///
  /// Reloads the fleet against it (see [InstancesNotifier.edit]), so this
  /// awaits real network work and holds the buttons disabled while it runs —
  /// which is also what proves the token beyond the Test Connection probe.
  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    final navigator = Navigator.of(context);
    final activeId = ref.read(instancesProvider).value?.activeId;
    // Always present once `instancesProvider` has loaded — `SecureStorageService.load`
    // seeds the hardcoded instance whenever nothing else is persisted, so
    // there is no "no instance to sign into" state to guard against here in
    // practice. The check is defensive, not reachable.
    if (activeId == null) return;

    setState(() => _saving = true);
    try {
      await ref
          .read(instancesProvider.notifier)
          .edit(
            id: activeId,
            baseUrl: kInsightBaseUrl,
            operatorToken: _tokenController.text,
          );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;

    showToast(context, l10n.connectionSaved);

    if (widget.firstRun) {
      // `RootGate` watches the same provider and swaps in the shell on its own
      // as soon as the instance has a token — there is nothing to pop back to
      // here.
      return;
    }
    navigator.maybePop();
  }

  Future<void> _signOut() async {
    final l10n = context.l10n;
    await ref.read(instancesProvider.notifier).signOut();
    if (!mounted) return;
    setState(() {
      _tokenController.clear();
      _testResult = null;
      _resultIsError = false;
    });
    showToast(context, l10n.signedOut);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final connectionState = ref.watch(connectionStateProvider);
    final isUnauthorized =
        connectionState.status == ConnectionStatus.unauthorized;
    final activeInstance = ref.watch(activeInstanceProvider);
    final isConfigured = activeInstance?.operatorToken.isNotEmpty ?? false;
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

              // ---- The hardcoded instance ------------------------------
              // Read-only: Insight talks to exactly one deployment, so there
              // is nothing here to type or change.
              SectionHeader(l10n.credentialsSection),
              _FieldLabel(l10n.baseUrlLabel),
              const SizedBox(height: AppSpacing.sm),
              const _FixedBaseUrl(),
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
                          ? l10n.saving
                          : isConfigured
                          ? l10n.saveInstanceButton
                          : l10n.saveAndContinue,
                      variant: AppBtnVariant.primary,
                      icon: Icons.check,
                      expand: true,
                      onPressed: busy ? null : _signIn,
                    ),
                  ),
                ],
              ),
              if (_testResult != null) ...[
                const SizedBox(height: AppSpacing.xl),
                _ResultPanel(text: _testResult!, isError: _resultIsError),
              ],
              if (isConfigured) ...[
                const SizedBox(height: AppSpacing.xxl),
                Divider(color: c.lineSoft, height: 1),
                const SizedBox(height: AppSpacing.xl),
                _SignOutCard(onSignOut: busy ? null : _signOut),
              ],
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

/// Read-only display of [kInsightBaseUrl] — Insight has no field to type a
/// Base URL into, only this label of the one deployment it talks to.
class _FixedBaseUrl extends StatelessWidget {
  const _FixedBaseUrl();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: c.lineSoft),
      ),
      child: Row(
        children: [
          Icon(Icons.link, size: 18, color: c.textDim),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: SelectableText(
              kInsightBaseUrl,
              style: AppText.mono.copyWith(color: c.text),
            ),
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

/// Clears the saved operator token, keeping the hardcoded instance — "for my
/// own sanity" per the operator who asked for it to stay. Shown only once a
/// token is actually saved, since there is nothing to sign out of otherwise.
class _SignOutCard extends StatelessWidget {
  const _SignOutCard({required this.onSignOut});
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(color: c.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.l10n.signOutTitle,
            style: AppText.title.copyWith(color: c.text),
          ),
          const SizedBox(height: 4),
          Text(
            context.l10n.signOutBody,
            style: AppText.small.copyWith(color: c.textDim),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(
            context.l10n.signOutButton,
            variant: AppBtnVariant.outline,
            icon: Icons.logout,
            onPressed: onSignOut,
          ),
        ],
      ),
    );
  }
}
