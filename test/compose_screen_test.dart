// Render/behaviour smoke test for the operator authoring (compose) screen.
//
// Exercises the parts that don't touch the network: it renders inside the real
// Cortado theme + localization harness (so a missing ThemeExtension or ARB key
// would fail here, not just at runtime), toggles write/preview, and checks the
// empty-content publish guard. The actual POST path is covered separately.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/screens/compose_screen.dart';

Widget _harness() => ProviderScope(
  child: MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: const ComposeScreen(),
  ),
);

/// The whole screen is a single tall scroll view; give the test surface enough
/// height that every section is laid out (so off-screen lazy slivers build).
void _tallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders the editor, metadata and publish CTA', (tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    expect(find.text('Compose'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Publish'), findsOneWidget);
    // Format + mode toggles are present.
    expect(find.text('Markdown'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });

  testWidgets('preview pane reflects the source', (tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    // Empty preview first.
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('Nothing to preview yet.'), findsOneWidget);

    // Type into the source editor, then preview shows it back (raw passthrough).
    await tester.tap(find.text('Write'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '# Hello world');
    await tester.tap(find.text('Preview'));
    await tester.pump();
    expect(find.text('# Hello world'), findsWidgets);
  });

  testWidgets('publishing empty content is guarded', (tester) async {
    _tallSurface(tester);
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publish'));
    await tester.pump(); // surface the validation toast
    expect(find.text('Write some content before publishing.'), findsOneWidget);
  });
}
