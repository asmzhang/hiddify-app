// 逐功能集成测试（用户使用顺序）—— integration_test 真窗口运行。
// 运行: flutter test -d windows integration_test/app_test.dart
//
// 定稿要点（前几轮踩坑后的结论，勿退回去）：
//
// 1. 启动只走 hiddify_app.dart 的 startHiddifyApp()：它预写 locale=en +
//    intro_completed=true，布局和文案才确定；跟随系统语言会让断言随机器飘。
// 2. **一个文件只保留一次真实启动**。flutter_test 的 TestWidgetsFlutterBinding
//    在每个 testWidgets 开头的 `_runTestBody` 里都会
//    `runApp(Container(key: UniqueKey(), child: _preTestMessage))`
//    （flutter_test/src/binding.dart:1047，占位页 = "Test starting..."），
//    即把整棵树重置成占位页。「第二个用例复用上一例的树」不可能成立，
//    后续步骤必须写在同一个 testWidgets 里按用户顺序串起来。
// 3. 等待一律用「轮询 + 超时」或 settleBounded：app 有常驻动画与每秒统计数据流，
//    裸 pumpAndSettle 永不沉降；盲 pump 固定秒数会在慢机器上假失败。
// 4. **不要覆盖 tester.view.physicalSize**。老版本为了让布局按宽窗切
//    NavigationRail 而把视口改成 2560×1400，但宿主窗口只有 868×668，
//    且 bootstrap 里的 WindowNotifier 会在启动过程中 maximize 真窗口——
//    两者互相打架。已确认的症状「onstage 文本 0 个 / 全量 1580 个元素」
//    正好是「树在但不在台上」的指纹（find.* 默认 skipOffstage: true，
//  allElements 用 skipOffstage: false，见 flutter_test/src/controller.dart:856），
//    而渲染视口/Overlay 都会按自身状态摘子树，所以少一个变量就少一个怀疑对象。
//    布局自适应两种形态：宽窗 NavigationRail，窄窗 NavigationDrawer（下面用
//    openDrawerIfNeeded 统一处理）。
// 5. 失败必须留现场：dumpUi 同时打 onstage（find.* 视角）与含 offstage 的全量
//    视角 + onstage 类型直方图。只留一句 "Found 0 widgets" 无法定位。
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/db/provider/db_providers.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/proxy/data/node_import.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:integration_test/integration_test.dart';

import 'hiddify_app.dart';
import 'smoke_test.dart' show settleBounded;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('用户顺序 · 启动 → 分组页可达', (tester) async {
    addTearDown(() => stopHiddifyCore(tester));
    // 真启动（bootstrap 全链路：SP/DB/内核/gRPC/托盘）。
    await startHiddifyApp();
    await waitForApp(tester);
    await settleBounded(tester, timeout: const Duration(seconds: 10));

    dumpUi(tester, '功能1 启动后');

    // 主界面四要素（与 smoke_test 同口径）。
    expect(find.byType(FloatingActionButton), findsOneWidget, reason: 'FAB 连接开关必须在');
    final hasRail = tester.any(find.byType(NavigationRail));
    final hasDrawer = tester.any(find.byType(NavigationDrawer));
    expect(hasRail || hasDrawer, isTrue, reason: '宽窗应有 NavigationRail，窄窗才是抽屉');
    expect(find.byType(BottomNavigationBar), findsNothing, reason: 'PC 不应出现移动端底栏');

    // 功能2 分组列表页可达：点侧栏分组项再断言。
    // startHiddifyApp 已钉 en，故文案是 en 的 groups.title = "Group"。
    await tapSidebarEntry(tester, 'Group');
    await settleBounded(tester, timeout: const Duration(seconds: 10));
    dumpUi(tester, '功能2 点分组后');

    // 持久化分组 Tab（订阅名）只出现在分组页，用它判定页面真的切过去了。
    expect(find.text('云霄'), findsWidgets, reason: '分组页应列出持久化的分组/订阅名');

    // 回到配置页，继续连接与导入主流程。
    await tapSidebarEntry(tester, 'Configuration');
    await settleBounded(tester, timeout: const Duration(seconds: 10));
    final appElement = tester.element(find.byType(Scaffold).first);
    final container = ProviderScope.containerOf(appElement, listen: false);
    final db = container.read(dbProvider);

    // 功能3：真实连接闭环。后台核心已经运行但未接管；点 FAB 打开系统代理，
    // Connected 后 StatsBar 才出现，再点 Stop 回到未连接。对齐 NekoBox
    // ServiceButton + StatsBar 的可见状态与动作语义。
    await container.read(connectionNotifierProvider.notifier).toggleConnection();
    await waitForConnectionStatus(tester, container, (status) => status is Connected);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Connected, tap here to test the connection'), findsOneWidget);

    await container.read(connectionNotifierProvider.notifier).toggleConnection();
    await waitForConnectionStatus(tester, container, (status) => status is Disconnected);
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.text('Connected, tap here to test the connection'), findsNothing);

    // 功能4：真实 Core.Parse(content) → BASIC 实体导入，不创建 ProfileEntry。
    await (db.delete(db.proxyEntities)..where((t) => t.tag.like('ui-import%'))).go();
    final profilesBefore = await db.select(db.profileEntries).get();
    final activeProfilesBefore = profilesBefore.where((p) => p.active).toList();
    final activeBefore = activeProfilesBefore.isEmpty ? null : activeProfilesBefore.first.id;
    const importLink = 'anytls://ui-import-password@example.com:443?sni=example.com#ui-import-link';
    const importJson = '{"type":"socks","tag":"ui-import-json","server":"127.0.0.1","server_port":1080}';
    final outcome = await container.read(proxiesOverviewNotifierProvider.notifier).importNodeInputs([
      importLink,
      importJson,
    ]);
    expect(
      outcome,
      isA<NodeImportSucceeded>().having((e) => e.count, 'count', 2),
      reason: '链接与 JSON entry 应独立 Parse 后一次落库',
    );

    final imported = await (db.select(db.proxyEntities)..where((t) => t.tag.like('ui-import%'))).get();
    expect(imported, hasLength(2), reason: '两个 entry 必须在同一事务中完整落入实体表');
    expect(imported.map((e) => e.groupId).toSet(), hasLength(1));
    final importedGroup = await (db.select(
      db.proxyGroups,
    )..where((t) => t.id.equals(imported.first.groupId))).getSingle();
    expect(importedGroup.type, ProxyGroupType.basic, reason: '节点导入不能创建 subscription 组');
    final profilesAfter = await db.select(db.profileEntries).get();
    expect(profilesAfter, hasLength(profilesBefore.length), reason: '节点导入不能新增 ProfileEntry');
    final activeProfilesAfter = profilesAfter.where((p) => p.active).toList();
    final activeAfter = activeProfilesAfter.isEmpty ? null : activeProfilesAfter.first.id;
    expect(activeAfter, activeBefore, reason: '节点导入不能切换活动 Profile');

    await (db.delete(db.proxyEntities)..where((t) => t.tag.like('ui-import%'))).go();
    if (importedGroup.ungrouped) {
      await (db.delete(db.proxyGroups)..where((t) => t.id.equals(importedGroup.id))).go();
    }
    await container.read(selectedProxyGroupTagProvider.notifier).update('');
  });
}

Future<void> waitForConnectionStatus(
  WidgetTester tester,
  ProviderContainer container,
  bool Function(ConnectionStatus? status) matches, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (matches(container.read(connectionNotifierProvider).valueOrNull)) return;
  }
  final status = container.read(connectionNotifierProvider);
  fail('连接状态在 ${timeout.inSeconds}s 内未到达预期：$status');
}

/// 轮询等待主界面就位。
/// 用 skipOffstage: false —— 即便树「在但不在台上」也要能被判定为已启动，
/// 否则这里会超时，误导成「启动失败」。
Future<void> waitForApp(WidgetTester tester, {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 250));
    if (tester.any(find.byType(FloatingActionButton, skipOffstage: false))) return;
  }
  debugPrint('WAIT-APP 超时：${timeout.inSeconds}s 内未见 FAB（树可能仍是占位页）');
}

/// 点侧栏项：宽窗直接点 NavigationRail，窄窗先开 NavigationDrawer。
Future<void> tapSidebarEntry(WidgetTester tester, String label) async {
  await openDrawerIfNeeded(tester);
  for (final container in [find.byType(NavigationRail), find.byType(NavigationDrawer)]) {
    if (!tester.any(container)) continue;
    final entry = find.descendant(of: container, matching: find.text(label));
    if (tester.any(entry)) {
      debugPrint('SIDEBAR: 在侧栏里点 [$label]');
      await tester.tap(entry.first);
      return;
    }
    debugPrint('SIDEBAR: 侧栏存在但没有 [$label] 项');
  }
  debugPrint('SIDEBAR: 未找到侧栏容器或 [$label] 项，跳过点击');
}

/// 窄窗布局下 NavigationDrawer 默认是关着的（树里都没有），先打开。
Future<void> openDrawerIfNeeded(WidgetTester tester) async {
  if (!tester.any(find.byType(NavigationDrawer))) {
    final scaffolds = find.byType(Scaffold);
    if (tester.any(scaffolds)) {
      final state = tester.state<ScaffoldState>(scaffolds.first);
      if (state.hasDrawer && !state.isDrawerOpen) {
        debugPrint('SIDEBAR: 打开 NavigationDrawer');
        state.openDrawer();
        await tester.pump(const Duration(milliseconds: 500));
      }
    }
  }
}

/// 打印 UI 现场：onstage / 含 offstage 双视角 + 布局标记。
///
/// 为什么要双视角：`find.*` 默认 `skipOffstage: true`（走
/// `debugVisitOnstageChildren`），而 `WidgetController.allElements` 用
/// `collectAllElementsFrom(skipOffstage: false)`（flutter_test/src/controller.dart:856）。
/// 差值就是「树建好了但不在台上」的直接证据。框架里会摘下子树的闸门只有：
/// `Offstage` / `_IndexedStackElement` / `_TheatreElement`(Overlay) /
/// `_ViewportElement`(滚动视口) / sliver 系列（basic.dart:3566、4890，
/// overlay.dart:1019，viewport.dart:322，sliver.dart:1268/1504/1860）。
void dumpUi(WidgetTester tester, String tag) {
  String text(Text w) => w.data ?? w.textSpan?.toPlainText() ?? '(rich)';

  final onstageTexts = tester.widgetList<Text>(find.byType(Text)).map(text).toList();
  final allTexts = tester.widgetList<Text>(find.byType(Text, skipOffstage: false)).map(text).toList();

  final hist = <String, int>{};
  for (final e in find.byWidgetPredicate((_) => true).evaluate()) {
    final name = e.widget.runtimeType.toString();
    hist[name] = (hist[name] ?? 0) + 1;
  }
  final top = hist.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

  // app 实际布局用的尺寸（最外层 MediaQuery），用来核对视口尺寸是否被改坏。
  Size? layoutSize;
  final mediaQueries = find.byType(MediaQuery, skipOffstage: false).evaluate();
  if (mediaQueries.isNotEmpty) {
    layoutSize = (mediaQueries.first.widget as MediaQuery).data.size;
  }

  debugPrint('=== UI-DUMP[$tag] ==================================================');
  debugPrint('view: physical=${tester.view.physicalSize} dpr=${tester.view.devicePixelRatio}');
  debugPrint('app 布局尺寸(最外层 MediaQuery): $layoutSize');
  debugPrint(
    '元素数: onstage=${find.byWidgetPredicate((_) => true).evaluate().length} '
    '/ 全量(含 offstage)=${tester.allElements.length}',
  );
  debugPrint('文本数: onstage=${onstageTexts.length} / 全量=${allTexts.length}');
  debugPrint('onstage 文本(前 40): ${onstageTexts.take(40).toList()}');
  debugPrint('全量文本(前 60): ${allTexts.take(60).toList()}');
  debugPrint('onstage 类型 top20: ${top.take(20).map((e) => '${e.key}x${e.value}').join(', ')}');
  debugPrint(
    '布局标记: rail=${tester.any(find.byType(NavigationRail))} '
    'drawer=${tester.any(find.byType(NavigationDrawer))} '
    'scaffold=${tester.any(find.byType(Scaffold))} '
    'appbar=${tester.any(find.byType(AppBar))} '
    'fab=${tester.any(find.byType(FloatingActionButton))} '
    'bottombar=${tester.any(find.byType(BottomNavigationBar))} '
    '占位页=${tester.any(find.text('Test starting...'))}',
  );
  debugPrint('=== UI-DUMP END ====================================================');
}
