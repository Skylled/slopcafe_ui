// The three pushed worklists, checked at a phone width and a desktop one.
//
// These screens — the change feed, the review queue and the orphan worklist —
// share a problem the shell does not have. Each of them is *only* refreshable
// by pulling the list down, and a pull is a gesture no mouse makes: Flutter's
// desktop and web `ScrollBehavior` does not accept drags from a pointer, so
// `RefreshIndicator` is touch-only by construction. The shell solved this for
// its own tabs with an explicit refresh action in the side rail, but all three
// of these are pushed routes and a pushed route covers the rail. On a desktop
// browser that left an operator looking at a stale list with no way to ask
// again.
//
// So each screen now carries its own refresh control beside its title, and this
// file is what keeps it there — at both idioms, because a control that only
// exists on one of them is the bug we started with.
//
// ## What these tests can and cannot see
//
// They pump the real screens, so a layout that overflows fails here: Flutter
// throws on a `RenderFlex` overflow in debug, and a 36px button added to a
// header row at 500px is exactly the kind of thing that would.
//
// They deliberately drive each screen's EMPTY state. That is not a shortcut —
// it is the state that motivated the work. An empty list is shorter than the
// viewport, which is when `ClampingScrollPhysics` refuses drags altogether and
// even a touch user loses pull-to-refresh (hence `AlwaysScrollableScrollPhysics`
// on all three lists), and it is the state with no rows to tap and nothing else
// to try. It also keeps the tests honest about time: rows animate in through
// `RiseIn`, and a screen full of pending animations turns a missing frame into
// a flaky assertion rather than a real one.
//
// Providers are faked at the seam each screen actually reads, so nothing here
// touches storage or HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/changes.dart';
import 'package:slopcafe_ui/core/design/layout.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/providers/changes_provider.dart';
import 'package:slopcafe_ui/providers/links_provider.dart';
import 'package:slopcafe_ui/providers/review_provider.dart';
import 'package:slopcafe_ui/screens/changes_screen.dart';
import 'package:slopcafe_ui/screens/orphans_screen.dart';
import 'package:slopcafe_ui/screens/review_queue_screen.dart';
import 'package:slopcafe_ui/widgets/app_button.dart';

/// A phone: below [AppLayout.railBreakpoint], the compact idiom.
const Size _compact = Size(500, 900);

/// A desktop window: wide enough that [AdaptiveGutter] stops using the plain
/// screen padding and starts centring the column instead.
const Size _expanded = Size(1400, 900);

/// The app's real theme and localizations around one screen.
///
/// The `overrides` list stays at each call site rather than being threaded
/// through a helper: `flutter_riverpod` does not export the `Override` type, so
/// a parameter holding one cannot be written down.
Widget _app(Widget home) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

/// Renders [widget] in a window of exactly [size] logical pixels.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget widget) async {
  tester.view
    ..devicePixelRatio = 1.0
    ..physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(widget);
  // A single frame, not pumpAndSettle: every one of these screens can hold a
  // CircularProgressIndicator, which never settles.
  await tester.pump();
}

/// The refresh control the desktop case depends on.
///
/// Found by icon rather than by widget type because [AppIconButton] is the
/// shared primitive — the assertion is about the affordance being present and
/// live, not about which class draws it.
Finder get _refreshButton => find.widgetWithIcon(AppIconButton, Icons.refresh);

void _expectUsableRefresh(WidgetTester tester) {
  expect(
    _refreshButton,
    findsOneWidget,
    reason: 'No explicit refresh on a pushed worklist: a mouse cannot pull the '
        'list down, so this screen would have no way to re-fetch at all.',
  );
  expect(
    tester.widget<AppIconButton>(_refreshButton).onPressed,
    isNotNull,
    reason: 'The refresh is present but disabled in a settled, non-loading '
        'state — an affordance that is always greyed out is not one.',
  );
}

/// The touch half of the pair: pulling an EMPTY list down still refreshes it.
///
/// Driven as a gesture rather than by inspecting `ListView.physics`, and the
/// difference matters. The obvious assertion — that the list carries
/// `AlwaysScrollableScrollPhysics` — cannot fail: `ScrollView` already supplies
/// exactly that when a vertical list has no controller and no explicit
/// `primary` (scroll_view.dart, where `physics` defaults on `primary == null &&
/// controller == null && vertical`). An earlier draft asserted it, passed, and
/// went on passing with the line deleted from the screen. The gesture asks the
/// real question instead, and it stays honest if a future `ScrollController`
/// turns `primary` off and takes the default away.
Future<void> _expectPullRefreshes(
  WidgetTester tester,
  int Function() reloads,
) async {
  final before = reloads();
  await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
  await tester.pump(); // start the fling
  await tester.pump(const Duration(seconds: 1)); // scroll settles
  await tester.pump(const Duration(seconds: 1)); // indicator fires and hides

  expect(
    reloads(),
    greaterThan(before),
    reason: 'Pulling this list down did not refresh it. In the empty state the '
        'content is shorter than the viewport, which is where clamping physics '
        'refuses the drag outright — and this screen has nothing else to offer '
        'a touch user.',
  );
}

// ---------------------------------------------------------------------------
// Fakes. Each screen reads exactly one seam; these are the smallest things that
// satisfy them without a network, and each one counts the refreshes it was
// asked for so the gesture test above has something to observe.
// ---------------------------------------------------------------------------

int _feedReloads = 0;
int _queueReloads = 0;
int _orphanFetches = 0;

class _EmptyChangeFeed extends ChangeFeedNotifier {
  @override
  ChangeFeedState build() => const ChangeFeedState(hasLoaded: true);
  @override
  Future<void> reload({ChangeWindow? window}) async => _feedReloads++;
}

class _EmptyReviewQueue extends ReviewQueueNotifier {
  @override
  ReviewQueueState build() =>
      const ReviewQueueState(hasLoaded: true, isComplete: true);
  @override
  Future<void> reload() async => _queueReloads++;
}

class _EmptyLinkGraph extends LinkGraphService {
  _EmptyLinkGraph(super.ref);
  @override
  Future<OrphanDocumentsResponse> fetchOrphans() async {
    _orphanFetches++;
    return const OrphanDocumentsResponse(documents: []);
  }
}

void main() {
  for (final (label, size) in [('compact', _compact), ('expanded', _expanded)]) {
    group('$label (${size.width.toInt()}px)', () {
      testWidgets('the change feed refreshes by pointer and by pull', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          size,
          ProviderScope(
            overrides: [changeFeedProvider.overrideWith(_EmptyChangeFeed.new)],
            child: _app(const ChangesScreen()),
          ),
        );
        _expectUsableRefresh(tester);
        await _expectPullRefreshes(tester, () => _feedReloads);
      });

      testWidgets('the review queue refreshes by pointer and by pull', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          size,
          ProviderScope(
            overrides: [
              reviewQueueProvider.overrideWith(_EmptyReviewQueue.new),
            ],
            child: _app(const ReviewQueueScreen()),
          ),
        );
        _expectUsableRefresh(tester);
        await _expectPullRefreshes(tester, () => _queueReloads);
      });

      testWidgets('the orphan worklist refreshes by pointer and by pull', (
        tester,
      ) async {
        await _pumpAt(
          tester,
          size,
          ProviderScope(
            overrides: [
              linkGraphServiceProvider.overrideWith(_EmptyLinkGraph.new),
            ],
            child: _app(const OrphansScreen()),
          ),
        );
        // One extra frame: this screen resolves its list through a FutureBuilder
        // rather than a notifier, so the settled state is a microtask away.
        await tester.pump();
        _expectUsableRefresh(tester);
        await _expectPullRefreshes(tester, () => _orphanFetches);
      });
    });
  }
}
