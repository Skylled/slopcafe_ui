import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../api/api.dart';
import '../core/api_client.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../core/publication.dart';
import '../core/review.dart';
import '../core/secure_storage.dart';
import '../l10n/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/document_provider.dart';
import '../providers/review_provider.dart';
import '../widgets/app_button.dart';
import '../widgets/press_card.dart';
import '../widgets/sheets.dart';
import '../widgets/toast.dart';
import 'reader_screen.dart';

/// Side-by-side review of a gated document: what readers are served today
/// against what they would be served if the operator approved.
///
/// **Two WebViews, not one.** The screen holds a live controller per side and
/// swaps which one is painted, rather than driving a single WebView back and
/// forth. That costs a second platform view for the lifetime of one pushed
/// route, and buys three things a single-WebView tab switcher cannot have:
///
///  1. **Each pane keeps its scroll offset.** The entire point of the switcher
///     is flipping between the same passage in two versions. A shared WebView
///     re-renders on every flip and lands back at the top, which makes the one
///     interaction this screen exists for useless past the first screenful.
///  2. **A flip costs nothing.** No request, no `loadHtmlString`, no re-layout
///     of untrusted HTML — just a change of painted child. Comparing means
///     flipping repeatedly and quickly, and a reload's worth of latency on each
///     one reads as the app stuttering.
///  3. **Failures stay local.** A version whose bytes are gone leaves its own
///     pane showing the error while the other still renders, so the operator can
///     see what *is* live even when the head won't load.
///
/// The controller owns the underlying platform WebView — `WebViewWidget` only
/// displays it — so both sides load concurrently on open regardless of which is
/// painted, and `IndexedStack` (which lays out every child, unlike `Offstage`)
/// keeps the hidden one alive and warm.
///
/// **Both panes read the same route shape**, `/d/:id/v/:n/raw`, including the
/// live side, which `/d/:id/raw` would also have served. That is deliberate:
/// comparing a pinned version read against a serve-the-published-version read
/// would compare two code paths, and any difference in the rendered output
/// would be ambiguous between "the content changed" and "the route differs".
/// Pinning both makes every difference on screen attributable to the content.
///
/// **Nothing here touches the offline body cache.** `saveCachedHtml` evicts
/// every other cached version of a document before writing, so caching either
/// pane would evict the Reader's cached body — and the two panes would evict
/// each other on every load. This screen is strictly read-only against the
/// cache.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.doc});

  /// The queued document. Both `publishedVer` and `currentVer` are non-null on
  /// anything [DocumentReview.isAwaitingReview] admits, which is the only way
  /// into this screen.
  final DocumentListing doc;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

enum _PaneStatus { loading, ready, failed }

/// One side of the comparison: its version, its WebView, and how that load went.
class _Pane {
  _Pane({required this.side, required this.version});

  final ReviewSide side;
  final int version;

  WebViewController? controller;
  _PaneStatus status = _PaneStatus.loading;

  /// Armed around each programmatic `loadHtmlString(..., baseUrl:)`. On macOS,
  /// WKWebView reports that synthetic load to the navigation delegate as a
  /// request for the bare base URL; without letting it through, the pane
  /// intercepts its own content load and stays blank. Same mechanism as the
  /// Reader's flag, per pane — the two WebViews load independently, so one
  /// shared flag would let whichever load finished first disarm the other's.
  bool expectSyntheticBaseLoad = false;
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  String? _baseUrl;
  bool _isLoadingBaseUrl = true;
  bool _publishing = false;

  late DocumentListing _currentDoc;
  late final _Pane _live;
  late final _Pane _latest;

  ReviewSide _side = ReviewSide.live;

  /// A version the byte path reported as current that is *ahead* of the version
  /// under review — i.e. somebody wrote to this document while it was open.
  int? _headMovedTo;

  @override
  void initState() {
    super.initState();
    _currentDoc = widget.doc;
    // Non-null by the queue's admission rule; the fallbacks keep a
    // hand-constructed instance from crashing rather than papering over a bug.
    _live = _Pane(
      side: ReviewSide.live,
      version: _currentDoc.versionFor(ReviewSide.live) ?? 1,
    );
    _latest = _Pane(
      side: ReviewSide.latest,
      version: _currentDoc.versionFor(ReviewSide.latest) ?? 1,
    );
    _init();
  }

  Iterable<_Pane> get _panes => [_live, _latest];

  _Pane _paneFor(ReviewSide side) => side == ReviewSide.live ? _live : _latest;

  Future<void> _init() async {
    final url = await SecureStorageService.instance.getBaseUrl();
    if (!mounted) return;
    _baseUrl = url;

    if (url != null) {
      for (final pane in _panes) {
        pane.controller = _buildController(pane);
      }
    }

    setState(() => _isLoadingBaseUrl = false);

    if (url == null) return;
    // Both sides start together. The operator can read whichever lands first,
    // and the flip is instant once the other arrives.
    await Future.wait(_panes.map(_loadPane));
  }

  WebViewController _buildController(_Pane pane) {
    return WebViewController()
      // Identical security posture to the Reader: document HTML is untrusted
      // content authored by agents, so no JavaScript and a strict injected CSP.
      // A review surface is the last place to relax that — it is where an
      // operator is deciding to put those bytes in front of the public.
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            if (url == 'about:blank' || url.startsWith('data:')) {
              return NavigationDecision.navigate;
            }
            if (pane.expectSyntheticBaseLoad && _isBareBaseUrl(url)) {
              pane.expectSyntheticBaseLoad = false;
              return NavigationDecision.navigate;
            }
            // In-page anchors scroll natively — they move within the version
            // being reviewed, which is exactly what this screen is for.
            if (_isSameDocumentFragment(url)) {
              return NavigationDecision.navigate;
            }
            // Everything else is refused. Following a link would replace this
            // pane's content and destroy the comparison the operator set up,
            // and there is no second surface here to open it into. The Reader
            // owns link traversal; this screen owns one document's two versions.
            _reportInertLink();
            return NavigationDecision.prevent;
          },
        ),
      );
  }

  void _reportInertLink() {
    if (!mounted) return;
    showToast(context, context.l10n.reviewLinksInert);
  }

  bool _isBareBaseUrl(String url) {
    final base = _baseUrl;
    if (base == null) return false;
    String norm(String u) => u.endsWith('/') ? u.substring(0, u.length - 1) : u;
    return norm(url) == norm(base);
  }

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

  /// Fetch one version's rendered bytes and paint them into that pane's WebView.
  ///
  /// No `If-None-Match` and no cache write: the panes are a live comparison, and
  /// the body cache holds one version per document by construction (see the
  /// class doc).
  Future<void> _loadPane(_Pane pane) async {
    final controller = pane.controller;
    if (controller == null || _baseUrl == null) return;
    final l10n = context.l10n;

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.get(
        '/d/${_currentDoc.publicId}/v/${pane.version}/raw',
        options: Options(validateStatus: (status) => status == 200),
      );

      _noteHeadMoved(response.headers);

      final html = _injectCspMeta(response.data as String);
      pane.expectSyntheticBaseLoad = true;
      await controller.loadHtmlString(html, baseUrl: _baseUrl);
      if (!mounted) return;
      setState(() => pane.status = _PaneStatus.ready);
    } catch (e) {
      if (!mounted) return;
      // The failure is rendered *into* the pane rather than swapping the
      // WebView out for an error widget: the platform view stays alive, the
      // other pane is untouched, and a retry has somewhere to paint.
      await controller.loadHtmlString(
        _buildErrorHtml(
          l10n.reviewPaneLoadFailed(pane.version),
          ApiError.describe(e),
        ),
      );
      if (!mounted) return;
      setState(() => pane.status = _PaneStatus.failed);
    }
  }

  /// Notice a version written while this review was open.
  ///
  /// `x-doc-current-version` rides these responses, so a write that lands mid-
  /// review is visible without polling. Only a version strictly ahead of the one
  /// under review counts.
  ///
  /// [resolveCurrentVersion] falls back to the ETag when the header is absent,
  /// and on a pinned version route that ETag names the pinned version — but it
  /// can never trip this check: a pane is pinned to `published_ver` or
  /// `current_ver`, both of which are ≤ the head, so the fallback can only ever
  /// produce a number at or behind what we already hold. The header is the only
  /// thing that can push this past the guard, which is the intent.
  void _noteHeadMoved(Headers headers) {
    final current = resolveCurrentVersion(headers);
    if (current == null || current <= _latest.version) return;
    if (!mounted || _headMovedTo == current) return;
    setState(() => _headMovedTo = current);
  }

  String _injectCspMeta(String html) {
    const csp =
        "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; img-src data:; style-src 'unsafe-inline' data:; font-src data:; base-uri 'none'; form-action 'none'\">";
    if (html.contains('<head>')) {
      return html.replaceFirst('<head>', '<head>\n$csp');
    }
    return '$csp\n$html';
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
          h1 { font-size: 19px; margin: 0 0 10px; color: ${hex(c.text)}; }
          p { font-size: 14px; line-height: 1.5; margin: 0; }
        </style>
      </head>
      <body><div class="container"><h1>$title</h1><p>$message</p></div></body>
      </html>
    ''';
  }

  // ----------------------------------------------------------------
  // Approve
  // ----------------------------------------------------------------

  /// Publish the version this screen actually rendered.
  ///
  /// The version number is the one the latest pane was pinned to when the screen
  /// opened, **not** "whatever is current now". That distinction is the whole
  /// safety property of reviewing: if an agent writes v9 while the operator is
  /// reading v8, approving must still publish v8 — the bytes they read — and the
  /// banner tells them v9 exists so they can come back for it. Publishing "the
  /// latest" would put bytes nobody reviewed in front of the public, which is
  /// the exact failure the gate was added to prevent.
  Future<void> _publish() async {
    final l10n = context.l10n;
    final version = _latest.version;

    final confirmed = await showConfirmSheet(
      context,
      title: l10n.publishVersionTitle(version),
      cta: l10n.publishAction,
      danger: false,
      body: Text(l10n.publishVersionBody(version)),
    );
    if (!confirmed || !mounted) return;

    setState(() => _publishing = true);
    try {
      final promoted = await ref
          .read(documentsListProvider.notifier)
          .promoteVersion(_currentDoc.publicId, version);

      if (!mounted) return;
      // The response is canonical for `published_ver`; the queue re-evaluates
      // the row against it rather than assuming the request's number landed.
      ref
          .read(reviewQueueProvider.notifier)
          .resolve(_currentDoc.publicId, promoted.publishedVer);

      showToast(context, l10n.publishedToast(promoted.publishedVer));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _publishing = false);
      final failed = ApiError.fromException(e).code == ErrorCode.versionNotFound
          ? l10n.versionNotFoundToast
          : l10n.publishFailedToast;
      showToast(context, failed, danger: true);
    }
  }

  void _openInReader() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: _currentDoc)));
  }

  // ----------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

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
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                l10n.noBaseUrlConfigured,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: c.textDim),
              ),
            ),
          ),
        ),
      );
    }

    final topPad = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: c.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final chromeGutter = AppLayout.gutterFor(
            w,
            max: AppLayout.readerMax,
            min: 14,
          );
          final bodyGutter = AppLayout.gutterFor(
            w,
            max: AppLayout.readerMax,
            min: 0,
          );

          return Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  chromeGutter,
                  topPad + 10,
                  chromeGutter,
                  0,
                ),
                child: _buildChrome(c, l10n),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: bodyGutter),
                  child: _buildPanes(c),
                ),
              ),
              _buildApproveBar(c, l10n, chromeGutter),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChrome(AppColors c, AppLocalizations l10n) {
    final comparison = _currentDoc.sourceComparison;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _CircleAction(
              icon: Icons.chevron_left,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.reviewEyebrow.toUpperCase(),
                    style: AppText.label.copyWith(
                      fontSize: 11,
                      letterSpacing: 0.8,
                      color: c.textFaint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currentDoc.title ?? l10n.untitled,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleSerif.copyWith(
                      fontSize: 20,
                      color: c.text,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _CircleAction(
              icon: Icons.article_outlined,
              onTap: _openInReader,
              tooltip: l10n.reviewOpenInReader,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SideSwitcher(
          value: _side,
          live: _live.version,
          latest: _latest.version,
          onChanged: (side) {
            if (side == _side) return;
            // The whole flip: repaint a different child of the IndexedStack.
            // No fetch, no reload, no scroll reset in either pane.
            setState(() => _side = side);
          },
        ),
        // A write that landed while this screen was open. Stated rather than
        // silently absorbed: the operator is about to approve a version that is
        // no longer the head, and that is a legitimate thing to do — but only
        // knowingly.
        if (_headMovedTo != null) ...[
          const SizedBox(height: 10),
          _Note(
            icon: Icons.bolt_outlined,
            text: l10n.reviewHeadMovedNote(_headMovedTo!, _latest.version),
          ),
        ],
        // Identical source hashes: approving moves the pointer without changing
        // what the source says. Worth surfacing — it is the one case where the
        // operator can approve without reading closely.
        if (comparison == SourceComparison.identical) ...[
          const SizedBox(height: 10),
          _Note(
            icon: Icons.difference_outlined,
            text: l10n.reviewIdenticalSourceNote,
            tone: _NoteTone.neutral,
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  /// The two panes. `IndexedStack` lays out both children and paints one, so the
  /// hidden WebView stays mounted, loaded and scrolled where the operator left
  /// it. Children are built from `ReviewSide.values` and indexed by lookup, so
  /// nothing depends on the enum's declaration order.
  Widget _buildPanes(AppColors c) {
    return IndexedStack(
      index: ReviewSide.values.indexOf(_side),
      sizing: StackFit.expand,
      children: [
        for (final side in ReviewSide.values) _buildPane(c, _paneFor(side)),
      ],
    );
  }

  Widget _buildPane(AppColors c, _Pane pane) {
    final controller = pane.controller;
    if (controller == null) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: controller)),
        // Painted over the WebView rather than replacing it, so the platform
        // view is never torn down and rebuilt between loading and ready.
        if (pane.status == _PaneStatus.loading)
          Positioned.fill(
            child: ColoredBox(
              color: c.bg,
              child: Center(child: CircularProgressIndicator(color: c.clay)),
            ),
          ),
      ],
    );
  }

  Widget _buildApproveBar(AppColors c, AppLocalizations l10n, double gutter) {
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    // Approving is only offered once the bytes it approves have actually
    // rendered. Publishing a version whose pane failed to load would be
    // approving something unread, which is precisely what the gate exists to
    // stop.
    final canPublish = _latest.status == _PaneStatus.ready && !_publishing;

    return Container(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, bottomPad + 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.public, size: 15, color: c.textFaint),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  l10n.reviewApproveHint(_live.version, _latest.version),
                  style: AppText.small.copyWith(color: c.textFaint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppButton(
            _publishing
                ? l10n.publishAction
                : l10n.reviewPublishCta(_latest.version),
            icon: Icons.check,
            expand: true,
            onPressed: canPublish ? _publish : null,
          ),
        ],
      ),
    );
  }
}

/// The Live / Latest tab switcher — the same segmented idiom as the change
/// feed's window selector and Search's mode selector, with each segment naming
/// the concrete version it paints.
class _SideSwitcher extends StatelessWidget {
  const _SideSwitcher({
    required this.value,
    required this.live,
    required this.latest,
    required this.onChanged,
  });

  final ReviewSide value;
  final int live;
  final int latest;
  final ValueChanged<ReviewSide> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final l10n = context.l10n;

    Widget seg(ReviewSide side) {
      final active = side == value;
      final label = switch (side) {
        ReviewSide.live => l10n.reviewTabLive(live),
        ReviewSide.latest => l10n.reviewTabLatest(latest),
      };
      return Expanded(
        child: Tappable(
          onTap: () => onChanged(side),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: active ? c.clay : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  side == ReviewSide.live
                      ? Icons.public
                      : Icons.pending_outlined,
                  size: 14,
                  color: active ? c.surface : c.textDim,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.small.copyWith(
                      fontWeight: FontWeight.w700,
                      color: active ? c.surface : c.textDim,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        border: Border.all(color: c.lineSoft),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Row(children: [for (final s in ReviewSide.values) seg(s)]),
    );
  }
}

enum _NoteTone { honey, neutral }

/// A compact inline note in the honey caution idiom used by the Reader's
/// served-version banner and the change feed's standing note.
class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.text,
    this.tone = _NoteTone.honey,
  });

  final IconData icon;
  final String text;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final honey = tone == _NoteTone.honey;
    final fg = honey ? c.honeyD : c.textDim;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: honey ? c.honey.withValues(alpha: 0.12) : c.surface2,
        border: Border.all(
          color: honey ? c.honey.withValues(alpha: 0.30) : c.lineSoft,
        ),
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: AppText.small.copyWith(
                fontWeight: FontWeight.w600,
                color: fg,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular chrome button matching the Reader's back/more affordances.
class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final button = DecoratedBox(
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
            child: Icon(icon, size: 20, color: c.clayD),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
