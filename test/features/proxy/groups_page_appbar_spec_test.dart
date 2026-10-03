// L1 结构测试 —— 分组页 AppBar 的抽屉汉堡键（差异清单 D-1）。
//
// 规格依据：NekoBox 分组页是 `MainActivity` 里的一个导航 fragment
// （`ui/GroupFragment.kt`），toolbar 与 `DrawerLayout` 都由 Activity 提供 ⇒
// **分组页必须有打开导航抽屉的入口**（NekoBox 里是系统的返回/汉堡键）。
// 本项目手机端统一写法（全仓 10 处，`tools_page.dart:31` / `settings_page.dart:57` …）：
//   leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null
// 唯独分组页此前漏了（HANDOVER 差异清单 D-1：抽屉里的「分组」进去后出不来）。
//
// 断点语义（`lib/core/router/go_router/helper/active_breakpoint_notifier.dart:28-51`）：
//   width < 600 → mobile（汉堡键）；600..840 → tablet；> 840 → desktop（左侧常驻 rail，无键）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/overview/groups_page.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 标准泵：zh-CN + mock 偏好；组列表 provider 用空表覆盖
/// （真实 provider 要 drift repository，本测试只关心 AppBar 骨架）。
Future<void> _pump(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  // slang 非 base 语言是 deferred 库：必须在 runAsync 里 build（HANDOVER §4#13）。
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      proxyGroupListProvider.overrideWith(
        (ref) => const <({ProxyGroupEntry group, int nodeCount})>[],
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: GroupsPage()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('GroupsPage AppBar（D-1）', () {
    testWidgets('①mobile 400dp：title=分组 + 抽屉汉堡键', (tester) async {
      await _pump(tester, width: 400);

      expect(find.text('分组'), findsOneWidget, reason: 'AppBar title = t.pages.groups.title');
      expect(find.byType(ShellDrawerButton), findsOneWidget, reason: 'Breakpoint mobile → 抽屉键（D-1 修复项）');
    });

    testWidgets('②desktop 1080dp：无汉堡键（左侧常驻 rail）', (tester) async {
      await _pump(tester, width: 1080);

      expect(find.text('分组'), findsOneWidget);
      expect(find.byType(ShellDrawerButton), findsNothing, reason: '非 mobile 断点 leading=null');
    });

    testWidgets('③最窄 320dp：骨架渲染无溢出', (tester) async {
      await _pump(tester, width: 320);

      expect(tester.takeException(), isNull);
      expect(find.byType(ShellDrawerButton), findsOneWidget);
    });
  });
}
