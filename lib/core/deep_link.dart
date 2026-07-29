/// The shared vocabulary for **inbound web links** — a tap on a
/// `https://<host>/d/:public_id` or `https://<host>/s/:slug` URL anywhere on
/// the device opening that document in the Reader instead of a browser.
///
/// This is the fifth hermetic core module, beside `publication.dart`,
/// `links.dart`, `changes.dart` and `review.dart`: no Flutter imports, no
/// `dart:io`, one constant and one pure function. The platform plumbing (the
/// `app_links` subscription and the mobile-only rule) lives in
/// `lib/providers/deep_link_provider.dart`, and the navigation lives in
/// `AppShell`.
///
/// ## The two addressable namespaces
///
/// These are the same two the link graph resolves (`lib/core/links.dart`) and
/// the same two the Reader already handles for in-WebView taps: `/d/` is the
/// immutable capability id, `/s/` is the mutable, retirable name. Nothing else
/// on the public origin is claimed — see the path-prefix note below.
///
/// ## Why the host is pinned in source rather than read from settings
///
/// The app's *runtime* deployment knob is the Base URL in secure storage, and
/// it would be tempting to match an inbound link against that instead. It
/// cannot work: Android decides whether this app even sees the tap long before
/// any Dart runs, from the `<intent-filter>` compiled into the manifest. The
/// host is therefore a **build-time** fact, and [kDeepLinkHost] is the one
/// place in Dart that states it.
///
/// That does duplicate the literal — the manifest needs it too — so the pair is
/// pinned by `test/deep_link_test.dart`, which reads `deepLinkHost` back out of
/// `android/app/build.gradle.kts` and asserts the two agree. Drift becomes a
/// red test rather than an app that quietly stops answering its own links.
library;

/// The public web host whose document links this build claims.
///
/// **This is the knob an adopter changes.** It must be kept identical to the
/// `deepLinkHost` manifest placeholder in `android/app/build.gradle.kts`; the
/// invariant is enforced by `test/deep_link_test.dart`.
///
/// Bare host only — no scheme, no port, no path. Both `http` and `https` links
/// to it are claimed (see [parseDeepLink]). To claim a second host as well
/// (`www.` being the usual one), add a matching `<data>` tuple to the
/// `AndroidManifest.xml` intent-filter and widen this file's comparison; a
/// second host also needs its own `assetlinks.json`, because App Links
/// verification is per-host.
const String kDeepLinkHost = 'slopcafe.com';

/// A document addressed by an inbound web link.
///
/// Deliberately carries the *raw addressed name* rather than a resolved
/// document, for the same reason the link graph does: `/s/` names are late-
/// bound, so what a slug points at is a property of the read, not of the link.
/// Resolution is [DocumentsListNotifier.resolveListing]'s job.
///
/// Exactly one of [publicId] / [slug] is non-null.
class DeepLinkTarget {
  const DeepLinkTarget._({this.publicId, this.slug});

  /// A `/d/<public_id>` link — the immutable capability id.
  const DeepLinkTarget.publicId(String publicId) : this._(publicId: publicId);

  /// A `/s/<slug>` link — the mutable, retirable name.
  const DeepLinkTarget.slug(String slug) : this._(slug: slug);

  final String? publicId;
  final String? slug;

  @override
  bool operator ==(Object other) =>
      other is DeepLinkTarget &&
      other.publicId == publicId &&
      other.slug == slug;

  @override
  int get hashCode => Object.hash(publicId, slug);

  @override
  String toString() =>
      publicId != null ? 'DeepLinkTarget(/d/$publicId)' : 'DeepLinkTarget(/s/$slug)';
}

/// The document [uri] addresses, or null when it addresses none.
///
/// A null result means "not ours" and callers must treat it as a no-op rather
/// than as an error: Android's intent-filter is scoped to the `/d/` and `/s/`
/// path prefixes, so in practice nothing else reaches this function, and a
/// future filter widening should degrade to silence rather than to a toast
/// about a link the operator never expected the app to claim.
///
/// Accepted:
///
/// * `https://<host>/d/<public_id>` and `http://` likewise. Plain `http` is
///   claimed because letting an unencrypted link escape to the browser is
///   strictly worse than opening it here — the app then talks to its own
///   configured (`https`) Base URL regardless of the scheme it was handed.
/// * `https://<host>/s/<slug>`.
/// * Both of the above with **trailing segments**, which are ignored. The byte
///   paths a copied URL can carry — `/d/:id/raw`, `/d/:id/v/:n/raw` — still
///   identify the document, and opening it beats bouncing to a browser. Note
///   the consequence: a link pinned to a historical version opens the *latest*
///   view, because [ReaderScreen] owns version selection in its own state
///   rather than in its constructor. That is a deliberate under-delivery, not
///   an oversight.
///
/// Rejected: any other scheme, any other host, any other first segment
/// (`/openapi.json`, `/`, …), and an empty id/slug (`/d/`, `/s//`).
DeepLinkTarget? parseDeepLink(Uri uri) {
  final scheme = uri.scheme.toLowerCase();
  if (scheme != 'https' && scheme != 'http') return null;

  // `Uri` already lowercases the host it parses, but the comparison is made
  // explicit rather than leaning on that, since a caller may hand us a `Uri`
  // built by other means.
  if (uri.host.toLowerCase() != kDeepLinkHost.toLowerCase()) return null;

  final segments = uri.pathSegments;
  if (segments.length < 2) return null;

  // `pathSegments` percent-decodes for us, so a slug that travelled encoded
  // arrives as the name the corpus actually stores.
  final name = segments[1].trim();
  if (name.isEmpty) return null;

  switch (segments[0]) {
    case 'd':
      return DeepLinkTarget.publicId(name);
    case 's':
      return DeepLinkTarget.slug(name);
    default:
      return null;
  }
}
