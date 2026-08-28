import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/deep_link.dart';
import '../core/design/layout.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../l10n/l10n.dart';
import '../providers/deep_link_provider.dart';
import '../providers/document_provider.dart';
import '../providers/instances_provider.dart';
import '../providers/refresh.dart';
import '../widgets/cafe_logo.dart';
import '../widgets/instance_switcher.dart';
import '../widgets/press_card.dart';
import '../widgets/toast.dart';
import 'library_screen.dart';
import 'reader_screen.dart';
import 'search_screen.dart';
import 'settings_screen.dart';

/// The two-tab Cortado app shell, adaptive to the window width:
///
/// * **Compact** (phones): an [IndexedStack] of Library / Search
///   under a floating pill tab bar (mirrors the old `MainNavigationShell`).
/// * **Expanded** (tablets / desktop, `>= AppLayout.railBreakpoint`): the same
///   stack beside a left side rail carrying the tabs plus desktop affordances —
///   an explicit refresh action (pull-to-refresh has no mouse gesture) and a
///   Settings shortcut.
///
/// Both idioms share the global 401 interception that surfaces Settings, and
/// both reach the instance quick switcher without a detour through Settings:
/// the rail's logo opens it here, and the Operate header's chip opens it on
/// phones (`operate_screen.dart`).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _settingsOpen = false;

  /// The inbound web-link subscription — see [_openDeepLink].
  StreamSubscription<DeepLinkTarget>? _linkSub;

  @override
  void initState() {
    super.initState();
    // Subscribing from the shell rather than from the app root is deliberate.
    // Resolving a link needs a Base URL and an operator token, and the shell is
    // exactly the widget that does not exist until [RootGate] has both — so a
    // link that arrives on an unconfigured install waits for setup instead of
    // failing against a deployment the app has not been pointed at yet. Nothing
    // is lost in that wait: the platform side holds the launching link until
    // its first subscriber attaches (see [inboundDeepLinksProvider]).
    _linkSub = ref.read(inboundDeepLinksProvider).listen(_openDeepLink);
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  /// Open the document an inbound web link addressed.
  ///
  /// The link carries a raw name, so it takes the same resolution path an
  /// in-WebView tap and a link-graph row take — which also means a **private**
  /// target opens rather than dead-ending, the one thing a browser could never
  /// have done with this URL.
  ///
  /// The Reader is pushed on top of whatever is on screen rather than replacing
  /// it: the operator was doing something when the link arrived, and a link tap
  /// is an excursion they should be able to back out of. A `/d/` link always
  /// resolves (to a placeholder at worst), so the toast below is in practice
  /// the `/s/` case — a slug nothing answers to, which is a fact about the
  /// corpus and worth saying out loud rather than swallowing into a dead tap.
  Future<void> _openDeepLink(DeepLinkTarget target) async {
    await _switchToLinkHostIfNeeded();
    if (!mounted) return;

    final doc = await ref
        .read(documentsListProvider.notifier)
        .resolveListing(publicId: target.publicId, slug: target.slug);

    if (!mounted) return;
    if (doc == null) {
      showToast(context, context.l10n.deepLinkUnresolved, danger: true);
      return;
    }

    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(doc: doc)));
  }

  /// Point the app at the instance that can actually answer for an inbound link
  /// before resolving it.
  ///
  /// Only one host's links reach this app at all — Android decides that from the
  /// manifest filter, long before any Dart runs, which is why [kDeepLinkHost] is
  /// a build-time constant (see `deep_link.dart`). So the question is never
  /// *which* host the link named; it is whether the deployment currently active
  /// is the one serving that host.
  ///
  /// Once an operator keeps a fork alongside upstream, the answer is often no,
  /// and resolving anyway looks exactly like a broken link: the public id is
  /// meaningless to the fork, so a real, live document reports as unresolvable.
  /// Worse, ids are per-deployment, so a collision would open the *wrong*
  /// document under the right name. Switching first makes a tapped link mean the
  /// same thing whichever instance the operator happened to leave active.
  ///
  /// A no-op when the active instance already serves that host, or when no saved
  /// instance does — in the latter case the link falls through to the active
  /// deployment and the usual unresolved toast, which is the pre-existing
  /// behaviour.
  Future<void> _switchToLinkHostIfNeeded() async {
    final set = ref.read(instancesProvider).value;
    if (set == null) return;
    final target = set.byHost(kDeepLinkHost);
    if (target == null || target.id == set.activeId) return;

    await ref.read(instancesProvider.notifier).switchTo(target.id);
    if (!mounted) return;
    showToast(context, context.l10n.deepLinkSwitchedInstance(target.label));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // 401 interception: when the operator token is rejected, push Settings.
    ref.listen<ApiConnectionState>(connectionStateProvider, (prev, next) {
      if (next.status == ConnectionStatus.unauthorized && !_settingsOpen) {
        _settingsOpen = true;
        showToast(
          context,
          next.errorMessage ?? context.l10n.tokenRejectedDetail,
          danger: true,
        );
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
            .whenComplete(() => _settingsOpen = false);
      }
    });

    final content = IndexedStack(
      index: _index,
      children: const [LibraryScreen(), SearchScreen()],
    );

    if (context.isExpandedLayout) {
      return Scaffold(
        backgroundColor: c.bg,
        body: Row(
          children: [
            _SideRail(
              index: _index,
              onSelect: (i) => setState(() => _index = i),
              onOpenSettings: _openSettings,
            ),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          content,
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _FloatingTabBar(
              index: _index,
              onSelect: (i) => setState(() => _index = i),
            ),
          ),
        ],
      ),
    );
  }
}

/// Icons shared by both navigation idioms, in tab order.
const _tabIcons = [
  Icons.coffee_outlined,
  Icons.search,
];

List<String> _tabLabels(BuildContext context) {
  final l10n = context.l10n;
  return [l10n.tabLibrary, l10n.tabSearch];
}

// ============================================================
// Expanded idiom: side navigation rail
// ============================================================

class _SideRail extends ConsumerStatefulWidget {
  const _SideRail({
    required this.index,
    required this.onSelect,
    required this.onOpenSettings,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<_SideRail> createState() => _SideRailState();
}

class _SideRailState extends ConsumerState<_SideRail> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    try {
      await refreshFleetData(ref);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pad = MediaQuery.paddingOf(context);
    final labels = _tabLabels(context);
    final active = ref.watch(activeInstanceProvider);

    return Container(
      width: AppLayout.railWidth,
      padding: EdgeInsets.only(top: pad.top + 18, bottom: pad.bottom + 14),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(right: BorderSide(color: c.line)),
      ),
      child: Column(
        children: [
          // The logo doubles as the desktop quick switcher: it is the one
          // element of the rail that was pure decoration, and it already reads
          // as "which Slopcafe is this". The active instance's name sits under
          // it so the answer is visible without opening anything.
          Tooltip(
            message: context.l10n.instanceSwitcherTitle,
            child: Tappable(
              onTap: () => showInstanceSwitcher(context),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    const CafeLogo(size: 26),
                    if (active != null) ...[
                      const SizedBox(height: 5),
                      Text(
                        active.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: AppText.label.copyWith(color: c.textDim),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          for (var i = 0; i < _tabIcons.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _RailTab(
                icon: _tabIcons[i],
                label: labels[i],
                active: widget.index == i,
                onTap: () => widget.onSelect(i),
              ),
            ),
          const Spacer(),
          _RailAction(
            icon: Icons.refresh,
            tooltip: context.l10n.refresh,
            busy: _refreshing,
            onTap: _refresh,
          ),
          const SizedBox(height: 4),
          _RailAction(
            icon: Icons.settings_outlined,
            tooltip: context.l10n.connectionTitle,
            onTap: widget.onOpenSettings,
          ),
        ],
      ),
    );
  }
}

class _RailTab extends StatelessWidget {
  const _RailTab({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                width: 52,
                height: 34,
                decoration: BoxDecoration(
                  color: active ? c.clay : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Icon(
                  icon,
                  size: 19,
                  color: active ? c.onAccent : c.textFaint,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: AppText.title.copyWith(
                  fontSize: 11,
                  color: active ? c.clayD : c.textFaint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailAction extends StatelessWidget {
  const _RailAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 40,
            height: 40,
            child: busy
                ? Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.clay,
                      ),
                    ),
                  )
                : Icon(icon, size: 19, color: c.textDim),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Compact idiom: floating pill tab bar
// ============================================================

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final labels = _tabLabels(context);
    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        bottom: 26 + MediaQuery.paddingOf(context).bottom * 0.0,
      ),
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: 0.86),
                border: Border.all(color: c.line),
                borderRadius: BorderRadius.circular(AppRadii.pill),
                boxShadow: c.shadowLg,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < _tabIcons.length; i++)
                    _TabButton(
                      icon: _tabIcons[i],
                      label: labels[i],
                      active: index == i,
                      onTap: () => onSelect(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(
            horizontal: active ? 18 : 14,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: active ? c.clay : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 19, color: active ? c.onAccent : c.textFaint),
              if (active) ...[
                const SizedBox(width: 7),
                Text(
                  label,
                  style: AppText.title.copyWith(
                    fontSize: 14,
                    color: c.onAccent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
