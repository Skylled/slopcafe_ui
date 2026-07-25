import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/document_cache.dart';
import '../core/format.dart';
import '../api/api.dart';
import '../core/links.dart';
import '../core/publication.dart';
import '../core/secure_storage.dart';
import '../l10n/l10n.dart';
import '../providers/document_provider.dart';
import '../providers/links_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sheets.dart';
import '../widgets/slug_repair_sheet.dart';
import '../widgets/toast.dart';
import 'document_list_screen.dart';

/// ReaderScreen — the Cortado "plate". A full-bleed pushed route built around a
/// single rendered WebView. The chrome is intentionally minimal — a compact
/// top bar, a one-line title, a thin meta row and tappable tags — so the
/// WebView (which scrolls internally) owns the majority of the screen. It
/// preserves the original offline cache + version-first conditional-GET
/// strategy and all operator actions (now consolidated into the more-sheet).
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.doc});

  final DocumentListing doc;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final WebViewController _webViewController;
  String? _baseUrl;
  bool _isLoadingBaseUrl = true;
  bool _isRevoking = false;
  bool _updatingProperties = false;

  /// 0 == latest; any other value is a pinned historical version.
  int _selectedVersion = 0;

  /// Armed around each programmatic `loadHtmlString(..., baseUrl: _baseUrl)`.
  /// On macOS, WKWebView reports that synthetic load to the navigation
  /// delegate as a request for the bare base URL — it must be allowed
  /// through, or the reader intercepts its *own* content load (the WebView
  /// stays blank and an "open in browser?" prompt appears). Real link taps
  /// never run with this flag set. iOS/Android never fire the delegate for
  /// loadHtmlString, so the flag simply stays armed until the next load there.
  bool _expectSyntheticBaseLoad = false;

  late DocumentListing _currentDoc;

  @override
  void initState() {
    super.initState();
    _currentDoc = widget.doc;
    _initBaseUrlAndWebview();
  }

  // ----------------------------------------------------------------
  // WebView + version-first offline cache (ported verbatim in logic)
  // ----------------------------------------------------------------

  Future<void> _initBaseUrlAndWebview() async {
    final storage = SecureStorageService.instance;
    final url = await storage.getBaseUrl();
    _baseUrl = url;

    if (url != null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.disabled)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (NavigationRequest request) {
              final reqUrl = request.url;
              if (reqUrl == 'about:blank' || reqUrl.startsWith('data:')) {
                return NavigationDecision.navigate;
              }
              // The synthetic base-URL navigation of our own loadHtmlString
              // (macOS WKWebView) — see [_expectSyntheticBaseLoad].
              if (_expectSyntheticBaseLoad && _isBareBaseUrl(reqUrl)) {
                _expectSyntheticBaseLoad = false;
                return NavigationDecision.navigate;
              }
              // In-page anchor (#fragment) → let the WebView scroll natively.
              if (_isSameDocumentFragment(reqUrl)) {
                return NavigationDecision.navigate;
              }
              _handleNavigation(reqUrl);
              return NavigationDecision.prevent;
            },
          ),
        );

      await _loadHtmlIntoWebview();
    }

    if (mounted) {
      setState(() {
        _isLoadingBaseUrl = false;
      });
    }

    // Silently reconcile metadata with the server after the first paint, so the
    // chrome (version, tags, title, …) isn't stale until the operator manually
    // refreshes. Deliberately runs *after* the reveal above so it never delays
    // the instant cached render; it touches only the chrome (never reloads the
    // body) and no-ops when nothing changed.
    if (url != null && mounted) {
      await _refreshMetadata();
    }
  }

  /// Re-render the document. [force] performs a *hard* refresh for the
  /// more-sheet Refresh action: it drops the
  /// `If-None-Match` conditional so the server can never answer a 304, asks any
  /// intermediary to revalidate, and always re-renders the freshly fetched
  /// bytes. Without it, the bandwidth-saving conditional-GET path can resolve a
  /// just-published version as "unchanged" and leave stale HTML on screen until
  /// the app is restarted.
  Future<void> _reloadWebview({bool force = false}) async {
    if (_baseUrl == null) return;
    await _loadHtmlIntoWebview(force: force);
  }

  Future<DocumentListing?> _resolveDocumentListing(
    String? publicId,
    String? slug,
  ) async {
    final docsList = ref.read(documentsListProvider).documents;
    if (publicId != null) {
      for (final d in docsList) {
        if (d.publicId == publicId) return d;
      }
    }
    if (slug != null) {
      for (final d in docsList) {
        if (d.slug == slug) return d;
      }
    }

    final dio = ref.read(dioProvider);

    // Try fetching by slug
    if (slug != null) {
      try {
        final response = await dio.get(
          '/admin/documents',
          queryParameters: {'slug': slug},
        );
        final docs = ListDocumentsResponse.fromJson(
          response.data as Map<String, dynamic>,
        ).documents;
        if (docs.isNotEmpty) {
          return docs.first;
        }
      } catch (e) {
        // Fallback
      }
    }

    // Try fetching by publicId
    if (publicId != null) {
      try {
        final response = await dio.get('/admin/documents/$publicId');
        if (response.statusCode == 200) {
          return DocumentListing.fromJson(
            response.data as Map<String, dynamic>,
          );
        }
      } catch (e) {
        // Fallback
      }

      // Placeholder fallback if not found or unauthorized. We know nothing
      // about this document's history, so `updatedAt` borrows the same
      // synthesised "now" as `createdAt` — a record we invented has never been
      // touched, and claiming any other timestamp would be a fabrication.
      final now = DateTime.now();
      return DocumentListing(
        publicId: publicId,
        createdAt: now,
        updatedAt: now,
        createdByKind: 'agent',
        tags: [],
        status: 'active',
        title: publicId,
        visibility: 'private',
      );
    }
    return null;
  }

  /// Whether [url] is exactly the configured base URL (modulo a trailing
  /// slash) — the URL WKWebView reports for our own
  /// `loadHtmlString(..., baseUrl:)` navigations on macOS.
  bool _isBareBaseUrl(String url) {
    final base = _baseUrl;
    if (base == null) return false;
    String norm(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;
    return norm(url) == norm(base);
  }

  /// Whether [url] is an in-page anchor jump within the loaded document, i.e.
  /// it differs from the base URL only by a `#fragment`. Those should scroll
  /// natively rather than route through external/document navigation.
  bool _isSameDocumentFragment(String url) {
    final reqUri = Uri.tryParse(url);
    if (reqUri == null || !reqUri.hasFragment || reqUri.fragment.isEmpty) {
      return false;
    }
    final baseUri = _baseUrl != null ? Uri.tryParse(_baseUrl!) : null;
    if (baseUri == null) return false;
    String norm(String p) => p.isEmpty ? '/' : p;
    return reqUri.scheme == baseUri.scheme &&
        reqUri.host == baseUri.host &&
        norm(reqUri.path) == norm(baseUri.path);
  }

  Future<void> _handleNavigation(String url) async {
    final reqUri = Uri.tryParse(url);
    if (reqUri == null) {
      await _openExternalBrowser(url);
      return;
    }

    final baseUrlStr = _baseUrl;
    Uri? baseUri;
    if (baseUrlStr != null) {
      baseUri = Uri.tryParse(baseUrlStr);
    }

    final bool isHostMatch =
        baseUri != null &&
        reqUri.host.isNotEmpty &&
        reqUri.host.toLowerCase() == baseUri.host.toLowerCase();

    if (isHostMatch) {
      final pathSegments = reqUri.pathSegments;
      String? publicId;
      String? slug;

      if (pathSegments.length >= 2) {
        if (pathSegments[0] == 'd') {
          publicId = pathSegments[1];
        } else if (pathSegments[0] == 's') {
          slug = pathSegments[1];
        }
      }

      if (publicId != null || slug != null) {
        final doc = await _resolveDocumentListing(publicId, slug);
        if (doc != null && mounted) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
          return;
        }
      }
    }

    // External link flow: show confirmation sheet
    if (!mounted) return;
    final l10n = context.l10n;
    final proceed = await showConfirmSheet(
      context,
      title: l10n.openInBrowserDialogTitle,
      cta: l10n.proceed,
      danger: false,
      body: Text(l10n.openInBrowserDialogBody(url)),
    );

    if (proceed == true) {
      await _openExternalBrowser(url);
    }
  }

  /// Silently reconcile this document's metadata (version, title, tags, size,
  /// visibility) with the server via the documents provider. No spinner and no
  /// WebView reload — only the chrome updates, and only when something actually
  /// changed: [DocumentsListNotifier.refreshDocument] no-ops on an unchanged
  /// record, and the [setState] here is skipped when the listing is value-equal
  /// to what's already on screen, so a refresh with no new version is a true
  /// no-op. Best-effort: offline/transient failures are swallowed so the reader
  /// keeps showing the listing it already has.
  ///
  /// Runs on open (so the chrome isn't stale until a manual refresh) and ahead
  /// of the body fetch on a forced refresh. (Previously the version was reverse-
  /// engineered from the /raw ETag — which carries the representation format,
  /// not the document version — and written only to local widget state, so
  /// every refresh mislabeled the document "v1" and the change was lost on
  /// reopen.)
  Future<void> _refreshMetadata() async {
    try {
      final fresh = await ref
          .read(documentsListProvider.notifier)
          .refreshDocument(_currentDoc.publicId);
      if (!mounted || fresh == _currentDoc) return;
      setState(() => _currentDoc = fresh);
    } catch (_) {
      // Best-effort: keep the current listing on offline/transient errors.
    }
  }

  /// Adopt the document's CURRENT version from a byte-path response, so the
  /// chrome can tell the operator that what they are reading is behind the
  /// head.
  ///
  /// The listing alone can no longer answer "is there newer work?": it is
  /// fetched once and the head moves whenever an agent writes. The `/raw`
  /// response answers it on every load — `x-doc-current-version` rides 200s and
  /// 304s alike — so the reader learns about a write it never asked about.
  ///
  /// Only a version AHEAD of what we hold is adopted. Versions only ever count
  /// upwards (a restore appends a new head; a promote moves no version at all),
  /// so a lower number is never news about the document — it is
  /// [resolveCurrentVersion] falling back to the ETag because the header was
  /// absent, which on a promoted public document yields the published version.
  /// Writing that back would erase the very divergence this is here to report.
  void _adoptCurrentVersion(Headers headers) {
    final current = resolveCurrentVersion(headers);
    if (current == null) return;
    final known = _currentDoc.currentVer;
    if (known != null && current <= known) return;
    if (!mounted) return;
    setState(() => _currentDoc = _currentDoc.copyWith(currentVer: current));
  }

  Future<void> _loadHtmlIntoWebview({bool force = false}) async {
    if (_baseUrl == null) return;
    final l10n = context.l10n;

    final String publicId = _currentDoc.publicId;

    // A forced refresh (the more-sheet Refresh) reconciles the
    // canonical metadata record *first*, so the version, title, tags, size and
    // visibility shown in the chrome update too — not just the HTML body — and
    // the body below loads against the freshly resolved version.
    if (force) {
      await _refreshMetadata();
      if (!mounted) return;
    }

    // Which version's body to render and cache under. 0 == latest, i.e.
    // whatever `/d/:id/raw` serves; any other value is a pinned historical
    // version, which names itself in the URL.
    //
    // For the latest view that is the SERVED version, not `currentVer`: under
    // the 2.0.0 publication gate a public document with a promoted
    // `published_ver` serves those older bytes to everyone, this operator
    // included. Expecting `currentVer` here would file the published bytes
    // under the current version number, and every surface reading that cache —
    // the chip, the offline render, the next conditional GET — would then
    // mislabel them.
    final int versionToLoad = _selectedVersion == 0
        ? (_currentDoc.servedVer ?? 1)
        : _selectedVersion;

    // Locate a cached body to paint instantly (offline resilience). For a
    // pinned historical view only the exact version qualifies; for the latest
    // view we accept a cached body at or behind the served version, but never
    // one AHEAD of it.
    //
    // That cut-off is the publication gate applied to the cache. Pinning to the
    // unpublished head — which the served-version banner's CTA exists to do —
    // caches those bytes and evicts every other body for the document, so the
    // only body on disk is one no reader can get. Painting it here would put
    // unpublished bytes under a chip that says "Live v4" and a banner that says
    // the operator is reading what everyone else is served, and offline (or on a
    // failed request, where the catch below deliberately leaves the cached body
    // up) that is where it would stay. A body at or behind the served version is
    // ordinary staleness — it was really served once, and the fresh response
    // replaces it — so it still paints. When we have no served version to
    // compare against, we cannot call the cache ahead and it paints as before.
    int? cachedVersion;
    if (_selectedVersion == 0) {
      final cached = await DocumentCacheManager.getCachedVersion(publicId);
      final servedVer = _currentDoc.servedVer;
      cachedVersion = (cached != null && servedVer != null && cached > servedVer)
          ? null
          : cached;
    } else if (await DocumentCacheManager.isCached(
      publicId,
      _selectedVersion,
    )) {
      cachedVersion = _selectedVersion;
    }

    final cachedHtml = cachedVersion != null
        ? await DocumentCacheManager.getCachedHtml(publicId, cachedVersion)
        : null;

    // On a forced refresh the current document is already on screen, so skip
    // the instant cached re-render — it would only flicker and reset the scroll
    // position before the fresh bytes arrive.
    if (!force && cachedHtml != null) {
      final securedHtml = _injectCspMeta(cachedHtml);
      _expectSyntheticBaseLoad = true;
      await _webViewController.loadHtmlString(securedHtml, baseUrl: _baseUrl);
    }

    // Fetch fresh version from server in background/foreground
    try {
      final dio = ref.read(dioProvider);
      final String path = _selectedVersion == 0
          ? '/d/$publicId/raw'
          : '/d/$publicId/v/$versionToLoad/raw';

      final response = await dio.get(
        path,
        options: Options(
          headers: {
            // A hard refresh sends no validator (forcing a 200 body) and asks
            // intermediaries to revalidate; otherwise we send the cached
            // version's ETag so an unchanged document comes back as a cheap 304.
            if (!force && cachedVersion != null)
              'If-None-Match': '"v$cachedVersion"',
            if (force) 'Cache-Control': 'no-cache',
          },
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );

      // Both branches below carry `x-doc-current-version`, so the document's
      // head is reconciled either way — a 304 is the likeliest answer we get on
      // a gated document (the published bytes it serves rarely change), and it
      // is precisely then that the head has moved on without us.
      _adoptCurrentVersion(response.headers);

      if (response.statusCode == 304) {
        // Cache is valid and matches the server version!
        // No need to update the cache or reload the WebView since we already
        // loaded cachedHtml.
        return;
      }

      // 200 OK: render fresh HTML and update the body cache.
      final freshHtml = response.data as String;

      // The ETag names the version the server just handed us, so it outranks
      // anything the metadata record predicted — it is the server describing
      // the exact bytes in hand rather than us inferring them from a listing
      // that may have been fetched before the last promote. The predicted
      // [versionToLoad] stays as the fallback for a stripped or malformed
      // header. The pinned historical view is exempt: its URL already names the
      // version, and taking the label from a header there could file the bytes
      // under a key the cache lookup would never ask for again.
      final int versionToCache = _selectedVersion == 0
          ? (resolveServedVersion(response.headers) ?? versionToLoad)
          : versionToLoad;

      // Idempotent body update: when the freshly fetched bytes are identical to
      // what's already cached (and on screen), don't rewrite the cache or reload
      // the WebView — even on a forced refresh. The chrome was already
      // reconciled via _refreshMetadata, so a document with no new version is a
      // true no-op: no disk churn, no flicker, no scroll reset.
      if (cachedHtml != null && freshHtml == cachedHtml) {
        return;
      }

      // Cache the body under the authoritative version. saveCachedHtml evicts
      // any other cached version of this document first, so a stale label
      // self-heals here.
      await DocumentCacheManager.saveCachedHtml(
        publicId,
        versionToCache,
        freshHtml,
      );

      // Render fresh HTML (now from the network, not the cache)
      final securedHtml = _injectCspMeta(freshHtml);
      _expectSyntheticBaseLoad = true;
      await _webViewController.loadHtmlString(securedHtml, baseUrl: _baseUrl);
    } on DioException catch (dioErr) {
      final statusCode = dioErr.response?.statusCode;
      if (statusCode == 404 || statusCode == 410) {
        // Document has been revoked or deleted. Clean up cache!
        await DocumentCacheManager.deleteCachedDoc(publicId);

        final errorTitle = statusCode == 410
            ? l10n.documentRevokedTitle
            : l10n.documentNotFound;
        final errorMsg = statusCode == 410
            ? l10n.documentRevokedHtmlBody
            : l10n.documentNotFoundHtmlBody;

        final errorHtml = _buildErrorHtml(errorTitle, errorMsg);
        await _webViewController.loadHtmlString(errorHtml);
      } else {
        // Network/connection/server error
        if (cachedHtml == null) {
          final errorHtml = _buildErrorHtml(
            l10n.offlineConnectionError,
            l10n.couldNotRetrieve,
          );
          await _webViewController.loadHtmlString(errorHtml);
        }
      }
    } catch (e) {
      if (cachedHtml == null) {
        final errorHtml = _buildErrorHtml(
          l10n.errorTitle,
          ApiError.describe(e),
        );
        await _webViewController.loadHtmlString(errorHtml);
      }
    }
  }

  String _injectCspMeta(String html) {
    const csp =
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline' data:; font-src data:; base-uri 'none'; form-action 'none'\">";
    if (html.contains('<head>')) {
      return html.replaceFirst('<head>', '<head>\n$csp');
    } else {
      return '$csp\n$html';
    }
  }

  String _buildErrorHtml(String title, String message) {
    final c = context.colors;
    String hex(Color col) =>
        '#${(col.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return '''
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body {
            font-family: Georgia, 'Times New Roman', serif;
            padding: 48px 20px;
            margin: 0;
            color: ${hex(c.textDim)};
            background-color: ${hex(c.bg)};
            text-align: center;
          }
          .container {
            max-width: 420px;
            margin: 0 auto;
            background: ${hex(c.surface)};
            border: 1px solid ${hex(c.line)};
            border-radius: 16px;
            padding: 26px;
          }
          h1 {
            font-size: 22px;
            font-weight: 400;
            color: ${hex(c.red)};
            margin: 0 0 12px;
          }
          p {
            font-family: -apple-system, system-ui, sans-serif;
            font-size: 14px;
            line-height: 1.5;
            margin: 0;
          }
        </style>
      </head>
      <body>
        <div class="container">
          <h1>$title</h1>
          <p>$message</p>
        </div>
      </body>
      </html>
    ''';
  }

  // ----------------------------------------------------------------
  // Clipboard / browser helpers (ported)
  // ----------------------------------------------------------------

  Future<void> _copyToClipboard(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showToast(context, message);
  }

  Future<void> _openExternalBrowser(String url) async {
    final l10n = context.l10n;
    try {
      final uri = Uri.tryParse(url);
      if (uri != null && (Platform.isAndroid || Platform.isIOS)) {
        if (await canLaunchUrl(uri)) {
          if (!mounted) return;
          showToast(context, l10n.openingInBrowser);
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return;
        }
      }

      if (Platform.isMacOS) {
        await Process.run('open', [url]);
        if (!mounted) return;
        showToast(context, l10n.openingInBrowser);
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        showToast(context, l10n.urlCopiedPaste);
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      showToast(context, l10n.couldNotLaunchBrowser, danger: true);
    }
  }

  // ----------------------------------------------------------------
  // Operator actions (ported, restyled to Cortado sheets)
  // ----------------------------------------------------------------

  Future<void> _revokeDocument() async {
    if (_baseUrl == null) return;
    final l10n = context.l10n;
    setState(() => _isRevoking = true);

    final dio = ref.read(dioProvider);
    try {
      final response = await dio.delete('/d/${_currentDoc.publicId}');
      final revoke = RevokeResponse.fromJson(
        response.data as Map<String, dynamic>,
      );

      final now = DateTime.now();
      ref
          .read(documentsListProvider.notifier)
          .revokeDocumentLocally(_currentDoc.publicId, now);

      final revokedTitle = _currentDoc.title ?? l10n.untitledPlain;

      setState(() {
        // The backend clears ver/size/slug on revoke; mirror that locally.
        _currentDoc = _currentDoc.copyWith(
          currentSize: null,
          currentVer: null,
          slug: null,
          revokedAt: now,
        );
        _isRevoking = false;
      });

      if (!mounted) return;
      showToast(
        context,
        l10n.documentRevokedToast(revokedTitle, revoke.r2ObjectsPurged),
        danger: true,
      );

      // Pop back indicating a successful revocation to refresh parent screen.
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isRevoking = false);
      if (!mounted) return;
      showToast(
        context,
        l10n.revocationFailed(ApiError.describe(e)),
        danger: true,
      );
    }
  }

  Future<void> _confirmRevoke() async {
    final c = context.colors;
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      context,
      title: l10n.revokeDocumentTitle,
      confirmWord: l10n.revokeConfirmWord,
      cta: l10n.revokePermanently,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.revokePermanentWarning,
            style: AppText.body.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: c.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(l10n.revokeDocumentBodyLong),
        ],
      ),
    );
    if (confirmed) {
      await _revokeDocument();
    }
  }

  Future<void> _toggleVisibility() async {
    final l10n = context.l10n;
    final nextVisibility = _currentDoc.visibility == 'public'
        ? 'private'
        : 'public';
    setState(() => _updatingProperties = true);

    try {
      final updated = await ref
          .read(documentsListProvider.notifier)
          .updateVisibility(_currentDoc.publicId, nextVisibility);

      setState(() {
        _currentDoc = updated;
        _updatingProperties = false;
      });

      await _reloadWebview();

      if (!mounted) return;
      showToast(context, l10n.nowVisibility(nextVisibility.toUpperCase()));
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(
        context,
        l10n.failedUpdateVisibility(ApiError.describe(e)),
        danger: true,
      );
    }
  }

  Future<void> _confirmToggleVisibility() async {
    final l10n = context.l10n;
    final makingPublic = _currentDoc.visibility != 'public';
    final confirmed = await showConfirmSheet(
      context,
      title: makingPublic ? l10n.makePublic : l10n.makePrivate,
      cta: makingPublic ? l10n.makePublic : l10n.makePrivate,
      danger: false,
      body: Text(
        makingPublic ? l10n.makePublicBody : l10n.makePrivateBodyReader,
      ),
    );
    if (confirmed) {
      await _toggleVisibility();
    }
  }

  /// Toggle lifecycle status — the Reader twin of the Operate sheet's flow.
  /// Deprecating routes through the deprecate sheet (optional superseded_by
  /// target); re-activating is a plain confirm (the backend clears the
  /// pointer on 'active').
  Future<void> _toggleStatus() async {
    final l10n = context.l10n;
    final deprecating = _currentDoc.status != 'deprecated';
    String? supersededBy;
    if (deprecating) {
      final target = await showDeprecateSheet(
        context,
        initialTarget: _currentDoc.supersededBy,
      );
      if (target == null) return;
      supersededBy = target.isEmpty ? null : target;
    } else {
      final confirmed = await showConfirmSheet(
        context,
        title: l10n.markActive,
        body: Text(l10n.markActiveBody),
        cta: l10n.markActive,
        danger: false,
      );
      if (!confirmed) return;
    }

    setState(() => _updatingProperties = true);
    try {
      final next = deprecating ? 'deprecated' : 'active';
      final updated = await ref
          .read(documentsListProvider.notifier)
          .updateStatus(_currentDoc.publicId, next, supersededBy: supersededBy);

      setState(() {
        _currentDoc = updated;
        _updatingProperties = false;
      });

      if (!mounted) return;
      showToast(context, l10n.statusSet(next.toUpperCase()));
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(
        context,
        l10n.failedUpdateStatus(ApiError.describe(e)),
        danger: true,
      );
    }
  }

  Future<void> _editSlugAndTags() async {
    final l10n = context.l10n;
    final slugController = TextEditingController(text: _currentDoc.slug ?? '');
    final tagsController = TextEditingController(
      text: _currentDoc.tags.join(', '),
    );

    final saved = await showAppSheet<bool>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        InputDecoration deco(String hint) => InputDecoration(
          hintText: hint,
          isDense: true,
          filled: true,
          fillColor: c.surface2,
          hintStyle: AppText.body.copyWith(color: c.textFaint),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: c.lineSoft),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: c.lineSoft),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
            borderSide: BorderSide(color: c.clay),
          ),
        );

        return AppSheet(
          title: l10n.editSlugTags,
          subtitle: l10n.documentProperties,
          icon: Icons.sell_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.slugLabel,
                style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: slugController,
                style: AppText.mono.copyWith(fontSize: 14, color: c.text),
                decoration: deco(l10n.slugHint),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.honey.withValues(alpha: 0.12),
                  border: Border.all(color: c.honey.withValues(alpha: 0.30)),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Text(
                  l10n.slugRetiredNote,
                  style: AppText.small.copyWith(color: c.honeyD),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.tagsLabel,
                style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: tagsController,
                style: AppText.body.copyWith(color: c.text),
                decoration: deco(l10n.tagsHintReader),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.separateTagsWithCommas,
                style: AppText.small.copyWith(color: c.textFaint),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      l10n.cancel,
                      variant: AppBtnVariant.outline,
                      expand: true,
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      l10n.save,
                      variant: AppBtnVariant.primary,
                      icon: Icons.check,
                      expand: true,
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    final newSlug = slugController.text.trim();
    final newTags = tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    slugController.dispose();
    tagsController.dispose();

    if (saved != true) return;

    final slugChanged = newSlug != (_currentDoc.slug ?? '');
    final tagsChanged = !_listEquals(newTags, _currentDoc.tags);
    if (!slugChanged && !tagsChanged) return;

    setState(() => _updatingProperties = true);
    try {
      DocumentListing updated = _currentDoc;
      if (slugChanged) {
        updated = await ref
            .read(documentsListProvider.notifier)
            .updateSlug(_currentDoc.publicId, newSlug);
      }
      if (tagsChanged) {
        updated = await ref
            .read(documentsListProvider.notifier)
            .updateTags(_currentDoc.publicId, newTags);
      }

      setState(() {
        _currentDoc = updated;
        _updatingProperties = false;
      });

      if (slugChanged) await _reloadWebview();

      if (!mounted) return;
      showToast(context, l10n.documentPropertiesUpdated);
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(context, l10n.failedUpdate(ApiError.describe(e)), danger: true);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Restore is restore-as-new: the backend re-writes the chosen version's
  /// retained source as a brand-new head, so [RestoreResponse.version] is a
  /// number that did not exist before the call — never [version] itself.
  ///
  /// It moves `current_ver` and deliberately leaves `published_ver` where it
  /// was, so on a gated public document the restored head is *not* what readers
  /// get. Resetting to the latest view is still right (it is the honest one),
  /// and the served-version banner is what now explains the gap.
  Future<void> _restoreVersion(int version) async {
    final l10n = context.l10n;
    setState(() => _updatingProperties = true);
    try {
      final restored = await ref
          .read(documentsListProvider.notifier)
          .restoreVersion(_currentDoc.publicId, version);

      setState(() {
        _selectedVersion = 0; // reset to latest
        _currentDoc = _currentDoc.copyWith(currentVer: restored.version);
        _updatingProperties = false;
      });

      await _reloadWebview();

      if (!mounted) return;
      showToast(context, l10n.restoredVersion(version, restored.version));
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(
        context,
        l10n.restoreFailed(ApiError.describe(e)),
        danger: true,
      );
    }
  }

  Future<void> _confirmRestore(int version) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      context,
      title: l10n.restoreVersionTitle(version),
      cta: l10n.restoreVersionTitle(version),
      danger: false,
      body: Text(l10n.restoreVersionBody(version)),
    );
    if (confirmed) {
      await _restoreVersion(version);
    }
  }

  /// Move the publication pointer to [version] — the operator-only act that
  /// decides which bytes `/d/:id/raw` and `/s/:slug` hand to everyone.
  ///
  /// The response is canonical for `published_ver`, so it is folded onto
  /// `_currentDoc` — the listing this screen is already showing, which is the
  /// only copy guaranteed to exist for a document opened from Search or from an
  /// in-WebView link. The version chip and the served-version banner both derive
  /// from it and have to re-evaluate the moment the pointer moves. The body is
  /// re-fetched only when the served version actually changed — promoting on a
  /// private document stages the choice without changing a single served byte,
  /// and a pinned historical view is reading a URL the pointer does not affect.
  Future<void> _publishVersion(int version) async {
    final l10n = context.l10n;
    final servedBefore = _currentDoc.servedVer;
    setState(() => _updatingProperties = true);
    try {
      final promoted = await ref
          .read(documentsListProvider.notifier)
          .promoteVersion(_currentDoc.publicId, version);

      if (!mounted) return;
      final updated = _currentDoc.copyWith(publishedVer: promoted.publishedVer);
      setState(() {
        _currentDoc = updated;
        _updatingProperties = false;
      });

      // Report what the backend actually pointed at rather than what we asked
      // for.
      showToast(context, l10n.publishedToast(promoted.publishedVer));

      if (_selectedVersion == 0 && updated.servedVer != servedBefore) {
        await _reloadWebview(force: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _updatingProperties = false);
      // A promote can only fail on a version the server no longer has, so name
      // that case rather than blaming the network for it.
      final failed = ApiError.fromException(e).code == ErrorCode.versionNotFound
          ? l10n.versionNotFoundToast
          : l10n.publishFailedToast;
      showToast(context, failed, danger: true);
    }
  }

  Future<void> _confirmPublish(int version) async {
    final l10n = context.l10n;
    final confirmed = await showConfirmSheet(
      context,
      title: l10n.publishVersionTitle(version),
      cta: l10n.publishAction,
      danger: false,
      body: Text(l10n.publishVersionBody(version)),
    );
    if (confirmed) {
      await _publishVersion(version);
    }
  }

  // ----------------------------------------------------------------
  // Sheets
  // ----------------------------------------------------------------

  /// Version history, read live from `GET /admin/documents/:id/versions`.
  ///
  /// The list is fetched per open and never cached: a promote or a restore
  /// invalidates it the instant it happens, and the two things the rows assert
  /// — which version is CURRENT and which one is LIVE — are independent under
  /// the publication gate, so a stale list would misstate what readers are
  /// actually being served. The future is started here, outside the builder, so
  /// a sheet rebuild (keyboard, rotation) doesn't re-issue the request.
  void _openVersionSheet() {
    final l10n = context.l10n;
    final history = ref
        .read(documentsListProvider.notifier)
        .fetchVersions(_currentDoc.publicId);

    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return AppSheet(
          title: l10n.versionHistory,
          subtitle: l10n.onTheMenu,
          icon: Icons.layers_outlined,
          child: FutureBuilder<ListVersionsResponse>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: CircularProgressIndicator(color: c.clay),
                  ),
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return Row(
                  children: [
                    Icon(Icons.cloud_off, size: 17, color: c.red),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        l10n.versionHistoryLoadFailed,
                        style: AppText.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.red,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return _buildVersionList(sheetContext, data);
            },
          ),
        );
      },
    );
  }

  /// The body of the version sheet once the history has landed.
  ///
  /// The served version is recomputed from the fetched history rather than read
  /// off `_currentDoc`, because the history is the fresher of the two: it names
  /// the head and the published row as of this request. Visibility is the one
  /// term it cannot supply — the serving rule only consults `published_ver` for
  /// a public document — so that still comes from the listing.
  Widget _buildVersionList(
    BuildContext sheetContext,
    ListVersionsResponse history,
  ) {
    final l10n = sheetContext.l10n;

    int? publishedNo;
    for (final entry in history.versions) {
      if (entry.isPublished) {
        publishedNo = entry.versionNo;
        break;
      }
    }
    final int servedNo = (_currentDoc.isPublic && publishedNo != null)
        ? publishedNo
        : history.currentVer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_selectedVersion != 0)
          _SheetNote(
            icon: Icons.history,
            text: l10n.viewingHistoricalShort(_selectedVersion),
          ),
        if (_currentDoc.isPublic && publishedNo == null)
          _SheetNote(icon: Icons.public_off, text: l10n.nothingPublishedYet),
        for (final entry in history.versions)
          _VersionRow(
            entry: entry,
            // A row is "selected" when the reader is showing its bytes: the
            // latest view is showing whichever version the byte path serves,
            // which on a gated document is not the head.
            isSelected:
                (_selectedVersion == 0 && entry.versionNo == servedNo) ||
                _selectedVersion == entry.versionNo,
            onTap: () {
              Navigator.of(sheetContext).pop();
              setState(() {
                // Only the served version can be reached through the latest
                // view; anything else has to be pinned to `/d/:id/v/:n/raw`,
                // including the head of a document whose newer work is still
                // behind the publication gate.
                _selectedVersion = entry.versionNo == servedNo
                    ? 0
                    : entry.versionNo;
              });
              _reloadWebview();
            },
            onPublish: entry.isPublished || _updatingProperties
                ? null
                : () {
                    Navigator.of(sheetContext).pop();
                    _confirmPublish(entry.versionNo);
                  },
            // Restore rewrites a version's retained source as a new head, so it
            // is meaningless on the head itself and impossible without that
            // source — a pre-retention version can only be read, never revived.
            // The row still shows the disabled control in the latter case and
            // says why; silently omitting it would read as an app bug.
            showRestore: !entry.isCurrent,
            onRestore: entry.sourcePresent && !_updatingProperties
                ? () {
                    Navigator.of(sheetContext).pop();
                    _confirmRestore(entry.versionNo);
                  }
                : null,
          ),
      ],
    );
  }

  /// The document's link-graph neighborhood, read live from
  /// `GET /d/:id/links`.
  ///
  /// Fetched per open and never cached, for the same reason the version sheet
  /// is: `backlinks` describes *other* documents' current versions and
  /// `outbound` resolves its targets at read time, so any write anywhere in the
  /// corpus can change this answer. The future is started outside the builder
  /// so a sheet rebuild doesn't re-issue the request.
  void _openLinksSheet() {
    final l10n = context.l10n;
    final graph = ref
        .read(linkGraphServiceProvider)
        .fetchLinks(_currentDoc.publicId);

    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        return AppSheet(
          title: l10n.linksAction,
          subtitle: l10n.linksSubtitle,
          icon: Icons.account_tree_outlined,
          child: FutureBuilder<DocumentLinksResponse>(
            future: graph,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Center(
                    child: CircularProgressIndicator(color: c.clay),
                  ),
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return Row(
                  children: [
                    Icon(Icons.cloud_off, size: 17, color: c.red),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        l10n.linksLoadFailed,
                        style: AppText.small.copyWith(
                          fontWeight: FontWeight.w600,
                          color: c.red,
                        ),
                      ),
                    ),
                  ],
                );
              }
              return _buildLinkGraph(sheetContext, data);
            },
          ),
        );
      },
    );
  }

  /// The body of the links sheet once the neighborhood has landed.
  Widget _buildLinkGraph(BuildContext sheetContext, DocumentLinksResponse graph) {
    final c = sheetContext.colors;
    final l10n = sheetContext.l10n;
    final broken = graph.brokenCount;

    if (graph.hasNoGraph) {
      return _SheetNote(icon: Icons.link_off, text: l10n.linksNoGraph);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (broken > 0)
          _SheetNote(
            icon: Icons.report_problem_outlined,
            text: l10n.linksBrokenNote(broken),
          ),
        _LinkSectionLabel(l10n.linksBacklinksHeading),
        if (graph.backlinks.isEmpty)
          _LinkEmptyLine(l10n.linksNoBacklinks)
        else
          // Backlinks arrive as full listing rows, so the Reader opens straight
          // onto them — no resolution hop, unlike an outbound link, which
          // carries only the raw name its author typed.
          for (final doc in graph.backlinks)
            _BacklinkRow(
              doc: doc,
              onTap: () {
                Navigator.of(sheetContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)),
                );
              },
            ),
        const SizedBox(height: 18),
        _LinkSectionLabel(l10n.linksOutboundHeading),
        if (graph.outbound.isEmpty)
          _LinkEmptyLine(l10n.linksNoOutbound)
        else
          for (final link in graph.outbound)
            _OutboundLinkRow(
              link: link,
              onTap: link.canOpen
                  ? () {
                      Navigator.of(sheetContext).pop();
                      _openLinkTarget(link.targetPublicId!);
                    }
                  : null,
              onRepair: link.canRepairSlug
                  ? () {
                      Navigator.of(sheetContext).pop();
                      showSlugRepairSheet(context, initialSlug: link.value);
                    }
                  : null,
            ),
        const SizedBox(height: 14),
        Text(
          l10n.linksGraphCaveat,
          style: AppText.small.copyWith(color: c.textFaint, height: 1.4),
        ),
      ],
    );
  }

  /// Opens the document an outbound link resolves to.
  ///
  /// The graph hands back a `target_public_id` rather than a listing, so this
  /// takes the same resolution path an in-WebView link tap does — which also
  /// means a private or unlisted target still opens, rather than dead-ending.
  Future<void> _openLinkTarget(String publicId) async {
    final doc = await _resolveDocumentListing(publicId, null);
    if (doc == null || !mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  void _openMoreSheet() {
    final isPublic = _currentDoc.visibility == 'public';
    final l10n = context.l10n;
    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final canEdit = !_currentDoc.isRevoked && !_updatingProperties;
        return AppSheet(
          title: _currentDoc.title ?? l10n.untitledPlain,
          subtitle: l10n.operatorActions,
          child: Column(
            children: [
              SheetActionRow(
                icon: Icons.refresh,
                label: l10n.refresh,
                onTap: (!_currentDoc.isRevoked && _baseUrl != null)
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _reloadWebview(force: true);
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.link,
                label: l10n.copyLink,
                onTap: (_baseUrl != null && !_currentDoc.isRevoked)
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _copyToClipboard(
                          '$_baseUrl/d/${_currentDoc.publicId}',
                          l10n.linkCopied,
                        );
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.account_tree_outlined,
                label: l10n.linksAction,
                // Revoke deletes the document's link rows and `/links` answers
                // 404 for a revoked id, so there is no neighborhood left to
                // show — offering the row there would only produce an error.
                onTap: !_currentDoc.isRevoked
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _openLinksSheet();
                      }
                    : null,
              ),
              SheetActionRow(
                icon: isPublic ? Icons.lock_outline : Icons.public,
                label: isPublic ? l10n.makePrivate : l10n.makePublic,
                onTap: canEdit
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _confirmToggleVisibility();
                      }
                    : null,
              ),
              SheetActionRow(
                icon: _currentDoc.status == 'deprecated'
                    ? Icons.task_alt
                    : Icons.history_toggle_off,
                label: _currentDoc.status == 'deprecated'
                    ? l10n.markActive
                    : l10n.markDeprecated,
                onTap: canEdit
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _toggleStatus();
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.sell_outlined,
                label: l10n.editSlugTags,
                onTap: canEdit
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _editSlugAndTags();
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.tag,
                label: l10n.copySlugUrl,
                onTap: (_baseUrl != null && _currentDoc.slug != null)
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _copyToClipboard(
                          '$_baseUrl/s/${_currentDoc.slug}',
                          l10n.slugUrlCopied,
                        );
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.open_in_new,
                label: l10n.openInBrowser,
                onTap: _baseUrl != null
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _openExternalBrowser(
                          '$_baseUrl/d/${_currentDoc.publicId}',
                        );
                      }
                    : null,
              ),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: c.lineSoft,
              ),
              SheetActionRow(
                icon: Icons.delete_outline,
                label: l10n.revokeDocumentTitle,
                danger: true,
                onTap: (!_currentDoc.isRevoked && !_isRevoking)
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _confirmRevoke();
                      }
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    if (_isLoadingBaseUrl) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Center(child: CircularProgressIndicator(color: c.clay)),
      );
    }

    if (_baseUrl == null) {
      return Scaffold(
        backgroundColor: c.bg,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    context.l10n.noBaseUrlConfigured,
                    textAlign: TextAlign.center,
                    style: AppText.body.copyWith(color: c.textDim),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                left: 14,
                child: _BackPill(onTap: () => Navigator.of(context).pop()),
              ),
            ],
          ),
        ),
      );
    }

    final isRevoked = _currentDoc.isRevoked;
    final ver = _currentDoc.currentVer;
    final topPad = MediaQuery.paddingOf(context).top;

    // What the WebView is actually showing on the latest view. On a gated
    // public document those are the published bytes, not the head, so the chip
    // has to name the served version — labelling the screen "v7" while the
    // reader is looking at v5 is the exact lie 2.0.0 makes possible.
    final servedVer = _currentDoc.servedVer;
    final showingServed =
        _selectedVersion == 0 &&
        _currentDoc.hasUnpublishedWork &&
        servedVer != null;

    // On wide layouts the document surface centers into a readable column
    // ([AppLayout.readerMax]); on phones the gutters collapse to the original
    // insets (0 for the WebView card, which owns the screen edge-to-edge).
    final Widget body = LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final barGutter = AppLayout.gutterFor(
          w,
          max: AppLayout.readerMax,
          min: 14,
        );
        final headerGutter = AppLayout.gutterFor(
          w,
          max: AppLayout.readerMax,
          min: 18,
        );
        final bodyGutter = AppLayout.gutterFor(
          w,
          max: AppLayout.readerMax,
          min: 0,
        );
        return Column(
          children: [
            // ---- Compact top bar: back · version · more ----
            Padding(
              padding: EdgeInsets.fromLTRB(
                barGutter,
                topPad + 10,
                barGutter,
                0,
              ),
              child: Row(
                children: [
                  _BackPill(onTap: () => Navigator.of(context).pop()),
                  const Spacer(),
                  if (ver != null && !isRevoked) ...[
                    _VersionChip(
                      version: showingServed ? servedVer : ver,
                      live: showingServed,
                      onTap: _openVersionSheet,
                    ),
                    const SizedBox(width: 8),
                  ],
                  _CircleIconButton(
                    icon: Icons.more_horiz,
                    onTap: _openMoreSheet,
                  ),
                ],
              ),
            ),

            // ---- Minimal document header: title · meta · tags ----
            Padding(
              padding: EdgeInsets.fromLTRB(headerGutter, 14, headerGutter, 12),
              child: _buildHeader(c, isRevoked),
            ),

            // ---- WebView (or revoked state) owns the rest of the screen ----
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: bodyGutter),
                child: _buildReaderBody(),
              ),
            ),
          ],
        );
      },
    );

    return Scaffold(backgroundColor: c.bg, body: body);
  }

  Widget _buildHeader(AppColors c, bool isRevoked) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _currentDoc.title ?? l10n.untitled,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.titleSerif.copyWith(
            fontSize: 22,
            color: isRevoked ? c.textFaint : c.text,
            decoration: isRevoked ? TextDecoration.lineThrough : null,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (isRevoked)
              Pill(
                l10n.revokedUpper,
                tone: PillTone.red,
                icon: Icons.block,
                small: true,
              )
            else ...[
              VisBadge(_currentDoc.visibility),
              if (_currentDoc.status == 'deprecated') ...[
                const SizedBox(width: 6),
                const DeprecatedBadge(),
              ],
            ],
            const MetaDot(),
            Flexible(
              child: Text(
                _currentDoc.createdByName ?? l10n.deletedAgent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.small.copyWith(
                  color: c.textDim,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const MetaDot(),
            Text(
              fmtDate(_currentDoc.createdAt),
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
        ),
        if (_currentDoc.tags.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(
            height: 26,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: _currentDoc.tags.length,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, i) {
                final tag = _currentDoc.tags[i];
                return TagChip(
                  tag,
                  small: true,
                  onTap: () => DocumentListScreen.openForTag(context, tag),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildReaderBody() {
    if (_currentDoc.isRevoked) {
      return SingleChildScrollView(child: _buildRevokedState());
    }
    return Column(
      children: [
        if (_currentDoc.status == 'deprecated') _buildDeprecatedBanner(),
        if (_selectedVersion != 0) _buildHistoricalBanner(),
        if (_selectedVersion == 0 && _currentDoc.hasUnpublishedWork)
          _buildServedBanner(),
        Expanded(child: _buildReadView()),
      ],
    );
  }

  Widget _buildReadView() {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.xl),
        boxShadow: c.shadow,
      ),
      child: WebViewWidget(controller: _webViewController),
    );
  }

  /// Honey caution banner on a deprecated document (the lifecycle `status`
  /// axis). When a `superseded_by` replacement is named, an Open CTA navigates
  /// to it — the contract never auto-follows the pointer, so the tap is the
  /// reader's explicit decision.
  Widget _buildDeprecatedBanner() {
    final c = context.colors;
    final l10n = context.l10n;
    final hasTarget = _currentDoc.supersededBy != null;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.honey.withValues(alpha: 0.12),
        border: Border.all(color: c.honey.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.history_toggle_off, size: 18, color: c.honeyD),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasTarget
                  ? l10n.deprecatedBannerSuperseded
                  : l10n.deprecatedBanner,
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.honeyD,
              ),
            ),
          ),
          if (hasTarget) ...[
            const SizedBox(width: 8),
            AppButton(
              l10n.openReplacement,
              variant: AppBtnVariant.warm,
              icon: Icons.arrow_forward,
              small: true,
              onPressed: _openSupersededBy,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openSupersededBy() async {
    final target = _currentDoc.supersededBy;
    if (target == null) return;
    final doc = await _resolveDocumentListing(target, null);
    if (doc == null || !mounted) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  /// Honey caution banner on a pinned historical version.
  ///
  /// Restore is offered for every pinned version except the head. Pinning to
  /// the head is an ordinary state now that the served-version banner's CTA
  /// leads there — it is the only way to read unpublished work — and restoring
  /// it would just append a duplicate of what is already current.
  Widget _buildHistoricalBanner() {
    final c = context.colors;
    final isHead = _selectedVersion == _currentDoc.currentVer;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.honey.withValues(alpha: 0.12),
        border: Border.all(color: c.honey.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: c.honeyD),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.l10n.viewingHistoricalLong(_selectedVersion),
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.honeyD,
              ),
            ),
          ),
          if (!isHead) ...[
            const SizedBox(width: 8),
            AppButton(
              context.l10n.restore,
              variant: AppBtnVariant.warm,
              icon: Icons.refresh,
              small: true,
              onPressed: _updatingProperties
                  ? null
                  : () => _confirmRestore(_selectedVersion),
            ),
          ],
        ],
      ),
    );
  }

  /// Honey caution banner for the publication gate: the document has a newer
  /// version than the one `/d/:id/raw` serves, so the WebView above is showing
  /// the operator exactly what an anonymous visitor sees — which, without
  /// saying so, reads as if the newest write never landed.
  ///
  /// The CTA pins the view to the head, which routes through the same
  /// operator-only `/d/:id/v/:n/raw` path the version sheet uses; the byte path
  /// has no way to serve the unpublished head, and this deliberately does not
  /// publish anything on the operator's behalf.
  Widget _buildServedBanner() {
    final c = context.colors;
    final l10n = context.l10n;
    final currentVer = _currentDoc.currentVer;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: c.honey.withValues(alpha: 0.12),
        border: Border.all(color: c.honey.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.public, size: 18, color: c.honeyD),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.readerServedBannerTitle,
                  style: AppText.small.copyWith(
                    fontWeight: FontWeight.w700,
                    color: c.honeyD,
                  ),
                ),
                if (currentVer != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.readerServedBannerBody(currentVer),
                    style: AppText.small.copyWith(color: c.honeyD),
                  ),
                ],
              ],
            ),
          ),
          if (currentVer != null) ...[
            const SizedBox(width: 8),
            AppButton(
              l10n.readerViewNewestAction(currentVer),
              variant: AppBtnVariant.warm,
              icon: Icons.arrow_forward,
              small: true,
              onPressed: () {
                setState(() => _selectedVersion = currentVer);
                _reloadWebview();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRevokedState() {
    final c = context.colors;
    final l10n = context.l10n;
    final dateStr = _currentDoc.revokedAt != null
        ? fmtDate(_currentDoc.revokedAt)
        : l10n.unknownDate;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.delete_outline, size: 56, color: c.red),
          const SizedBox(height: 16),
          Text(
            l10n.documentRevokedTitle,
            style: AppText.headline.copyWith(color: c.red),
          ),
          const SizedBox(height: 10),
          Text(
            l10n.documentRevokedOn(dateStr),
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.revokedStateDetail,
            textAlign: TextAlign.center,
            style: AppText.small.copyWith(color: c.textFaint),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// Private presentation widgets
// ==================================================================

class _BackPill extends StatelessWidget {
  const _BackPill({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        side: BorderSide(color: c.line),
      ),
      shadowColor: const Color(0x00000000),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          decoration: BoxDecoration(
            boxShadow: c.shadow,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          padding: const EdgeInsets.fromLTRB(8, 8, 14, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.chevron_left, size: 18, color: c.clayD),
              const SizedBox(width: 4),
              Text(
                context.l10n.cafeBack,
                style: AppText.titleSm.copyWith(fontSize: 14, color: c.clayD),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: c.shadow),
      child: Material(
        color: c.surface,
        shape: CircleBorder(side: BorderSide(color: c.line)),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, size: 18, color: c.textDim),
          ),
        ),
      ),
    );
  }
}

/// Compact version pill in the top bar — taps through to the version sheet.
///
/// [live] says the number is the SERVED (published) version rather than the
/// document's head, which is the only honest label when the two differ: the
/// chip describes what is on screen, so it reads "Live v5" in honey while the
/// head sits at v7 behind the publication gate.
class _VersionChip extends StatelessWidget {
  const _VersionChip({
    required this.version,
    required this.live,
    required this.onTap,
  });
  final int version;
  final bool live;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final fg = live ? c.honeyD : c.textDim;
    return PressCard(
      onPress: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: live ? c.honey : c.line),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: c.shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              live ? Icons.public : Icons.layers_outlined,
              size: 14,
              color: fg,
            ),
            const SizedBox(width: 6),
            Text(
              live
                  ? context.l10n.liveVersionLabel('$version')
                  : context.l10n.versionLabel('$version'),
              style: AppText.titleSm.copyWith(fontSize: 12.5, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline honey note inside a sheet — the sheet-scale sibling of the reader's
/// banners, used for the state of the list as a whole rather than of one row.
class _SheetNote extends StatelessWidget {
  const _SheetNote({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: c.honey.withValues(alpha: 0.12),
        border: Border.all(color: c.honey.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: c.honeyD),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.honeyD,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One row of the real version history.
///
/// CURRENT and LIVE are orthogonal badges, not two names for the newest thing:
/// CURRENT is the head every credentialed surface reads, LIVE is the version
/// the HTML byte path hands to readers. A row can carry both (the usual case),
/// either (a public document with older published work), or neither.
class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.entry,
    required this.isSelected,
    required this.onTap,
    required this.onPublish,
    required this.showRestore,
    required this.onRestore,
  });

  final VersionListing entry;
  final bool isSelected;
  final VoidCallback onTap;

  /// Null when this version is already the published one, or a publish is
  /// already in flight.
  final VoidCallback? onPublish;

  /// Whether restore is offered at all — it is not, on the head itself.
  final bool showRestore;

  /// Null when the version's source was never retained (the control stays
  /// visible but disabled, explained by the note beneath it).
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final author = entry.authorName;
    final hasActions = onPublish != null || showRestore;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? c.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.isPublished
                        ? c.green
                        : (entry.isCurrent ? c.honey : c.line),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  l10n.versionLabel('${entry.versionNo}'),
                  style: AppText.mono.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
                if (entry.isCurrent) ...[
                  const SizedBox(width: 8),
                  Pill(
                    l10n.versionBadgeCurrent,
                    tone: PillTone.honey,
                    small: true,
                  ),
                ],
                if (entry.isPublished) ...[
                  const SizedBox(width: 6),
                  Pill(
                    l10n.versionBadgeLive,
                    tone: PillTone.green,
                    icon: Icons.public,
                    small: true,
                  ),
                ],
                const Spacer(),
                Text(
                  relTime(l10n, entry.createdAt),
                  style: AppText.small.copyWith(color: c.textFaint),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.only(left: 21),
              child: Text(
                [
                  if (author != null && author.isNotEmpty)
                    l10n.versionAuthorBy(author),
                  fmtDate(entry.createdAt),
                  fmtBytes(entry.sizeBytes),
                  if (!entry.sourcePresent) l10n.versionNoSource,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.small.copyWith(color: c.textFaint),
              ),
            ),
            if (hasActions) ...[
              const SizedBox(height: 9),
              Padding(
                padding: const EdgeInsets.only(left: 21),
                child: Row(
                  children: [
                    if (onPublish != null) ...[
                      AppButton(
                        l10n.publishAction,
                        variant: AppBtnVariant.warm,
                        icon: Icons.public,
                        small: true,
                        onPressed: onPublish,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (showRestore)
                      AppButton(
                        l10n.restore,
                        variant: AppBtnVariant.outline,
                        icon: Icons.refresh,
                        small: true,
                        onPressed: onRestore,
                      ),
                  ],
                ),
              ),
              if (showRestore && !entry.sourcePresent) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 21),
                  child: Text(
                    l10n.versionNoSourceHint,
                    style: AppText.small.copyWith(color: c.textFaint),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Link graph (GET /d/:id/links) — the sheet's section labels and rows.
// ===========================================================================

/// Uppercase label above a section of the links sheet.
class _LinkSectionLabel extends StatelessWidget {
  const _LinkSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
      child: Text(
        text,
        style: AppText.label.copyWith(
          fontSize: 12,
          color: c.textFaint,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// The "nothing here" line under an empty section of the links sheet.
class _LinkEmptyLine extends StatelessWidget {
  const _LinkEmptyLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
      child: Text(text, style: AppText.small.copyWith(color: c.textFaint)),
    );
  }
}

/// One document that links to the one being read.
///
/// Backlinks are full listing rows for documents the operator may not have
/// open anywhere else — including private ones, which is why this surface is
/// credentialed — so the row shows enough to identify the document without
/// opening it.
class _BacklinkRow extends StatelessWidget {
  const _BacklinkRow({required this.doc, required this.onTap});
  final DocumentListing doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Row(
          children: [
            Icon(Icons.subdirectory_arrow_left, size: 17, color: c.textFaint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title ?? l10n.untitledPlain,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSm.copyWith(color: c.text),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      VisBadge(doc.visibility),
                      if (doc.status == 'deprecated') ...[
                        const SizedBox(width: 6),
                        const DeprecatedBadge(),
                      ],
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          relTime(l10n, doc.updatedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.small.copyWith(color: c.textFaint),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: c.textFaint),
          ],
        ),
      ),
    );
  }
}

/// One on-platform link this document carries, with the state it resolves to.
///
/// The raw addressed name is shown as the path that was authored (`/s/name` or
/// `/d/id`) rather than as a resolved title, because that is the string an
/// operator has to go and find in the source to fix it. A resolved title sits
/// underneath as confirmation of where it actually lands.
class _OutboundLinkRow extends StatelessWidget {
  const _OutboundLinkRow({
    required this.link,
    required this.onTap,
    required this.onRepair,
  });

  final OutboundLink link;

  /// Null when nothing resolves — the three broken states carry no target.
  final VoidCallback? onTap;

  /// Null unless a slug tombstone is the thing standing in the way.
  final VoidCallback? onRepair;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    final state = link.linkState;
    final prefix = link.linkKind == LinkKind.publicId ? '/d/' : '/s/';
    final dotColor = switch (state) {
      LinkState.live => c.green,
      LinkState.redirected => c.honey,
      LinkState.unknown => c.line,
      _ => c.red,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '$prefix${link.value}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.mono.copyWith(fontSize: 13, color: c.text),
                  ),
                ),
                const SizedBox(width: 8),
                LinkStateBadge(state),
              ],
            ),
            if (link.title != null && link.title!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 21),
                child: Text(
                  link.title!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.small.copyWith(color: c.textFaint),
                ),
              ),
            ],
            if (onRepair != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 21),
                child: AppButton(
                  l10n.linksRepairAction,
                  variant: AppBtnVariant.outline,
                  icon: Icons.build_outlined,
                  small: true,
                  onPressed: onRepair,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
