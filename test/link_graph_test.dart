// Unit + render tests for the link graph (GET /d/:id/links) and the slug
// tombstones that repair the link rot it reports.
//
// The graph resolves each outbound link's target at read time and reports one
// of five states. Two rules built on top of that carry the whole feature, and
// both are easy to get subtly wrong:
//
//   - WHICH STATES ARE BROKEN. `retired`, `revoked` and `missing` are dead;
//     `redirected` still reaches a document and is merely stale. Folding
//     `redirected` in would tell the operator a working link needs fixing, and
//     an unrecognised future state must not read as rot at all.
//   - WHICH LINKS THE SLUG REPAIR APPLIES TO. A redirect may only be set on a
//     name that is ALREADY retired, so the actionable set is narrower than
//     "broken" in one direction (a `missing` name has no tombstone; a `/d/`
//     link has no slug) and wider in the other (`redirected` is not broken but
//     is the only state the clear/release actions operate on).
//
// Everything here is hermetic: the state matrix builds `OutboundLink` values
// directly, because what is under test is the vocabulary, not HTTP.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slopcafe_ui/api/api.dart';
import 'package:slopcafe_ui/core/links.dart';
import 'package:slopcafe_ui/core/theme.dart';
import 'package:slopcafe_ui/l10n/app_localizations.dart';
import 'package:slopcafe_ui/widgets/pill.dart';

OutboundLink _link({
  required String kind,
  required String state,
  String value = 'some-name',
  String? targetPublicId,
  String? title,
}) => OutboundLink(
  kind: kind,
  value: value,
  state: state,
  targetPublicId: targetPublicId,
  title: title,
);

DocumentListing _listing(String publicId) => DocumentListing(
  publicId: publicId,
  createdAt: DateTime(2026, 5, 1),
  updatedAt: DateTime(2026, 6, 9),
  createdByKind: 'agent',
  tags: const [],
  status: 'active',
  visibility: 'public',
  title: 'Backlinking document',
);

Widget _harness(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('LinkState.fromWire', () {
    test('parses every state the contract defines', () {
      expect(LinkState.fromWire('live'), LinkState.live);
      expect(LinkState.fromWire('redirected'), LinkState.redirected);
      expect(LinkState.fromWire('retired'), LinkState.retired);
      expect(LinkState.fromWire('revoked'), LinkState.revoked);
      expect(LinkState.fromWire('missing'), LinkState.missing);
    });

    test('tolerates case and surrounding whitespace', () {
      expect(LinkState.fromWire('  LIVE '), LinkState.live);
      expect(LinkState.fromWire('Redirected'), LinkState.redirected);
    });

    test('resolves an unrecognised or absent value to unknown', () {
      expect(LinkState.fromWire('quantum'), LinkState.unknown);
      expect(LinkState.fromWire(''), LinkState.unknown);
      expect(LinkState.fromWire(null), LinkState.unknown);
    });

    test('never resolves anything TO the unknown sentinel by its wire value', () {
      // `unknown` carries the empty string so it can't be matched by a real
      // wire value; the empty case above lands there by falling through, not by
      // matching. Guards against a future state being given an empty wire.
      expect(LinkState.unknown.wire, isEmpty);
    });
  });

  group('which states are broken', () {
    test('the three dead states are broken', () {
      expect(LinkState.retired.isBroken, isTrue);
      expect(LinkState.revoked.isBroken, isTrue);
      expect(LinkState.missing.isBroken, isTrue);
    });

    test('a live link is not broken', () {
      expect(LinkState.live.isBroken, isFalse);
    });

    // A redirect still reaches a document. Grouping it with the dead links
    // would put a repair prompt on a link that works.
    test('a redirected link is stale, not broken', () {
      expect(LinkState.redirected.isBroken, isFalse);
    });

    // The forward-compat guarantee: a state a newer backend added must not be
    // reported as link rot by an older build.
    test('an unknown state is never reported as broken', () {
      expect(LinkState.unknown.isBroken, isFalse);
    });
  });

  group('LinkKind.fromWire', () {
    test('parses both namespaces', () {
      expect(LinkKind.fromWire('public_id'), LinkKind.publicId);
      expect(LinkKind.fromWire('slug'), LinkKind.slug);
    });

    test('resolves anything else to unknown', () {
      expect(LinkKind.fromWire('urn'), LinkKind.unknown);
      expect(LinkKind.fromWire(null), LinkKind.unknown);
    });
  });

  group('opening an outbound link', () {
    test('a live link opens its own target', () {
      final link = _link(
        kind: 'slug',
        state: 'live',
        targetPublicId: 'abcdefghijklmnopqrstuv',
      );
      expect(link.canOpen, isTrue);
    });

    // A redirect resolves to the forward target, so it is navigable even though
    // the link itself wants rewriting.
    test('a redirected link opens the forward target', () {
      final link = _link(
        kind: 'slug',
        state: 'redirected',
        targetPublicId: 'abcdefghijklmnopqrstuv',
      );
      expect(link.canOpen, isTrue);
    });

    test('a broken link has nothing to open', () {
      for (final state in ['retired', 'revoked', 'missing']) {
        expect(
          _link(kind: 'slug', state: state).canOpen,
          isFalse,
          reason: 'state $state carries no target',
        );
      }
    });
  });

  group('which links the slug repair applies to', () {
    test('a retired slug can be repaired — it has a tombstone', () {
      expect(_link(kind: 'slug', state: 'retired').canRepairSlug, isTrue);
    });

    // Not broken, but it is the only state the clear/release actions have
    // anything to act on.
    test('a redirected slug can be repaired', () {
      expect(_link(kind: 'slug', state: 'redirected').canRepairSlug, isTrue);
    });

    // Broken, but a name nothing ever claimed has no tombstone: the redirect
    // route would answer 404. The fix is to edit the document.
    test('a missing name cannot be repaired despite being broken', () {
      expect(_link(kind: 'slug', state: 'missing').canRepairSlug, isFalse);
    });

    test('a live slug needs no repair', () {
      expect(_link(kind: 'slug', state: 'live').canRepairSlug, isFalse);
    });

    // A /d/ link addresses an immutable id. A revoked document has no slug to
    // point anywhere, and its id can never resolve again.
    test('a public_id link is never repairable, whatever its state', () {
      for (final state in [
        'live',
        'redirected',
        'retired',
        'revoked',
        'missing',
      ]) {
        expect(
          _link(kind: 'public_id', state: state).canRepairSlug,
          isFalse,
          reason: '/d/ links carry no slug (state $state)',
        );
      }
    });
  });

  group('the neighborhood as a whole', () {
    test('counts only the dead links as broken', () {
      final graph = DocumentLinksResponse(
        publicId: 'abcdefghijklmnopqrstuv',
        backlinks: const [],
        outbound: [
          _link(kind: 'slug', state: 'live', targetPublicId: 'a'),
          _link(kind: 'slug', state: 'redirected', targetPublicId: 'b'),
          _link(kind: 'slug', state: 'retired'),
          _link(kind: 'public_id', state: 'revoked'),
          _link(kind: 'slug', state: 'missing'),
          _link(kind: 'slug', state: 'a-state-from-the-future'),
        ],
      );

      // 6 links, 3 dead: the live one, the redirect and the unknown all count
      // as working.
      expect(graph.brokenCount, 3);
      expect(
        graph.brokenOutbound.map((l) => l.linkState),
        [LinkState.retired, LinkState.revoked, LinkState.missing],
      );
      expect(graph.hasNoGraph, isFalse);
    });

    // A pre-backfill document and a genuinely unlinked one are indistinguishable
    // from here, which is why the UI says "nothing recorded" rather than
    // "nothing links here".
    test('an empty neighborhood in both directions has no graph', () {
      const graph = DocumentLinksResponse(
        publicId: 'abcdefghijklmnopqrstuv',
        backlinks: [],
        outbound: [],
      );
      expect(graph.hasNoGraph, isTrue);
      expect(graph.brokenCount, 0);
    });

    test('a document with only backlinks still has a graph', () {
      final graph = DocumentLinksResponse(
        publicId: 'abcdefghijklmnopqrstuv',
        backlinks: [_listing('vutsrqponmlkjihgfedcba')],
        outbound: const [],
      );
      expect(graph.hasNoGraph, isFalse);
    });
  });

  group('the state badge', () {
    Future<void> pumpBadge(WidgetTester tester, LinkState state) async {
      await tester.pumpWidget(_harness(LinkStateBadge(state)));
      await tester.pumpAndSettle();
    }

    testWidgets('names each state', (tester) async {
      await pumpBadge(tester, LinkState.live);
      expect(find.text('LIVE'), findsOneWidget);

      await pumpBadge(tester, LinkState.redirected);
      expect(find.text('REDIRECTED'), findsOneWidget);

      await pumpBadge(tester, LinkState.retired);
      expect(find.text('RETIRED'), findsOneWidget);

      await pumpBadge(tester, LinkState.revoked);
      expect(find.text('REVOKED'), findsOneWidget);

      await pumpBadge(tester, LinkState.missing);
      expect(find.text('MISSING'), findsOneWidget);
    });

    // Neutral, not red: an unrecognised state is not evidence of link rot.
    testWidgets('renders an unknown state without alarm', (tester) async {
      await pumpBadge(tester, LinkState.unknown);
      expect(find.text('UNKNOWN'), findsOneWidget);

      final pill = tester.widget<Pill>(find.byType(Pill));
      expect(pill.tone, PillTone.neutral);
    });

    testWidgets('tones a working link apart from a dead one', (tester) async {
      await pumpBadge(tester, LinkState.live);
      expect(tester.widget<Pill>(find.byType(Pill)).tone, PillTone.green);

      // Honey, like DEPRECATED: a caution about how the link resolves, not the
      // red of something dead.
      await pumpBadge(tester, LinkState.redirected);
      expect(tester.widget<Pill>(find.byType(Pill)).tone, PillTone.honey);

      await pumpBadge(tester, LinkState.retired);
      expect(tester.widget<Pill>(find.byType(Pill)).tone, PillTone.red);
    });
  });
}
