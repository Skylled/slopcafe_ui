import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Pull-to-refresh for an embedded [WebViewWidget].
///
/// A bare WebView owns its own native vertical scrolling, so it never emits the
/// Flutter [ScrollNotification]s a [RefreshIndicator] listens for — the
/// indicator simply never fires. Wrapping the WebView in a
/// [SingleChildScrollView] "fixes" the notifications but breaks the WebView's
/// internal scroll height and modal/overlay positioning, so that path is a
/// dead end.
///
/// The workaround is a custom [VerticalDragGestureRecognizer] that rides
/// alongside the WebView's native scrolling. It reads the WebView's native
/// scroll offset and, when the user drags down while already pinned to the top
/// of the document, synthesizes the [ScrollNotification]s (with
/// [FixedScrollMetrics]) that a real [Scrollable] would emit. The enclosing
/// [RefreshIndicator] then animates and triggers exactly as it would for a
/// normal list. Away from the top, the recognizer stays out of the way and the
/// WebView scrolls natively.
///
/// Source / prior art — preserved so this isn't "simplified" back into a broken
/// SingleChildScrollView wrapper by a future change:
///   - Reference implementation: https://github.com/cefaci/flutter_web_refresh
///     (the `DragGesturePullToRefresh` recognizer; tested against
///     webview_flutter 4.4.2, working here on 4.9.0).
///   - Root issue & discussion: https://github.com/flutter/flutter/issues/39389
///     ("Pull to refresh in WebView") and the related rejectGesture trick.
///
/// No JavaScript injection is required, so this is compatible with the reader's
/// JavaScript-disabled WebView and its strict Content-Security-Policy.
///
/// Usage: keep one instance for the lifetime of the [State], dispose it in
/// `dispose()`, and inside the [RefreshIndicator]'s child [Builder] call
/// [attach] with the builder context + the [WebViewController], then hand
/// [asGestureRecognizers] to the [WebViewWidget]:
///
/// ```dart
/// RefreshIndicator(
///   onRefresh: _pullToRefresh.refresh,
///   child: Builder(
///     builder: (ctx) {
///       _pullToRefresh.attach(ctx, _controller);
///       return WebViewWidget(
///         controller: _controller,
///         gestureRecognizers: _pullToRefresh.asGestureRecognizers,
///       );
///     },
///   ),
/// )
/// ```
class WebViewPullToRefresh extends VerticalDragGestureRecognizer {
  WebViewPullToRefresh({
    required this.onRefresh,
    this.topThreshold = 12,
    this.dragHeightEnd = 200,
  }) {
    onStart = _handleDragStart;
    onUpdate = _handleDragUpdate;
    onEnd = _handleDragEnd;
    onCancel = _handleDragCancel;
  }

  /// Invoked when a completed pull asks for a refresh. The [RefreshIndicator]
  /// keeps spinning until the returned future completes.
  final Future<void> Function() onRefresh;

  /// Native scroll offset (px) at or below which the document counts as "at the
  /// top", so a downward drag arms the refresh instead of scrolling. A few px
  /// of slack absorbs sub-pixel rounding.
  final double topThreshold;

  /// Distance the synthesized metrics treat as a full pull. Cosmetic — it sets
  /// the drag-to-spinner ratio, mirroring a viewport height.
  final double dragHeightEnd;

  BuildContext? _context;
  WebViewController? _controller;

  bool _refreshing = false;
  bool _dragStarted = false;
  double _dragDistance = 0;

  /// Bind the recognizer to the [RefreshIndicator]'s [context] (the origin of
  /// dispatched notifications) and the WebView's [controller] (queried for the
  /// native scroll offset). Safe to call on every build.
  WebViewPullToRefresh attach(
    BuildContext context,
    WebViewController controller,
  ) {
    _context = context;
    _controller = controller;
    return this;
  }

  /// A single-element gesture set whose [Factory] always returns this instance,
  /// so the recognizer wired to the WebView is the same one [attach]ed above.
  Set<Factory<OneSequenceGestureRecognizer>> get asGestureRecognizers =>
      {Factory<OneSequenceGestureRecognizer>(() => this)};

  /// The [RefreshIndicator.onRefresh] callback. Guards against a fresh drag
  /// re-arming the indicator while a refresh is already in flight.
  Future<void> refresh() async {
    _refreshing = true;
    try {
      await onRefresh();
    } finally {
      _refreshing = false;
    }
  }

  // Always win the gesture arena so we observe the drag deltas; the native
  // WebView still receives the touch sequence and scrolls. Overriding the usual
  // rejection is the crux of the workaround (flutter/flutter#39389).
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);

  FixedScrollMetrics _metrics({
    required double minScrollExtent,
    required double pixels,
    required AxisDirection axisDirection,
  }) {
    return FixedScrollMetrics(
      minScrollExtent: minScrollExtent,
      maxScrollExtent: dragHeightEnd,
      pixels: pixels,
      viewportDimension: dragHeightEnd,
      axisDirection: axisDirection,
      devicePixelRatio: 1,
    );
  }

  void _clearDrag() {
    _dragStarted = false;
    _dragDistance = 0;
  }

  Future<void> _handleDragStart(DragStartDetails details) async {
    final controller = _controller;
    if (controller == null || _refreshing) return;

    // Native call (no JS) — works regardless of JavaScript mode.
    final scrollPos = await controller.getScrollPosition();
    // Only arm the indicator when the document is already at its top.
    if (scrollPos.dy > topThreshold) return;

    // The widget may have been torn down while awaiting the scroll position.
    final context = _context;
    if (context == null || !context.mounted) return;

    _dragStarted = true;
    _dragDistance = 0;
    ScrollStartNotification(
      metrics: _metrics(
        minScrollExtent: 0,
        pixels: 0,
        axisDirection: AxisDirection.down,
      ),
      dragDetails: details,
      context: context,
    ).dispatch(context);
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_dragStarted) return;
    final context = _context;
    if (context == null) return;

    final dy = details.delta.dy;
    _dragDistance += dy;
    ScrollUpdateNotification(
      metrics: _metrics(
        minScrollExtent: dy > 0 ? 0 : _dragDistance,
        pixels: dy > 0 ? -dy : _dragDistance,
        axisDirection:
            _dragDistance < 0 ? AxisDirection.up : AxisDirection.down,
      ),
      context: context,
      scrollDelta: -dy,
    ).dispatch(context);

    // Dragging back up past the top hands control to native scrolling.
    if (_dragDistance < 0) _clearDrag();
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!_dragStarted) return;
    final context = _context;
    if (context != null) {
      ScrollEndNotification(
        metrics: _metrics(
          minScrollExtent: 0,
          pixels: _dragDistance,
          axisDirection: AxisDirection.down,
        ),
        context: context,
      ).dispatch(context);
    }
    _clearDrag();
  }

  void _handleDragCancel() {
    if (!_dragStarted) return;
    final context = _context;
    if (context != null) {
      ScrollUpdateNotification(
        metrics: _metrics(
          minScrollExtent: 0,
          pixels: 1,
          axisDirection: AxisDirection.up,
        ),
        context: context,
        scrollDelta: 0,
      ).dispatch(context);
    }
    _clearDrag();
  }
}
