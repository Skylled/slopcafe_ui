import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'core/theme.dart';
import 'core/secure_storage.dart';
import 'core/api_client.dart';
import 'screens/documents_screen.dart';
import 'screens/agents_screen.dart';

void main() {
  runApp(
    const ProviderScope(
      child: SlopcafeAdminApp(),
    ),
  );
}

class SlopcafeAdminApp extends ConsumerWidget {
  const SlopcafeAdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Slopcafe Operator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const MainNavigationShell(),
    );
  }
}

/// Simple state provider for current navigation screen.
enum ActiveScreen { settings, documents, agents }

final activeScreenProvider = StateProvider<ActiveScreen>((ref) => ActiveScreen.settings);

class MainNavigationShell extends ConsumerStatefulWidget {
  const MainNavigationShell({super.key});

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    final storage = SecureStorageService.instance;
    final url = await storage.getBaseUrl();
    final token = await storage.getOperatorToken();

    if (url != null && token != null) {
      ref.read(activeScreenProvider.notifier).state = ActiveScreen.documents;
    } else {
      ref.read(activeScreenProvider.notifier).state = ActiveScreen.settings;
    }

    setState(() {
      _initializing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final activeScreen = ref.watch(activeScreenProvider);
    // Observe the connectionState to force UI updates or handle banners
    ref.watch(connectionStateProvider);

    // If unauthorized, intercept and show modal/banner on Settings screen
    ref.listen<ApiConnectionState>(connectionStateProvider, (previous, next) {
      if (next.status == ConnectionStatus.unauthorized) {
        ref.read(activeScreenProvider.notifier).state = ActiveScreen.settings;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage ?? 'Operator token rejected'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    });

    return Scaffold(
      body: Row(
        children: [
          // Navigation rail for macOS / Desktop or larger screens
          if (MediaQuery.of(context).size.width >= 600)
            NavigationRail(
              selectedIndex: _getRailIndex(activeScreen),
              onDestinationSelected: (index) => _onNavigationSelected(index),
              labelType: NavigationRailLabelType.all,
              destinations: const [
                NavigationRailDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings),
                  label: Text('Settings'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.description_outlined),
                  selectedIcon: Icon(Icons.description),
                  label: Text('Documents'),
                ),
                NavigationRailDestination(
                  icon: Icon(Icons.people_outline),
                  selectedIcon: Icon(Icons.people),
                  label: Text('Agents'),
                ),
              ],
            ),
          Expanded(
            child: _buildScreen(activeScreen),
          ),
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).size.width < 600
          ? BottomNavigationBar(
              currentIndex: _getRailIndex(activeScreen),
              onTap: (index) => _onNavigationSelected(index),
              type: BottomNavigationBarType.fixed,
              selectedItemColor: Theme.of(context).colorScheme.primary,
              unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings_outlined),
                  activeIcon: Icon(Icons.settings),
                  label: 'Settings',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.description_outlined),
                  activeIcon: Icon(Icons.description),
                  label: 'Documents',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.people_outline),
                  activeIcon: Icon(Icons.people),
                  label: 'Agents',
                ),
              ],
            )
          : null,
    );
  }

  int _getRailIndex(ActiveScreen screen) {
    switch (screen) {
      case ActiveScreen.settings:
        return 0;
      case ActiveScreen.documents:
        return 1;
      case ActiveScreen.agents:
        return 2;
    }
  }

  void _onNavigationSelected(int index) {
    final screens = [
      ActiveScreen.settings,
      ActiveScreen.documents,
      ActiveScreen.agents,
    ];
    ref.read(activeScreenProvider.notifier).state = screens[index];
  }

  Widget _buildScreen(ActiveScreen screen) {
    switch (screen) {
      case ActiveScreen.settings:
        return const SettingsScreen();
      case ActiveScreen.documents:
        return const DocumentsScreen();
      case ActiveScreen.agents:
        return const AgentsScreen();
    }
  }
}

/// Settings and Connection Configuration Screen
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadConnectionSettings();
  }

  Future<void> _loadConnectionSettings() async {
    final storage = SecureStorageService.instance;
    final url = await storage.getBaseUrl();
    final token = await storage.getOperatorToken();
    if (url != null) _urlController.text = url;
    if (token != null) _tokenController.text = token;
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testingConnection = true;
      _testResult = null;
    });

    final dio = ref.read(dioProvider);
    final url = _urlController.text.trim();
    final token = _tokenController.text.trim();

    try {
      // 1. Health Probe
      final healthResponse = await dio.get('$url/');
      
      // 2. Auth Probe
      final authResponse = await dio.get(
        '$url/admin/agents?limit=1',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (healthResponse.statusCode == 200 && authResponse.statusCode == 200) {
        setState(() {
          _testResult = 'Connection successful!\n'
              'Sanitizer version: ${healthResponse.data['sanitizer_version']}\n'
              'Storage cap: ${healthResponse.data['storage_cap_bytes']} bytes';
        });
        ref.read(connectionStateProvider.notifier).setStatus(ConnectionStatus.connected);
      } else {
        setState(() {
          _testResult = 'Connection probe failed with unexpected codes.';
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Connection failed: ${e.toString()}';
      });
    } finally {
      setState(() {
        _testingConnection = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;
    await SecureStorageService.instance.saveConnectionDetails(
      baseUrl: _urlController.text,
      operatorToken: _tokenController.text,
    );
    ref.read(activeScreenProvider.notifier).state = ActiveScreen.documents;
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved successfully')),
    );
  }

  Future<void> _clearAll() async {
    await SecureStorageService.instance.clearAll();
    _urlController.clear();
    _tokenController.clear();
    ref.read(connectionStateProvider.notifier).reset();
    setState(() {
      _testResult = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Secure storage cleared')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionStateProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Slopcafe Connection'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (connectionState.status == ConnectionStatus.unauthorized)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.onErrorContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            connectionState.errorMessage ?? 'Operator token was rejected.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Configure your operator-level admin settings below to securely connect to your Slopcafe deployment.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _urlController,
                decoration: const InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://agent-web-host.skylled.workers.dev',
                  prefixIcon: Icon(Icons.link),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a Base URL';
                  }
                  if (!value.startsWith('http://') && !value.startsWith('https://')) {
                    return 'Must start with http:// or https://';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _tokenController,
                obscureText: _obscureToken,
                decoration: InputDecoration(
                  labelText: 'Operator Token',
                  prefixIcon: const Icon(Icons.vpn_key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureToken ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter the Operator token';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _testingConnection ? null : _testConnection,
                      icon: _testingConnection
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.offline_bolt_outlined),
                      label: const Text('Test Connection'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      child: const Text('Save & Continue'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton.icon(
                  onPressed: _clearAll,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Clear Secure Storage'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              if (_testResult != null) ...[
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _testResult!,
                    style: const TextStyle(fontFamily: 'Courier', fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashboard Screen showing core Slopcafe metrics and controls.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Slopcafe Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Trigger reload metrics
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome Back, Operator',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'All services operational. Below are the global statistics of your fleet.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            // Statistics Grid Layout
            GridView.count(
              crossAxisCount: MediaQuery.of(context).size.width >= 600 ? 3 : 1,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStatTile(
                  context,
                  title: 'Active Agents',
                  value: '8',
                  icon: Icons.people_outline,
                  color: Theme.of(context).colorScheme.primary,
                ),
                _buildStatTile(
                  context,
                  title: 'Total Documents',
                  value: '142',
                  icon: Icons.description_outlined,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                _buildStatTile(
                  context,
                  title: 'Storage capacity',
                  value: '2.4 / 10 GB',
                  icon: Icons.pie_chart_outline,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ],
            ),
            const SizedBox(height: 32),
            Text(
              'Quick Fleet Actions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      ref.read(activeScreenProvider.notifier).state = ActiveScreen.agents;
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Theme.of(context).colorScheme.primary,
                            Theme.of(context).colorScheme.secondary,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.people, color: Colors.white, size: 36),
                          SizedBox(height: 12),
                          Text(
                            'Manage Agents',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      ref.read(activeScreenProvider.notifier).state = ActiveScreen.documents;
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.description, color: Theme.of(context).colorScheme.primary, size: 36),
                          const SizedBox(height: 12),
                          Text(
                            'View Documents',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatTile(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Icon(icon, color: color, size: 28),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
