import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/api_client.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/providers/document_provider.dart';
import 'package:slopcafe_ui/providers/health_provider.dart';
import 'package:slopcafe_ui/screens/document_list_screen.dart';

DocumentListing _doc(String id) => DocumentListing(
      publicId: id,
      createdAt: DateTime(2026, 5, 1),
      currentVersionAt: DateTime(2026, 5, 1),
      updatedAt: DateTime(2026, 5, 1),
      createdByKind: 'operator',
      tags: const ['demo'],
      status: 'active',
      visibility: 'public',
      title: 'Doc $id',
      currentVer: 1,
    );

void main() {
  group('DocumentsListState.hasMore', () {
    test('reports false when nextCursor is null or empty', () {
      final s1 = DocumentsListState(nextCursor: null);
      expect(s1.hasMore, isFalse);

      final s2 = DocumentsListState(nextCursor: '');
      expect(s2.hasMore, isFalse);
    });

    test('reports true when nextCursor is present', () {
      final s = DocumentsListState(nextCursor: 'cursor_page_2');
      expect(s.hasMore, isTrue);
    });
  });

  group('HealthState & HealthNotifier', () {
    test('stores d1Documents and d1Agents', () {
      const state = HealthState(
        sanitizerVersion: '2.0.0',
        storageCapBytes: 1000,
        storageUsedBytes: 500,
        d1Documents: 3421,
        d1Agents: 12,
      );

      expect(state.d1Documents, equals(3421));
      expect(state.d1Agents, equals(12));
    });

    test('HealthNotifier.load parses d1 counts from /healthz response', () async {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path == '/healthz') {
              return handler.resolve(
                Response(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'ok': true,
                    'service': 'slopcafe',
                    'sanitizer_version': '1.2.3',
                    'storage_cap_bytes': 1000000,
                    'd1': {
                      'documents': 2500,
                      'agents': 8,
                    },
                    'r2': {
                      'bucket_reachable': true,
                      'sample_object_count': 3000,
                    },
                  },
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );

      final container = ProviderContainer(
        overrides: [
          dioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      final notifier = container.read(healthProvider.notifier);
      await notifier.load();

      final state = container.read(healthProvider);
      expect(state.sanitizerVersion, equals('1.2.3'));
      expect(state.d1Documents, equals(2500));
      expect(state.d1Agents, equals(8));
    });
  });

  group('DocumentListScreen pagination', () {
    testWidgets('shows Load more button when hasMore is true and no tag filter', (
      tester,
    ) async {
      final testDocs = [_doc('doc1'), _doc('doc2')];

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(documentsListProvider.notifier).state = DocumentsListState(
        documents: testDocs,
        nextCursor: 'cursor_123',
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DocumentListScreen(
              title: 'All Documents',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsOneWidget);
    });

    testWidgets('does not show Load more button when hasMore is false', (
      tester,
    ) async {
      final testDocs = [_doc('doc1'), _doc('doc2')];

      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(documentsListProvider.notifier).state = DocumentsListState(
        documents: testDocs,
        nextCursor: null,
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const DocumentListScreen(
              title: 'All Documents',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Load more'), findsNothing);
    });
  });
}
