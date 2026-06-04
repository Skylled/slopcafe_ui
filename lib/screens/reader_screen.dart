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

  Future<void> _handleNavigation(String url) async {
    await _openExternalBrowser(url);
  }

  Future<void> _loadHtmlIntoWebview() async {
    if (_baseUrl == null) return;

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
            ? 'Document revoked'
            : 'Document not found';
        final errorMsg = statusCode == 410
            ? 'This document has been permanently revoked.'
            : 'This document could not be found on the server.';

        final errorHtml = _buildErrorHtml(errorTitle, errorMsg);
        await _webViewController.loadHtmlString(errorHtml);
      } else {
        // Network/connection/server error
        if (cachedHtml == null) {
          final errorHtml = _buildErrorHtml(
            'Offline / connection error',
            'Could not retrieve the document. Please check your internet '
                'connection.',
          );
          await _webViewController.loadHtmlString(errorHtml);
        }
      }
    } catch (e) {
      if (cachedHtml == null) {
        final errorHtml = _buildErrorHtml('Error', e.toString());
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
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
        if (!mounted) return;
        showToast(context, 'Opening in browser…');
      } else {
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        showToast(context, 'URL copied — paste it in your browser');
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      showToast(
        context,
        'Could not launch browser — URL copied instead',
        danger: true,
      );
    }
  }

  // ----------------------------------------------------------------
  // Operator actions (ported, restyled to Craft sheets)
  // ----------------------------------------------------------------

  Future<void> _revokeDocument() async {
    if (_baseUrl == null) return;
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

      final revokedTitle = _currentDoc.title ?? 'Untitled';

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
        'Revoked "$revokedTitle" · $r2Purged R2 object(s) purged',
        danger: true,
      );

      // Pop back indicating a successful revocation to refresh parent screen.
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isRevoking = false);
      if (!mounted) return;
      showToast(context, 'Revocation failed: ${e.toString()}', danger: true);
    }
  }

  Future<void> _confirmRevoke() async {
    final c = context.colors;
    final confirmed = await showConfirmSheet(
      context,
      title: 'Revoke document',
      confirmWord: 'REVOKE',
      cta: 'Revoke permanently',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This action is permanent and irreversible.',
            style: AppText.body.copyWith(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: c.red,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Document files will be immediately purged from R2 storage. '
            'Live slugs will be cleared for reuse.',
          ),
        ],
      ),
    );
    if (confirmed) {
      await _revokeDocument();
    }
  }

  Future<void> _toggleVisibility() async {
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
      showToast(context, 'Now ${nextVisibility.toUpperCase()}');
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(
        context,
        'Failed to update visibility: ${e.toString()}',
        danger: true,
      );
    }
  }

  Future<void> _confirmToggleVisibility() async {
    final makingPublic = _currentDoc.visibility != 'public';
    final confirmed = await showConfirmSheet(
      context,
      title: makingPublic ? 'Make public' : 'Make private',
      cta: makingPublic ? 'Make public' : 'Make private',
      danger: false,
      body: Text(
        makingPublic
            ? 'Anyone with the link will be able to read this document.'
            : 'Only operators will be able to read this document.',
      ),
    );
    if (confirmed) {
      await _toggleVisibility();
    }
  }

  Future<void> _editSlugAndTags() async {
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
          title: 'Edit slug & tags',
          subtitle: 'Document properties',
          icon: Icons.sell_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SLUG',
                style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: slugController,
                style: AppText.mono.copyWith(fontSize: 14, color: c.text),
                decoration: deco('e.g. my-cool-document'),
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
                  'Slugs are retired permanently when cleared or changed — the '
                  'old slug then returns 410 Gone. Leave empty to clear.',
                  style: AppText.small.copyWith(color: c.honeyD),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'TAGS',
                style: AppText.label.copyWith(fontSize: 11, color: c.textFaint),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: tagsController,
                style: AppText.body.copyWith(color: c.text),
                decoration: deco('e.g. guide, tutorial, reference'),
              ),
              const SizedBox(height: 8),
              Text(
                'Separate tags with commas.',
                style: AppText.small.copyWith(color: c.textFaint),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      'Cancel',
                      variant: AppBtnVariant.outline,
                      expand: true,
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: AppButton(
                      'Save',
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
      showToast(context, 'Document properties updated');
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(context, 'Failed to update: ${e.toString()}', danger: true);
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
      showToast(context, 'Restored v$version (now live as v$newVer)');
    } catch (e) {
      setState(() => _updatingProperties = false);
      if (!mounted) return;
      showToast(context, 'Restore failed: ${e.toString()}', danger: true);
    }
  }

  Future<void> _confirmRestore(int version) async {
    final confirmed = await showConfirmSheet(
      context,
      title: 'Restore v$version',
      cta: 'Restore v$version',
      danger: false,
      body: Text(
        'This creates a new live version of the document with the exact '
        'contents of v$version.',
      ),
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
    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final count = maxVer < 6 ? maxVer : 6;
        final versions = List<int>.generate(count, (i) => maxVer - i);
        return AppSheet(
          title: 'Version history',
          subtitle: 'On the menu',
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
                          'Viewing historical v$_selectedVersion — not the '
                          'live version.',
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
                  'Restore v$_selectedVersion',
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
    showAppSheet<void>(
      context,
      builder: (sheetContext) {
        final c = sheetContext.colors;
        final canEdit = !_currentDoc.isRevoked && !_updatingProperties;
        return AppSheet(
          title: _currentDoc.title ?? 'Untitled',
          subtitle: 'Operator actions',
          child: Column(
            children: [
              SheetActionRow(
                icon: Icons.link,
                label: 'Copy link',
                onTap: (_baseUrl != null && !_currentDoc.isRevoked)
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _copyToClipboard(
                          '$_baseUrl/d/${_currentDoc.publicId}',
                          'Link copied',
                        );
                      }
                    : null,
              ),
              SheetActionRow(
                icon: isPublic ? Icons.lock_outline : Icons.public,
                label: isPublic ? 'Make private' : 'Make public',
                onTap: canEdit
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _confirmToggleVisibility();
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.sell_outlined,
                label: 'Edit slug & tags',
                onTap: canEdit
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _editSlugAndTags();
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.tag,
                label: 'Copy slug URL',
                onTap: (_baseUrl != null && _currentDoc.slug != null)
                    ? () {
                        Navigator.of(sheetContext).pop();
                        _copyToClipboard(
                          '$_baseUrl/s/${_currentDoc.slug}',
                          'Slug URL copied',
                        );
                      }
                    : null,
              ),
              SheetActionRow(
                icon: Icons.open_in_new,
                label: 'Open in browser',
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
                label: 'Revoke document',
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
                    'No base URL configured. Open Settings to connect.',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _currentDoc.title ?? '[Untitled]',
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
              const Pill(
                'REVOKED',
                tone: PillTone.red,
                icon: Icons.block,
                small: true,
              )
            else
              VisBadge(_currentDoc.visibility),
            const MetaDot(),
            Flexible(
              child: Text(
                _currentDoc.createdByName ?? 'Deleted agent',
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
              'Viewing historical version v$_selectedVersion. This is not the '
              'live version.',
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: c.honeyD,
              ),
            ),
          ),
          const SizedBox(width: 8),
          AppButton(
            'Restore',
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
    final dateStr = _currentDoc.revokedAt != null
        ? fmtDate(_currentDoc.revokedAt)
        : 'an unknown date';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.delete_outline, size: 56, color: c.red),
          const SizedBox(height: 16),
          Text(
            'Document revoked',
            style: AppText.headline.copyWith(color: c.red),
          ),
          const SizedBox(height: 10),
          Text(
            'This document was permanently revoked on $dateStr.',
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: c.textDim),
          ),
          const SizedBox(height: 8),
          Text(
            'All R2 file bytes have been purged and slugs released. The public '
            'and debug views now return 404.',
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
                'Café',
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
              'v$version',
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
              'v$version',
              style: AppText.mono.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
            const SizedBox(width: 8),
            if (isLatest)
              const Pill('CURRENT', tone: PillTone.honey, small: true),
            const Spacer(),
            Text(
              isLatest ? relTime(createdAt) : 'earlier',
              style: AppText.small.copyWith(color: c.textFaint),
            ),
          ],
        ),
      ),
    );
  }
}
