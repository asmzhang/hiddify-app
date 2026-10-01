// L1 结构对等测试 —— 协议表单弹层 ProtocolFormModal 1:1 对照 NekoBox
// ProfileSettingsActivity（用例 g-l，①「手动新建节点」链的表单半区；
// 用例 a-f 见 manual_node_flow_spec_test.dart）。
// - 覆盖：新建表单字段渲染（g）/ 空名拒存（h）/ 填名落库断参（i）/
//   unsupported 占位（j）/ 坏 JSON 占位（k）/ 编辑回显与未编辑键保留（l）；
// - 注入面：proxiesOverviewNotifierProvider 用 fake notifier —— override build()
//   为现成 Stream，**不调 ref.disposeDelay** ⇒ 无 15s Timer 残留，FakeAsync 不会炸
//   "A Timer is still pending"（同 logs 页 disposeDelay 坑）；toast 用记账 fake
//   （不碰 overlay）；无需 proxyEntityRepository（fake 不碰仓库）⇒ 无 drift 真异步
//   ⇒ pumpAndSettle 全程可用；表单弹层是 DraggableScrollableSheet，无循环动画；
// - 弹层走 showRootBottomSheet（rootNavKey 栈）→ GoRouter + MaterialApp.router 包裹；
//   本链路不读 PlatformUtils ⇒ 不设 debugDefaultTargetPlatformOverride（无 invariant 收尾）。
// 刻意不测：15 协议字段级规格矩阵（⑤规格 P0/P1/P2 三批另测，见
// .workbuddy/spec-protocol-forms-tests.md）。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/protocol_form_modal.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

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

/// 假列表 notifier：build() 给现成 Stream（不挂 disposeDelay ⇒ 无 Timer 残留），
/// 三个写方法记账并返回成功值（成功值形状照 db.dart 的 ProxyEntityEntry 全字段构造）。
class _FakeOverviewNotifier extends ProxiesOverviewNotifier {
  final createCalls = <Map<String, Object?>>[];
  final updatePayloadCalls = <Map<String, Object?>>[];
  final updateOverridesCalls = <Map<String, Object?>>[];

  @override
  Stream<OutboundGroup?> build() => Stream<OutboundGroup?>.value(OutboundGroup());

  @override
  Future<ProxyEntityEntry?> createNode({required int groupId, required String tag, required String type, required String payload}) async {
    createCalls.add({'groupId': groupId, 'tag': tag, 'type': type, 'payload': payload});
    return ProxyEntityEntry(
      id: 1,
      groupId: groupId,
      tag: tag,
      type: type,
      displayName: tag,
      userOrder: 0,
      tx: 0,
      rx: 0,
      status: 0,
      ping: 0,
      payload: payload,
      customOutbound: '',
      customConfig: '',
    );
  }

  @override
  Future<bool> updateNodePayload({String? profileId, int? groupId, required String tag, required String payload}) async {
    updatePayloadCalls.add({'profileId': profileId, 'groupId': groupId, 'tag': tag, 'payload': payload});
    return true;
  }

  @override
  Future<bool> updateNodeOverrides({String? profileId, int? groupId, required String tag, String? customOutbound, String? customConfig}) async {
    updateOverridesCalls.add({'profileId': profileId, 'groupId': groupId, 'tag': tag, 'customOutbound': customOutbound, 'customConfig': customConfig});
    return true;
  }
}

class _Fixture {
  final notifications = _FakeNotificationController();
  final notifier = _FakeOverviewNotifier();
}

/// 弹层入口宿主：真实页面里是「＋ → 手动输入」（新建）/ 节点行 ✎（编辑），
/// 这里收敛成一个按钮，由用例决定打开方式。
class _HostPage extends StatelessWidget {
  const _HostPage({required this.open});

  final void Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: FilledButton(onPressed: () => open(context), child: const Text('GO'))));
}

Future<void> _pump(WidgetTester tester, {required void Function(BuildContext context) open, _Fixture? fixture}) async {
  final f = fixture ?? _Fixture();
  // 弹层高 0.75 视口 + ListView 懒构建：默认 800x600 只建得下前几个字段，
  // 放大视口保证 anytls 全字段（配置名称 → uTLS 指纹）一次全部建出。
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // 弹层链路会构造 selectedProxyGroupTagProvider（构造即读 prefs）——虽然本文件
  // 的 fake notifier 不再触发它，保持与 manual_node_flow 同一套注入底座。
  SharedPreferences.setMockInitialValues(const {});
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
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

/// 按 label 找字段并整体替换文本（TextFormField 的 label 渲染成子 Text，可定位）。
Future<void> _fill(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
  await tester.pump();
}

void main() {
  group('协议表单弹层（新建/编辑）', () {
    testWidgets('g 新建表单渲染：anytls 全字段 + 分节 + 布尔/下拉形态 + ⋮ 菜单不存在', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'anytls'), fixture: f);
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      // 头部：createTitle + 协议类型副标题；isCreate 才有配置名称；⋮ 菜单只在编辑模式
      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('anytls'), findsOneWidget);
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      // 分节（_sectionLabel → section.proxy / section.security）
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget);
      // 字段（_fieldLabel → t.pages.proxies.form.*，与规格矩阵 server→uTLS 全列）
      expect(find.text('服务器'), findsOneWidget);
      expect(find.text('服务器端口'), findsOneWidget);
      expect(find.text('密码'), findsOneWidget);
      expect(find.text('服务器名称指示'), findsOneWidget);
      expect(find.text('允许不安全的连接'), findsOneWidget);
      expect(find.text('应用层协议协商'), findsOneWidget);
      expect(find.text('证书 (链)'), findsOneWidget);
      expect(find.text('uTLS 指纹'), findsOneWidget);
      // 形态：boolean = SwitchListTile（anytls 仅 allowInsecure 一个布尔字段）
      expect(find.byWidgetPredicate((w) => w is SwitchListTile), findsOneWidget);
      // 形态：choice 空值显示 notSet（uTLS 指纹未选）
      expect(find.text('未设置'), findsOneWidget);
    });

    testWidgets('h 空名拒存：新建不落库 + name 错误标星 + 错误 toast；补名后放行', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'anytls'), fixture: f);
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      // 只填服务器、不填配置名称 → 保存被拦
      await _fill(tester, '服务器', '1.2.3.4');
      await tester.tap(find.text('保存'));
      await tester.pump();

      expect(f.notifications.errors, ['意外错误']); // showErrorToast(t.errors.unexpected)
      expect(f.notifier.createCalls, isEmpty); // 不落库
      expect(find.text('新建节点'), findsOneWidget); // 弹层仍开着
      // TextFormField 不暴露 decoration ⇒ 断言内层 TextField
      final nameField = tester.widget<TextField>(find.widgetWithText(TextField, '配置名称'));
      expect(nameField.decoration?.errorText, '*'); // isCreate && name.isEmpty → 'name' 错误
      final serverField = tester.widget<TextField>(find.widgetWithText(TextField, '服务器'));
      expect(serverField.decoration?.errorText, isNull); // 服务器已填，不标错

      // 补上名字再存 → 放行（证明拦的就是名字）
      await _fill(tester, '配置名称', '临时名');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(f.notifier.createCalls.single['tag'], '临时名');
    });

    testWidgets('i 填名保存：createNode 断参 + payload 成形 + 成功 toast + 关弹层', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'anytls'), fixture: f);
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      await _fill(tester, '配置名称', '节点甲');
      await _fill(tester, '服务器', '5.6.7.8');
      await _fill(tester, '服务器端口', '443');
      await _fill(tester, '密码', 'pw-9');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final call = f.notifier.createCalls.single;
      expect(call['groupId'], 7);
      expect(call['tag'], '节点甲');
      expect(call['type'], 'anytls');
      final payload = jsonDecode(call['payload']! as String) as Map<String, dynamic>;
      expect(payload['type'], 'anytls');
      expect(payload['tag'], '节点甲');
      expect(payload['server'], '5.6.7.8');
      expect(payload['server_port'], 443); // integer 字段落成数字
      expect(payload['password'], 'pw-9');
      // 种子键 tls.enabled=true 原样保留（protocolSeedPayload）；没填的 TLS 字段不写键
      expect(payload['tls'], {'enabled': true});
      // 成功 toast（t.pages.proxies.form.created）+ 弹层已关（Navigator.pop）
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });

    testWidgets('j unsupported：trojan_go 无表单规格 = 占位文案页（不移植协议，规格 §1）', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'trojan_go'), fixture: f);
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      expect(find.text('该协议暂无编辑表单'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing); // 无字段无输入
      expect(find.text('保存'), findsNothing);
    });

    testWidgets('k 坏 JSON：编辑打开解析失败 = 占位文案页', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'anytls', tag: '旧节点', payloadJson: '{not json', groupId: 7),
        fixture: f,
      );
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      expect(find.text('无法解析该节点的出站 JSON'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
      expect(find.text('保存'), findsNothing);
    });

    testWidgets('l 编辑回显：字段回显 + ⋮ 菜单在 + 保存只动改过的键', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'anytls', tag: '旧节点', payloadJson: _anytlsEditPayload, groupId: 7),
        fixture: f,
      );
      await tester.tap(find.text('GO'));
      await tester.pumpAndSettle();

      // 头部：编辑标题 + 「协议 · tag」副标题；编辑无配置名称字段；⋮ 菜单只在编辑模式
      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('anytls · 旧节点'), findsOneWidget);
      expect(find.text('配置名称'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      // 回显（readProtocolFormValues + _stringify：int→toString、List→逗号连接）
      expect(find.text('1.1.1.1'), findsOneWidget);
      expect(find.text('8443'), findsOneWidget);
      expect(find.text('pw-1'), findsOneWidget);
      expect(find.text('old.example.com'), findsOneWidget);
      expect(find.text('h2,http/1.1'), findsOneWidget);
      expect(find.text('CERT-1'), findsOneWidget);
      expect(find.text('chrome'), findsOneWidget); // choice trailing 当前取值

      // 只改服务器地址 → 保存
      await _fill(tester, '服务器', '9.9.9.9');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final call = f.notifier.updatePayloadCalls.single;
      expect(call['groupId'], 7);
      expect(call['profileId'], isNull);
      expect(call['tag'], '旧节点'); // 编辑不改名（tag 是身份，改名是独立功能）
      final payload = jsonDecode(call['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], '9.9.9.9'); // 改过的键生效
      // 未动键原样保留（applyProtocolForm 只写表单管的键，其余原样）
      expect(payload['server_port'], 8443);
      expect(payload['password'], 'pw-1');
      expect(payload['tag'], '旧节点');
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls['enabled'], true); // 表单没有对应字段 ⇒ 靠"原样保留"活下来
      expect(tls['server_name'], 'old.example.com');
      expect(tls['insecure'], true);
      expect((tls['utls']! as Map<String, dynamic>)['fingerprint'], 'chrome');
      // 没碰 ⋮ 菜单 ⇒ 不写节点级覆写
      expect(f.notifier.updateOverridesCalls, isEmpty);
      // 成功 toast（t.pages.proxies.form.saved）+ 弹层已关
      expect(f.notifications.successes, ['节点已更新']);
      expect(find.text('编辑节点'), findsNothing);
    });
  });
}

/// 编辑回显素材：anytls 全字段已填 + 非表单键（tls.enabled）+ 嵌套 utls 容器。
const _anytlsEditPayload =
    '{"type":"anytls","tag":"旧节点","server":"1.1.1.1","server_port":8443,"password":"pw-1",'
    '"tls":{"enabled":true,"server_name":"old.example.com","insecure":true,'
    '"alpn":["h2","http/1.1"],"certificate":"CERT-1","utls":{"enabled":true,"fingerprint":"chrome"}}}';
