import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'agent_provider.dart';
import 'document_provider.dart';
import 'health_provider.dart';

/// Reload everything the home tabs render — the document list, the agent fleet,
/// and the best-effort backend health snapshot — concurrently. This is exactly
/// the set of fetches a cold app open kicks off (Library/Operate `initState`),
/// so calling it is "as if the app were opened anew".
///
/// Both the Library and Operate pull-to-refresh gestures funnel through here, so
/// either gesture produces the same full reload of *both* tabs' data — not just
/// the data of the tab the pull happened on.
Future<void> refreshFleetData(WidgetRef ref) {
  return Future.wait([
    ref.read(documentsListProvider.notifier).loadNextPage(clear: true),
    ref.read(agentsListProvider.notifier).loadNextPage(clear: true),
    ref.read(healthProvider.notifier).load(),
  ]);
}
