import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/agent.dart';
import '../providers/agent_provider.dart';
import 'agent_detail_screen.dart';

class AgentsScreen extends ConsumerStatefulWidget {
  const AgentsScreen({super.key});

  @override
  ConsumerState<AgentsScreen> createState() => _AgentsScreenState();
}

class _AgentsScreenState extends ConsumerState<AgentsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    // Initial load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Fleet',
            onPressed: () {
              ref.read(agentsListProvider.notifier).loadNextPage(clear: true);
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Mint Agent',
            onPressed: _showNewAgentDialog,
          ),
        ],
      ),
      body: _buildBody(state, theme),
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
}
