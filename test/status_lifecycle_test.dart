// Render/behaviour test for the lifecycle-status (deprecation) surfacing:
// the DEPRECATED badge on the document card and the deprecate sheet's
// confirm/cancel contract. Renders inside the real Cortado theme + localization
// harness (so a missing ThemeExtension or ARB key fails here, not at
// runtime). The POST /admin/documents/:id/status path is network and covered
// by the generated-layer smoke test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/widgets/doc_feed_card.dart';
import 'package:slopcafe_ui/widgets/pill.dart';
import 'package:slopcafe_ui/widgets/sheets.dart';

DocumentListing _doc({String status = 'active', String? supersededBy}) =>
    DocumentListing(
      publicId: 'abcdefghijklmnopqrstuv',
      createdAt: DateTime(2026, 5, 1),
      createdByKind: 'agent',
      tags: const [],
      status: status,
      visibility: 'public',
      supersededBy: supersededBy,
      title: 'Test document',
      currentVer: 1,
    );

Widget _harness(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  testWidgets('deprecated document card shows the DEPRECATED badge', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(DocFeedCard(doc: _doc(status: 'deprecated'), onOpen: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DeprecatedBadge), findsOneWidget);
    expect(find.text('DEPRECATED'), findsOneWidget);
  });

  testWidgets('active document card carries no badge', (tester) async {
    await tester.pumpWidget(
      _harness(DocFeedCard(doc: _doc(), onOpen: (_) {})),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DeprecatedBadge), findsNothing);
  });

  testWidgets('deprecate sheet returns the trimmed target on confirm', (
    tester,
  ) async {
    String? result = 'sentinel';
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDeprecateSheet(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '  hdbOcFnhL1y9fe0tWpBvXA ',
    );
    // 'Mark deprecated' is both the sheet title and the CTA; tap the CTA.
    await tester.tap(find.text('Mark deprecated').last);
    await tester.pumpAndSettle();

    expect(result, 'hdbOcFnhL1y9fe0tWpBvXA');
  });

  testWidgets('deprecate sheet returns null on cancel', (tester) async {
    String? result = 'sentinel';
    await tester.pumpWidget(
      _harness(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDeprecateSheet(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
