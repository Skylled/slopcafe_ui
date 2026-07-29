import 'dart:io' show Platform;

import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/deep_link.dart';

/// Whether this build answers inbound web links at all.
///
/// **Mobile only, by choice as well as by circumstance.** The circumstance is
/// that macOS cannot deliver these links today: a `https://` link only reaches
/// a Mac app through Universal Links, which needs an `Associated Domains`
/// entitlement, which needs a Developer Program team — and this app is ad-hoc
/// signed with no team (see the macOS notes in GEMINI.md). Registering the
/// origin as a plain URL scheme instead would hijack the operator's browser
/// links system-wide, which is exactly what a desktop operator does *not* want:
/// on a Mac the browser is where a `slopcafe.com` link belongs.
///
/// The choice is that we say so here rather than letting it be incidental. iOS
/// is included ahead of the target existing so that adding one is an Xcode
/// capability plus an `apple-app-site-association` file, not a hunt through
/// Dart for a platform check that silently excluded it.
bool get deepLinksSupported => Platform.isAndroid || Platform.isIOS;

/// The `app_links` handle. Overridable in tests; the package itself is a
/// singleton, so this provider is about injection, not lifetime.
final appLinksProvider = Provider<AppLinks>((ref) => AppLinks());

/// Every inbound web link that addresses a document, cold-start one included.
///
/// A plain `Provider<Stream<…>>` rather than a `StreamProvider` on purpose. The
/// consumer ([AppShell]) wants *each* link as an event to navigate on, and
/// `StreamProvider` would hand it de-duplicated application state instead:
/// re-opening the same URL twice in a row is a repeat of an equal
/// `AsyncData<DeepLinkTarget>`, so a `ref.listen` would never fire the second
/// time and the tap would land on nothing.
///
/// Cold-start delivery needs no separate `getInitialLink()` call, and adding
/// one would be a bug rather than belt-and-braces. The Android plugin holds the
/// launch intent's URL and flushes it to the *first* subscriber, once, guarded
/// by its own `initialLinkSent` flag — so a subscriber that only attaches after
/// the operator has finished configuring the deployment still receives the link
/// that launched the app, and a later re-subscription does not replay it into a
/// second Reader.
final inboundDeepLinksProvider = Provider<Stream<DeepLinkTarget>>((ref) {
  if (!deepLinksSupported) return const Stream<DeepLinkTarget>.empty();

  return ref
      .watch(appLinksProvider)
      .uriLinkStream
      .map(parseDeepLink)
      .where((target) => target != null)
      .cast<DeepLinkTarget>();
});
