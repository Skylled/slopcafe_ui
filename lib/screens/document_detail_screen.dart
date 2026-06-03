import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../models/document.dart';
import '../core/secure_storage.dart';
import '../core/api_client.dart';
import '../providers/document_provider.dart';
import '../core/document_cache.dart';

enum DocumentViewMode { rendered, source, markdown, retainedSource }

class DocumentDetailScreen extends ConsumerStatefulWidget {
  final DocumentListing document;

  const DocumentDetailScreen({super.key, required this.document});

  @override
  ConsumerState<DocumentDetailScreen> createState() =>
      _DocumentDetailScreenState();
}

class _DocumentDetailScreenState extends ConsumerState<DocumentDetailScreen> {
  DocumentViewMode _viewMode = DocumentViewMode.rendered;
  late final WebViewController _webViewController;
  String? _baseUrl;
  bool _isLoadingBaseUrl = true;
  bool _isRevoking = false;
  bool _updatingProperties = false;
  int _selectedVersion = 0;
  late DocumentListing _currentDoc;

  @override
  void initState() {
    super.initState();
    _currentDoc = widget.document;
    _initBaseUrlAndWebview();
  }

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
              final url = request.url;
              if (url == 'about:blank' || url.startsWith('data:')) {
                return NavigationDecision.navigate;
              }
              _handleNavigation(url);
              return NavigationDecision.prevent;
            },
          ),
        );

      await _loadHtmlIntoWebview();
    }

    setState(() {
      _isLoadingBaseUrl = false;
    });
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
    final int versionToLoad = _selectedVersion == 0
        ? (_currentDoc.currentVer ?? 1)
        : _selectedVersion;

    // 1. Try to load from cache first for instant/offline viewing
    final cachedHtml = await DocumentCacheManager.getCachedHtml(publicId, versionToLoad);
    if (cachedHtml != null) {
      final securedHtml = _injectCspMeta(cachedHtml);
      await _webViewController.loadHtmlString(securedHtml, baseUrl: _baseUrl);
    }

    // 2. Fetch fresh version from server in background/foreground
    try {
      final dio = ref.read(dioProvider);
      final String path = _selectedVersion == 0
          ? '/d/$publicId/raw'
          : '/d/$publicId/v/$versionToLoad/raw';

      final response = await dio.get(path);
      final freshHtml = response.data as String;

      // Update cache
      await DocumentCacheManager.saveCachedHtml(publicId, versionToLoad, freshHtml);

      // Render fresh HTML
      final securedHtml = _injectCspMeta(freshHtml);
      await _webViewController.loadHtmlString(securedHtml, baseUrl: _baseUrl);
    } on DioException catch (dioErr) {
      final statusCode = dioErr.response?.statusCode;
      if (statusCode == 404 || statusCode == 410) {
        // Document has been revoked or deleted. Clean up cache!
        await DocumentCacheManager.deleteCachedDoc(publicId);
        
        final errorTitle = statusCode == 410 ? 'Document Revoked' : 'Document Not Found';
        final errorMsg = statusCode == 410 
            ? 'This document has been permanently revoked.' 
            : 'This document could not be found on the server.';
            
        final errorHtml = _buildErrorHtml(errorTitle, errorMsg);
        await _webViewController.loadHtmlString(errorHtml);
      } else {
        // Network/connection/server error
        if (cachedHtml == null) {
          final errorHtml = _buildErrorHtml(
            'Offline / Connection Error',
            'Could not retrieve the document. Please check your internet connection.',
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
    const csp = "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline' data:; font-src data:; base-uri 'none'; form-action 'none'\">";
    if (html.contains('<head>')) {
      return html.replaceFirst('<head>', '<head>\n$csp');
    } else {
      return '$csp\n$html';
    }
  }

  String _buildErrorHtml(String title, String message) {
    return '''
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body {
            font-family: system-ui, -apple-system, sans-serif;
            padding: 32px 16px;
            margin: 0;
            color: #666;
            background-color: #fafafa;
            text-align: center;
          }
          .container {
            max-width: 400px;
            margin: 0 auto;
            background: white;
            border: 1px solid #e5e5e5;
            border-radius: 12px;
            padding: 24px;
            box-shadow: 0 2px 8px rgba(0,0,0,0.05);
          }
          h1 {
            font-size: 18px;
            color: #d32f2f;
            margin: 0 0 12px;
          }
          p {
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

  Future<void> _copyToClipboard(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _openExternalBrowser(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else {
        // Fallback for Android / other platforms or if open fails
        await Clipboard.setData(ClipboardData(text: url));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'URL copied to clipboard. Paste in your browser: $url',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      await Clipboard.setData(ClipboardData(text: url));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Failed to launch browser. URL copied to clipboard instead.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showRevokeDialog() async {
    final theme = Theme.of(context);
    final confirmController = TextEditingController();
    bool canRevoke = false;

    showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  const Text('Confirm Revocation'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'This actions is permanent and irreversible.',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Document files will be immediately purged from R2 storage. '
                    'Live slugs will be cleared for reuse.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Type "REVOKE" below to confirm:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: confirmController,
                    decoration: const InputDecoration(
                      hintText: 'REVOKE',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (text) {
                      setState(() {
                        canRevoke = text.trim() == 'REVOKE';
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: canRevoke
                      ? () => Navigator.pop(context, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colorScheme.error,
                    foregroundColor: theme.colorScheme.onError,
                  ),
                  child: const Text('Revoke Permanently'),
                ),
              ],
            );
          },
        );
      },
    ).then((confirmed) {
      confirmController.dispose();
      if (confirmed == true) {
        _revokeDocument();
      }
    });
  }

  Future<void> _revokeDocument() async {
    if (_baseUrl == null) return;
    setState(() {
      _isRevoking = true;
    });

    final dio = ref.read(dioProvider);
    try {
      final response = await dio.delete('/d/${_currentDoc.publicId}');
      final data = response.data as Map<String, dynamic>;
      final r2Purged = data['r2_objects_purged'] ?? 0;

      final now = DateTime.now();
      ref
          .read(documentsListProvider.notifier)
          .revokeDocumentLocally(_currentDoc.publicId, now);

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Document "${_currentDoc.title ?? 'Untitled'}" revoked. $r2Purged R2 object(s) purged.',
          ),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Pop back indicating a successful revocation to refresh parent screen
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _isRevoking = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Revocation failed: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRevoked = _currentDoc.isRevoked;
    final publicDocUrl = _baseUrl != null
        ? '$_baseUrl/d/${_currentDoc.publicId}'
        : '';
    final slugDocUrl = (_baseUrl != null && _currentDoc.slug != null)
        ? '$_baseUrl/s/${_currentDoc.slug}'
        : '';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentDoc.title ?? '[Untitled]',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          // 1. View switcher popup menu (User suggestion incorporated)
          PopupMenuButton<DocumentViewMode>(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Select Mode',
            onSelected: (mode) {
              if (isRevoked && mode != DocumentViewMode.rendered) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Debug source views are unavailable for revoked documents.',
                    ),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              setState(() {
                _viewMode = mode;
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: DocumentViewMode.rendered,
                child: Row(
                  children: [
                    Icon(
                      Icons.public,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text('Rendered WebView'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: DocumentViewMode.source,
                enabled: !isRevoked,
                child: Row(
                  children: [
                    Icon(
                      Icons.code,
                      color: theme.colorScheme.secondary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'HTML Source (Debug)',
                      style: TextStyle(
                        color: isRevoked
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: DocumentViewMode.markdown,
                enabled: !isRevoked,
                child: Row(
                  children: [
                    Icon(
                      Icons.text_snippet_outlined,
                      color: theme.colorScheme.tertiary,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Markdown Text (Debug)',
                      style: TextStyle(
                        color: isRevoked
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: DocumentViewMode.retainedSource,
                enabled: !isRevoked,
                child: Row(
                  children: [
                    Icon(
                      Icons.lock_person_outlined,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Retained Source (Debug)',
                      style: TextStyle(
                        color: isRevoked
                            ? theme.colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 2. Action operations popup menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'Actions',
            onSelected: (value) {
              switch (value) {
                case 'copy_url':
                  _copyToClipboard(
                    publicDocUrl,
                    'Public URL copied to clipboard',
                  );
                  break;
                case 'copy_slug_url':
                  if (slugDocUrl.isNotEmpty) {
                    _copyToClipboard(
                      slugDocUrl,
                      'Slug URL copied to clipboard',
                    );
                  }
                  break;
                case 'open_browser':
                  _openExternalBrowser(publicDocUrl);
                  break;
                case 'toggle_visibility':
                  _toggleVisibility();
                  break;
                case 'edit_slug':
                  _showEditSlugDialog();
                  break;
                case 'edit_tags':
                  _showEditTagsDialog();
                  break;
                case 'revoke':
                  _showRevokeDialog();
                  break;
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'copy_url',
                enabled: publicDocUrl.isNotEmpty,
                child: const Row(
                  children: [
                    Icon(Icons.copy, size: 20),
                    SizedBox(width: 8),
                    Text('Copy Document URL'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'copy_slug_url',
                enabled: slugDocUrl.isNotEmpty,
                child: const Row(
                  children: [
                    Icon(Icons.link, size: 20),
                    SizedBox(width: 8),
                    Text('Copy Slug URL'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'open_browser',
                enabled: publicDocUrl.isNotEmpty,
                child: const Row(
                  children: [
                    Icon(Icons.open_in_browser, size: 20),
                    SizedBox(width: 8),
                    Text('Open in Browser'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'toggle_visibility',
                enabled: !isRevoked && !_updatingProperties,
                child: Row(
                  children: [
                    Icon(
                      _currentDoc.visibility == 'public' ? Icons.lock_outline : Icons.public,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(_currentDoc.visibility == 'public' ? 'Make Private' : 'Make Public'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit_slug',
                enabled: !isRevoked && !_updatingProperties,
                child: const Row(
                  children: [
                    Icon(Icons.bookmark_outline, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Slug'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'edit_tags',
                enabled: !isRevoked && !_updatingProperties,
                child: const Row(
                  children: [
                    Icon(Icons.tag, size: 20),
                    SizedBox(width: 8),
                    Text('Edit Tags'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'revoke',
                enabled: !isRevoked && !_isRevoking,
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_forever,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Revoke Document',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoadingBaseUrl
          ? const Center(child: CircularProgressIndicator())
          : _baseUrl == null
          ? const Center(
              child: Text(
                'Base URL configuration not found. Please review Settings.',
              ),
            )
          : Column(
              children: [
                // 1. Static Metadata Header Card
                _buildMetadataHeaderCard(),

                // 1.5. Version Selector Row (if not revoked)
                if (!isRevoked) _buildVersionSelector(),

                // 1.6. Historical Version Banner (if viewing history)
                if (!isRevoked) _buildHistoricalVersionBanner(),

                // 2. View mode toggle banner (subtle, informs user which mode they are looking at)
                _buildViewModeBanner(),

                // 3. Dynamic content viewport
                Expanded(
                  child: isRevoked
                      ? _buildRevokedEmptyState()
                      : _isRevoking
                      ? const Center(child: CircularProgressIndicator())
                      : _buildContentView(),
                ),
              ],
            ),
    );
  }

  Widget _buildMetadataHeaderCard() {
    final theme = Theme.of(context);
    final sizeFormatted = _currentDoc.isRevoked
        ? '0 B'
        : '${_currentDoc.currentSize ?? 0} B';
    final dateStr = DateFormat.yMMMd().format(_currentDoc.createdAt.toLocal());

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.surfaceContainerHighest,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_currentDoc.description != null &&
              _currentDoc.description!.trim().isNotEmpty) ...[
            Text(
              _currentDoc.description!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (_currentDoc.slug != null)
                _buildHeaderLabel(Icons.bookmark_outline, _currentDoc.slug!),
              if (!_currentDoc.isRevoked && _currentDoc.currentVer != null)
                _buildHeaderLabel(
                  Icons.layers_outlined,
                  'v${_currentDoc.currentVer}',
                ),
              _buildHeaderLabel(Icons.save_outlined, sizeFormatted),
              _buildHeaderLabel(
                Icons.person_outline,
                _currentDoc.createdByName ?? 'Deleted Agent',
              ),
              _buildHeaderLabel(Icons.calendar_today_outlined, dateStr),
              if (_currentDoc.isRevoked)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'REVOKED',
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _currentDoc.visibility == 'public'
                        ? theme.colorScheme.primary.withValues(alpha: 0.15)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _currentDoc.visibility == 'public'
                          ? theme.colorScheme.primary.withValues(alpha: 0.3)
                          : theme.colorScheme.outlineVariant,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _currentDoc.visibility == 'public'
                            ? Icons.public
                            : Icons.lock_outline,
                        size: 10,
                        color: _currentDoc.visibility == 'public'
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _currentDoc.visibility == 'public' ? 'PUBLIC' : 'PRIVATE',
                        style: TextStyle(
                          color: _currentDoc.visibility == 'public'
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          if (_currentDoc.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 22,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _currentDoc.tags.map((tag) {
                  return Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.3,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        tag,
                        style: TextStyle(
                          fontSize: 9,
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeaderLabel(IconData icon, String label) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildViewModeBanner() {
    final theme = Theme.of(context);
    if (_currentDoc.isRevoked) return const SizedBox.shrink();
    if (_viewMode == DocumentViewMode.rendered) return const SizedBox.shrink();

    String title = '';
    Color bgColor = theme.colorScheme.surfaceContainerHighest;
    IconData icon = Icons.public;

    switch (_viewMode) {
      case DocumentViewMode.rendered:
        return const SizedBox.shrink();
      case DocumentViewMode.source:
        title = 'Raw HTML Source View (Debug Mode)';
        bgColor = theme.colorScheme.secondary.withValues(alpha: 0.08);
        icon = Icons.code;
        break;
      case DocumentViewMode.markdown:
        title = 'Parsed Markdown View (Debug Mode)';
        bgColor = theme.colorScheme.tertiary.withValues(alpha: 0.08);
        icon = Icons.text_snippet_outlined;
        break;
      case DocumentViewMode.retainedSource:
        title = 'Retained Source View (Debug Mode)';
        bgColor = theme.colorScheme.error.withValues(alpha: 0.08);
        icon = Icons.lock_person_outlined;
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: bgColor,
      child: Row(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRevokedEmptyState() {
    final theme = Theme.of(context);
    final dateStr = _currentDoc.revokedAt != null
        ? DateFormat.yMMMd().add_jm().format(_currentDoc.revokedAt!.toLocal())
        : 'Unknown';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.delete_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Document Revoked',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This document was permanently revoked on $dateStr.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(
              'All R2 file bytes have been purged, and slugs released. Accessing this document public or debug views will return a 404.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentView() {
    switch (_viewMode) {
      case DocumentViewMode.rendered:
        return Container(
          margin: const EdgeInsets.only(top: 8),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                width: 1.5,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(14.5),
              topRight: Radius.circular(14.5),
            ),
            child: WebViewWidget(controller: _webViewController),
          ),
        );
      case DocumentViewMode.source:
        return _buildSourceHtmlView();
      case DocumentViewMode.markdown:
        return _buildMarkdownTextView();
      case DocumentViewMode.retainedSource:
        return _buildRetainedSourceView();
    }
  }

  Widget _buildSourceHtmlView() {
    final theme = Theme.of(context);
    final htmlAsync = _selectedVersion == 0
        ? ref.watch(documentDetailHtmlProvider(_currentDoc.publicId))
        : ref.watch(documentDetailHistoryRawProvider(
            (publicId: _currentDoc.publicId, version: _selectedVersion),
          ));

    return htmlAsync.when(
      data: (html) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(
                alpha: 0.3,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
            child: SelectableText(
              html,
              style: const TextStyle(
                fontFamily: 'Courier',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          'Failed to load raw HTML: ${err.toString()}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    );
  }

  Widget _buildMarkdownTextView() {
    final theme = Theme.of(context);
    final mdAsync = ref.watch(documentDetailTextProvider(_currentDoc.publicId));

    return mdAsync.when(
      data: (res) {
        return Column(
          children: [
            if (_selectedVersion != 0)
              Container(
                width: double.infinity,
                color: theme.colorScheme.secondaryContainer,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer, size: 16),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Markdown view only supports the latest version. Showing latest version.',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Markdown(
                data: res.markdown,
                selectable: true,
                padding: const EdgeInsets.all(16),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildFooterChip('Sanitizer: ${res.sanitizerVersion}'),
                  _buildFooterChip('Converter: ${res.converterVersion}'),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          'Failed to load Markdown text: ${err.toString()}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    );
  }

  Widget _buildRetainedSourceView() {
    final theme = Theme.of(context);
    final sourceAsync = ref.watch(documentDetailSourceProvider(_currentDoc.publicId));

    return sourceAsync.when(
      data: (res) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_selectedVersion != 0)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  color: theme.colorScheme.secondaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.colorScheme.onSecondaryContainer, size: 16),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Retained source view only supports the latest version. Showing latest version.',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              if (res.unsanitized)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.error),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Warning: This source contains unsanitized content. Exercise caution.',
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFooterChip('Format: ${res.sourceFormat}'),
                  _buildFooterChip('Sanitizer: ${res.sanitizerVersion}'),
                  _buildFooterChip('Version: v${res.versionNo}'),
                ],
              ),
              const SizedBox(height: 16),
              if (res.stripped.isNotEmpty) ...[
                Text(
                  'Stripped Elements:',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: res.stripped.map((item) => Chip(
                      label: Text(item, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (res.willNotRender.isNotEmpty) ...[
                Text(
                  'Unrendered / Unsupported Elements:',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: res.willNotRender.map((item) => Chip(
                      label: Text(item, style: const TextStyle(fontSize: 11)),
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Retained Authored Source:',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    tooltip: 'Copy Source',
                    onPressed: () => _copyToClipboard(res.source, 'Source code copied to clipboard'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.surfaceContainerHighest),
                ),
                child: SelectableText(
                  res.source,
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(
        child: Text(
          'Failed to load retained source: ${err.toString()}',
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    );
  }

  Widget _buildVersionSelector() {
    final maxVer = _currentDoc.currentVer;
    if (maxVer == null || maxVer <= 1) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final items = <DropdownMenuItem<int>>[
      DropdownMenuItem(
        value: 0,
        child: Text('Latest Version (v$maxVer)'),
      ),
    ];
    for (int i = maxVer; i >= 1; i--) {
      items.add(DropdownMenuItem(
        value: i,
        child: Text('Version v$i'),
      ));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.history_toggle_off, color: theme.colorScheme.onSurfaceVariant, size: 20),
          const SizedBox(width: 8),
          Text(
            'Viewing Version:',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedVersion,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
              ),
              items: items,
              onChanged: (val) {
                if (val == null) return;
                setState(() {
                  _selectedVersion = val;
                });
                _reloadWebview();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoricalVersionBanner() {
    if (_selectedVersion == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Viewing historical version v$_selectedVersion. This is not the live version.',
              style: TextStyle(
                color: theme.colorScheme.onErrorContainer,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _updatingProperties ? null : () => _restoreVersionConfirm(_selectedVersion),
            icon: const Icon(Icons.settings_backup_restore, size: 16),
            label: const Text('Restore', style: TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restoreVersionConfirm(int version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Restore'),
        content: Text('Are you sure you want to restore the document to version v$version? This will create a new version of the document matching version v$version.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
            ),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() {
        _updatingProperties = true;
      });

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Document successfully restored to version v$version (new version v$newVer).'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        setState(() {
          _updatingProperties = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Restore failed: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _toggleVisibility() async {
    final nextVisibility = _currentDoc.visibility == 'public' ? 'private' : 'public';
    setState(() {
      _updatingProperties = true;
    });

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Visibility updated to: ${nextVisibility.toUpperCase()}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      setState(() {
        _updatingProperties = false;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update visibility: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _showEditSlugDialog() async {
    final controller = TextEditingController(text: _currentDoc.slug ?? '');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Document Slug'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Specify a unique URL-friendly slug. Leave empty to clear the slug.',
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g. my-cool-document',
                labelText: 'Slug',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.amber.shade400),
              ),
              child: const Text(
                'Note: Slugs are retired permanently when cleared or changed, making the old slug return 410 Gone.',
                style: TextStyle(fontSize: 11, color: Colors.black87),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final newSlug = controller.text.trim();
      setState(() {
        _updatingProperties = true;
      });

      try {
        final updated = await ref
            .read(documentsListProvider.notifier)
            .updateSlug(_currentDoc.publicId, newSlug);

        setState(() {
          _currentDoc = updated;
          _updatingProperties = false;
        });

        await _reloadWebview();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newSlug.isEmpty
                ? 'Slug cleared successfully (old slug retired)'
                : 'Slug updated to: $newSlug'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        setState(() {
          _updatingProperties = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update slug: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _showEditTagsDialog() async {
    final controller = TextEditingController(text: _currentDoc.tags.join(', '));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Document Tags'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter tags separated by commas:'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g. guide, tutorial, slop',
                labelText: 'Tags',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final tagsInput = controller.text;
      final tagsList = tagsInput
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      setState(() {
        _updatingProperties = true;
      });

      try {
        final updated = await ref
            .read(documentsListProvider.notifier)
            .updateTags(_currentDoc.publicId, tagsList);

        setState(() {
          _currentDoc = updated;
          _updatingProperties = false;
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tags updated successfully'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        setState(() {
          _updatingProperties = false;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update tags: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildFooterChip(String label) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
