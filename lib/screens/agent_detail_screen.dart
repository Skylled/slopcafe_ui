import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:dio/dio.dart';
import '../models/agent.dart';
import '../providers/agent_provider.dart';

class AgentDetailScreen extends ConsumerStatefulWidget {
  final AgentListing agent;

  const AgentDetailScreen({super.key, required this.agent});

  @override
  ConsumerState<AgentDetailScreen> createState() => _AgentDetailScreenState();
}

class _AgentDetailScreenState extends ConsumerState<AgentDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Local state for OAuth discovery
  bool _loadingOAuth = false;
  bool _knowsOAuthExistence = false;
  String? _existingClientId;
  String? _oAuthHint;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _killAgent() async {
    final theme = Theme.of(context);
    final confirmController = TextEditingController();
    bool isDeleting = false;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              icon: Icon(Icons.dangerous, color: theme.colorScheme.error, size: 40),
              title: const Text('Kill Agent Fleet Profile?'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WARNING: This is a cascading destruction. It will instantly revoke all bearer keys and delete its OAuth client.',
                    style: TextStyle(color: theme.colorScheme.error, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'To confirm, please type the exact agent name below: "${widget.agent.name}"',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: confirmController,
                    enabled: !isDeleting,
                    decoration: const InputDecoration(
                      labelText: 'Agent Name Confirmation',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isDeleting ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (isDeleting || confirmController.text != widget.agent.name)
                      ? null
                      : () async {
                          setState(() => isDeleting = true);
                          try {
                            final res = await ref.read(agentsListProvider.notifier).killAgent(widget.agent.id);
                            if (context.mounted) {
                              Navigator.pop(context, true); // Confirmed & Deleted
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Agent profile killed! Revoked ${res['keys_revoked']} key(s) and deleted ${res['oauth_clients_deleted']} OAuth client(s).',
                                  ),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                            }
                          } catch (e) {
                            setState(() => isDeleting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to kill agent: ${e.toString()}'),
                                  backgroundColor: theme.colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  child: isDeleting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Confirm KILL'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm == true && mounted) {
      Navigator.pop(context, true); // Return to agents list with refresh trigger
    }
  }

  Future<void> _revokeKey(AgentKey key) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Revoke Bearer API Key?'),
          content: Text(
            'Are you sure you want to revoke key prefix "${key.keyPrefix}"? This action is irreversible and the worker using this key will immediately be locked out.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Revoke Key'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await ref.read(agentManagerServiceProvider).revokeAgentKey(key.id);
        ref.invalidate(agentKeysProvider(widget.agent.id));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Key prefixed ${key.keyPrefix} revoked successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to revoke key: ${e.toString()}'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _mintKey() async {
    try {
      final res = await ref.read(agentManagerServiceProvider).mintAgentKey(widget.agent.id);
      ref.invalidate(agentKeysProvider(widget.agent.id));
      _showOneShotKeyModal(res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mint key: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  void _showOneShotKeyModal(MintKeyResponse response) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool hasStoredSecret = false;
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            return PopScope(
              canPop: false,
              child: AlertDialog(
                icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 40),
                title: const Text('One-Time Bearer Key Minted'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'This is the only time you\'ll see this secret key. Slopcafe does not retain it in plaintext on the server.',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Key Plaintext:',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: theme.colorScheme.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SelectableText(
                                  response.key,
                                  style: const TextStyle(
                                    fontFamily: 'Courier',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: response.key));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Key copied to clipboard')),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: hasStoredSecret,
                            onChanged: (val) {
                              setState(() {
                                hasStoredSecret = val ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text(
                                'I have securely stored this key. I understand it cannot be displayed again.',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: hasStoredSecret
                        ? () {
                            Navigator.pop(context);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                      foregroundColor: theme.colorScheme.onError,
                    ),
                    child: const Text('Dismiss & Purge Secret'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _mintOAuthClient() async {
    setState(() {
      _loadingOAuth = true;
    });

    try {
      final res = await ref.read(agentManagerServiceProvider).mintOAuthClient(widget.agent.id);
      _showOneShotOAuthModal(res);
      setState(() {
        _knowsOAuthExistence = true;
        _existingClientId = res.clientId;
        _oAuthHint = null;
      });
    } on DioException catch (e) {
      if (e.response?.statusCode == 409) {
        final data = e.response?.data as Map<String, dynamic>?;
        setState(() {
          _knowsOAuthExistence = true;
          _existingClientId = data?['client_id'] as String?;
          _oAuthHint = data?['hint'] as String?;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OAuth client already exists for this agent.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to mint OAuth client: ${e.toString()}'),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingOAuth = false;
        });
      }
    }
  }

  void _showOneShotOAuthModal(MintOAuthResponse response) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        bool hasStoredSecret = false;
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            return PopScope(
              canPop: false,
              child: AlertDialog(
                icon: Icon(Icons.vpn_lock, color: theme.colorScheme.primary, size: 40),
                title: const Text('OAuth Client Created'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Store these credentials securely now. The client secret is shown only once and will never be returned again.',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildCopyField('Client ID', response.clientId, theme),
                      const SizedBox(height: 12),
                      _buildCopyField('Client Secret (ONE-SHOT)', response.clientSecret, theme, isSecret: true),
                      const SizedBox(height: 12),
                      _buildCopyField('MCP Connection URL', response.mcpUrl, theme),
                      const SizedBox(height: 12),
                      Text(
                        'Note:',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        response.note,
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: hasStoredSecret,
                            onChanged: (val) {
                              setState(() {
                                hasStoredSecret = val ?? false;
                              });
                            },
                          ),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(top: 8.0),
                              child: Text(
                                'I have securely stored the client secret. I understand it cannot be displayed again.',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  ElevatedButton(
                    onPressed: hasStoredSecret
                        ? () {
                            Navigator.pop(context);
                          }
                        : null,
                    child: const Text('Dismiss Credentials'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildCopyField(String label, String value, ThemeData theme, {bool isSecret = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    value,
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSecret ? theme.colorScheme.error : null,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: value));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('$label copied to clipboard')),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteOAuthClient(String clientId) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete OAuth Client?'),
          content: Text(
            'Are you sure you want to delete OAuth client ID "$clientId"? This will instantly revoke every live access and refresh token issued to Claude or external MCP hosts.',
            style: const TextStyle(fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              child: const Text('Delete & Deactivate'),
            ),
          ],
        );
      },
    );

    if (confirm == true) {
      setState(() {
        _loadingOAuth = true;
      });
      try {
        await ref.read(agentManagerServiceProvider).deleteOAuthClient(clientId);
        setState(() {
          _knowsOAuthExistence = false;
          _existingClientId = null;
          _oAuthHint = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('OAuth client deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete OAuth client: ${e.toString()}'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _loadingOAuth = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keysAsync = ref.watch(agentKeysProvider(widget.agent.id));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.agent.name),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Identity'),
            Tab(icon: Icon(Icons.vpn_key_outlined), text: 'API Keys'),
            Tab(icon: Icon(Icons.vpn_lock_outlined), text: 'OAuth Client'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildIdentityTab(theme),
          _buildKeysTab(keysAsync, theme),
          _buildOAuthTab(theme),
        ],
      ),
    );
  }

  Widget _buildIdentityTab(ThemeData theme) {
    final dateStr = DateFormat.yMMMMd().add_jm().format(widget.agent.createdAt.toLocal());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Agent Name',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            widget.agent.name,
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Text(
            'Unique UUID Identifier',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.surfaceContainerHighest),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    widget.agent.id,
                    style: const TextStyle(
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: widget.agent.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Agent UUID copied to clipboard')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildMetaCard(
                  Icons.calendar_today_outlined,
                  'Minted On',
                  dateStr,
                  theme.colorScheme.primary,
                  theme,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildMetaCard(
                  Icons.description_outlined,
                  'Live Documents',
                  '${widget.agent.liveDocs} files',
                  theme.colorScheme.secondary,
                  theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 24),
          Text(
            'Danger Zone',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Killing this agent profile is irreversible. It cascades to immediately terminate and delete every security credential registered under it.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _killAgent,
            icon: const Icon(Icons.delete_forever),
            label: const Text('Kill Agent Profile (Cascading)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              minimumSize: const Size(double.infinity, 54),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaCard(IconData icon, String label, String value, Color color, ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 12),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeysTab(AsyncValue<AgentKeysResult> keysAsync, ThemeData theme) {
    return keysAsync.when(
      data: (result) {
        final activeKeys = result.keys.where((k) => !k.isRevoked).toList();
        final revokedKeys = result.keys.where((k) => k.isRevoked).toList();

        return Column(
          children: [
            // Control shelf
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ref.invalidate(agentKeysProvider(widget.agent.id));
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh Keys'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _mintKey,
                      icon: const Icon(Icons.add),
                      label: const Text('Mint Key'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (activeKeys.isNotEmpty) ...[
                    _buildSectionHeader('Active Keys (${activeKeys.length})', theme),
                    ...activeKeys.map((key) => _buildKeyRow(key, theme)),
                  ],
                  if (revokedKeys.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _buildSectionHeader('Revoked Audit History (${revokedKeys.length})', theme),
                    ...revokedKeys.map((key) => _buildKeyRow(key, theme)),
                  ],
                  if (activeKeys.isEmpty && revokedKeys.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 64),
                        child: Column(
                          children: [
                            Icon(Icons.key_off, size: 48, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            const Text('No keys registered. Please mint a key to authorize clients.'),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, stack) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
              const SizedBox(height: 12),
              Text('Error fetching keys: ${e.toString()}', textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildKeyRow(AgentKey key, ThemeData theme) {
    final dateStr = DateFormat.yMMMd().format(key.createdAt.toLocal());
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: key.isRevoked ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
      ),
      child: ListTile(
        leading: Icon(
          Icons.key,
          color: key.isRevoked ? theme.colorScheme.onSurfaceVariant : theme.colorScheme.primary,
        ),
        title: Text(
          key.keyPrefix,
          style: TextStyle(
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
            decoration: key.isRevoked ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          key.isRevoked
              ? 'Revoked at ${DateFormat.yMMMd().format(key.revokedAt!.toLocal())}'
              : 'Created: $dateStr',
          style: TextStyle(
            color: key.isRevoked ? theme.colorScheme.error : null,
            fontSize: 12,
          ),
        ),
        trailing: key.isRevoked
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'REVOKED',
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              )
            : IconButton(
                icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                tooltip: 'Revoke Key',
                onPressed: () => _revokeKey(key),
              ),
      ),
    );
  }

  Widget _buildOAuthTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Informational Alert Card explaining limitations
          Card(
            color: theme.colorScheme.primaryContainer,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, color: theme.colorScheme.onPrimaryContainer, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Connection Mode',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'OAuth client configuration (Door A) allows secure multi-tenant MCP access (e.g. within Cowork or claude.ai).\n\n'
                          'Note: The Slopcafe backend does not currently support listing OAuth clients. We attempt to mint a client to verify existence.',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Main View switcher
          if (_loadingOAuth)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_knowsOAuthExistence && _existingClientId != null)
            _buildOAuthActiveCard(theme)
          else
            _buildOAuthMintCard(theme),
        ],
      ),
    );
  }

  Widget _buildOAuthActiveCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified, color: theme.colorScheme.primary, size: 24),
              const SizedBox(width: 8),
              Text(
                'OAuth Client Registered',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'An active OAuth client exists for this agent. Tapping below will immediately delete it and deauthorize its live tokens.',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 16),
          _buildCopyField('Client ID', _existingClientId ?? '', theme),
          if (_oAuthHint != null) ...[
            const SizedBox(height: 12),
            Text(
              'Server Hint:',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _oAuthHint!,
              style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: () => _deleteOAuthClient(_existingClientId!),
            icon: Icon(Icons.link_off, color: theme.colorScheme.error),
            label: const Text('Delete OAuth Client Connection'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOAuthMintCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.surfaceContainerHighest),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mint OAuth Client',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Create custom OAuth tokens to connect this agent to Claude or Cowork systems.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _mintOAuthClient,
            icon: const Icon(Icons.add_link),
            label: const Text('Mint OAuth Client'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: () {
                // Check if client already exists by triggering the mint and handling 409
                _mintOAuthClient();
              },
              child: const Text('Detect Existing Client (Sync)'),
            ),
          )
        ],
      ),
    );
  }
}
