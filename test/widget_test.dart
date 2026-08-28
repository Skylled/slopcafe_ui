// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/instances.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/main.dart';
import 'package:slopcafe_ui/providers/instances_provider.dart';
import 'package:slopcafe_ui/screens/settings_screen.dart';

/// Serves a fixed [InstanceSet] instead of the real secure storage — the same
/// approach `instances_test.dart`'s sibling widget tests used before this
/// branch removed them, and the only way to pump [SettingsScreen] in
/// isolation without a keychain, which has no meaningful behaviour under
/// `flutter_test`.
class _FakeInstancesNotifier extends InstancesNotifier {
  _FakeInstancesNotifier(this._initial);
  final InstanceSet _initial;

  @override
  Future<InstanceSet> build() async => _initial;
}

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    // Build our app wrapped in ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(
        child: SlopcafeAdminApp(),
      ),
    );

    // Verify Settings screen displays initially (Base URL field exists)
    expect(find.byType(SlopcafeAdminApp), findsOneWidget);
  });

  testWidgets(
    'first run shows the hardcoded instance and a token-only connection form',
    (WidgetTester tester) async {
      // Insight seeds exactly one instance, pointed at kInsightBaseUrl with
      // an empty token — see `SecureStorageService.load`. `isConfigured` is
      // false until a token is saved, which is what routes RootGate to this
      // first-run screen in the real app.
      final seeded = SlopcafeInstance(
        id: 'insight',
        label: 'Insight',
        baseUrl: kInsightBaseUrl,
        operatorToken: '',
      );
      final set = InstanceSet(instances: [seeded], activeId: seeded.id);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            instancesProvider.overrideWith(() => _FakeInstancesNotifier(set)),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const SettingsScreen(firstRun: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Connection'), findsOneWidget);

      // The instance is shown, not editable: Insight has no Base URL field,
      // only a read-only label of the one deployment it talks to.
      expect(find.text(kInsightBaseUrl), findsOneWidget);

      // Exactly one text field on the form — the operator token. A second
      // (editable) field would mean the Base URL field is back.
      expect(find.byType(TextFormField), findsOneWidget);

      // No affordance to add, switch or manage a second deployment.
      expect(find.byIcon(Icons.swap_horiz), findsNothing);
      expect(find.byIcon(Icons.add), findsNothing);
    },
  );
}
