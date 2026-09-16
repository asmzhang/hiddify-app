import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/app/routing/routing_config_notifier.dart';
import 'package:hiddify/app/shell/nav_items.dart';
import 'package:hiddify/app/shell/shell_route_action.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/theme/nk_palette_preferences.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_summary.dart';
import 'package:hiddify/features/stats/widget/side_bar_stats_overview.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class MyAdaptiveLayout extends HookConsumerWidget {
  const MyAdaptiveLayout({
    super.key,
    required this.navigationShell,
    required this.isMobileBreakpoint,
    required this.showProfilesAction,
  });
  // managed by go router(Shell Route)
  final StatefulNavigationShell navigationShell;
  final bool isMobileBreakpoint;
  final bool showProfilesAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    // focus switch management
    final primaryFocusHash = useState<int?>(null);
    final navScopeNode = useFocusScopeNode();
    useEffect(() {
      bool handler(KeyEvent event) {
        final arrows = isMobileBreakpoint ? KeyboardConst.verticalArrows : KeyboardConst.horizontalArrows;
        if (!arrows.contains(event.logicalKey)) return false;
        if (event is KeyDownEvent) {
          primaryFocusHash.value = FocusManager.instance.primaryFocus.hashCode;
        } else {
          // focus node does not change => true.
          if (primaryFocusHash.value == FocusManager.instance.primaryFocus.hashCode) {
            if (branchesScope.values.any((node) => node.hasFocus)) {
              navScopeNode.requestFocus();
            } else if (navScopeNode.hasFocus) {
              branchesScope[getNameOfBranch(showProfilesAction, navigationShell.currentIndex)]?.requestFocus();
            }
          }
        }
        return true;
      }

      HardwareKeyboard.instance.addHandler(handler);
      return () {
        HardwareKeyboard.instance.removeHandler(handler);
      };
    }, [isMobileBreakpoint, showProfilesAction, navigationShell.currentIndex]);

    final actions = _actions(t, showProfilesAction);
    // 当前分支在"可见导航项"里的下标（隐藏分支如 profiles 会返回 -1 → 无高亮）。
    final navSel = navIndexForBranch(showProfilesAction, navigationShell.currentIndex);

    return Material(
      child: Scaffold(
        // 手机端：抽屉由顶级页面的汉堡键（ShellDrawerButton）打开。
        // PC 端：不使用抽屉，左侧是常驻 NavigationRail。
        key: rootDrawerScaffoldKey,
        drawer: isMobileBreakpoint
            ? FocusScope(
                node: navScopeNode,
                child: NavigationDrawer(
                  selectedIndex: navSel < 0 ? null : navSel,
                  onDestinationSelected: (index) {
                    final branch = branchIndexForNav(showProfilesAction, index);
                    if (branch >= 0) _onTap(context, branch);
                    rootDrawerScaffoldKey.currentState?.closeDrawer();
                  },
                  children: [
                    // NekoBox 复刻 · 抽屉头（main_drawer_menu.xml 的 dhead）：
                    // 深主色底 + 应用名 + 一行连接状态（"已连接 · 香港-01 · 200ms"）。
                    // 数据走 connectionSummaryProvider —— 与配置页底部状态栏同一份口径。
                    _NkDrawerHeader(t: t),
                    // NekoBox 复刻 · 抽屉按三组分段（配置组/工具组/关于），组间画分隔线。
                    ..._drawerChildren(t, showProfilesAction),
                  ],
                ),
              )
            : null,
        body: isMobileBreakpoint
            ? navigationShell
            : Row(
                children: [
                  FocusScope(
                    node: navScopeNode,
                    child: NavigationRail(
                      extended: Breakpoint(context).isDesktop(),
                      destinations: _navRailDests(actions),
                      selectedIndex: navSel < 0 ? null : navSel,
                      onDestinationSelected: (index) {
                        final branch = branchIndexForNav(showProfilesAction, index);
                        if (branch >= 0) _onTap(context, branch);
                      },
                      trailing: Breakpoint(context).isDesktop()
                          ? const Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: SizedBox(width: 220, child: SideBarStatsOverview()),
                              ),
                            )
                          : null,
                    ),
                  ),
                  Expanded(child: navigationShell),
                ],
              ),
      ),
    );
  }

  // shell route action onTap
  void _onTap(BuildContext context, int index) {
    navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex);
  }

  // NekoBox 复刻 · 抽屉分组：组与组之间画一条分隔线（对标 main_drawer_menu.xml 的三段）。
  List<Widget> _drawerChildren(Translations t, bool showProfilesAction) {
    final metas = navVisibleMetas(showProfilesAction);
    final actions = _actions(t, showProfilesAction);
    final children = <Widget>[];
    NkNavGroup? last;
    for (var i = 0; i < metas.length; i++) {
      if (last != null && metas[i].group != last) {
        children.add(const Divider(indent: 28, endIndent: 28));
      }
      last = metas[i].group;
      final e = actions[i];
      children.add(NavigationDrawerDestination(icon: Icon(e.icon), label: Text(e.title)));
    }
    return children;
  }

  // 导航项完全由 navMetas 推导（唯一数据源）；这里只取**可见**项（navVisible）。
  // 顺序/显隐/图标/标签都在 nav_items.dart 一处定义。
  List<ShellRouteAction> _actions(Translations t, bool showProfilesAction) =>
      navVisibleMetas(showProfilesAction).map((m) => ShellRouteAction(m.icon, m.label(t))).toList();

  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}

/// 抽屉头（对标 NekoBox `main_drawer_menu.xml` 的 `dhead`）：深主色底、白字，
/// 上行应用名，下行连接状态。
///
/// 放在 app 层而不是 core：它要读 feature 的连接状态（[connectionSummaryProvider]）。
/// 深主色用 `NkPalette.primaryDark`（即 NekoBox 的 `colorPrimaryDark`），
/// 与工具栏的 `colorPrimary` 拉开层次。
class _NkDrawerHeader extends ConsumerWidget {
  const _NkDrawerHeader({required this.t});

  final Translations t;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(nkPalettePreferencesProvider);
    final summary = ref.watch(connectionSummaryProvider);

    final stateText = switch (summary.state) {
      NkConnectionState.connected => t.connection.connected,
      NkConnectionState.connecting => t.connection.connecting,
      NkConnectionState.error => t.connection.disconnected,
      NkConnectionState.disconnected => t.connection.disconnected,
    };
    final line = [
      stateText,
      if (summary.nodeName != null) summary.nodeName!,
      // 延迟只在真连上时才有意义（未连接时清单里没有实测值）。
      if (summary.connected && summary.delayMs > 0) '${summary.delayMs}ms',
    ].join(' · ');

    return Container(
      width: double.infinity,
      color: palette.primaryDark,
      padding: const EdgeInsets.fromLTRB(28, 20, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Hiddify',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            line,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.white.withValues(alpha: .85), fontSize: 12),
          ),
        ],
      ),
    );
  }
}
