import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';

import '../core/api_client.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/document_cache.dart';
import '../core/format.dart';
import '../core/secure_storage.dart';
import '../l10n/l10n.dart';
import '../models/document.dart';
import '../providers/document_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/pill.dart';
import '../widgets/press_card.dart';
import '../widgets/section_header.dart';
import '../widgets/sheets.dart';
import '../widgets/toast.dart';
import 'document_list_screen.dart';

/// ReaderScreen — the Craft "plate". A full-bleed pushed route built around a
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
  }

  Future<void> _reloadWebview() async {
    if (_baseUrl == null) return;
    await _loadHtmlIntoWebview();
  }

  Future<DocumentListing?> _resolveDocumentListing(String? publicId, String? slug) async {
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
        final response = await dio.get('/admin/documents', queryParameters: {'slug': slug});
        final data = response.data as Map<String, dynamic>;
        final List<dynamic> docsJson = data['documents'] ?? [];
        if (docsJson.isNotEmpty) {
          return DocumentListing.fromJson(docsJson.first);
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
          return DocumentListing.fromJson(response.data as Map<String, dynamic>);
        }
      } catch (e) {
        // Fallback
      }

      // Placeholder fallback if not found or unauthorized
      return DocumentListing(
        publicId: publicId,
        createdAt: DateTime.now(),
        tags: [],
        title: publicId,
        visibility: 'private',
      );
    }
    return null;
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

    final bool isHostMatch = baseUri != null &&
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
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)),
          );
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

  Future<void> _loadHtmlIntoWebview() async {
    if (_baseUrl == null) return;
    final l10n = context.l10n;

    final String publicId = _currentDoc.publicId;
    int versionToLoad = _selectedVersion == 0
        ? (_currentDoc.currentVer ?? 1)
        : _selectedVersion;

    // Check if we have a cached version for this document
    int? cachedVersion;
    if (_selectedVersion == 0) {
      cachedVersion = await DocumentCacheManager.getCachedVersion(publicId);
      if (cachedVersion != null) {
        versionToLoad = cachedVersion;
      }
    } else {
      final exists = await DocumentCacheManager.isCached(
        publicId,
        _selectedVersion,
      );
      if (exists) {
        cachedVersion = _selectedVersion;
      }
    }

    final cachedHtml = cachedVersion != null
        ? await DocumentCacheManager.getCachedHtml(publicId, cachedVersion)
        : null;

    if (cachedHtml != null) {
      final securedHtml = _injectCspMeta(cachedHtml);
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
            if (cachedVersion != null) 'If-None-Match': '"v$cachedVersion"',
          },
          validateStatus: (status) => status == 200 || status == 304,
        ),
      );

      if (response.statusCode == 304) {
        // Cache is valid and matches the server version!
        // No need to update the cache or reload the WebView since we already
        // loaded cachedHtml.
        return;
      }

      // If response is 200 OK, update the cache and render fresh HTML
      final freshHtml = response.data as String;

      // Extract new version from etag header if present
      final etagHeader =
          response.headers.value('etag') ?? response.headers.value('ETag');
      int newVersion = versionToLoad;
      if (etagHeader != null) {
        final cleanEtag = etagHeader.replaceAll('"', '').trim();
        if (cleanEtag.startsWith('v')) {
          final ver = int.tryParse(cleanEtag.substring(1));
          if (ver != null) {
            newVersion = ver;
          }
        }
      }

      // Client-side guard: if the version matches the cached version, we don't
      // need to reload or save.
      if (newVersion == cachedVersion && cachedHtml != null) {
        return;
      }

      // Update cache
      await DocumentCacheManager.saveCachedHtml(
        publicId,
        newVersion,
        freshHtml,
      );

      // If version has changed, update _currentDoc so UI shows correct version
      if (_selectedVersion == 0 && _currentDoc.currentVer != newVersion) {
        if (mounted) {
          setState(() {
            _currentDoc = DocumentListing(
              publicId: _currentDoc.publicId,
              createdAt: _currentDoc.createdAt,
              tags: _currentDoc.tags,
              createdById: _currentDoc.createdById,
              createdByName: _currentDoc.createdByName,
              currentSize: _currentDoc.currentSize,
              currentVer: newVersion,
              description: _currentDoc.description,
              slug: _currentDoc.slug,
              title: _currentDoc.title,
              visibility: _currentDoc.visibility,
              revokedAt: _currentDoc.revokedAt,
            );
          });
        }
      }

      // Render fresh HTML (now from the network, not the cache)
      final securedHtml = _injectCspMeta(freshHtml);
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
        final errorHtml = _buildErrorHtml(l10n.errorTitle, e.toString());
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
    // The original screen had no url_launcher dependency: it shells out to
    // `open` on macOS and otherwise copies the URL. We keep that exact
    // behavior, surfacing feedback via the Craft toast instead of a SnackBar.
    final l10n = context.l10n;
    try {
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
  // Operator actions (ported, restyled to Craft sheets)
  // ----------------------------------------------------------------

  Future<void> _revokeDocument() async {
    if (_baseUrl == null) return;
    final l10n = context.l10n;
    setState(() => _isRevoking = true);

    final dio = ref.read(dioProvider);
    try {
      final response = await dio.delete('/d/${_currentDoc.publicId}');
      final data = response.data as Map<String, dynamic>;
      final r2Purged = data['r2_objects_purged'] ?? 0;

      final now = DateTime.now();
      ref
          .read(documentsListProvider.notifier)
          .revokeDocumentLocally(_currentDoc.publicId, now);

      final revokedTitle = _currentDoc.title ?? l10n.untitledPlain;

      setState(() {
        _currentDoc = DocumentListing(
          publicId: _currentDoc.publicId,
          createdAt: _currentDoc.createdAt,
          tags: _currentDoc.tags,
          createdById: _currentDoc.createdById,
          createdByName: _currentDoc.createdByName,
          currentSize: null,
          currentVer: null,
          description: _currentDoc.description,
          slug: null,
          title: _currentDoc.title,
          revokedAt: now,
        );
        _isRevoking = false;
      });

      if (!mounted) return;
      showToast(
        context,
        l10n.documentRevokedToast(revokedTitle, r2Purged),
        danger: true,
      );

      // Pop back indicating a successful revocation to refresh parent screen.
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isRevoking = false);
      if (!mounted) return;
      showToast(context, l10n.revocationFailed(e.toString()), danger: true);
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
        l10n.failedUpdateVisibility(e.toString()),
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
      showToast(context, l10n.failedUpdate(e.toString()), danger: true);
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _restoreVersion(int version) async {
    final l10n = context.l10n;
    setState(() => _updatingProperties = true);
    try {
      final newVer = await ref
          .read(documentsListProvider.notifier)
          .restoreVersion(_currentDoc.publicId, version);

      setState(() {
        _selectedVersion = 0; // reset to latest
        _currentDoc = DocumentListing(
          publicId: _currentDoc.publicId,
          createdAt: _currentDoc.createdAt,
          tags: _currentDoc.tags,
          createdById: _currentDoc.createdById,
          createdByName: _currentDoc.createdByName,
          currentSize: _currentDoc.currentSize,
          currentVer: newVer,
          description: _currentDoc.description,
          slug: _currentDoc.slug,
          title: _currentDoc.title,
          revokedAt: _currentDoc.revokedAt,
          visibility: _currentDoc.visibility,
        );
        _updatingProperties = false;
      });

      await _reloadWebview();

      if (!mounted) return;
      showToast(context, l10n.restoredVersion(version, newVer));
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(context, l10n.restoreFailed(e.toString()), danger: true);
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

  // ----------------------------------------------------------------
  // Sheets
  // ----------------------------------------------------------------

  void _openVersionSheet() {
    final maxVer = _currentDoc.currentVer;
    if (maxVer == null) return;
    final l10n = context.l10n;
    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final count = maxVer < 6 ? maxVer : 6;
        final versions = List<int>.generate(count, (i) => maxVer - i);
        return AppSheet(
          title: l10n.versionHistory,
          subtitle: l10n.onTheMenu,
          icon: Icons.layers_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedVersion != 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: c.honey.withValues(alpha: 0.12),
                    border: Border.all(color: c.honey.withValues(alpha: 0.30)),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 16, color: c.honeyD),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          l10n.viewingHistoricalShort(_selectedVersion),
                          style: AppText.small.copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.honeyD,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final v in versions)
                _VersionRow(
                  version: v,
                  isLatest: v == maxVer,
                  isSelected:
                      (_selectedVersion == 0 && v == maxVer) ||
                      _selectedVersion == v,
                  createdAt: _currentDoc.createdAt,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _selectedVersion = v == maxVer ? 0 : v);
                    _reloadWebview();
                  },
                ),
              if (_selectedVersion != 0) ...[
                const SizedBox(height: 14),
                AppButton(
                  l10n.restoreVersionTitle(_selectedVersion),
                  variant: AppBtnVariant.primary,
                  icon: Icons.refresh,
                  expand: true,
                  onPressed: _updatingProperties
                      ? null
                      : () {
                          Navigator.of(sheetContext).pop();
                          _confirmRestore(_selectedVersion);
                        },
                ),
              ],
            ],
          ),
        );
      },
    );
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

    return Scaffold(
      backgroundColor: c.bg,
      body: Column(
        children: [
          // ---- Compact top bar: back · version · more ----
          Padding(
            padding: EdgeInsets.fromLTRB(14, topPad + 10, 14, 0),
            child: Row(
              children: [
                _BackPill(onTap: () => Navigator.of(context).pop()),
                const Spacer(),
                if (ver != null && !isRevoked) ...[
                  _VersionChip(version: ver, onTap: _openVersionSheet),
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
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
            child: _buildHeader(c, isRevoked),
          ),

          // ---- WebView (or revoked state) owns the rest of the screen ----
          Expanded(child: _buildReaderBody()),
        ],
      ),
    );
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
            else
              VisBadge(_currentDoc.visibility),
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
        if (_selectedVersion != 0) _buildHistoricalBanner(),
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

  Widget _buildHistoricalBanner() {
    final c = context.colors;
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
class _VersionChip extends StatelessWidget {
  const _VersionChip({required this.version, required this.onTap});
  final int version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PressCard(
      onPress: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          boxShadow: c.shadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.layers_outlined, size: 14, color: c.textDim),
            const SizedBox(width: 6),
            Text(
              context.l10n.versionLabel('$version'),
              style: AppText.titleSm.copyWith(fontSize: 12.5, color: c.textDim),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.version,
    required this.isLatest,
    required this.isSelected,
    required this.createdAt,
    required this.onTap,
  });
  final int version;
  final bool isLatest;
  final bool isSelected;
  final DateTime createdAt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: isSelected ? c.surface2 : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isLatest ? c.honey : c.line,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              l10n.versionLabel('$version'),
              style: AppText.mono.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(width: 8),
            if (isLatest)
              Pill(l10n.currentBadge, tone: PillTone.honey, small: true),
            const Spacer(),
            Text(
              isLatest ? relTime(l10n, createdAt) : l10n.earlier,
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
