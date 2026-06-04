import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/format.dart';
import '../core/secure_storage.dart';
import '../models/agent.dart';
import '../models/document.dart';
import '../providers/agent_provider.dart';
import '../providers/document_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sheets.dart';
import '../widgets/stat.dart';
import '../widgets/toast.dart';
import 'reader_screen.dart';

/// Operate — "The Pass" (back of house). The single most feature-dense screen:
/// fleet/document statistics, R2 storage, an agent kitchen (mint/keys/OAuth/kill)
/// and an admin document list (visibility/slug/tags/revoke).
///
/// Ported from the legacy `agents_screen`, `agent_detail_screen`,
/// `documents_screen` and `document_detail_screen`. All API/cache/confirm wiring
/// is preserved against the unchanged providers; only the presentation is reskinned.
class OperateScreen extends ConsumerStatefulWidget {
  const OperateScreen({super.key});

  @override
  ConsumerState<OperateScreen> createState() => _OperateScreenState();
}

enum _OpSeg { kitchen, docs }

class _OperateScreenState extends ConsumerState<OperateScreen> {
  _OpSeg _seg = _OpSeg.kitchen;
  bool _includeRevoked = false;

  // Best-effort /healthz metrics (sanitizer version + R2 storage cap/used).
  String? _sanitizerVersion;
  int? _storageCapBytes;
  int? _storageUsedBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(agentsListProvider).agents.isEmpty) {
        ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
      }
      if (ref.read(documentsListProvider).documents.isEmpty) {
        ref.read(documentsListProvider.notifier).loadNextPage(clear: true);
      }
      _loadHealth();
    });
  }

  // -------------------------------------------------------------------------
  // Best-effort backend health (sanitizer version, R2 storage).
  // -------------------------------------------------------------------------
  Future<void> _loadHealth() async {
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/healthz');
      final data = res.data;
      if (data is Map) {
        final sanitizer = data['sanitizer_version'];
        final cap = data['storage_cap_bytes'];
        // No canonical "used" field is documented; read it opportunistically so
        // the bar fills in if the backend ever exposes one, but never invent it.
        final used = data['storage_used_bytes'] ?? data['storage_bytes_used'];
        if (mounted) {
          setState(() {
            _sanitizerVersion = sanitizer?.toString();
            _storageCapBytes = cap is int ? cap : int.tryParse('${cap ?? ''}');
            _storageUsedBytes = used is int
                ? used
                : int.tryParse('${used ?? ''}');
          });
        }
      }
    } catch (_) {
      // Health is non-essential; leave metrics as "—" / hide the bar.
    }
  }

  // -------------------------------------------------------------------------
  // Kitchen: mint agent (name -> createAgent -> one-shot secret).
  // -------------------------------------------------------------------------
  Future<void> _showNewAgentSheet() async {
    await showAppSheet<void>(
      context,
      builder: (sheetCtx) => _NewAgentSheet(
        onSubmit: (name) async {
          final mint = await ref
              .read(agentsListProvider.notifier)
              .createAgent(name);
          if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
          if (!mounted) return;
          await showSecretSheet(
            context,
            title: 'Agent hired',
            fields: [
              SecretField('Agent ID', mint.agentId),
              SecretField('Plaintext bearer key', mint.key, secret: true),
            ],
            note: mint.note.isEmpty ? null : mint.note,
          );
        },
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Kitchen: unbound OAuth clients (mint + list/delete from local store).
  // -------------------------------------------------------------------------
  Future<void> _showUnboundClientsSheet() async {
    await showAppSheet<void>(
      context,
      builder: (_) => _UnboundClientsSheet(ref: ref, host: context),
    );
  }

  // -------------------------------------------------------------------------
  // Kitchen: per-agent management sheet.
  // -------------------------------------------------------------------------
  Future<void> _openAgentSheet(AgentListing agent) async {
    await showAppSheet<void>(
      context,
      builder: (_) => _AgentSheet(ref: ref, host: context, agent: agent),
    );
  }

  // -------------------------------------------------------------------------
  // Documents: per-row admin actions sheet.
  // -------------------------------------------------------------------------
  Future<void> _openDocActions(DocumentListing doc) async {
    await showAppSheet<void>(
      context,
      builder: (_) => _DocActionsSheet(ref: ref, host: context, doc: doc),
    );
  }

  void _openReader(DocumentListing doc) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final agentsState = ref.watch(agentsListProvider);
    final docsState = ref.watch(documentsListProvider);

    final agents = agentsState.agents;
    final docs = docsState.documents;

    final liveDocs = docs.where((d) => !d.isRevoked).length;
    final publicDocs = docs
        .where((d) => !d.isRevoked && d.visibility == 'public')
        .length;
    final activeAgents = agents.where((a) => a.activeKeys > 0).length;
    final activeKeys = agents.fold<int>(0, (s, a) => s + a.activeKeys);
    final mintedKeys = agents.fold<int>(0, (s, a) => s + a.totalKeys);

    return Scaffold(
      backgroundColor: c.bg,
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.screenH,
          MediaQuery.paddingOf(context).top + 12,
          AppSpacing.screenH,
          AppSpacing.bottomInset,
        ),
        children: [
          // ---- Header ----
          const Eyebrow('Back of house'),
          const SizedBox(height: 3),
          Text('The Pass', style: AppText.display.copyWith(color: c.text)),
          const SizedBox(height: 18),

          // ---- Stat grid (2x2) ----
          Row(
            children: [
              Expanded(
                child: OpStat(
                  icon: Icons.description_outlined,
                  label: 'Live documents',
                  value: '$liveDocs',
                  sub: '$publicDocs public',
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: OpStat(
                  icon: Icons.person_outline,
                  label: 'Active agents',
                  value: '$activeAgents',
                  sub: 'of ${agents.length}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Expanded(
                child: OpStat(
                  icon: Icons.key_outlined,
                  label: 'Active keys',
                  value: '$activeKeys',
                  sub: '$mintedKeys minted',
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: OpStat(
                  icon: Icons.shield_outlined,
                  label: 'Sanitizer',
                  value: _sanitizerVersion ?? '—',
                  sub: _sanitizerVersion != null ? 'all green' : 'unavailable',
                  mono: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ---- R2 storage bar (hidden gracefully if cap unknown) ----
          if (_storageCapBytes != null) _buildStorageBar(c),
          if (_storageCapBytes != null) const SizedBox(height: 22),
          if (_storageCapBytes == null) const SizedBox(height: 10),

          // ---- Segmented control ----
          _Segmented(value: _seg, onChanged: (v) => setState(() => _seg = v)),
          const SizedBox(height: 16),

          // ---- Content ----
          if (_seg == _OpSeg.kitchen)
            _buildKitchen(c, agentsState)
          else
            _buildDocuments(c, docsState),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Storage bar
  // -------------------------------------------------------------------------
  Widget _buildStorageBar(AppColors c) {
    final cap = _storageCapBytes!;
    final used = _storageUsedBytes;
    final pct = (used != null && cap > 0) ? (used / cap).clamp(0.0, 1.0) : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl + 1),
        boxShadow: c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.bolt, size: 15, color: c.honeyD),
                  const SizedBox(width: 7),
                  Text(
                    'R2 storage',
                    style: AppText.titleSm.copyWith(color: c.text),
                  ),
                ],
              ),
              Text(
                used != null
                    ? '${fmtBytes(used)} / ${fmtBytes(cap)}'
                    : 'cap ${fmtBytes(cap)}',
                style: AppText.mono.copyWith(color: c.textDim),
              ),
            ],
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 10,
              color: c.surface3,
              child: pct == null
                  ? null
                  : FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: pct,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [c.clay, c.honey]),
                        ),
                      ),
                    ),
            ),
          ),
          if (pct == null) ...[
            const SizedBox(height: 8),
            Text(
              'Usage figure unavailable.',
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Kitchen tab
  // -------------------------------------------------------------------------
  Widget _buildKitchen(AppColors c, AgentsListState state) {
    final agents = state.agents;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row: count + new agent.
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${agents.length} agents',
                style: AppText.label.copyWith(
                  fontSize: 12.5,
                  color: c.textFaint,
                  letterSpacing: 0.6,
                ),
              ),
              GestureDetector(
                onTap: _showNewAgentSheet,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add, size: 16, color: c.clayD),
                    const SizedBox(width: 6),
                    Text(
                      'New agent',
                      style: AppText.title.copyWith(
                        fontSize: 13.5,
                        color: c.clayD,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Manage unbound OAuth clients entry.
        PressCard(
          onPress: _showUnboundClientsSheet,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.lg),
            ),
            child: Row(
              children: [
                Icon(Icons.link, size: 18, color: c.textDim),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unbound OAuth clients',
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Global clients not tied to any agent profile.',
                        style: AppText.small.copyWith(color: c.textFaint),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: c.textFaint),
              ],
            ),
          ),
        ),

        // Agent list / empty / error.
        if (agents.isEmpty && state.isLoading)
          _loadingTile(c)
        else if (agents.isEmpty && state.hasError)
          _errorTile(
            c,
            'Could not load the fleet.',
            state.errorMessage,
            () =>
                ref.read(agentsListProvider.notifier).loadNextPage(clear: true),
          )
        else if (agents.isEmpty)
          _emptyTile(
            c,
            Icons.person_outline,
            'No agents on the line yet. Hire one to begin.',
          )
        else
          ...List.generate(agents.length, (i) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RiseIn(
                delay: Duration(milliseconds: (i * 30).clamp(0, 250)),
                child: _AgentRow(
                  agent: agents[i],
                  onPress: () => _openAgentSheet(agents[i]),
                ),
              ),
            );
          }),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Documents tab
  // -------------------------------------------------------------------------
  Widget _buildDocuments(AppColors c, DocumentsListState state) {
    final all = state.documents;
    final docs = _includeRevoked
        ? all
        : all.where((d) => !d.isRevoked).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'All documents',
                style: AppText.label.copyWith(
                  fontSize: 12.5,
                  color: c.textFaint,
                  letterSpacing: 0.6,
                ),
              ),
              GestureDetector(
                onTap: () => setState(() => _includeRevoked = !_includeRevoked),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _includeRevoked
                          ? Icons.check_box_outlined
                          : Icons.check_box_outline_blank,
                      size: 17,
                      color: _includeRevoked ? c.clayD : c.textFaint,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Include revoked',
                      style: AppText.title.copyWith(
                        fontSize: 13,
                        color: _includeRevoked ? c.clayD : c.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (docs.isEmpty && state.isLoading)
          _loadingTile(c)
        else if (docs.isEmpty && state.hasError)
          _errorTile(
            c,
            'Could not load documents.',
            state.errorMessage,
            () => ref
                .read(documentsListProvider.notifier)
                .loadNextPage(clear: true),
          )
        else if (docs.isEmpty)
          _emptyTile(c, Icons.description_outlined, 'No documents to show.')
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.xl + 2),
              boxShadow: c.shadow,
            ),
            child: Column(
              children: List.generate(docs.length, (i) {
                return _AdminDocRow(
                  doc: docs[i],
                  last: i == docs.length - 1,
                  onOpen: () => _openReader(docs[i]),
                  onMore: () => _openDocActions(docs[i]),
                );
              }),
            ),
          ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Shared state tiles
  // -------------------------------------------------------------------------
  Widget _loadingTile(AppColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: c.clay),
        ),
      ),
    );
  }

  Widget _emptyTile(AppColors c, IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: c.textFaint),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.textDim),
          ),
        ],
      ),
    );
  }

  Widget _errorTile(
    AppColors c,
    String title,
    String? detail,
    VoidCallback onRetry,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: Column(
        children: [
          Icon(Icons.warning_amber_rounded, size: 38, color: c.red),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppText.titleSm.copyWith(color: c.text),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            'Retry',
            variant: AppBtnVariant.outline,
            icon: Icons.refresh,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Segmented control (port of the mockup `MSeg`).
// ===========================================================================
class _Segmented extends StatelessWidget {
  const _Segmented({required this.value, required this.onChanged});
  final _OpSeg value;
  final ValueChanged<_OpSeg> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget seg(_OpSeg v, String label) {
      final active = v == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(v),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
            decoration: BoxDecoration(
              color: active ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: active ? c.shadow : null,
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppText.body.copyWith(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: active ? c.text : c.textFaint,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.md + 1),
      ),
      child: Row(
        children: [
          seg(_OpSeg.kitchen, 'The Kitchen'),
          const SizedBox(width: 3),
          seg(_OpSeg.docs, 'Documents'),
        ],
      ),
    );
  }
}

// ===========================================================================
// Agent row (PressCard).
// ===========================================================================
class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.agent, required this.onPress});
  final AgentListing agent;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final accent = c.accentForId(agent.id);
    final online = agent.activeKeys > 0;

    return PressCard(
      onPress: onPress,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.lineSoft),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: c.shadow,
        ),
        child: Row(
          children: [
            // Decorative accent tile (not data).
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadii.md + 1),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.person_outline, size: 21, color: accent),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.title.copyWith(color: c.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    agent.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.monoLabel.copyWith(color: c.textFaint),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Pill(
                        '${agent.activeKeys}/${agent.totalKeys}',
                        tone: PillTone.clay,
                        small: true,
                        icon: Icons.key_outlined,
                      ),
                      const SizedBox(width: 7),
                      Pill(
                        '${agent.liveDocs}',
                        tone: PillTone.neutral,
                        small: true,
                        icon: Icons.description_outlined,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: online ? c.green : c.line,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Admin document row (inside the bordered list card).
// ===========================================================================
class _AdminDocRow extends StatelessWidget {
  const _AdminDocRow({
    required this.doc,
    required this.last,
    required this.onOpen,
    required this.onMore,
  });
  final DocumentListing doc;
  final bool last;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final revoked = doc.isRevoked;
    final (tintBg, tintFg) = c.tagTint(
      doc.tags.isEmpty ? null : doc.tags.first,
    );

    return Opacity(
      opacity: revoked ? 0.55 : 1,
      child: Container(
        decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: c.lineSoft)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: GestureDetector(
                onTap: revoked ? null : onOpen,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: tintBg,
                        borderRadius: BorderRadius.circular(AppRadii.sm + 1),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.description_outlined,
                        size: 16,
                        color: tintFg,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            doc.title ?? '[Untitled]',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.body.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: c.text,
                              decoration: revoked
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            revoked
                                ? 'revoked'
                                : 'v${doc.currentVer ?? 1} · ${fmtBytes(doc.currentSize)}',
                            style: AppText.monoLabel.copyWith(
                              fontSize: 11,
                              color: c.textFaint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            if (revoked)
              Pill('Revoked', tone: PillTone.red, small: true)
            else ...[
              Icon(
                doc.visibility == 'public' ? Icons.public : Icons.lock_outline,
                size: 14,
                color: c.textFaint,
              ),
              const SizedBox(width: 4),
              AppIconButton(
                Icons.more_horiz,
                size: 18,
                onPressed: onMore,
                tooltip: 'Document actions',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// New-agent sheet (name input -> createAgent).
// ===========================================================================
class _NewAgentSheet extends StatefulWidget {
  const _NewAgentSheet({required this.onSubmit});
  final Future<void> Function(String name) onSubmit;

  @override
  State<_NewAgentSheet> createState() => _NewAgentSheetState();
}

class _NewAgentSheetState extends State<_NewAgentSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a name.');
      return;
    }
    if (name.length > 200) {
      setState(() => _error = 'Name must be 200 characters or less.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmit(name);
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showToast(context, 'Failed to hire agent: $e', danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheet(
      title: 'Hire an agent',
      subtitle: 'New profile',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Creates a logical agent profile and mints its initial bearer key. '
            'The key is shown only once.',
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 16),
          Text(
            'AGENT NAME',
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            enabled: !_submitting,
            autofocus: true,
            style: AppText.body.copyWith(color: c.text),
            decoration: const InputDecoration(hintText: 'e.g. Claude Writer'),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: AppText.small.copyWith(color: c.red)),
          ],
          const SizedBox(height: 18),
          AppButton(
            _submitting ? 'Hiring…' : 'Hire agent',
            variant: AppBtnVariant.primary,
            icon: Icons.add,
            expand: true,
            onPressed: _submitting ? null : _submit,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Unbound OAuth clients sheet (mint + list/delete from secure storage).
// ===========================================================================
class _UnboundClientsSheet extends StatefulWidget {
  const _UnboundClientsSheet({required this.ref, required this.host});
  final WidgetRef ref;
  final BuildContext host;

  @override
  State<_UnboundClientsSheet> createState() => _UnboundClientsSheetState();
}

class _UnboundClientsSheetState extends State<_UnboundClientsSheet> {
  List<String> _ids = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ids = await SecureStorageService.instance.getUnboundOAuthClientIds();
    if (mounted) {
      setState(() {
        _ids = ids;
        _loading = false;
      });
    }
  }

  Future<void> _mint() async {
    setState(() => _busy = true);
    try {
      final res = await widget.ref
          .read(agentManagerServiceProvider)
          .mintUnboundOAuthClient();
      await SecureStorageService.instance.addUnboundOAuthClientId(res.clientId);
      await _load();
      if (!widget.host.mounted) return;
      await showSecretSheet(
        widget.host,
        title: 'OAuth client created',
        fields: [
          SecretField('Client ID', res.clientId),
          SecretField(
            'Client secret (one-shot)',
            res.clientSecret,
            secret: true,
          ),
          SecretField('MCP connection URL', res.mcpUrl),
        ],
        note: res.note.isEmpty ? null : res.note,
      );
    } catch (e) {
      if (mounted) {
        showToast(context, 'Failed to mint unbound client: $e', danger: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String clientId) async {
    final confirmed = await showConfirmSheet(
      widget.host,
      title: 'Delete unbound client',
      body: Text(
        'Delete unbound OAuth client "$clientId"? This instantly revokes all '
        'live sessions and tokens issued under it.',
      ),
      cta: 'Delete client',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await widget.ref
          .read(agentManagerServiceProvider)
          .deleteOAuthClient(clientId);
      await SecureStorageService.instance.removeUnboundOAuthClientId(clientId);
      await _load();
      if (widget.host.mounted) {
        showToast(widget.host, 'Unbound client deleted.');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Failed to delete client: $e', danger: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheet(
      title: 'Unbound OAuth clients',
      subtitle: 'Global connections',
      icon: Icons.link,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Unbound clients are not tied to any single agent profile. They let '
            'operators authenticate valid agent flows dynamically.',
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 16),
          AppButton(
            _busy ? 'Working…' : 'Mint unbound client',
            variant: AppBtnVariant.primary,
            icon: Icons.add,
            expand: true,
            onPressed: _busy ? null : _mint,
          ),
          const SizedBox(height: 20),
          Text(
            'MINTED ON THIS DEVICE',
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 10),
          if (_loading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.clay,
                  ),
                ),
              ),
            )
          else if (_ids.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No unbound clients recorded on this device.',
                style: AppText.small.copyWith(
                  fontStyle: FontStyle.italic,
                  color: c.textFaint,
                ),
              ),
            )
          else
            for (final id in _ids)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                decoration: BoxDecoration(
                  color: c.surface2,
                  border: Border.all(color: c.lineSoft),
                  borderRadius: BorderRadius.circular(AppRadii.lg),
                ),
                child: Row(
                  children: [
                    Icon(Icons.shield_outlined, size: 16, color: c.textDim),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.mono.copyWith(
                          fontWeight: FontWeight.w700,
                          color: c.text,
                        ),
                      ),
                    ),
                    AppIconButton(
                      Icons.delete_outline,
                      size: 17,
                      color: c.red,
                      onPressed: _busy ? null : () => _delete(id),
                      tooltip: 'Delete client',
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Agent management sheet (keys, mint key, OAuth client, kill agent).
// ===========================================================================
class _AgentSheet extends ConsumerStatefulWidget {
  const _AgentSheet({
    required this.ref,
    required this.host,
    required this.agent,
  });
  final WidgetRef ref;
  final BuildContext host;
  final AgentListing agent;

  @override
  ConsumerState<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends ConsumerState<_AgentSheet> {
  bool _oauthBusy = false;
  // OAuth discovery state, mirroring agent_detail_screen.
  bool _knowsOAuthExistence = false;
  String? _existingClientId;
  String? _oAuthHint;

  AgentListing get agent => widget.agent;

  Future<void> _mintKey() async {
    try {
      final res = await widget.ref
          .read(agentManagerServiceProvider)
          .mintAgentKey(agent.id);
      widget.ref.invalidate(agentKeysProvider(agent.id));
      if (!widget.host.mounted) return;
      await showSecretSheet(
        widget.host,
        title: 'Bearer key minted',
        fields: [SecretField('Key plaintext', res.key, secret: true)],
        note: res.note.isEmpty ? null : res.note,
      );
    } catch (e) {
      if (mounted) showToast(context, 'Failed to mint key: $e', danger: true);
    }
  }

  Future<void> _revokeKey(AgentKey key) async {
    final confirmed = await showConfirmSheet(
      widget.host,
      title: 'Revoke key',
      body: Text(
        'Revoke key "${key.keyPrefix}"? This is irreversible — the worker using '
        'it is immediately locked out.',
      ),
      cta: 'Revoke key',
    );
    if (!confirmed) return;
    try {
      await widget.ref.read(agentManagerServiceProvider).revokeAgentKey(key.id);
      widget.ref.invalidate(agentKeysProvider(agent.id));
      if (widget.host.mounted) {
        showToast(widget.host, 'Key ${key.keyPrefix} revoked.');
      }
    } catch (e) {
      if (mounted) showToast(context, 'Failed to revoke key: $e', danger: true);
    }
  }

  Future<void> _mintOAuth() async {
    setState(() => _oauthBusy = true);
    try {
      final res = await widget.ref
          .read(agentManagerServiceProvider)
          .mintOAuthClient(agent.id);
      if (mounted) {
        setState(() {
          _knowsOAuthExistence = true;
          _existingClientId = res.clientId;
          _oAuthHint = null;
        });
      }
      if (widget.host.mounted) {
        await showSecretSheet(
          widget.host,
          title: 'OAuth client created',
          fields: [
            SecretField('Client ID', res.clientId),
            SecretField(
              'Client secret (one-shot)',
              res.clientSecret,
              secret: true,
            ),
            SecretField('MCP connection URL', res.mcpUrl),
          ],
          note: res.note.isEmpty ? null : res.note,
        );
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final data = e.response?.data as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _knowsOAuthExistence = true;
            _existingClientId = data?['client_id'] as String?;
            _oAuthHint = data?['hint'] as String?;
          });
          showToast(context, 'OAuth client already exists for this agent.');
        }
      } else {
        if (mounted) {
          showToast(context, 'Failed to mint OAuth client: $e', danger: true);
        }
      }
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
    }
  }

  Future<void> _deleteOAuth(String clientId) async {
    final confirmed = await showConfirmSheet(
      widget.host,
      title: 'Delete OAuth client',
      body: Text(
        'Delete OAuth client "$clientId"? This instantly revokes every live '
        'access and refresh token issued to Claude or external MCP hosts.',
      ),
      cta: 'Delete client',
    );
    if (!confirmed) return;
    setState(() => _oauthBusy = true);
    try {
      await widget.ref
          .read(agentManagerServiceProvider)
          .deleteOAuthClient(clientId);
      if (mounted) {
        setState(() {
          _knowsOAuthExistence = false;
          _existingClientId = null;
          _oAuthHint = null;
        });
      }
      if (widget.host.mounted) {
        showToast(widget.host, 'OAuth client deleted.');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Failed to delete OAuth client: $e', danger: true);
      }
    } finally {
      if (mounted) setState(() => _oauthBusy = false);
    }
  }

  Future<void> _killAgent() async {
    final c = context.colors;
    final confirmed = await showConfirmSheet(
      widget.host,
      title: 'Kill agent profile',
      body: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Cascading destruction. ',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w700,
                color: c.red,
              ),
            ),
            const TextSpan(
              text:
                  'This instantly revokes all bearer keys and deletes the agent\'s '
                  'OAuth client.',
            ),
          ],
        ),
      ),
      confirmWord: agent.name,
      cta: 'Kill profile',
    );
    if (!confirmed) return;
    try {
      final res = await widget.ref
          .read(agentsListProvider.notifier)
          .killAgent(agent.id);
      if (widget.host.mounted) {
        showToast(
          widget.host,
          'Agent killed. Revoked ${res['keys_revoked'] ?? 0} key(s), '
          'deleted ${res['oauth_clients_deleted'] ?? 0} client(s).',
          danger: true,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) showToast(context, 'Failed to kill agent: $e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keysAsync = ref.watch(agentKeysProvider(agent.id));

    return AppSheet(
      title: agent.name,
      subtitle: 'Agent profile',
      icon: Icons.person_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity line.
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: c.surface2,
              border: Border.all(color: c.lineSoft),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    agent.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono.copyWith(color: c.textDim),
                  ),
                ),
                Pill(
                  '${agent.liveDocs} docs',
                  tone: PillTone.neutral,
                  small: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Mint key + OAuth client buttons.
          Row(
            children: [
              Expanded(
                child: AppButton(
                  'Mint key',
                  variant: AppBtnVariant.primary,
                  icon: Icons.add,
                  small: true,
                  expand: true,
                  onPressed: _mintKey,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  _oauthBusy ? 'Working…' : 'OAuth client',
                  variant: AppBtnVariant.outline,
                  icon: Icons.link,
                  small: true,
                  expand: true,
                  onPressed: _oauthBusy ? null : _mintOAuth,
                ),
              ),
            ],
          ),

          // OAuth existence card (after a 409 or successful mint).
          if (_knowsOAuthExistence && _existingClientId != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border.all(color: c.lineSoft),
                borderRadius: BorderRadius.circular(AppRadii.lg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.verified_outlined, size: 16, color: c.green),
                      const SizedBox(width: 7),
                      Text(
                        'OAuth client registered',
                        style: AppText.titleSm.copyWith(color: c.text),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _existingClientId!,
                    style: AppText.monoLabel.copyWith(color: c.textDim),
                  ),
                  if (_oAuthHint != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _oAuthHint!,
                      style: AppText.small.copyWith(
                        fontStyle: FontStyle.italic,
                        color: c.textFaint,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  AppButton(
                    'Delete OAuth client',
                    variant: AppBtnVariant.danger,
                    icon: Icons.link_off,
                    small: true,
                    expand: true,
                    onPressed: _oauthBusy
                        ? null
                        : () => _deleteOAuth(_existingClientId!),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'API KEYS',
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 10),

          keysAsync.when(
            data: (result) {
              final active = result.keys.where((k) => !k.isRevoked).toList();
              final revoked = result.keys.where((k) => k.isRevoked).toList();
              if (active.isEmpty && revoked.isEmpty) {
                return Text(
                  'No keys registered. Mint one to authorize clients.',
                  style: AppText.small.copyWith(
                    fontStyle: FontStyle.italic,
                    color: c.textFaint,
                  ),
                );
              }
              return Column(
                children: [
                  for (final k in active)
                    _KeyRow(keyItem: k, onRevoke: () => _revokeKey(k)),
                  if (revoked.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'REVOKED AUDIT (${revoked.length})',
                        style: AppText.label.copyWith(
                          fontSize: 10.5,
                          color: c.textFaint,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final k in revoked) _KeyRow(keyItem: k),
                  ],
                ],
              );
            },
            loading: () => Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.clay,
                  ),
                ),
              ),
            ),
            error: (e, _) => Text(
              'Error fetching keys: $e',
              style: AppText.small.copyWith(color: c.red),
            ),
          ),

          const SizedBox(height: 20),
          AppButton(
            'Kill agent profile',
            variant: AppBtnVariant.danger,
            icon: Icons.delete_outline,
            expand: true,
            onPressed: _killAgent,
          ),
        ],
      ),
    );
  }
}

class _KeyRow extends StatelessWidget {
  const _KeyRow({required this.keyItem, this.onRevoke});
  final AgentKey keyItem;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final revoked = keyItem.isRevoked;
    return Opacity(
      opacity: revoked ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Icon(
              Icons.key_outlined,
              size: 16,
              color: revoked ? c.textFaint : c.clayD,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    keyItem.keyPrefix,
                    style: AppText.mono.copyWith(
                      fontWeight: FontWeight.w700,
                      color: c.text,
                      decoration: revoked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    revoked
                        ? 'Revoked ${fmtDate(keyItem.revokedAt)}'
                        : 'Minted ${fmtDate(keyItem.createdAt)}',
                    style: AppText.small.copyWith(
                      fontSize: 11,
                      color: c.textFaint,
                    ),
                  ),
                ],
              ),
            ),
            if (revoked)
              Pill('REVOKED', tone: PillTone.red, small: true)
            else
              GestureDetector(
                onTap: onRevoke,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  child: Text(
                    'Revoke',
                    style: AppText.title.copyWith(fontSize: 13, color: c.red),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Document admin actions sheet (visibility / slug / tags / copy / revoke).
// ===========================================================================
class _DocActionsSheet extends StatefulWidget {
  const _DocActionsSheet({
    required this.ref,
    required this.host,
    required this.doc,
  });
  final WidgetRef ref;
  final BuildContext host;
  final DocumentListing doc;

  @override
  State<_DocActionsSheet> createState() => _DocActionsSheetState();
}

class _DocActionsSheetState extends State<_DocActionsSheet> {
  late DocumentListing _doc = widget.doc;
  bool _busy = false;

  Future<String?> _baseUrl() => SecureStorageService.instance.getBaseUrl();

  Future<void> _toggleVisibility() async {
    final next = _doc.visibility == 'public' ? 'private' : 'public';
    final confirmed = await showConfirmSheet(
      widget.host,
      title: next == 'public' ? 'Make public' : 'Make private',
      body: Text(
        next == 'public'
            ? 'Anyone with the link will be able to read this document.'
            : 'Only authorized operators will be able to read this document.',
      ),
      cta: next == 'public' ? 'Make public' : 'Make private',
      danger: false,
    );
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.ref
          .read(documentsListProvider.notifier)
          .updateVisibility(_doc.publicId, next);
      if (mounted) setState(() => _doc = updated);
      if (widget.host.mounted) {
        showToast(widget.host, 'Visibility set to ${next.toUpperCase()}.');
      }
    } catch (e) {
      if (mounted) {
        showToast(context, 'Failed to update visibility: $e', danger: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editSlugAndTags() async {
    await showAppSheet<void>(
      widget.host,
      builder: (_) => _EditSlugTagsSheet(
        doc: _doc,
        ref: widget.ref,
        host: widget.host,
        onUpdated: (updated) {
          if (mounted) setState(() => _doc = updated);
        },
      ),
    );
  }

  Future<void> _copySlugUrl() async {
    final base = await _baseUrl();
    if (base == null || _doc.slug == null) {
      if (widget.host.mounted) {
        showToast(widget.host, 'No slug URL available.', danger: true);
      }
      return;
    }
    final url = '$base/s/${_doc.slug}';
    await _copy(url, 'Slug URL copied.');
  }

  Future<void> _copy(String value, String msg) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (widget.host.mounted) showToast(widget.host, msg);
  }

  // Revoke uses the exact dio DELETE + local revoke from document_detail_screen.
  Future<void> _revoke() async {
    final confirmed = await showConfirmSheet(
      widget.host,
      title: 'Revoke document',
      body: const Text(
        'This is permanent and irreversible. Document files are purged from R2 '
        'storage and the slug is released for reuse.',
      ),
      confirmWord: 'REVOKE',
      cta: 'Revoke permanently',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      final dio = widget.ref.read(dioProvider);
      final response = await dio.delete('/d/${_doc.publicId}');
      final data = response.data as Map<String, dynamic>;
      final r2Purged = data['r2_objects_purged'] ?? 0;

      final now = DateTime.now();
      widget.ref
          .read(documentsListProvider.notifier)
          .revokeDocumentLocally(_doc.publicId, now);

      if (widget.host.mounted) {
        showToast(
          widget.host,
          'Document revoked. $r2Purged R2 object(s) purged.',
          danger: true,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, 'Revocation failed: $e', danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isPublic = _doc.visibility == 'public';
    return AppSheet(
      title: _doc.title ?? '[Untitled]',
      subtitle: 'Document actions',
      icon: Icons.description_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              VisBadge(_doc.visibility),
              const SizedBox(width: 8),
              if (_doc.currentVer != null)
                Pill(
                  'v${_doc.currentVer}',
                  tone: PillTone.neutral,
                  small: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_busy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: c.clay,
                  ),
                ),
              ),
            ),
          SheetActionRow(
            icon: isPublic ? Icons.lock_outline : Icons.public,
            label: isPublic ? 'Make private' : 'Make public',
            onTap: _busy ? null : _toggleVisibility,
          ),
          SheetActionRow(
            icon: Icons.sell_outlined,
            label: 'Edit slug & tags',
            onTap: _busy ? null : _editSlugAndTags,
          ),
          SheetActionRow(
            icon: Icons.link,
            label: 'Copy slug URL',
            onTap: _busy ? null : _copySlugUrl,
          ),
          Divider(color: c.lineSoft, height: 16),
          SheetActionRow(
            icon: Icons.delete_outline,
            label: 'Revoke document',
            danger: true,
            onTap: _busy ? null : _revoke,
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Edit slug & tags sheet.
// ===========================================================================
class _EditSlugTagsSheet extends StatefulWidget {
  const _EditSlugTagsSheet({
    required this.doc,
    required this.ref,
    required this.host,
    required this.onUpdated,
  });
  final DocumentListing doc;
  final WidgetRef ref;
  final BuildContext host;
  final ValueChanged<DocumentListing> onUpdated;

  @override
  State<_EditSlugTagsSheet> createState() => _EditSlugTagsSheetState();
}

class _EditSlugTagsSheetState extends State<_EditSlugTagsSheet> {
  late final TextEditingController _slug = TextEditingController(
    text: widget.doc.slug ?? '',
  );
  late final TextEditingController _tags = TextEditingController(
    text: widget.doc.tags.join(', '),
  );
  bool _busy = false;

  @override
  void dispose() {
    _slug.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final notifier = widget.ref.read(documentsListProvider.notifier);
    final newSlug = _slug.text.trim();
    final newTags = _tags.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    try {
      DocumentListing updated = await notifier.updateSlug(
        widget.doc.publicId,
        newSlug,
      );
      updated = await notifier.updateTags(widget.doc.publicId, newTags);
      widget.onUpdated(updated);
      if (widget.host.mounted) {
        showToast(widget.host, 'Slug & tags updated.');
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, 'Failed to update: $e', danger: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppSheet(
      title: 'Edit slug & tags',
      subtitle: 'Document metadata',
      icon: Icons.sell_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SLUG',
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _slug,
            enabled: !_busy,
            style: AppText.body.copyWith(color: c.text),
            decoration: const InputDecoration(
              hintText: 'e.g. my-cool-document',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Slugs are retired permanently when cleared or changed — the old '
            'slug then returns 410 Gone. Leave empty to clear.',
            style: AppText.small.copyWith(color: c.textFaint),
          ),
          const SizedBox(height: 16),
          Text(
            'TAGS',
            style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _tags,
            enabled: !_busy,
            style: AppText.body.copyWith(color: c.text),
            decoration: const InputDecoration(
              hintText: 'comma, separated, tags',
            ),
          ),
          const SizedBox(height: 18),
          AppButton(
            _busy ? 'Saving…' : 'Save changes',
            variant: AppBtnVariant.primary,
            icon: Icons.check,
            expand: true,
            onPressed: _busy ? null : _save,
          ),
        ],
      ),
    );
  }
}
