import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/agent.dart';
import '../providers/agent_provider.dart';
import '../core/secure_storage.dart';
import 'agent_detail_screen.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _scrollController = ScrollController();
  List<String> _unboundClientIds = [];
  bool _loadingUnbound = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _scrollController.addListener(_onScroll);

    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
      _loadUnboundClientIds();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadUnboundClientIds() async {
    final ids = await SecureStorageService.instance.getUnboundOAuthClientIds();
    setState(() {
      _unboundClientIds = ids;
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(agentsListProvider.notifier).loadNextPage();
    }
  }

  Future<void> _showNewAgentDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: !isSubmitting,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Mint New Agent'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'This will create a logical agent profile and generate its initial bearer API key.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameController,
                      enabled: !isSubmitting,
                      decoration: const InputDecoration(
                        labelText: 'Agent Name',
                        hintText: 'e.g. Claude Writer',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a name';
                        }
                        if (value.trim().length > 200) {
                          return 'Name must be 200 characters or less';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setState(() => isSubmitting = true);

                          try {
                            final notifier = ref.read(agentsListProvider.notifier);
                            final mintResponse = await notifier.createAgent(
                              nameController.text.trim(),
                            );
                            
                            if (context.mounted) {
                              Navigator.pop(context); // Close creation dialog
                              _showOneShotSecretModal(mintResponse);
                            }
                          } catch (e) {
                            setState(() => isSubmitting = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to mint agent: ${e.toString()}'),
                                  backgroundColor: Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Mint Agent'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showOneShotSecretModal(MintAgentResponse mintResponse) {
    showDialog(
      context: context,
      barrierDismissible: false, // Force them to explicitly dismiss
      builder: (context) {
        bool hasStoredSecret = false;
        return StatefulBuilder(
          builder: (context, setState) {
            final theme = Theme.of(context);
            return PopScope(
              canPop: false, // Suppress back button on Android/macOS
              child: AlertDialog(
                icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error, size: 40),
                title: const Text('One-Time Credentials Generated'),
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
                        'Agent ID:',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        mintResponse.agentId,
                        style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Plaintext Bearer Key:',
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
                                  mintResponse.key,
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
                              tooltip: 'Copy to Clipboard',
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: mintResponse.key));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('API Key copied to clipboard'),
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        mintResponse.note,
                        style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(agentsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Agents Fleet'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline), text: 'Agent Profiles'),
            Tab(icon: Icon(Icons.vpn_lock_outlined), text: 'Unbound OAuth'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              if (_tabController.index == 0) {
                ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
              } else {
                _loadUnboundClientIds();
              }
            },
          ),
          if (_tabController.index == 0)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Mint Agent',
              onPressed: _showNewAgentDialog,
            )
          else
            IconButton(
              icon: const Icon(Icons.add_link),
              tooltip: 'Mint Unbound OAuth Client',
              onPressed: _mintUnboundOAuthClient,
            ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBody(state, theme),
          _buildUnboundOAuthTab(theme),
        ],
      ),
    );
  }

  Widget _buildBody(AgentsListState state, ThemeData theme) {
    if (state.agents.isEmpty && !state.isLoading) {
      if (state.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi_off, size: 64, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Failed to load fleet: ${state.errorMessage}',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
                  },
                  child: const Text('Retry'),
                )
              ],
            ),
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text(
              'No active agents found in this fleet.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _showNewAgentDialog,
              icon: const Icon(Icons.add),
              label: const Text('Mint Your First Agent'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: state.agents.length + (state.isLoading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == state.agents.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final agent = state.agents[index];
          return _buildAgentRow(agent, theme);
        },
      ),
    );
  }

  Widget _buildAgentRow(AgentListing agent, ThemeData theme) {
    final dateStr = DateFormat.yMMMd().add_jm().format(agent.createdAt.toLocal());
    final truncatedId = agent.id.length > 10
        ? '${agent.id.substring(0, 8)}...${agent.id.substring(agent.id.length - 4)}'
        : agent.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AgentDetailScreen(agent: agent),
            ),
          );
          if (result == true) {
            // Agent was deleted, refresh fleet list
            ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      agent.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'ID: $truncatedId',
                    style: TextStyle(
                      fontFamily: 'Courier',
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: agent.id));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Agent ID copied to clipboard'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4.0),
                      child: Icon(
                        Icons.copy,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  _buildMetaChip(
                    Icons.vpn_key_outlined,
                    '${agent.activeKeys}/${agent.totalKeys} Keys',
                    theme.colorScheme.primary,
                    theme,
                  ),
                  _buildMetaChip(
                    Icons.description_outlined,
                    '${agent.liveDocs} Docs',
                    theme.colorScheme.secondary,
                    theme,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: theme.colorScheme.surfaceContainerHighest, height: 1),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Fleet Profile',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Minted: $dateStr',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label, Color color, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnboundOAuthTab(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                          'Unbound OAuth Clients',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Unbound OAuth clients are global connections not tied to any single agent profile. '
                          'They allow operators to authenticate any valid agent flow dynamically.',
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
          Container(
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
                  'Provision Unbound Client',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Mint a new unbound OAuth client key and secret pair. Write down the secret as it cannot be shown again.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _loadingUnbound ? null : _mintUnboundOAuthClient,
                  icon: const Icon(Icons.add_link),
                  label: const Text('Mint Unbound OAuth Client'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _showManualRevokeDialog(theme),
                  icon: const Icon(Icons.link_off),
                  label: const Text('Manual Revoke by Client ID'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Minted on this Device:',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_unboundClientIds.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No unbound clients recorded on this device.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _unboundClientIds.length,
              itemBuilder: (context, index) {
                final clientId = _unboundClientIds[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.surfaceContainerHighest),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.vpn_lock),
                    title: SelectableText(
                      clientId,
                      style: const TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, color: theme.colorScheme.error),
                      tooltip: 'Revoke Unbound Client',
                      onPressed: () => _deleteUnboundOAuthClient(clientId),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _mintUnboundOAuthClient() async {
    setState(() {
      _loadingUnbound = true;
    });

    try {
      final res = await ref.read(agentManagerServiceProvider).mintUnboundOAuthClient();
      await SecureStorageService.instance.addUnboundOAuthClientId(res.clientId);
      await _loadUnboundClientIds();

      if (mounted) {
        _showOneShotOAuthModal(res);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to mint unbound OAuth client: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingUnbound = false;
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

  Future<void> _deleteUnboundOAuthClient(String clientId) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Unbound OAuth Client?'),
          content: Text(
            'Are you sure you want to delete unbound OAuth client ID "$clientId"? This will instantly revoke all live sessions and tokens issued under this client.',
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
        _loadingUnbound = true;
      });
      try {
        await ref.read(agentManagerServiceProvider).deleteOAuthClient(clientId);
        await SecureStorageService.instance.removeUnboundOAuthClientId(clientId);
        await _loadUnboundClientIds();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unbound OAuth client deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete unbound OAuth client: ${e.toString()}'),
              backgroundColor: theme.colorScheme.error,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _loadingUnbound = false;
          });
        }
      }
    }
  }

  Future<void> _showManualRevokeDialog(ThemeData theme) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isRevoking = false;

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Revoke Client ID'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Paste the exact OAuth client ID to revoke it and invalidate all associated tokens.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: controller,
                      enabled: !isRevoking,
                      decoration: const InputDecoration(
                        labelText: 'Client ID',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a client ID';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isRevoking ? null : () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isRevoking
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setState(() => isRevoking = true);

                          final clientId = controller.text.trim();
                          try {
                            await ref.read(agentManagerServiceProvider).deleteOAuthClient(clientId);
                            await SecureStorageService.instance.removeUnboundOAuthClientId(clientId);
                            await _loadUnboundClientIds();

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('OAuth client revoked successfully')),
                              );
                            }
                          } catch (e) {
                            setState(() => isRevoking = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to revoke client: ${e.toString()}'),
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
                  child: isRevoking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Revoke'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
