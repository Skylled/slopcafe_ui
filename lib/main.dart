import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme.dart';
import 'l10n/app_localizations.dart';
import 'l10n/l10n.dart';
import 'providers/instances_provider.dart';
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
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RootGate(),
    );
  }
}

/// First-launch gate: routes to [SettingsScreen] while no deployment is
/// configured, otherwise the [AppShell].
///
/// It watches [instancesProvider] rather than reading secure storage once at
/// `initState`, which is what makes the gate reactive: saving the first
/// instance swaps in the shell, and clearing every instance from the Settings
/// danger zone drops straight back to setup, with no callback threaded through
/// the screen to say so.
class RootGate extends ConsumerWidget {
  const RootGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instances = ref.watch(instancesProvider);

    return instances.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      // Storage is unreadable rather than empty. Setup is still the useful
      // destination: it is the one screen that can write a fresh set over
      // whatever is wrong, and its danger zone can clear it outright.
      error: (_, _) => const SettingsScreen(firstRun: true),
      data: (set) => set.isConfigured
          ? const AppShell()
          : const SettingsScreen(firstRun: true),
    );
  }
}
