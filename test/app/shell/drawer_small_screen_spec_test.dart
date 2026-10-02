// ⑨ 终验收 · 小屏形态（<600dp）——主壳 NavigationDrawer widget 级回归。
// HANDOVER §7「仍未见过小屏」四处之一；抽屉已有数据级测试（同目录
// drawer_entries_test.dart：nkDrawerEntries 结构/词表/图标），本文件补
// **真 MyAdaptiveLayout mobile 断点**的 widget 级：
//   StatefulShellRoute.indexedStack 搭 8 分支测试壳（顺序 = navVisibleMetas(false)，
//   分支索引与 lib 路由一致 ⇒ goBranch 不越界）→ ShellRoute builder 接真
//   MyAdaptiveLayout(isMobileBreakpoint: true) → 各分支占位页 AppBar 挂真
//   ShellDrawerButton（走真 rootDrawerScaffoldKey.openDrawer()）→ 抽屉渲染
//   真 nkDrawerEntries。
// 溢出判据同 rule_page_test.dart 小屏组：takeException isNull；
// 行为断言：抽屉 zh 词条（NekoBox 词表）+ 点「设置」goBranch 真导航。
// 依赖注入：translationsProvider / sharedPreferencesProvider（mobile build 路径
// 只 watch translations；prefs 兜底）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/app/shell/my_adaptive_layout.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 分支占位页：AppBar 挂真汉堡键 + 页面标记文本（供 goBranch 导航断言）。
class _BranchPage extends StatelessWidget {
  const _BranchPage(this.marker);

  final String marker;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(leading: const ShellDrawerButton()),
    body: Center(child: Text(marker)),
  );
}

Future<void> _pumpShell(WidgetTester tester, {required Size dp, required double dpr}) async {
  tester.view.physicalSize = Size(dp.width * dpr, dp.height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  // 分支表必须 = navMetas(false) **全序 9 项**（含 navVisible=false 的隐藏分支
  // subscriptions）：branchIndexForNav 按 navMetas 的全表 indexWhere 映射，
  // 抽屉点「设置」（目标 3）→ metaIndex 3 → branch 4。测试壳少搭隐藏分支
  // 会让 goBranch 落到错误页（首跑实证：8 分支壳 → '设置' 导航到 logs 位）。
  // showProfilesAction=false（与 drawer_entries_test 同态）。
  final branches = [
    ('/home', 'P-配置'),
    ('/groups', 'P-分组'),
    ('/subscriptions', 'P-订阅'), // 隐藏分支：导航不可见但占位
    ('/route', 'P-路由'),
    ('/settings', 'P-设置'),
    ('/logs', 'P-日志'),
    ('/traffic', 'P-仪表板'),
    ('/tools', 'P-工具'),
    ('/about', 'P-关于'),
  ];
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            MyAdaptiveLayout(navigationShell: shell, isMobileBreakpoint: true, showProfilesAction: false),
        branches: [
          for (final (path, marker) in branches)
            StatefulShellBranch(
              routes: [GoRoute(path: path, builder: (_, _) => _BranchPage(marker))],
            ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

void main() {
  group('⑨ 小屏 · 主壳抽屉（mobile 断点，<600dp）', () {
    testWidgets('360×640dp：汉堡键开抽屉，三组+分隔线+文档渲染无溢出', (tester) async {
      await _pumpShell(tester, dp: const Size(360, 640), dpr: 3.0);

      expect(find.byType(ShellDrawerButton), findsOneWidget, reason: 'mobile 断点 → 汉堡键');
      await tester.tap(find.byType(ShellDrawerButton));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull, reason: '抽屉（9 目标 + 2 分隔线）窄屏渲染不溢出');
      // 第一组四项（NekoBox main_drawer_menu.xml 组 1）必须直接可见。
      expect(find.text('配置'), findsOneWidget);
      expect(find.text('分组'), findsOneWidget);
      expect(find.text('路由'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
    });

    testWidgets('360×640dp：点「设置」→ goBranch 真导航 + 抽屉收起', (tester) async {
      await _pumpShell(tester, dp: const Size(360, 640), dpr: 3.0);
      await tester.tap(find.byType(ShellDrawerButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(find.text('P-设置'), findsOneWidget, reason: '抽屉目标 → 分支导航（faq 后索引映射）');
      expect(find.text('P-配置'), findsNothing, reason: '分支已切换');
    });

    testWidgets('320×568dp：抽屉开合渲染无溢出（iPhone SE 级最窄）', (tester) async {
      await _pumpShell(tester, dp: const Size(320, 568), dpr: 2.0);

      await tester.tap(find.byType(ShellDrawerButton));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('P-设置'), findsOneWidget);
    });
  });
}
