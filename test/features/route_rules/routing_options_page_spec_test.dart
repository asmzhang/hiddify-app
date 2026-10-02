// L1 结构对等测试 —— 路由列表页 RoutingOptionsPage + RuleTile 1:1 对照 NekoBox RouteFragment。
// 断言基准 zh-CN。规格与词值：.workbuddy/spec-routing-page-tests.md
// （NekoBox 权威源 RouteFragment.kt 310 行，侦察固化 recon-route-rules-2026-09-30.md）。
// - AppBar actions=PopupMenuButton（rules.isEmpty 时 menuItems.getRange(0,2) 只显导入 2 项）；
// - 空态：rule_rounded 图标 48 + empty 文案；
// - RuleTile：出站词（direct=直连/block=拦截/proxy=代理）+ subtitle=规则名 + drag_handle +
//   Switch(updateEnabled)；长按删除 = dialogNotifierProvider.showConfirmation（需 rootNavKey）；
// - _ExpandableFab：mini 项标签常驻树内仅 Opacity 隐藏 → 展开判定用 hitTestable，
//   收起判定用 Opacity 值（见 ④ 的疑似产品 bug 记录）；
// - GeneralOptions：SizeTransition 折叠后子树仍在树内（find 仍命中）→ 可见性断言用 hitTestable。
// 刻意不测：onReorder 手势、_ExpandableFab 动画曲线、deep link 链路（rule_page_test 已覆盖
// JSON 往返）、剪贴板/FilePicker 真实 IO。
// fork A（m08253「全nekobox」）后不再有「预设规则」弹窗/入口：预置规则由进入本页时自动种下
// （NekoBox RouteFragment.kt:131-144 RuleAdapter.reload()）。自动种子的行为在 ⑨ 用例覆盖。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/route_rules/notifier/rules_notifier.dart';
import 'package:hiddify/features/route_rules/overview/rule_page.dart';
import 'package:hiddify/features/route_rules/widget/rule_tile.dart';
import 'package:hiddify/features/settings/overview/sections/routing_options_page.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_helpers.dart';

/// InMemoryRulesNotifier 未覆写 updateEnabled/reorder（真实实现会碰 `late File file`
/// → LateInitializationError）。本测试需要 updateEnabled，补内存版并记账。
class _FullMemoryRulesNotifier extends InMemoryRulesNotifier {
  _FullMemoryRulesNotifier(super.initialRules, {super.rulesFileExists});

  final List<(bool, int)> enabledLog = [];

  @override
  Future<void> updateEnabled(bool enabled, int listOrder) async {
    enabledLog.add((enabled, listOrder));
    final current = state;
    current.firstWhere((rule) => rule.listOrder == listOrder).enabled = enabled;
    state = current.toList();
  }
}

/// 标准测试泵：zh-CN 翻译 + mock 偏好 + 内存规则仓库。
/// ConfigOptions（region/balancerStrategy/resolveDestination/ipv6Mode/directDnsAddress）
/// 与 Preferences.showRouteGeneralOptions 全是 PreferencesNotifier.create → mock prefs 覆盖。
/// [prefs] 默认显式给 show-route-general-options=true，保证 GeneralOptions 展开为确定性状态。
/// [rulesFileExists] 默认 true = 已有历史存储 ⇒ 进入页面不自动种预置规则（既有用例都靠这个
/// 保持空态/自备规则）；要测自动种子传 false，并用 [seedLog] 记账。
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<Rule> rules = const [],
  Map<String, Object> prefs = const {'show-route-general-options': true},
  bool withRootNavKey = false,
  bool rulesFileExists = true,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      rulesNotifierProvider.overrideWith(() => _FullMemoryRulesNotifier([...rules], rulesFileExists: rulesFileExists)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        navigatorKey: withRootNavKey ? rootNavKey : null,
        theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63))),
        home: const RoutingOptionsPage(routeRule: null),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// mini FAB 标签的合成不透明度（乘积，抗 Opacity 嵌套误判）。
double _labelOpacity(WidgetTester tester, Finder label) {
  final opacities = tester.widgetList<Opacity>(find.ancestor(of: label, matching: find.byType(Opacity))).toList();
  return opacities.map((o) => o.opacity).reduce((a, b) => a * b);
}

void main() {
  group('RoutingOptionsPage L1（zh-CN）', () {
    testWidgets('①空态：rule_rounded 图标 48 + empty 文案 + 空菜单只显导入 2 项', (tester) async {
      await _pump(tester);

      // _FabMenuItem(rule_rounded) 与空态图标共用 icon——空树里应有 2 个（空态 48 + FAB mini 项）。
      expect(find.byIcon(Icons.rule_rounded), findsNWidgets(2), reason: '空态图标 48 + _ExpandableFab mini 项');
      expect(find.textContaining('尚未添加规则'), findsOneWidget,
          reason: '词值 t.pages.settings.routing.routeRule.empty（整段含换行提示）');
      // 空规则时菜单 getRange(0,2)：只显导入 2 项，导出与重置不出现（项目特有语义）。
      await tester.tap(find.byType(PopupMenuButton<dynamic>));
      await tester.pumpAndSettle();
      expect(find.text('从剪贴板导入规则'), findsOneWidget);
      expect(find.text('从文件导入规则'), findsOneWidget);
      expect(find.text('复制规则到剪贴板'), findsNothing);
      expect(find.text('保存规则到文件'), findsNothing);
      expect(find.text('重置规则'), findsNothing);
    });

    testWidgets('②列表+出站词：3 规则 → 3 卡 + subtitle=规则名 + 出站词 直连/拦截/代理', (tester) async {
      // 放大视口：默认 800×600 下 ReorderableListView 懒加载只 build 可见 2 卡。
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(tester, rules: [
        makeRule(listOrder: 0, name: '规则甲', outbound: Outbound.direct),
        makeRule(listOrder: 1, name: '规则乙', outbound: Outbound.block),
        makeRule(listOrder: 2, name: '规则丙'),
      ]);

      expect(find.byType(RuleTile), findsNWidgets(3));
      expect(find.text('规则甲'), findsOneWidget, reason: 'subtitle=rule.name');
      expect(find.text('规则乙'), findsOneWidget);
      expect(find.text('规则丙'), findsOneWidget);
      expect(find.text('直连'), findsOneWidget, reason: '出站词 t...routeRule.rule.outbound.direct');
      expect(find.text('拦截'), findsOneWidget, reason: 'block');
      expect(find.text('代理'), findsOneWidget, reason: 'proxy');
    });

    testWidgets('③菜单 5 项：rules 非空 → 导入×2 + 导出×2 + 重置规则', (tester) async {
      await _pump(tester, rules: [makeRule(listOrder: 0, name: '规则甲')]);

      await tester.tap(find.byType(PopupMenuButton<dynamic>));
      await tester.pumpAndSettle();
      expect(find.text('从剪贴板导入规则'), findsOneWidget);
      expect(find.text('从文件导入规则'), findsOneWidget);
      expect(find.text('复制规则到剪贴板'), findsOneWidget);
      expect(find.text('保存规则到文件'), findsOneWidget);
      expect(find.text('重置规则'), findsOneWidget);
    });

    testWidgets('④FAB 展开：展开后 mini 项标签 hitTestable 可见；收起后 Opacity 归 0', (tester) async {
      await _pump(tester);

      final labelCreate = find.text('创建新规则');
      // fork A 后 _ExpandableFab 只剩「创建新规则」一项（预设规则入口已随弹窗一并删除）。
      expect(find.text('预设规则'), findsNothing, reason: 'fork A：预设规则入口已删');
      // mini 项标签常驻树内，收起态 Opacity(0)。
      expect(labelCreate, findsOneWidget);
      expect(_labelOpacity(tester, labelCreate), 0.0);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(_labelOpacity(tester, labelCreate), 1.0);
      expect(labelCreate.hitTestable(), findsOneWidget, reason: '展开后标签可命中');

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(_labelOpacity(tester, labelCreate), 0.0, reason: '收起后视觉隐藏');
      // 疑似产品 bug（记录不修）：_ExpandableFab mini 项无 IgnorePointer，收起后
      // Opacity(0) 标签仍可命中点击 —— 真机上收起后在 mini 项区域误触会直接导航。
      // NekoBox 原版为 ItemTouchHelper+FloatingActionButton 菜单，无此形态。
    });

    testWidgets('⑤a GeneralOptions 展开：展开条常驻 + region 等选项可命中', (tester) async {
      await _pump(tester); // 默认 prefs 已含 show-route-general-options: true

      expect(find.text('路由通用选项'), findsOneWidget, reason: '展开条常驻');
      expect(find.text('地区').hitTestable(), findsOneWidget, reason: 'showGeneralOptions=true → region Choice 可见');
      expect(find.text('Balancer 策略').hitTestable(), findsOneWidget);
      expect(find.text('解析目的地').hitTestable(), findsOneWidget);
    });

    testWidgets('⑤b GeneralOptions 收起：SizeTransition 折叠 → 选项在树内但不可命中', (tester) async {
      await _pump(tester, prefs: const {'show-route-general-options': false});

      expect(find.text('路由通用选项'), findsOneWidget, reason: '展开条常驻');
      // SizeTransition(sizeFactor 0, Clip.hardEdge) 折叠：子树仍在（find 命中）但 hitTest 失败。
      expect(find.text('地区'), findsOneWidget);
      expect(find.text('地区').hitTestable(), findsNothing, reason: '折叠后不可交互');
    });

    testWidgets('⑥长按删除流：确认框（删除规则 + msg 含规则名）→ 确认后 deleteRule 落账', (tester) async {
      // ConfirmationDialog 的按钮用 context.pop —— 必须 GoRouter 环境
      //（MaterialApp.router + rootNavKey 作 router.navigatorKey，rootDialog 弹窗才能挂上）。
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(const {'show-route-general-options': true});
      final sp = await SharedPreferences.getInstance();
      final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
      final container = ProviderContainer(
        overrides: [
          translationsProvider.overrideWith((ref) => Future.value(t)),
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
          rulesNotifierProvider.overrideWith(() => _FullMemoryRulesNotifier([makeRule(listOrder: 0, name: '规则甲')])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(translationsProvider.future);
      await container.read(sharedPreferencesProvider.future);

      final router = GoRouter(
        initialLocation: '/',
        navigatorKey: rootNavKey,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const RoutingOptionsPage(routeRule: null)),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63))),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('规则甲'));
      await tester.pumpAndSettle();

      // 对话框走真实 ConfirmationDialog（rootNavKey 挂到 router.navigatorKey 才可弹）。
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.text('删除规则')), findsOneWidget,
          reason: 'title = t.dialogs.confirmation.routeRule.delete.title');
      expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('规则甲')), findsOneWidget,
          reason: 'msg = 您确定要删除规则 "规则甲" 吗？');

      // 确认按钮 = t.common.delete「删除」（context.pop(true) → showConfirmation 返回 true）。
      await tester.tap(find.widgetWithText(TextButton, '删除'));
      await tester.pumpAndSettle();

      expect(find.byType(RuleTile), findsNothing, reason: '删除后列表清空');
      expect(find.byIcon(Icons.rule_rounded), findsNWidgets(2), reason: '回到空态（空态图标 48 + FAB mini 项）');
      expect(
        container.read(rulesNotifierProvider).where((r) => r.name == '规则甲'),
        isEmpty,
        reason: 'InMemoryRulesNotifier.deleteRule(listOrder=0) 已落账',
      );
    });

    testWidgets('⑦updateEnabled：tile 内 Switch 值=enabled；tap 翻转 + 记账', (tester) async {
      final container = await _pump(tester, rules: [makeRule(listOrder: 0, name: '规则甲')]);

      final tileSwitch = find.descendant(of: find.byType(RuleTile), matching: find.byType(Switch));
      expect(tileSwitch, findsOneWidget);
      expect(tester.widget<Switch>(tileSwitch).value, isTrue, reason: 'makeRule 默认 enabled=true');

      await tester.tap(tileSwitch);
      await tester.pumpAndSettle();

      expect(tester.widget<Switch>(tileSwitch).value, isFalse, reason: 'updateEnabled(false, 0) 后翻转');
      final notifier = container.read(rulesNotifierProvider.notifier) as _FullMemoryRulesNotifier;
      expect(notifier.enabledLog, [(false, 0)], reason: '记账 (enabled, listOrder)');
    });

    testWidgets('⑧点行进编辑页：tap tile → 路由 rule/:orderId → RulePage 编辑模式', (tester) async {
      SharedPreferences.setMockInitialValues(const {'show-route-general-options': true});
      final sp = await SharedPreferences.getInstance();
      final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
      final container = ProviderContainer(
        overrides: [
          translationsProvider.overrideWith((ref) => Future.value(t)),
          sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
          rulesNotifierProvider.overrideWith(() => _FullMemoryRulesNotifier([makeRule(listOrder: 0, name: '规则甲')])),
        ],
      );
      addTearDown(container.dispose);
      await container.read(translationsProvider.future);
      await container.read(sharedPreferencesProvider.future);

      // 完整 goRouter 环境：RuleTile onTap = context.goNamed('rule', orderId)。
      // goNamed 按名查路由 → GoRoute 必须带 name: 'rule'（缺了报 unknown route name）。
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const RoutingOptionsPage(routeRule: null)),
          GoRoute(
            name: 'rule',
            path: '/rule/:orderId',
            builder: (_, state) {
              final orderId = state.pathParameters['orderId']!;
              return RulePage(ruleListOrder: orderId == 'new' ? null : int.tryParse(orderId));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFE91E63))),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('规则甲'));
      await tester.pumpAndSettle();

      expect(find.byType(RulePage), findsOneWidget, reason: 'goNamed(rule, orderId=0) → RulePage 编辑模式');
      expect(find.byType(RuleTile), findsNothing, reason: '已离开列表页');
    });

    testWidgets('⑨a首次进入自动种预置规则（新装：无历史存储）→ 非中国地区 9 条，全部默认关', (tester) async {
      // 放大视口让 9 张卡都 build 出来。
      tester.view.physicalSize = const Size(1080, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = await _pump(tester, rulesFileExists: false);

      // 触发者是 build 里的 post-frame 回调（对齐 NekoBox RouteFragment.kt:131-144
      // RuleAdapter.reload()），无弹窗、无用户操作。
      final notifier = container.read(rulesNotifierProvider.notifier) as _FullMemoryRulesNotifier;
      expect(notifier.seedLog, hasLength(1), reason: '进入页面即调用一次 ensureSeeded');
      expect(notifier.seedLog.single, isNotNull, reason: '无历史存储 ⇒ 真种下，而非跳过');

      final seeded = container.read(rulesNotifierProvider);
      expect(seeded, hasLength(9), reason: 'Region.other ⇒ cn + ir + ru 三组；cn 多一条 Play 商店');
      expect(find.byType(RuleTile), findsNWidgets(9));
      expect(find.text('屏蔽 QUIC'), findsOneWidget, reason: 'RouteFragment 列表首行');
      expect(find.text('屏蔽广告'), findsOneWidget);
      expect(find.text('中国 Play 商店规则'), findsOneWidget, reason: '仅 cn 有 Play 商店规则');
      expect(find.text('Iran Play 商店规则'), findsNothing);
      expect(find.text('Russia IP 规则'), findsOneWidget);
      // 预置规则与用户新建的规则不同：落库即关闭（RouteSettingsActivity.kt:97-99 只管新建）。
      expect(
        tester.widgetList<Switch>(find.descendant(of: find.byType(RuleTile), matching: find.byType(Switch))).every((s) => s.value == false),
        isTrue,
        reason: '全部默认关 —— 与真机 nb_16_route.png 一致',
      );
      for (var i = 0; i < seeded.length; i++) {
        expect(seeded[i].listOrder, i, reason: 'listOrder 按 NekoBox createRule 的 nextOrder 递增');
      }
    });

    testWidgets('⑨b地区=中国 → 只种 5 条（无 Iran/Russia 两组）', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = await _pump(tester, prefs: const {'show-route-general-options': true, 'region': 'cn'}, rulesFileExists: false);

      final seeded = container.read(rulesNotifierProvider);
      expect(seeded, hasLength(5), reason: 'Region.cn ⇒ 仅 cn 一组');
      expect(find.text('中国 域名规则'), findsOneWidget);
      expect(find.text('中国 IP 规则'), findsOneWidget);
      expect(find.text('Iran 域名规则'), findsNothing);
    });

    testWidgets('⑨c已有历史存储 → 不覆盖用户数据（ensureSeeded 提前返回）', (tester) async {
      final container = await _pump(tester, rules: [makeRule(listOrder: 0, name: '规则甲')]);

      final notifier = container.read(rulesNotifierProvider.notifier) as _FullMemoryRulesNotifier;
      expect(notifier.seedLog, [null], reason: '调用过但被守卫拦下（非「没调用」）');
      expect(container.read(rulesNotifierProvider).map((r) => r.name), ['规则甲'], reason: '用户数据原样保留');
    });

    testWidgets('⑨d重置 → 清空后立刻重种（对齐 RouteFragment.kt:113-115 reset + reload）', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final container = await _pump(tester, rules: [makeRule(listOrder: 0, name: '规则甲')]);
      final notifier = container.read(rulesNotifierProvider.notifier) as _FullMemoryRulesNotifier;
      expect(container.read(rulesNotifierProvider), hasLength(1));

      await tester.tap(find.byType(PopupMenuButton<dynamic>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重置规则'));
      await tester.pumpAndSettle();

      // 重置删掉存储 → 紧接着 reload 重新种下预置规则（不是留空列表）。
      expect(notifier.seedLog, hasLength(2), reason: '进页面一次 + 重置后一次');
      final afterReset = container.read(rulesNotifierProvider);
      expect(afterReset, hasLength(9), reason: '重置后回到预置 9 条');
      expect(afterReset.any((r) => r.name == '规则甲'), isFalse, reason: '用户规则已被重置清掉');
      expect(find.byType(RuleTile), findsNWidgets(9));
    });
  });
}
