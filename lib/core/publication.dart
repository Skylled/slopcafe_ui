/// The shared vocabulary for contract 2.0.0's publication gate.
///
/// From 2.0.0 the backend stores `published_ver` alongside `current_ver`, and
/// the HTML byte path (`GET /d/:id/raw`, `GET /s/:slug`) serves:
///
///     served = (visibility == 'public' && published_ver != null)
///         ? published_ver
///         : current_ver
///
/// There is no principal term in that rule. A public document serves its
/// published version to *everyone* — anonymous visitor, agent key and operator
/// alike — so this app cannot assume that what it renders in the reader is the
/// newest thing it wrote. A private document always serves `current_ver`, and
/// so does a public document that has never been promoted (`published_ver` is
/// null means the gate was never closed). Every credentialed, machine-readable
/// surface — `/d/:id/text`, `/d/:id/source`, the admin list, search — stayed on
/// `current_ver` and is untouched by 2.0.0; only the HTML bytes moved.
///
/// Two response headers carry those numbers back, and they answer *different*
/// questions:
///
/// - `ETag` names the version that was actually SERVED at that URL. It is
///   always present. The canonical form is `"v7"`, but Cloudflare rewrites it
///   to `W/"v7"` whenever it gzips the body (which it does routinely for
///   HTML), so nothing may assume the strong form survives the edge.
/// - `x-doc-current-version` is a bare integer naming the CURRENT version. It
///   is sent only to a non-anonymous caller, and it rides 304 responses as well
///   as 200s — a conditional request that validates still tells us where the
///   document's head is.
///
/// The ETag fallback in [resolveCurrentVersion] is load-bearing, not defensive
/// scaffolding, and it should not be "hardened" into an error path later. The
/// header is absent in exactly two situations: the caller was anonymous, or the
/// server predates 2.0.0. In both of those the publication gate is not in play
/// at all — a pre-2.0.0 server has no `published_ver`, and an anonymous request
/// from this app doesn't happen — so the ETag *is* the current version. Reading
/// it is the correct answer, not a degraded guess. Treating the header as
/// mandatory would break version resolution against every older deployment for
/// no gain.
library;

import 'package:dio/dio.dart';

import '../api/api.dart';

/// A version token with the ETag's optional `v` prefix, after the weak marker
/// and any surrounding quotes have been peeled off. `x-doc-current-version`
/// sends a bare integer, which this also accepts.
final RegExp _versionToken = RegExp(r'^v?(\d+)$', caseSensitive: false);

/// Parses a version out of an `ETag` or `x-doc-current-version` value.
///
/// Accepts every form the byte path can hand us: `"v7"`, `W/"v7"`, `v7`, `7`,
/// and a quoted bare number `"7"`, with surrounding whitespace. Returns null
/// for anything else.
///
/// This is deliberately strict rather than salvaging digits out of a
/// malformed value. A version drives cache keys, If-Match preflights and the
/// "unpublished work" badge; a wrong number is worse than no number, because
/// no number degrades to a visible unknown while a wrong one silently
/// mislabels the document or clobbers a newer write.
int? parseVersionTag(String? raw) {
  if (raw == null) return null;

  var token = raw.trim();
  if (token.isEmpty) return null;

  // Cloudflare weakens the ETag when it re-encodes the body. The `W/` prefix
  // describes the comparison semantics, not the version, so it is dropped.
  if (token.length > 2 && token.substring(0, 2).toUpperCase() == 'W/') {
    token = token.substring(2).trim();
  }

  // Quotes belong to the ETag grammar, not to the value. Only a matched pair
  // is stripped: a lone quote means the header is malformed, and guessing what
  // the sender meant is exactly what this parser refuses to do.
  if (token.length >= 2 && token.startsWith('"') && token.endsWith('"')) {
    token = token.substring(1, token.length - 1).trim();
  } else if (token.contains('"')) {
    return null;
  }

  final match = _versionToken.firstMatch(token);
  if (match == null) return null;

  // `int.tryParse` also rejects a value too large for a 64-bit int, which the
  // regexp alone would have waved through.
  return int.tryParse(match.group(1)!);
}

/// Reads the first usable value of a header, matched case-insensitively.
///
/// Dio's [Headers] is already backed by a case-insensitive map, but that is an
/// implementation detail of the transport rather than a guarantee the callers
/// of this file rely on, so the comparison is made explicit here. We also walk
/// the values ourselves instead of calling `Headers.value`, which throws when a
/// header arrived more than once — a duplicated `ETag` from an intermediary
/// should cost us a version, not crash the read path.
String? _header(Headers headers, String lowercaseName) {
  for (final entry in headers.map.entries) {
    if (entry.key.trim().toLowerCase() != lowercaseName) continue;
    for (final value in entry.value) {
      if (value.trim().isNotEmpty) return value;
    }
    return null;
  }
  return null;
}

/// The CURRENT version for a write preflight or staleness check, resolved from
/// a response's headers.
///
/// `x-doc-current-version` wins because it is the only header that answers this
/// question directly under the publication gate; the ETag is consulted only
/// when that header is missing or unparseable, for the reasons in the library
/// comment above. Falling back on an unparseable header is safe in the same way
/// as falling back on an absent one: the worst case is that we adopt the
/// published version of a promoted public document, which is never *newer* than
/// current, so a preflight built on it fails closed with a 412 rather than
/// overwriting someone else's work.
int? resolveCurrentVersion(Headers headers) {
  return parseVersionTag(_header(headers, 'x-doc-current-version')) ??
      parseVersionTag(_header(headers, 'etag'));
}

/// The version those headers say is actually SERVED at that URL.
///
/// This is the ETag and nothing else — it is what the bytes in hand represent,
/// which is what a cache key or an `If-None-Match` revalidation must be built
/// from. For a promoted public document it is deliberately *behind*
/// [resolveCurrentVersion], and that gap is the publication gate, not a bug.
int? resolveServedVersion(Headers headers) {
  return parseVersionTag(_header(headers, 'etag'));
}

/// The canonical `If-Match` value for a write against those headers, or null
/// when no version could be resolved.
///
/// A write targets the document's head, so this is built from
/// [resolveCurrentVersion] rather than the served version. We emit the strong
/// form `v<n>` — the value we send is ours to normalise, and echoing back
/// whatever weakened, quoted shape the edge happened to hand us would make the
/// request depend on Cloudflare's compression decisions. A null result means
/// the caller must not send `If-Match` at all rather than send a fabricated
/// one.
String? ifMatchFor(Headers headers) {
  final version = resolveCurrentVersion(headers);
  return version == null ? null : 'v$version';
}

/// The publication gate as it applies to a metadata record.
///
/// The admin list and search still report `current_ver`, so a listing row on
/// its own no longer tells you what a visitor would see. These accessors apply
/// the 2.0.0 serving rule to the row so the UI can talk about the two versions
/// separately.
extension DocumentPublication on DocumentListing {
  bool get isPublic => visibility == 'public';

  /// The version this document serves on the HTML byte path, by the 2.0.0 rule.
  int? get servedVer =>
      (isPublic && publishedVer != null) ? publishedVer : currentVer;

  /// Whether there is newer work sitting behind the publication gate.
  ///
  /// This reports PROVEN divergence only. A null `publishedVer` means nothing
  /// was ever promoted, so the gate is open and the document already serves its
  /// head; a null `currentVer` means we have no head to compare against. In
  /// neither case do we know of any withheld work, and claiming otherwise would
  /// put an "unpublished changes" badge on documents that have none.
  bool get hasUnpublishedWork =>
      isPublic &&
      publishedVer != null &&
      currentVer != null &&
      publishedVer != currentVer;
}
