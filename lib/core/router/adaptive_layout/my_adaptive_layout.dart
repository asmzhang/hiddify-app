import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
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

  // 顺序必须和 routing_config_notifier 里 branches 的顺序严格一致（导航用 currentIndex 索引分支）。
  // 手机端与 PC 端使用同一套导航项。首页和代理页**已合并**成一页，所以只有一个「代理」入口（它兼当首页）。
  List<ShellRouteAction> _actions(Translations t, bool showProfilesAction) => [
    ShellRouteAction(Icons.public_rounded, t.pages.proxies.title),
    if (showProfilesAction) ShellRouteAction(Icons.view_list_rounded, t.pages.profiles.title),
    ShellRouteAction(Icons.alt_route_rounded, t.pages.settings.routing.title),
    ShellRouteAction(Icons.settings_rounded, t.pages.settings.title),
    ShellRouteAction(Icons.monitor_heart_rounded, t.components.stats.traffic),
    ShellRouteAction(Icons.build_rounded, t.pages.tools.title),
    ShellRouteAction(Icons.description_rounded, t.pages.logs.title),
    ShellRouteAction(Icons.info_rounded, t.pages.about.title),
  ];

  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}
