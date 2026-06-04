import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api_client.dart';
import '../core/design/tokens.dart';
import '../core/design/typography.dart';
import '../widgets/toast.dart';
import 'library_screen.dart';
import 'search_screen.dart';
import 'operate_screen.dart';
import 'settings_screen.dart';

/// The three-tab Craft app shell: an [IndexedStack] of Library / Search /
/// Operate under a floating pill tab bar, with global 401 interception that
/// surfaces the Settings screen (mirrors the old `MainNavigationShell`).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _index = 0;
  bool _settingsOpen = false;

  void _goToSearch() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    // 401 interception: when the operator token is rejected, push Settings.
    ref.listen<ApiConnectionState>(connectionStateProvider, (prev, next) {
      if (next.status == ConnectionStatus.unauthorized && !_settingsOpen) {
        _settingsOpen = true;
        showToast(
          context,
          next.errorMessage ?? 'Operator token rejected',
          danger: true,
        );
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
            .whenComplete(() => _settingsOpen = false);
      }
    });

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: [
              LibraryScreen(onOpenSearch: _goToSearch),
              const SearchScreen(),
              const OperateScreen(),
            ],
          ),
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

class _FloatingTabBar extends StatelessWidget {
  const _FloatingTabBar({required this.index, required this.onSelect});
  final int index;
  final ValueChanged<int> onSelect;

  static const _tabs = [
    (Icons.coffee_outlined, 'Library'),
    (Icons.search, 'Search'),
    (Icons.notifications_outlined, 'Operate'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
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
                  for (var i = 0; i < _tabs.length; i++)
                    _TabButton(
                      icon: _tabs[i].$1,
                      label: _tabs[i].$2,
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
    return GestureDetector(
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
                style: AppText.title.copyWith(fontSize: 14, color: c.onAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
