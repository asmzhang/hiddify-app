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
import 'package:hiddify/utils/utils.dart';
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
        // 全局 drawer key 只属于手机形态。桌面过渡期可能同时保留两棵 shell，
        // 给无 drawer 的桌面 Scaffold 也挂同一个 GlobalKey 会触发重复 key。
        key: isMobileBreakpoint ? rootDrawerScaffoldKey : null,
        drawer: isMobileBreakpoint
            ? FocusScope(
                node: navScopeNode,
                child: NavigationDrawer(
                  // NekoBox 复刻 · 选中索引映射：faq 动作项插在关于之前，其后目标 +1。
                  selectedIndex: nkDrawerSelectedIndex(showProfilesAction, navSel),
                  onDestinationSelected: (index) {
                    // NekoBox 复刻 · nav_faq 动作项（`MainActivity.kt:343` →
                    // launchCustomTab）：文档站外部打开，不是路由分支。位置 =
                    // 关于**之前**（main_drawer_menu.xml 组 3 顺序 [faq, about]）。
                    if (index == nkFaqDestinationIndex(showProfilesAction)) {
                      rootDrawerScaffoldKey.currentState?.closeDrawer();
                      UriUtils.tryLaunch(Uri.parse(Constants.faqUrl));
                      return;
                    }
                    // faq 不占分支：其后目标索引回退 1 映射到可见 metas。
                    final faqPos = nkFaqDestinationIndex(showProfilesAction);
                    final metaIndex = index > faqPos ? index - 1 : index;
                    final branch = branchIndexForNav(showProfilesAction, metaIndex);
                    if (branch >= 0) _onTap(context, branch);
                    rootDrawerScaffoldKey.currentState?.closeDrawer();
                  },
                  // NekoBox 复刻 · 抽屉**无头**：规格实证 NekoBox NavigationView
                  // 只有 app:menu，无 headerLayout（旧「dhead」引用不存在，
                  // 2026-09-22）——直接渲染 nkDrawerEntries（三组 + 分隔线）。
                  children: _drawerChildren(t, showProfilesAction),
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

  // NekoBox 复刻 · 抽屉条目直接渲染 nkDrawerEntries（唯一数据源：三组分段 +
  // 分隔线 + faq 在关于之前）。Rail（桌面）不走这里，仍用 _actions 平铺。
  List<Widget> _drawerChildren(Translations t, bool showProfilesAction) =>
      nkDrawerEntries(showProfilesAction)
          .map(
            (e) => switch (e) {
              NkNavEntry(:final meta) =>
                NavigationDrawerDestination(icon: Icon(meta.icon), label: Text(meta.label(t))),
              NkFaqEntry(:final label, :final icon) =>
                NavigationDrawerDestination(icon: Icon(icon), label: Text(label(t))),
              NkDividerEntry() => const Divider(indent: 28, endIndent: 28),
            },
          )
          .toList();

  // 导航项完全由 navMetas 推导（唯一数据源）；这里只取**可见**项（navVisible）。
  // 顺序/显隐/图标/标签都在 nav_items.dart 一处定义。
  List<ShellRouteAction> _actions(Translations t, bool showProfilesAction) =>
      navVisibleMetas(showProfilesAction).map((m) => ShellRouteAction(m.icon, m.label(t))).toList();

  List<NavigationRailDestination> _navRailDests(List<ShellRouteAction> actions) =>
      actions.map((e) => NavigationRailDestination(icon: Icon(e.icon), label: Text(e.title))).toList();
}

/// 退役实现（2026-09-22）：深色抽屉头（应用名 + 连接状态行）。
///
/// 规格复核证明 NekoBox 抽屉**无头**：layout_main.xml 的 NavigationView 只有
/// `app:menu`、无 headerLayout，Kotlin 无 addHeaderView，此前引用的「dhead」
/// 不存在 —— 按 1:1 定案从抽屉移除；按「退役不删码」保留本类供回滚参考。
/// 连接状态仍由配置页底部状态栏承载（归一原则：一个数据源一个入口）。
class NkDrawerHeaderLegacy extends ConsumerWidget {
  const NkDrawerHeaderLegacy({required this.t});

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
