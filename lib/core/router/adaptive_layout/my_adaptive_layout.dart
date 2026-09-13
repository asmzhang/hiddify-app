import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/core/router/adaptive_layout/nav_items.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_route_action.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/router/go_router/routing_config_notifier.dart';
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
              branchesScope[getNameOfBranch(showProfilesAction, navigationShell.currentIndex)]
                  ?.requestFocus();
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

    return Material(
      child: Scaffold(
        // 手机端：抽屉由顶级页面的汉堡键（ShellDrawerButton）打开。
        // PC 端：不使用抽屉，左侧是常驻 NavigationRail。
        key: rootDrawerScaffoldKey,
        drawer: isMobileBreakpoint
            ? FocusScope(
                node: navScopeNode,
                child: NavigationDrawer(
                  selectedIndex: navigationShell.currentIndex,
                  onDestinationSelected: (index) {
                    _onTap(context, index);
                    rootDrawerScaffoldKey.currentState?.closeDrawer();
                  },
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
                      child: Text(
                        'Hiddify',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    ...actions.map(
                      (e) => NavigationDrawerDestination(icon: Icon(e.icon), label: Text(e.title)),
                    ),
                    const Divider(indent: 28, endIndent: 28),
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
                      selectedIndex: navigationShell.currentIndex,
                      onDestinationSelected: (index) => _onTap(context, index),
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

  // 导航项完全由 navMetas 推导（唯一数据源），这里只做 ShellRouteAction 适配。
  // 顺序/显隐/图标/标签都在 nav_items.dart 一处定义。
  List<ShellRouteAction> _actions(Translations t, bool showProfilesAction) =>
      navMetas(showProfilesAction).map((m) => ShellRouteAction(m.icon, m.label(t))).toList();

  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}
