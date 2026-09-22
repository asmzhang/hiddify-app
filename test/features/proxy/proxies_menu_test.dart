// L1 结构对等测试 —— ⋮ 菜单 1:1 对照 NekoBox `res/menu/add_profile_menu.xml`。
//
// 断言基准 = **zh-CN**（用户拍板：zh-CN 为基准推进，其余语言翻译批次放最后）。
// NekoBox zh-rCN 词表（values-zh-rCN/strings.xml）：
//   update_current_subscription = 更新当前组订阅
//   clear_traffic_statistics    = 清空流量统计数据
//   remove_duplicate            = 删除重复的服务器
//   connection_test_tcp_ping    = TCPing（translatable=false 全语言固定词）
//   connection_test_url_test    = URL Test（同上）
//   connection_test_clear_results = 清理测试结果
//   connection_test_delete_unavailable = 清理不可用配置
//   group_order                 = 排序
//   group_order_origin/name/by_delay = 原始 / 以名称 / 以延时（radio 子菜单三项）
//
// 被测组件是抽出来的 [ProxiesMenuButton]（页面在测它的引用，不重测行为）——
// 依赖只有 translations + proxiesSortNotifier（后者子类覆写成记录型 fake，
// 不碰 SharedPreferences）。动作 handler 的数据依赖（仓库/内核）本测试不触发：
// 结构与交互断言只到"点开/点子项"为止。
//
// **deferred 库坑**：slang 生成代码里非 base 语言都是 deferred import，
// `AppLocale.zhCn.build()` 内部的 `loadLibrary()` 是真实异步 —— 在 testWidgets
// 的 FakeAsync zone 里永远不完成（表现 = 用例 30s 超时、无任何异常输出）。
// 必须用 `tester.runAsync` 在真实事件循环里构建好，再以完成值注入 provider。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxies_menu_button.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 记录型 fake：不落盘（绕开 SharedPreferences 链路），只更新内存 state。
class FakeProxiesSortNotifier extends ProxiesSortNotifier {
  @override
  ProxiesSort build() => ProxiesSort.unsorted;

  @override
  Future<void> update(ProxiesSort value) async {
    state = value;
  }
}

/// 可播种初值的 fake（子菜单勾选态测试用）。
class SeededFakeProxiesSortNotifier extends FakeProxiesSortNotifier {
  SeededFakeProxiesSortNotifier(this.seed);
  final ProxiesSort seed;
  @override
  ProxiesSort build() => seed;
}

/// 标准测试泵：zh-CN 翻译（runAsync 预构建）+ 假排序器 + 被测按钮。
Future<ProviderContainer> pumpMenu(WidgetTester tester, {ProxiesSort initial = ProxiesSort.unsorted}) async {
  final t = await tester.runAsync(() => AppLocale.zhCn.build());
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      proxiesSortNotifierProvider.overrideWith(() => SeededFakeProxiesSortNotifier(initial)),
    ],
  );
  addTearDown(container.dispose);

  // Pre-warm（rule_page_test 同款）：override 后的 provider 实例是新的，
  // Future.value 也要一个微任务才落成 AsyncData；不预热首帧 build 会读到
  // AsyncLoading 而组件里是 requireValue ⇒ 直接炸。
  await container.read(translationsProvider.future);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Scaffold(body: Center(child: ProxiesMenuButton()))),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_vert));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('结构对等：八项 + 权威顺序 + 文案 = NekoBox zh-rCN 词表', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);

    // 1. 八项全在（文案逐词对齐 NekoBox zh-rCN）。
    const expected = [
      '更新当前组订阅', // action_update_subscription
      '清空流量统计数据', // action_clear_traffic_statistics
      '删除重复的服务器', // action_remove_duplicate
      'TCPing', // action_connection_tcp_ping
      'URL Test', // action_connection_url_test
      '清理测试结果', // action_connection_test_clear_results
      '清理不可用配置', // action_connection_test_delete_unavailable
      '排序', // action_order
    ];
    for (final label in expected) {
      expect(find.text(label), findsOneWidget, reason: '⋮ 菜单缺项/重复：$label');
    }

    // 2. 权威顺序（add_profile_menu.xml 的 action_misc 内层顺序）：所有可见文本里
    //    这八项的相对次序必须与规格一致。MenuAnchor 渲染为 overlay，
    //    find.text 全局取次序即菜单次序。
    final allTexts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .where((s) => expected.contains(s))
        .toList();
    expect(allTexts, expected, reason: '菜单项顺序必须 = NekoBox 规格顺序');

    // 3. 「路由」项删除回归：NekoBox 的路由在抽屉不在 ⋮ 菜单。
    expect(find.text('路由'), findsNothing);
    expect(find.text('Routing'), findsNothing);

    // 4. 旧文案回归（改版前 hiddify 文案，不许回流）。
    for (final stale in ['Test all delays', 'TCP ping', 'Update subscriptions', 'Sort proxies', '全部测速', 'TCP 测速', '更新订阅', '排序代理']) {
      expect(find.text(stale), findsNothing, reason: '旧文案回流：$stale');
    }
  });

  testWidgets('排序子菜单 = radio 三项（原始/以名称/以延时），无第四项', (tester) async {
    await pumpMenu(tester);
    await openMenu(tester);
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    // 子菜单三项 + 无 usage（hiddify 遗留值不进菜单）。
    expect(find.text('原始'), findsOneWidget);
    expect(find.text('以名称'), findsOneWidget);
    expect(find.text('以延时'), findsOneWidget);
    expect(find.text('按用量'), findsNothing, reason: 'usage 是 hiddify 遗留排序，NekoBox 无此项');
    expect(find.text('By usage'), findsNothing);
  });

  testWidgets('点子菜单项 = radio 单选落库（state 更新 + 菜单收起）', (tester) async {
    final container = await pumpMenu(tester);
    await openMenu(tester);
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('以延时'));
    await tester.pumpAndSettle();

    expect(container.read(proxiesSortNotifierProvider), ProxiesSort.delay, reason: 'radio 单选必须立即生效（每组持久语义的内存面）');
  });

  testWidgets('子菜单勾选态跟随当前排序（name ⇒ 以名称带 ✓）', (tester) async {
    // NekoBox checkOrderMenu（ConfigurationFragment.kt:1110-1155）：
    // 每组持久化 + 打开时勾选当前项。这里验证勾选态与 state 联动。
    await pumpMenu(tester, initial: ProxiesSort.name);
    await openMenu(tester);
    await tester.tap(find.text('排序'));
    await tester.pumpAndSettle();

    // 勾选实现 = leadingIcon ✓。断言两层：
    // ① 全树恰有一个 check（只有当前项带）；
    // ② 这个 check 与「以名称」文本同在一个按钮 Row 里（= 挂在以名称行上）。
    // MenuItemButton 的布局是 Row[leadingIcon?, Text]，而该 Row 的外层还有
    // 一个行级 Row（padding 行），所以 ancestor(Row) 会命中 2 个 —— 用
    // "check 的祖先 ∩ 文本的祖先 = 至少一个 Row" 表达同行关系，不用单匹配。
    expect(find.byIcon(Icons.check), findsOneWidget, reason: '只有当前排序项带 ✓');
    final checkAncestors = find.ancestor(of: find.byIcon(Icons.check), matching: find.byType(Row)).evaluate().toSet();
    final textAncestors = find.ancestor(of: find.text('以名称'), matching: find.byType(Row)).evaluate().toSet();
    expect(
      checkAncestors.intersection(textAncestors),
      isNotEmpty,
      reason: '✓ 必须与「以名称」同行（勾选态挂在当前排序项上）',
    );
  });

  testWidgets('组件可独立构建（无隐藏依赖，页面引用由 analyze+集成测试兜底）', (tester) async {
    await pumpMenu(tester);
    expect(find.byType(ProxiesMenuButton), findsOneWidget);
  });
}
