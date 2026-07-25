/// The shared vocabulary for the link graph (`GET /d/:public_id/links`).
///
/// The backend extracts every on-platform link out of a document's stored
/// render — `/d/<public_id>` and `/s/<slug>` hrefs — in the same D1 batch as
/// each write, and exposes both directions of the resulting wiki graph:
///
/// - `backlinks` — live documents whose CURRENT version links here, as full
///   listing rows. The "what else references this?" traversal primitive.
/// - `outbound` — this document's own links, in authored order, each carrying
///   the state its target resolves to *right now*.
///
/// Targets are stored as the raw addressed name and resolved per read — late
/// binding — which is why a link's state is a property of the read and not of
/// the document. Three of the five states are the broken-link report:
/// [LinkState.retired], [LinkState.revoked] and [LinkState.missing].
///
/// Two asymmetries in that graph are worth stating, because both look like
/// bugs from the UI side and neither is:
///
/// - The graph always reflects each document's CURRENT version, while the HTML
///   byte path may still be serving an older published one (see
///   `lib/core/publication.dart`). A public document behind the publication
///   gate can therefore render links the graph doesn't list yet, and list
///   links the rendered page doesn't carry.
/// - A link authored against a since-renamed slug is deliberately NOT counted
///   as a backlink on the document it now reaches. It only gets there through
///   the loud tombstone redirect, which is never followed implicitly, so it
///   shows up on the *source* document's outbound list as
///   [LinkState.redirected] instead — an item of link rot to repair, not an
///   edge in the graph.
///
/// Documents published before the link graph shipped have no rows at all until
/// the operator runs `POST /admin/links/backfill`. That is why an empty
/// neighborhood is reported as "nothing recorded" rather than "nothing links
/// here": the two are indistinguishable from the client, and only one of them
/// is a fact about the corpus.
library;

import '../api/api.dart';

/// What a document's outbound link resolves to at read time.
///
/// [unknown] is forward-compatibility only — a state a newer backend added
/// that this build doesn't know. It is deliberately NOT counted as broken:
/// flagging an unrecognised state as link rot would put a repair prompt on a
/// perfectly healthy link every time the contract grows a value, which is the
/// opposite of the failure this report exists to surface.
enum LinkState {
  /// A live document answers here; `target_public_id` and `title` are carried.
  live('live'),

  /// A retired slug that loudly forwards. `target_public_id` is the forward
  /// target — reachable, but the link should be rewritten to address it
  /// directly, because the redirect is never followed implicitly.
  redirected('redirected'),

  /// A retired slug with no redirect: `/s/<slug>` is 410 Gone. Dead.
  retired('retired'),

  /// A `/d/` link whose document was destroyed. Dead.
  revoked('revoked'),

  /// Nothing has ever answered here — an unclaimed slug or an unknown
  /// `public_id`. Usually a typo in the authored link. Dead.
  missing('missing'),

  /// A state this build does not recognise. Never treated as broken.
  unknown('');

  const LinkState(this.wire);

  /// The on-the-wire `state` value.
  final String wire;

  /// Maps a wire value to a state, tolerating case and surrounding whitespace.
  /// Anything unrecognised — including null — becomes [unknown].
  static LinkState fromWire(String? raw) {
    if (raw == null) return unknown;
    final token = raw.trim().toLowerCase();
    for (final state in values) {
      if (state != unknown && state.wire == token) return state;
    }
    return unknown;
  }

  /// Whether this link is dead — the broken-link report the contract names.
  ///
  /// [redirected] is pointedly excluded: it still reaches a document, so it is
  /// stale rather than broken, and grouping it with the dead links would tell
  /// the operator a working link needs fixing.
  bool get isBroken =>
      this == retired || this == revoked || this == missing;
}

/// Which namespace an outbound link addressed.
enum LinkKind {
  /// A `/d/<public_id>` link — an immutable capability id.
  publicId('public_id'),

  /// A `/s/<slug>` link — a mutable, retirable name.
  slug('slug'),

  /// A kind this build does not recognise.
  unknown('');

  const LinkKind(this.wire);

  /// The on-the-wire `kind` value.
  final String wire;

  /// Maps a wire value to a kind; anything unrecognised becomes [unknown].
  static LinkKind fromWire(String? raw) {
    if (raw == null) return unknown;
    final token = raw.trim().toLowerCase();
    for (final kind in values) {
      if (kind != unknown && kind.wire == token) return kind;
    }
    return unknown;
  }
}

/// The link-graph rules as they apply to one outbound link.
extension OutboundLinkGraph on OutboundLink {
  /// The parsed [LinkState] of the raw `state` string.
  LinkState get linkState => LinkState.fromWire(state);

  /// The parsed [LinkKind] of the raw `kind` string.
  LinkKind get linkKind => LinkKind.fromWire(kind);

  /// Whether this link is dead — see [LinkState.isBroken].
  bool get isBroken => linkState.isBroken;

  /// Whether tapping this link can open a document.
  ///
  /// Keyed on the resolved target rather than on the state, because the target
  /// is the thing navigation actually needs: `live` carries itself and
  /// `redirected` carries the forward target, and both are openable, while the
  /// three broken states carry null and are not.
  bool get canOpen => targetPublicId != null;

  /// Whether the slug-tombstone repair actions apply to this link.
  ///
  /// A redirect may only be set on a name that is ALREADY retired, so this is
  /// narrower than "is broken" in both directions:
  ///
  /// - [LinkKind.publicId] links are excluded outright. A `revoked` document
  ///   has no slug to point anywhere, and its id can never resolve again.
  /// - [LinkState.missing] is excluded even though it is broken and may well
  ///   be slug-shaped. A name nothing ever claimed has no tombstone, so
  ///   `POST /admin/slugs/:slug/redirect` answers 404 — the fix for a typo'd
  ///   link is to edit the document, not to conjure a redirect for it.
  /// - [LinkState.redirected] IS included even though it isn't broken, because
  ///   an existing redirect is the one thing the clear and release actions
  ///   operate on.
  bool get canRepairSlug =>
      linkKind == LinkKind.slug &&
      (linkState == LinkState.retired || linkState == LinkState.redirected);
}

/// The link-graph rules as they apply to a whole neighborhood.
extension DocumentLinkGraph on DocumentLinksResponse {
  /// This document's dead outbound links, in authored order.
  List<OutboundLink> get brokenOutbound =>
      outbound.where((link) => link.isBroken).toList();

  /// How many outbound links are dead. Drives the report's caution marker.
  int get brokenCount => brokenOutbound.length;

  /// Whether the graph recorded nothing at all for this document.
  ///
  /// Callers should read this as "nothing recorded", not "nothing links here":
  /// a corpus published before the link graph shipped has no rows until the
  /// operator runs the backfill, and the two cases look identical from here.
  bool get hasNoGraph => backlinks.isEmpty && outbound.isEmpty;
}
