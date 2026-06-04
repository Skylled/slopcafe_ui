import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'core/secure_storage.dart';
import 'screens/app_shell.dart';
import 'screens/settings_screen.dart';

void main() {
  runApp(const ProviderScope(child: SlopcafeAdminApp()));
}

class SlopcafeAdminApp extends StatelessWidget {
  const SlopcafeAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Slopcafe Operator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      home: const RootGate(),
    );
  }
}

/// First-launch gate: routes to [SettingsScreen] when the deployment is not yet
/// configured (no Base URL / Operator Token in secure storage), otherwise the
/// [AppShell]. Mirrors the connection check the old `MainNavigationShell` ran on
/// startup; the in-app 401 interception now lives in [AppShell].
class RootGate extends StatefulWidget {
  const RootGate({super.key});

  @override
  State<RootGate> createState() => _RootGateState();
}

class _RootGateState extends State<RootGate> {
  bool? _configured;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final storage = SecureStorageService.instance;
    final url = await storage.getBaseUrl();
    final token = await storage.getOperatorToken();
    if (!mounted) return;
    setState(() => _configured = url != null && token != null);
  }

  @override
  Widget build(BuildContext context) {
    final configured = _configured;
    if (configured == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!configured) {
      return SettingsScreen(onSaved: () => setState(() => _configured = true));
    }
    return const AppShell();
  }
}
