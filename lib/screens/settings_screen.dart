import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api.dart';
import '../core/api_client.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/secure_storage.dart';
import '../l10n/l10n.dart';
import '../widgets/app_button.dart';
import '../widgets/cafe_logo.dart';
import '../widgets/section_header.dart';
import '../widgets/toast.dart';

/// The Pass — operator connection setup.
///
/// Pushed route (its own Scaffold + AppBar titled "Connection"). Ported from
/// the legacy `SettingsScreen` in `lib/main.dart`: it stores the deployment
/// Base URL + Operator Token, runs the double-probe connection test
/// (`GET /healthz` then `GET /admin/agents?limit=1` with a Bearer token),
/// persists credentials via [SecureStorageService], and can clear secure
/// storage. The wiring is preserved exactly; only the presentation is restyled
/// into the Cortado language.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.onSaved});

  /// Optional callback fired after a successful save. When null, the screen
  /// pops itself instead (preserving the legacy navigate-away behavior).
  final VoidCallback? onSaved;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _obscureToken = true;
  bool _testingConnection = false;
  String? _testResult;
  bool _resultIsError = false;

  @override
  void initState() {
    super.initState();
    _loadConnectionSettings();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadConnectionSettings() async {
    final storage = SecureStorageService.instance;
    final url = await storage.getBaseUrl();
    final token = await storage.getOperatorToken();
    if (!mounted) return;
    if (url != null) _urlController.text = url;
    if (token != null) _tokenController.text = token;
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
      // 1. Health Probe (unauthenticated).
      final healthResponse = await dio.get('$url/healthz');

      // 2. Auth Probe (Bearer token).
      final authResponse = await dio.get(
        '$url/admin/agents?limit=1',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
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

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    await SecureStorageService.instance.saveConnectionDetails(
      baseUrl: _urlController.text,
      operatorToken: _tokenController.text,
    );
    if (!mounted) return;
    showToast(context, l10n.connectionSaved);
    final onSaved = widget.onSaved;
    if (onSaved != null) {
      onSaved();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    await SecureStorageService.instance.clearAll();
    _urlController.clear();
    _tokenController.clear();
    ref.read(connectionStateProvider.notifier).reset();
    if (!mounted) return;
    setState(() {
      _testResult = null;
      _resultIsError = false;
    });
    showToast(context, l10n.secureStorageCleared);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final connectionState = ref.watch(connectionStateProvider);
    final isUnauthorized =
        connectionState.status == ConnectionStatus.unauthorized;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        leading: const BackButton(),
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
              SectionHeader(l10n.credentialsSection),
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
                      onPressed: _testingConnection ? null : _testConnection,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: AppButton(
                      l10n.saveAndContinue,
                      variant: AppBtnVariant.primary,
                      icon: Icons.check,
                      expand: true,
                      onPressed: _testingConnection ? null : _saveSettings,
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
