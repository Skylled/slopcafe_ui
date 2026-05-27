import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:intl/intl.dart';
import '../models/document.dart';
import '../core/secure_storage.dart';
import '../core/api_client.dart';
import '../providers/document_provider.dart';

enum DocumentViewMode { rendered, source, markdown }

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
    setState(() {
      _baseUrl = url;
      _isLoadingBaseUrl = false;
    });

    if (url != null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadRequest(Uri.parse('$url/d/${_currentDoc.publicId}'));
    }
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
        ? '$_baseUrl/d/by-slug/${_currentDoc.slug}'
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
        // Already handled above, but kept to satisfy complete switch
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
              // left: BorderSide(
              //   color: Theme.of(context).colorScheme.surfaceContainerHighest,
              //   width: 1.5,
              // ),
              // right: BorderSide(
              //   color: Theme.of(context).colorScheme.surfaceContainerHighest,
              //   width: 1.5,
              // ),
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
    }
  }

  Widget _buildSourceHtmlView() {
    final theme = Theme.of(context);
    final htmlAsync = ref.watch(
      documentDetailHtmlProvider(_currentDoc.publicId),
    );

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
            Expanded(
              child: Markdown(
                data: res.markdown,
                selectable: true,
                padding: const EdgeInsets.all(16),
              ),
            ),
            // Header information row at bottom of markdown tab
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
