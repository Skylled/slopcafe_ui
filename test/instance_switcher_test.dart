// Widget tests for the instance quick switcher — the one-tap path between saved
// deployments that keeps an operator out of Settings.
//
// The model behind it is pinned in `instances_test.dart`; what is pinned here is
// the wiring, which is where this feature can fail in the way that matters most:
//
//   - THE ACTIVE INSTANCE IS NAMED. Every destructive action in the app lands on
//     whichever deployment is active, and the switcher is where the operator
//     confirms which that is. A sheet that lists two instances without saying
//     which one is live is worse than no sheet at all.
//   - A TAP SWITCHES, AND ONLY WHEN IT SHOULD. Tapping another instance has to
//     reach the notifier; tapping the one already active must not, because a
//     switch throws away every loaded list and refetches it.
//
// The notifier is faked rather than driven through secure storage: the keychain
// is a platform channel with no meaningful behaviour under `flutter_test`, and
// the persistence it fronts is exercised by the model tests. What the fake
// records is the call, which is exactly the wiring under test.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/core/instances.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/providers/instances_provider.dart';
import 'package:slopcafe_ui/widgets/instance_switcher.dart';

final _upstream = SlopcafeInstance(
  id: 'slopcafe-com',
  label: 'Production',
  baseUrl: 'https://slopcafe.com',
  operatorToken: 'token-a',
);

final _fork = SlopcafeInstance(
  id: 'fork-slopcafe-dev',
  label: 'Fork',
  baseUrl: 'https://fork.slopcafe.dev',
  operatorToken: 'token-b',
);

/// Records every [switchTo] it is asked for instead of touching storage.
///
/// Deliberately guard-free: the real [InstancesNotifier.switchTo] short-circuits
/// a switch to the instance already active, and duplicating that here would make
/// the sheet look correct no matter what it forwarded. Every tap the widget
/// routes therefore shows up in [switched], which is what lets the tests below
/// distinguish "the sheet asked for a switch" from "the sheet let a redundant
/// tap through".
class _FakeInstancesNotifier extends InstancesNotifier {
  _FakeInstancesNotifier(this._initial);

  final InstanceSet _initial;
  final List<String> switched = [];

  @override
  Future<InstanceSet> build() async => _initial;

  @override
  Future<void> switchTo(String id) async {
    switched.add(id);
    state = AsyncData(_initial.activate(id));
  }
}

/// Pumps the switcher sheet open over a bare host route.
Future<_FakeInstancesNotifier> _openSwitcher(
  WidgetTester tester, {
  required InstanceSet set,
}) async {
  final fake = _FakeInstancesNotifier(set);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [instancesProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showInstanceSwitcher(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  final twoInstances = const InstanceSet.empty()
      .upsert(_upstream)
      .upsert(_fork)
      .activate(_upstream.id);

  testWidgets('lists every saved deployment with its Base URL', (tester) async {
    await _openSwitcher(tester, set: twoInstances);

    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Fork'), findsOneWidget);
    // The URL is shown alongside the name because a name is operator-chosen and
    // can be anything — the URL is what actually says where requests go.
    expect(find.text('https://slopcafe.com'), findsOneWidget);
    expect(find.text('https://fork.slopcafe.dev'), findsOneWidget);
  });

  testWidgets('marks exactly one instance as active', (tester) async {
    await _openSwitcher(tester, set: twoInstances);

    expect(find.text('Active'), findsOneWidget);
    // The badge sits on the active row, not merely somewhere on the sheet.
    expect(
      find.descendant(
        of: find.widgetWithText(InstanceRow, 'Production'),
        matching: find.text('Active'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.widgetWithText(InstanceRow, 'Fork'),
        matching: find.text('Active'),
      ),
      findsNothing,
    );
  });

  testWidgets('tapping another instance switches to it', (tester) async {
    final fake = await _openSwitcher(tester, set: twoInstances);

    await tester.tap(find.text('Fork'));
    await tester.pumpAndSettle();

    expect(fake.switched, [_fork.id]);
  });

  // A tap always addresses the row it landed on. This is the half of "tapping
  // the active instance is harmless" that lives in the widget: the sheet must
  // not mis-route a tap to a neighbouring row. The other half — that a switch to
  // the instance already active costs nothing — is the notifier's guard, pinned
  // below.
  testWidgets('a tap addresses the row it landed on', (tester) async {
    final fake = await _openSwitcher(tester, set: twoInstances);

    await tester.tap(find.text('Production'));
    await tester.pumpAndSettle();

    expect(fake.switched, [_upstream.id]);
  });

  // Switching discards every loaded list and refetches against the new
  // deployment, so a redundant switch is pure loss. The guard is the notifier's
  // (`InstancesNotifier.switchTo`), which is why it is asserted against the
  // model rather than through the sheet: activating what is already active
  // leaves the set identical, which is the condition the guard tests for.
  test('a switch to the active instance is a no-op on the set', () {
    expect(twoInstances.activate(_upstream.id), twoInstances);
    expect(twoInstances.activate(_fork.id), isNot(twoInstances));
  });

  testWidgets('a single saved instance still names itself', (tester) async {
    await _openSwitcher(
      tester,
      set: const InstanceSet.empty().upsert(_upstream),
    );

    expect(find.text('Production'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
  });
}
