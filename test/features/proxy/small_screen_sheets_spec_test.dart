// ⑨ 终验收 · 小屏形态（<600dp）——HANDOVER §7 未验证清单最后一块：
//   协议表单 / chain 弹窗 / config 弹窗此前只在 Windows ≥600dp 看过。
// 样板照抄 test/features/route_rules/rule_page_test.dart 的「小屏手机形态」组：
//   tester.view.physicalSize/devicePixelRatio 钉视口，溢出会以 FlutterError
//   抛回测试 ⇒ 用例失败，所以「能渲染完 + takeException isNull」本身就是断言；
//   再补关键控件可达性断言（保存键/名字框在树）。
// 两档视口：360×640dp（常见安卓最小逻辑宽度，dpr 3.0）/ 320×568dp（iPhone SE
//   级最窄，dpr 2.0）——与路由规则页小屏组同参数。
// 基建照抄 protocol_form_fields_p0_spec_test.dart（六坑纪律同，见该文件头注）；
//   chain/config 弹窗 build 有 useFuture（drift 真异步）⇒ 有界泵
//   （manual_node_flow_spec_test.dart 的 _tapGoAndSettle bounded:false 同坑）。
import 'dart:convert';

import 'package:drift/native.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_repository.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/chain_settings_page.dart';
import 'package:hiddify/features/proxy/widget/config_settings_page.dart';
import 'package:hiddify/features/proxy/widget/protocol_form_modal.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
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

/// 假列表 notifier：build() 给现成 Stream（不挂 disposeDelay ⇒ 无 Timer 残留）。
/// 一次 _pump 一个新实例——同一实例挂进第二个 ProviderContainer 会炸
/// LateError（P2 实证新坑②）。
class _FakeOverviewNotifier extends ProxiesOverviewNotifier {
  @override
  Stream<OutboundGroup?> build() => Stream<OutboundGroup?>.value(OutboundGroup());
}

class _Fixture {
  final notifications = _FakeNotificationController();
  final notifier = _FakeOverviewNotifier();
}

/// 弹层入口宿主：由用例决定打开方式（协议新建 / chain 新建 / config 新建）。
class _HostPage extends StatelessWidget {
  const _HostPage({required this.open});

  final void Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: FilledButton(onPressed: () => open(context), child: const Text('GO'))));
}

Future<void> _pump(
  WidgetTester tester, {
  required void Function(BuildContext context) open,
  required Size dp,
  required double dpr,
}) async {
  tester.view.physicalSize = Size(dp.width * dpr, dp.height * dpr);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final db = Db(NativeDatabase.memory());
  addTearDown(db.close);
  final f = _Fixture();
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      // 真 repo + 内存库：chain/config 弹窗 build 里 useFuture(read selectableChainMembers)
      // 是 drift 真异步，P0 假 notifier 路线覆盖不到这里。
      proxyEntityRepositoryProvider.overrideWith(
        (ref) => ProxyEntityRepository(db: db, pathResolver: _MockPathResolver(), singbox: _MockCoreService()),
      ),
      proxiesOverviewNotifierProvider.overrideWith(() => f.notifier),
      inAppNotificationControllerProvider.overrideWith((ref) => f.notifications),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);

  final router = GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavKey,
    routes: [GoRoute(path: '/', builder: (_, _) => _HostPage(open: open))],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(UncontrolledProviderScope(container: container, child: MaterialApp.router(routerConfig: router)));
  await tester.pumpAndSettle();
}

/// 进弹层路径统一驱动。chain/config 弹窗 build 挂 drift useFuture ⇒ FakeAsync
/// 域内永不完成，pumpAndSettle 必超时 → 有界泵（12×50ms）+ runAsync 真时间兜底。
Future<void> _tapGoAndSettle(WidgetTester tester) async {
  await tester.tap(find.text('GO'));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('⑨ 小屏 · 协议表单（<600dp）', () {
    testWidgets('360×640dp：vless 新建渲染无溢出，18 字段一屏未裁剪', (tester) async {
      await _pump(
        tester,
        dp: const Size(360, 640),
        dpr: 3.0,
        open: (context) => showProtocolCreateSheet(groupId: 7, type: 'vless'),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      // 固定底栏（保存键恒在树，ListView 之外）。
      expect(find.text('保存'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '配置名称'), findsOneWidget);
      // 小屏语义：字段最多协议（vless 18 字段）的 TLS 分节**滚动可达**——
      // ListView 懒构建，360dp 一屏只有前几个字段在树（首跑实证：屏外分节
      // find 落空），滚到底部必须能到达。
      await tester.scrollUntilVisible(find.text('TLS 安全设置'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('TLS 安全设置'), findsOneWidget);
    });

    testWidgets('320×568dp：shadowsocks 新建渲染无溢出（含插件分节）', (tester) async {
      await _pump(
        tester,
        dp: const Size(320, 568),
        dpr: 2.0,
        open: (context) => showProtocolCreateSheet(groupId: 7, type: 'shadowsocks'),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      // 小屏语义：插件分节**滚动可达**（同上，ListView 懒构建）。分节标题 +
      // 字段 label 同文案「插件」⇒ findsNWidgets(2)（P0 坑⑤）。
      // 双匹配文本不能走 scrollUntilVisible（内部 single：No element / Too many
      // elements 两头炸，首跑实证）——手写有界拖拽循环。
      var reached = false;
      for (var i = 0; i < 30 && !reached; i++) {
        if (find.text('插件').evaluate().isNotEmpty) {
          reached = true;
          break;
        }
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -150));
        await tester.pump();
      }
      expect(reached, isTrue, reason: '插件分节滚动可达');
      expect(find.text('插件'), findsNWidgets(2));
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('360×640dp：编辑回显渲染无溢出（jsonInvalid 弹层走同一布局）', (tester) async {
      await _pump(
        tester,
        dp: const Size(360, 640),
        dpr: 3.0,
        open: (context) => showProtocolFormSheet(
          groupId: 7,
          tag: '旧节点',
          type: 'vless',
          payloadJson: jsonEncode({
            'address': 'example.com',
            'port': 443,
            'uuid': 'b831381d-6324-4d53-ad4f-8cda48b30811',
            'tls': {'enabled': true, 'server_name': 'example.com'},
          }),
        ),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });
  });

  group('⑨ 小屏 · chain 弹窗（<600dp）', () {
    testWidgets('360×640dp：新建渲染无溢出，名字框/添加行/保存键齐全', (tester) async {
      await _pump(
        tester,
        dp: const Size(360, 640),
        dpr: 3.0,
        open: (context) => showChainSettingsSheet(tag: '', groupId: '7', chainGroupId: 7, isNew: true),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextFormField, '配置名称'), findsOneWidget);
      expect(find.text('流量自上而下：第一个是入口，最后一个是落地。长按拖动排序，左滑删除。'),
          findsOneWidget, reason: '排序提示行（bodySmall）在窄屏不溢出');
      expect(find.text('添加节点'), findsOneWidget, reason: '空链也有 AddHolder 行');
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('320×568dp：编辑模式带成员渲染无溢出，跳位/落地副标题正确', (tester) async {
      await _pump(
        tester,
        dp: const Size(320, 568),
        dpr: 2.0,
        open: (context) => showChainSettingsSheet(
          tag: '旧链',
          groupId: '7',
          chainGroupId: 7,
          initialProxies: const ['入口A', '中转B', '落地C'], // 传成员 ⇒ 编辑模式（isNew 缺省 false）
        ),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('入口A'), findsOneWidget);
      expect(find.text('第 1 跳'), findsOneWidget, reason: '首行入口跳位');
      expect(find.text('第 2 跳'), findsOneWidget);
      expect(find.text('落地（出口）'), findsOneWidget, reason: '末行落地');
      expect(find.text('添加节点'), findsOneWidget);
    });
  });

  group('⑨ 小屏 · config 弹窗（<600dp）', () {
    testWidgets('360×640dp：新建渲染无溢出，名字框/JSON 框/保存键齐全', (tester) async {
      await _pump(
        tester,
        dp: const Size(360, 640),
        dpr: 3.0,
        open: (context) => showConfigSettingsSheet(tag: '', groupId: '7', configGroupId: 7, isNew: true),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(TextFormField, '配置名称'), findsOneWidget);
      expect(find.text('配置 JSON'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('320×568dp：编辑模式 outbound 形态提示渲染无溢出', (tester) async {
      await _pump(
        tester,
        dp: const Size(320, 568),
        dpr: 2.0,
        open: (context) => showConfigSettingsSheet(
          tag: '旧配置',
          groupId: '7',
          configGroupId: 7,
          initialPayload: jsonEncode({'type': 'shadowsocks', 'server': 'example.com', 'server_port': 8388}), // 传 payload ⇒ 编辑模式
        ),
      );
      await _tapGoAndSettle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('此 JSON 是单个出站（含 "type" 键）'), findsOneWidget,
          reason: '顶层 type 键 → outbound 形态提示');
      expect(find.text('配置 JSON'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });
  });
}
