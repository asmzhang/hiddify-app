// L1 结构对等测试 —— 手动新建节点动线 startManualNodeFlow 1:1 对照 NekoBox
// 节点页 ＋ → Manual Settings（`add_profile_menu.xml` 二级协议菜单）→ 对应
// `*SettingsActivity`（chain/config）或 `ProfileSettingsActivity`（editingId==0 分支）。
// - 三步动线：①选协议（未指定 initialProtocol 时 SimpleDialog 列全量
//   kManualCreatableProtocols）→ ②定归属组（selectedGroupForImport：无 BASIC
//   懒建「未分组」）→ ③分支开弹层（chain→ChainSettings 新建 / config→
//   ConfigSettings 新建 / 其余→ProtocolFormModal 新建）；
// - 弹层走 showRootBottomSheet（rootNavKey 栈）→ GoRouter + MaterialApp.router 包裹；
// - 注入面：translationsProvider（slang 延迟加载 zh-CN）、sharedPreferencesProvider
//   （弹层链路会构造 selectedProxyGroupTagProvider，构造即读 prefs）、
//   proxyEntityRepositoryProvider（ProxyEntityRepository 是具体类，纯 fake 不可行
//   → 真 repo + drift 内存库，golden 模式照 proxy_entity_import_repository_test.dart；
//   selectedGroupForImport(null) 懒建「未分组」返回真实主键）、
//   inAppNotificationControllerProvider（记账 fake，不碰 overlay）。
// 刻意不测：真实落库/内核换配置链（createNode 属 proxies_overview_notifier 测试面）。
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_repository.dart';
import 'package:hiddify/features/proxy/widget/manual_node_flow.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

class _MockPathResolver extends Mock implements ProfilePathResolver {}

class _MockCoreService extends Mock implements HiddifyCoreService {}

/// 记账版通知控制器：不碰 overlay，直接记下 toast 文本供断言。
class _FakeNotificationController extends InAppNotificationController {
  final errors = <String>[];
  final successes = <String>[];

  @override
  ToastificationItem? showErrorToast(String message) {
    errors.add(message);
    return null;
  }

  @override
  ToastificationItem? showSuccessToast(String message) {
    successes.add(message);
    return null;
  }
}

/// 动线入口：真实页面里是「＋ → 手动输入」菜单，这里收敛成一个按钮。
class _FlowHostPage extends ConsumerWidget {
  const _FlowHostPage({this.initialProtocol});

  final String? initialProtocol;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => startManualNodeFlow(context, ref, initialProtocol: initialProtocol),
        child: const Text('GO'),
      ),
    ),
  );
}

Future<void> _pump(WidgetTester tester, {String? initialProtocol}) async {
  // PlatformUtils 按 defaultTargetPlatform 判平台（可测试版设计），测试默认
  // android → 钉 Windows 对齐「Windows 宿主 = desktop OS」前提。
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  // 重置不能走 addTearDown：foundation invariant 检查在 test body 内执行
  // （flutter_test binding.dart:1073-1078），addTearDown 晚于它会炸
  // "The value of a foundation debug variable was changed by the test."
  // → 每个用例 body 末尾显式 _resetPlatformOverride()。
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // 弹层链路会读 selectedProxyGroupTagProvider（PreferencesNotifier 构造即读 prefs）。
  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final db = Db(NativeDatabase.memory());
  addTearDown(db.close);
  final notifications = _FakeNotificationController();
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      // 真 repo + 内存库：selectedGroupForImport(null) 会懒建「未分组」BASIC 组。
      proxyEntityRepositoryProvider.overrideWith(
        (ref) => ProxyEntityRepository(db: db, pathResolver: _MockPathResolver(), singbox: _MockCoreService()),
      ),
      inAppNotificationControllerProvider.overrideWith((ref) => notifications),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  final router = GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavKey,
    routes: [GoRoute(path: '/', builder: (_, _) => _FlowHostPage(initialProtocol: initialProtocol))],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)),
  );
  await tester.pumpAndSettle();
}

void _resetPlatformOverride() {
  debugDefaultTargetPlatformOverride = null;
}

/// 进弹层路径的统一驱动：点按钮 → 给 drift 一段真异步 → 泵到弹层稳定。
/// [bounded]=false 时禁用 pumpAndSettle：ChainSettingsModal 的 useFuture
/// （drift 真异步）在 FakeAsync 域内永不完成，pumpAndSettle 会超时
/// （与 logs 页 SliverLoadingBodyPlaceholder 同坑）→ 改有界泵。
Future<void> _tapGoAndSettle(WidgetTester tester, {bool bounded = true}) async {
  await tester.tap(find.text('GO'));
  // drift 内存库的查询 Future 链在 FakeAsync 域外完成更稳，真时间兜底一把。
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  if (bounded) {
    await tester.pumpAndSettle();
  } else {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }
}

void main() {
  group('手动新建节点动线', () {
    testWidgets('未指定 initialProtocol：先弹「选择协议」，列出全部可建协议', (tester) async {
      await _pump(tester);
      await _tapGoAndSettle(tester);

      expect(find.text('选择协议'), findsOneWidget);
      expect(find.byType(SimpleDialogOption), findsNWidgets(kManualCreatableProtocols.length));
      for (final protocol in kManualCreatableProtocols) {
        expect(find.text(protocolDisplayName(protocol)), findsWidgets, reason: '菜单缺 $protocol');
      }
      _resetPlatformOverride();
    });

    testWidgets('选协议取消：只关对话框，不开任何弹层', (tester) async {
      await _pump(tester);
      await _tapGoAndSettle(tester);
      expect(find.text('选择协议'), findsOneWidget);

      await tester.tapAt(const Offset(20, 20)); // 点 barrier = 取消
      await tester.pumpAndSettle();

      expect(find.byType(SimpleDialog), findsNothing);
      expect(find.text('新建节点'), findsNothing);
      expect(find.text('配置名称'), findsNothing);
      _resetPlatformOverride();
    });

    testWidgets('指定 initialProtocol：跳过选协议直达新建表单', (tester) async {
      await _pump(tester, initialProtocol: 'shadowsocks');
      await _tapGoAndSettle(tester);

      expect(find.text('选择协议'), findsNothing);
      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('配置名称'), findsOneWidget);
      _resetPlatformOverride();
    });

    testWidgets('protocol=chain：开 ChainSettings 新建弹层（空成员列表）', (tester) async {
      await _pump(tester, initialProtocol: kChainEntityType);
      await _tapGoAndSettle(tester, bounded: false);

      expect(find.text('新建节点'), findsNothing); // chain 不走协议表单
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.text('添加节点'), findsOneWidget); // 空成员 → 只有添加行
      expect(find.text('流量自上而下：第一个是入口，最后一个是落地。长按拖动排序，左滑删除。'), findsOneWidget);
      _resetPlatformOverride();
    });

    testWidgets('protocol=config：开 ConfigSettings 新建弹层', (tester) async {
      await _pump(tester, initialProtocol: kConfigEntityType);
      await _tapGoAndSettle(tester);

      expect(find.text('新建节点'), findsNothing); // config 不走协议表单
      expect(find.text('添加节点'), findsNothing);
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.text('配置 JSON'), findsOneWidget);
      _resetPlatformOverride();
    });

    testWidgets('普通协议：开 ProtocolFormModal 新建弹层', (tester) async {
      await _pump(tester, initialProtocol: 'shadowsocks');
      await _tapGoAndSettle(tester);

      expect(find.text('选择协议'), findsNothing);
      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.text('服务器'), findsOneWidget);
      _resetPlatformOverride();
    });
  });
}
