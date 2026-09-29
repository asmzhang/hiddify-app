// 冒烟断言集 —— 「先 PC」主线的自动化验收层。
// 由 main_test.dart 的唯一 testWidgets 调起（app 已在该测试体内启动）。
//
// 覆盖矩阵（对照 NekoBoxForAndroid 复刻批次）：
//   1. 应用能启动到主界面（lazyBootstrap 全链路不崩，含 core DLL setup）
//   2. 主界面四要素：FAB 连接开关 / NavigationRail(≥600dp) 或抽屉 / 无移动端底栏
//   3. ⋮ 菜单七项文案可达（en；排序项软校验）
// 人工留给：视觉、真实连接、托盘、真实订阅导入。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/features/connection/widget/connection_fab.dart';
import 'package:hiddify/features/proxy/widget/proxies_menu_button.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';

/// 主界面四要素断言。
Future<void> smokeMainScreen(WidgetTester tester) async {
  // 诊断输出：失败时能直接看出卡在哪个页面。
  final diagTexts = tester.widgetList<Text>(find.byType(Text)).take(3).map((t) => t.data ?? '(rich)').join(' | ');
  debugPrint(
    'SMOKE-DIAG Intro: ${tester.any(find.byIcon(Icons.rocket_launch))}, '
    'Scaffold: ${tester.any(find.byType(Scaffold))}, '
    'AppBar: ${tester.any(find.byType(AppBar))}, '
    'texts: [$diagTexts]',
  );

  // 1. FAB 连接开关常驻，并且是 NekoBox 四态实现。
  expect(find.byType(ConnectionFab), findsOneWidget);
  expect(find.byType(FloatingActionButton), findsOneWidget, reason: 'FAB 连接开关必须在');
  expect(find.byTooltip('Connect'), findsOneWidget);

  // 2. PC 宽窗（宿主窗口 ≥600dp）应有 NavigationRail；窄窗才是抽屉。
  final hasRail = tester.any(find.byType(NavigationRail));
  final hasDrawer = tester.any(find.byType(NavigationDrawer));
  expect(hasRail || hasDrawer, isTrue, reason: '桌面宽窗应有 NavigationRail（≥600dp），窄窗才有抽屉');

  // 3. 移动端底栏不应出现（PC 断点收口）。
  expect(find.byType(BottomNavigationBar), findsNothing, reason: 'PC 不应出现移动端底栏');

  // 4. ⋮ 菜单的组级动作必须拿到当前 Tab，不能静默按空范围执行。
  final menu = tester.widget<ProxiesMenuButton>(find.byType(ProxiesMenuButton));
  expect(menu.activeTab, isNotNull, reason: '配置页必须把当前分组传给 ⋮ 菜单');
}

/// 带上限的 settle：桌面 app 有常驻动画（连接转圈/速率刷新/gRPC 心跳重绘），
/// 裸 pumpAndSettle 会永远等不到静止。超时即视为"已稳定到可用"，继续断言。
Future<void> settleBounded(WidgetTester tester, {Duration timeout = const Duration(seconds: 5)}) async {
  try {
    await tester.pumpAndSettle(timeout);
  } catch (_) {
    // 永不空闲动画：接受。
  }
}

/// ＋ 菜单顶层与 Manual Settings 二级协议菜单可达。
Future<void> smokeAddMenu(WidgetTester tester) async {
  await settleBounded(tester);
  final addButton = find.byIcon(Icons.note_add_rounded);
  expect(addButton, findsOneWidget, reason: '＋ 添加按钮必须在 AppBar');
  await tester.tap(addButton);
  await settleBounded(tester);

  for (final label in ['Import from Clipboard', 'Import from file', 'Manual Settings', 'Add subscription']) {
    expect(find.text(label).hitTestable(), findsOneWidget, reason: '＋ 菜单缺项：$label');
  }
  await tester.tap(find.text('Manual Settings'));
  await settleBounded(tester);
  for (final label in ['VMess', 'VLESS', 'Hysteria 1', 'Hysteria 2', 'Custom Config', 'Proxy Chain']) {
    expect(find.text(label).hitTestable(), findsOneWidget, reason: 'Manual Settings 缺项：$label');
  }

  await tester.tapAt(const Offset(10, 10));
  await settleBounded(tester);
}

/// ⋮ 菜单八项可达断言（en 文案；NekoBox 1:1 对照。UI 语言由 startHiddifyApp 钉在 en）。
///
/// 2026-09-22 功能①：⋮ 菜单从 PopupMenuButton 改为 MenuAnchor（排序带 radio 子菜单），
/// 文案对齐 NekoBox strings.xml（en）：URL Test / TCPing / Update current Group's
/// subscription / Order 等。八项顺序断言在 widget 测试层（proxies_menu_test.dart，zh-CN），
/// 这里只做可达性冒烟（en 固定词）。
Future<void> smokeOverflowMenu(WidgetTester tester) async {
  await settleBounded(tester);
  // 新组件的图标显式用了 Icons.more_vert（MenuAnchor 包 IconButton）。
  final menuButton = find.byIcon(Icons.more_vert);
  expect(menuButton, findsOneWidget, reason: '⋮ 菜单按钮必须在 AppBar');
  await tester.tap(menuButton);
  await settleBounded(tester);

  // 诊断：菜单没弹出/文案不匹配时直接打印可见文本。
  final menuTexts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '(rich)').join(' | ');
  debugPrint('SMOKE-MENU texts: [$menuTexts]');

  const items = [
    "Update current Group's subscription", // action_update_subscription
    'Clear traffic statistics', // action_clear_traffic_statistics
    'Remove duplicate servers', // action_remove_duplicate
    'TCPing', // action_connection_tcp_ping（translatable=false）
    'URL Test', // action_connection_url_test（同上）
    'Clear test results', // action_connection_test_clear_results
    'Clear unavailable', // action_connection_test_delete_unavailable
    'Order', // action_order（含 radio 子菜单：Origin / By Name / By Delay）
  ];
  for (final item in items) {
    expect(find.text(item).hitTestable(), findsOneWidget, reason: '⋮ 菜单缺项：$item');
  }

  // 收起菜单（点空白处）。
  await tester.tapAt(const Offset(10, 10));
  await settleBounded(tester);
}

/// 第一张真实节点卡的分享菜单可达：标准二维码/剪贴板 + 配置导出组。
Future<void> smokeNodeShareMenu(WidgetTester tester) async {
  await settleBounded(tester);
  final tile = find.byType(ProxyTile).first;
  expect(tile, findsOneWidget, reason: '配置页至少应有一张真实节点卡');

  final adaptiveMenu = find.descendant(of: tile, matching: find.byType(AdaptiveMenu));
  expect(adaptiveMenu, findsOneWidget, reason: '普通节点必须有分享菜单');
  final shareButton = find.descendant(of: adaptiveMenu, matching: find.byType(NkCardAction));
  expect(shareButton, findsOneWidget);
  await tester.tap(shareButton);
  await settleBounded(tester);

  expect(find.text('QR code').hitTestable(), findsOneWidget);
  expect(find.text('Export to Clipboard').hitTestable(), findsOneWidget);
  final configurationGroup = find.descendant(of: find.byType(SubmenuButton), matching: find.text('Configuration'));
  expect(configurationGroup.hitTestable(), findsOneWidget);

  await tester.tapAt(const Offset(10, 10));
  await settleBounded(tester);
}
