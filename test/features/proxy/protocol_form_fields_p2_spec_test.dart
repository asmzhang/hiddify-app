// P2 批次（⑤规格 §3 批次 3）：协议表单「字段级 1:1」widget 测试 · 收尾批
// —— socks / http / shadowtls / mieru / wireguard / naive 六协议 + chain/config 入口 display 名
//    + 菜单 17 项顺序回归（nkManualProtocolMenu === kManualCreatableProtocols 逐项 label）。
// 每协议 2-3 用例：① 新建渲染（zh 字段 label 全在树、分节标题、choice/boolean 形态）；
//   ② 编辑回显（payload 按反查规则回显：writeValues 反查 / 数组逗号 join / int→toString）；
//   ③ 新建保存（payload 关键 path 落值：种子键 / writeValues 写 int·null / integerList 数字数组 /
//      死字段不落键 / 空值删键）。
// 判定基准：zh-CN 词表（assets/translations/zh-CN.i18n.json 的 pages.proxies.form.*）；
// 字段清单以代码 lib/features/proxy/data/protocol_form.dart 为准
// （socks:599 / http:625 / shadowtls:726 / mieru:764 / wireguard:797 /
//   naive:822 / kManualCreatableProtocols:894 / protocolDisplayName:917）。
// 基建与六坑纪律照抄 P0/P1 样板（protocol_form_fields_p0/p1_spec_test.dart）：
//   ① fake notifier build() 给现成 Stream、不挂 disposeDelay ⇒ 无 pending Timer；
//   ② 不注入 proxyEntityRepository ⇒ 无 drift 真异步 ⇒ pumpAndSettle 全程可用；
//   ③ 不设 debugDefaultTargetPlatformOverride（本链路不读 PlatformUtils）；
//   ④ zh 词表 runAsync 预构建 + translationsProvider.overrideWith + pre-warm future；
//   ⑤ 视口 1080x2400 / dpr 1.0（wireguard 9 行全字段一次建出）；
//   ⑥ TextFormField 无 decoration getter，断 errorText 用内层 TextField。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/overview/add_profile_menu_spec.dart';
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
/// 三个写方法记账并返回成功值（形状照 db.dart 的 ProxyEntityEntry 全字段构造）。
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

/// 弹层入口宿主：由用例决定打开方式（新建 / 编辑）。
class _HostPage extends StatelessWidget {
  const _HostPage({required this.open});

  final void Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: FilledButton(onPressed: () => open(context), child: const Text('GO'))));
}

Future<void> _pump(WidgetTester tester, {required void Function(BuildContext context) open, _Fixture? fixture}) async {
  final f = fixture ?? _Fixture();
  // 弹层高 0.75 视口 + ListView 懒构建：放大视口保证全字段一次建出，find 不漏。
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

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
  // pre-warm：translationsProvider 必须先读到值，弹层 build 里 requireValue 才不炸。
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

Future<void> _tapGo(WidgetTester tester) async {
  await tester.tap(find.text('GO'));
  await tester.pumpAndSettle();
}

/// 按 label 找字段并整体替换文本（TextFormField 的 label 渲染成子 Text，可定位）。
Future<void> _fill(WidgetTester tester, String label, String text) async {
  await tester.enterText(find.widgetWithText(TextFormField, label), text);
  await tester.pump();
}

/// 点开 choice 字段的下拉对话框并选中一项（对话框选项文本与表单不冲突时取 .last 兜底）。
Future<void> _pickChoice(WidgetTester tester, {required String label, required String option}) async {
  await tester.tap(find.widgetWithText(ListTile, label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(option).last);
  await tester.pumpAndSettle();
}

/// 拨动 boolean 字段（SwitchListTile）：开='true'，关='false'（关=删键语义）。
Future<void> _toggle(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(SwitchListTile, label));
  await tester.pump();
}

/// 六坑⑥：TextFormField 无 decoration getter，errorText 断内层 TextField。
String? _errorTextOf(WidgetTester tester, String label) =>
    tester.widget<TextField>(find.widgetWithText(TextField, label)).decoration?.errorText;

// ─────────────────────────────────────────────────────────────────────────────
// 编辑回显素材
// ─────────────────────────────────────────────────────────────────────────────

const _socksEditPayload =
    '{"type":"socks","tag":"socks节点","server":"s.example.com","server_port":1080,'
    '"version":"5","username":"u1","password":"p1"}';

const _httpEditPayload =
    '{"type":"http","tag":"http节点","server":"h.example.com","server_port":8080,'
    '"username":"hu","password":"hp",'
    '"tls":{"enabled":true,"server_name":"hs.example.com","insecure":true,"alpn":["h2"],"certificate":"HC-1",'
    '"utls":{"enabled":true,"fingerprint":"edge"}}}';

const _shadowtlsEditPayload =
    '{"type":"shadowtls","tag":"stl节点","server":"st.example.com","server_port":443,'
    '"version":3,"password":"stl-pw",'
    '"tls":{"enabled":true,"server_name":"sts.example.com","alpn":["h2"],"certificate":"STL-1","insecure":true}}';

/// mieru：portBindings[0] 数组下标路径（server/port/protocol 全落在 [0] 元素里）。
const _mieruEditPayload =
    '{"type":"mieru","tag":"mieru节点","server":"m.example.com",'
    '"portBindings":[{"port":12345,"protocol":"UDP"}],'
    '"username":"mu","password":"mp"}';

/// wireguard：peers[0] 数组下标路径 + reserved 数字数组 + localAddress CIDR 数组。
const _wireguardEditPayload =
    '{"type":"wireguard","tag":"wg节点","address":["172.16.0.2/32"],'
    '"private_key":"WG-PRIV","mtu":1420,'
    '"peers":[{"address":"wg.example.com","port":51820,"public_key":"WG-PBK",'
    '"pre_shared_key":"WG-PSK","reserved":[1,2,3]}]}';

const _naiveEditPayload =
    '{"type":"naive","tag":"naive节点","server":"n.example.com","server_port":443,'
    '"username":"nu","password":"np","quic":true,"insecure_concurrency":4,'
    '"tls":{"enabled":true,"server_name":"ns.example.com","certificate":"NC-1"}}';

void main() {
  group('P2 字段级 1:1 · socks（_socksSpec L481-490）', () {
    testWidgets('新建渲染：5 字段 + 协议下拉三档（4/4a/5）+ 无 TLS 组 + 星标仅服务器', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'socks'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('socks'), findsOneWidget);
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing); // 新建无 ⋮
      // 分节：只有 serverAddress 标 proxy —— 单节；socks 无 TLS
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsNothing);
      for (final label in const ['服务器', '服务器端口', '协议', '用户名', '密码']) {
        expect(find.text(label), findsOneWidget, reason: 'socks 缺字段 label：$label');
      }
      // choice 空值显示「未设置」：version 下拉未选
      expect(find.text('未设置'), findsOneWidget);
      // 服务器端口是 integer（无 valueSuffix），密码/用户名是 text；无 boolean
      expect(find.byType(SwitchListTile), findsNothing);

      // 必填星标：仅 serverAddress（required:true，其余字段 required 缺省）
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '用户名'), isNull);
      expect(_errorTextOf(tester, '密码'), isNull);
      expect(f.notifier.createCalls, isEmpty);
      expect(f.notifications.errors, ['意外错误']); // 表单拦截走 showErrorToast(errors.unexpected)
    });

    testWidgets('编辑回显：version 串原样 + user/pass 平铺', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'socks', tag: 'socks节点', payloadJson: _socksEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('socks · socks节点'), findsOneWidget);
      expect(find.text('s.example.com'), findsOneWidget);
      expect(find.text('1080'), findsOneWidget); // int → toString
      expect(find.text('5'), findsOneWidget); // version choice 原串
      expect(find.text('u1'), findsOneWidget);
      expect(find.text('p1'), findsOneWidget);
      expect(f.notifier.updatePayloadCalls, isEmpty);
    });

    testWidgets('新建保存：serverProtocol=5 → version 原串；全部空的可选键不落', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'socks'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'socks节点甲');
      await _fill(tester, '服务器', 'socks-new.example.com');
      await _fill(tester, '服务器端口', '1080');
      await _pickChoice(tester, label: '协议', option: '5');
      await _fill(tester, '用户名', 'su');
      await _fill(tester, '密码', 'sp');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(f.notifier.createCalls.single['type'], 'socks');
      expect(f.notifier.createCalls.single['tag'], 'socks节点甲');
      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'socks-new.example.com');
      expect(payload['server_port'], 1080);
      expect(payload['version'], '5'); // choice 原串写（无 writeValues）
      expect(payload['username'], 'su');
      expect(payload['password'], 'sp');
      expect(payload.containsKey('tls'), isFalse); // socks 无 TLS 字段无种子
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P2 字段级 1:1 · http（_httpSpec:625，含 ECH 两字段）', () {
    testWidgets('新建渲染：7 字段 + TLS 组（security 开关 + 7 字段含 ECH）+ 双分节 + 3 开关', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'http'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('http'), findsOneWidget);
      // 分节：proxy + security 两节
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget);
      for (final label in const [
        '服务器', '服务器端口', '用户名', '密码', '传输层加密', '服务器名称指示', '允许不安全的连接',
        '应用层协议协商', '证书 (链)', 'uTLS 指纹',
        // 缺口收口：ECH 两字段（HttpBean 同属 StandardV2RayBean 家族 ⇒ security 节可见）
        '启用 ECH', 'ECH 配置',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'http 缺字段 label：$label');
      }
      // security / allowInsecure / enableECH 是 boolean；utlsFingerprint 是 choice 空值「未设置」
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.text('未设置'), findsOneWidget);
      // **死字段 host/path 不在表单**（NekoBox HttpBean 分支 V2RayFmt.kt:628-637 不读它们）
      expect(find.text('HTTP 主机'), findsNothing);
      expect(find.text('HTTP 路径'), findsNothing);
    });

    testWidgets('编辑回显：TLS 叶子逐项回显（含 utls fingerprint）+ ECH 开关未开', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'http', tag: 'http节点', payloadJson: _httpEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('http · http节点'), findsOneWidget);
      expect(find.text('h.example.com'), findsOneWidget);
      expect(find.text('8080'), findsOneWidget);
      expect(find.text('hu'), findsOneWidget);
      expect(find.text('hp'), findsOneWidget);
      expect(find.text('hs.example.com'), findsOneWidget);
      expect(find.text('h2'), findsOneWidget); // alpn 数组 → 逗号 join（单元素无逗号）
      expect(find.text('HC-1'), findsOneWidget);
      expect(find.text('edge'), findsOneWidget); // utls.fingerprint 叶子值
      // boolean 回显：SwitchListTile.value == true（_FieldRow：value=='true'）
      final secSwitch = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '传输层加密'));
      expect(secSwitch.value, isTrue);
      final insSwitch = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接'));
      expect(insSwitch.value, isTrue);
      // 素材无 ech 键 ⇒ ECH 开关关、ECH 配置空
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '启用 ECH')).value, isFalse);
      expect(find.text('未设置'), findsNothing);
    });

    testWidgets('新建保存：security 关 ⇒ 整个 tls 容器摘除（连 sni 一起）+ 无 host/path 死字段', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'http'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'http节点甲');
      await _fill(tester, '服务器', 'http-new.example.com');
      await _fill(tester, '服务器端口', '8080');
      await _fill(tester, '用户名', 'hu2');
      await _fill(tester, '密码', 'hp2');
      // dropWhen 只认显式 'false'：开关 onChanged 写 'true'/'false'（未碰=空串不触发摘除）
      // ⇒ 先开再关，把 values['security'] 显式写成 'false'
      await _toggle(tester, '传输层加密');
      await _toggle(tester, '传输层加密');
      // sni 填了也该随容器整体摘除（dropped 前缀命中字段路径 ⇒ 字段跳过）
      await _fill(tester, '服务器名称指示', 'should-drop.example.com');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(f.notifier.createCalls.single['type'], 'http');
      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'http-new.example.com');
      expect(payload['server_port'], 8080);
      expect(payload['username'], 'hu2');
      expect(payload['password'], 'hp2');
      expect(payload.containsKey('tls'), isFalse); // security=false ⇒ dropWhen 容器整体摘除
      expect(payload.containsKey('host'), isFalse); // 死字段：表单无、payload 也无
      expect(payload.containsKey('path'), isFalse);
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P2 字段级 1:1 · shadowtls（_shadowtlsSpec L603-631）', () {
    testWidgets('新建渲染：4 平铺 + version 下拉三档 + TLS 组 5 字段 + 星标仅服务器', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'shadowtls'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('shadowtls'), findsOneWidget);
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget); // sni 标 section:'security'
      for (final label in const ['服务器', '服务器端口', '协议版本', '密码', '服务器名称指示', '应用层协议协商', '证书 (链)', '允许不安全的连接', 'uTLS 指纹']) {
        expect(find.text(label), findsOneWidget, reason: 'shadowtls 缺字段 label：$label');
      }
      // ''/2/3 三档 + uTLS 指纹 = 2 个 choice 空值「未设置」
      expect(find.text('未设置'), findsNWidgets(2));
      expect(find.byType(SwitchListTile), findsNWidgets(1)); // allowInsecure

      // 必填：仅 serverAddress
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：version int 3 → 下拉显示 "3"（toString 反查）', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'shadowtls', tag: 'stl节点', payloadJson: _shadowtlsEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('shadowtls · stl节点'), findsOneWidget);
      expect(find.text('st.example.com'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // int 3 → toString '3' 回显 choice
      expect(find.text('stl-pw'), findsOneWidget);
      expect(find.text('sts.example.com'), findsOneWidget);
      expect(find.text('h2'), findsOneWidget);
      expect(find.text('STL-1'), findsOneWidget);
    });

    testWidgets('新建保存：version=2 → JSON int 2（writeValues）+ 恒 TLS 种子 + 空 choice 不落', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'shadowtls'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'stl节点甲');
      await _fill(tester, '服务器', 'st-new.example.com');
      await _fill(tester, '服务器端口', '443');
      await _pickChoice(tester, label: '协议版本', option: '2');
      await _fill(tester, '密码', 'stl-pw2');
      await _fill(tester, '服务器名称指示', 'st-new-tls.example.com');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(f.notifier.createCalls.single['type'], 'shadowtls');
      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'st-new.example.com');
      expect(payload['server_port'], 443);
      expect(payload['version'], 2); // **int**（内核 ShadowTLSOutboundOptions version 是 int）
      expect(payload['password'], 'stl-pw2');
      final tls = payload['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], true); // 种子键（shadowtls 恒 TLS）
      expect(tls['server_name'], 'st-new-tls.example.com');
      // 未填的 alpn/certificate/insecure/utls 全不落（空值删键 + 无 uTLS 空壳）
      expect(tls.containsKey('alpn'), isFalse);
      expect(tls.containsKey('certificate'), isFalse);
      expect(tls.containsKey('insecure'), isFalse);
      expect(tls.containsKey('utls'), isFalse);
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P2 字段级 1:1 · mieru（_mieruSpec L641-655）', () {
    testWidgets('新建渲染：5 字段 + required 全家 4 项星标 + TCP/UDP 下拉', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'mieru'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('mieru'), findsOneWidget);
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsNothing);
      for (final label in const ['服务器', '服务器端口', '协议', '用户名', '密码']) {
        expect(find.text(label), findsOneWidget, reason: 'mieru 缺字段 label：$label');
      }
      expect(find.text('未设置'), findsOneWidget); // serverProtocol choice 空值

      // required 全家：serverAddress + serverPort + username + password（4 项）
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '服务器端口'), '*');
      expect(_errorTextOf(tester, '用户名'), '*');
      expect(_errorTextOf(tester, '密码'), '*');
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：portBindings[0] 数组下标三字段回显', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'mieru', tag: 'mieru节点', payloadJson: _mieruEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('mieru · mieru节点'), findsOneWidget);
      expect(find.text('m.example.com'), findsOneWidget);
      expect(find.text('12345'), findsOneWidget); // portBindings[0].port
      expect(find.text('UDP'), findsOneWidget); // portBindings[0].protocol choice 原串
      expect(find.text('mu'), findsOneWidget);
      expect(find.text('mp'), findsOneWidget);
    });

    testWidgets('新建保存：port/protocol 落 portBindings[0] + 种子占位数组', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'mieru'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'mieru节点甲');
      await _fill(tester, '服务器', 'mieru-new.example.com');
      await _fill(tester, '服务器端口', '12345');
      await _pickChoice(tester, label: '协议', option: 'TCP');
      await _fill(tester, '用户名', 'mu2');
      await _fill(tester, '密码', 'mp2');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(f.notifier.createCalls.single['type'], 'mieru');
      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'mieru-new.example.com');
      expect(payload['username'], 'mu2');
      expect(payload['password'], 'mp2');
      final bindings = payload['portBindings'] as List<dynamic>;
      expect(bindings, hasLength(1)); // 种子占位 [{}]
      final b0 = bindings[0] as Map<String, dynamic>;
      expect(b0['port'], 12345); // int
      expect(b0['protocol'], 'TCP'); // choice 原串
      expect(payload.containsKey('tls'), isFalse); // mieru 无 TLS 字段无种子
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P2 字段级 1:1 · wireguard（_wireguardSpec L674-686）', () {
    testWidgets('新建渲染：8 字段 + required 3 项 + reserved 未设置 + 单分节', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'wireguard'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('wireguard'), findsOneWidget);
      expect(find.text('服务器设置'), findsOneWidget); // 仅 serverAddress 标 proxy
      expect(find.text('TLS 安全设置'), findsNothing);
      for (final label in const ['服务器', '服务器端口', '本地地址 (CIDR)', '私钥', '对端公钥', '预共享密钥', 'MTU', 'Reserved']) {
        expect(find.text(label), findsOneWidget, reason: 'wireguard 缺字段 label：$label');
      }
      expect(find.text('未设置'), findsNothing); // 无 choice 字段
      expect(find.byType(SwitchListTile), findsNothing); // 无 boolean 字段

      // required 3 项：serverAddress + privateKey + （serverPort 不 required）
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '私钥'), '*');
      expect(_errorTextOf(tester, '对端公钥'), isNull);
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：peers[0] 下标回显 + reserved 数组 join + CIDR 数组 join', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'wireguard', tag: 'wg节点', payloadJson: _wireguardEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('wireguard · wg节点'), findsOneWidget);
      expect(find.text('wg.example.com'), findsOneWidget); // peers[0].address
      expect(find.text('51820'), findsOneWidget); // peers[0].port
      expect(find.text('172.16.0.2/32'), findsOneWidget); // address 数组（单元素）join
      expect(find.text('WG-PRIV'), findsOneWidget); // private_key 平铺
      expect(find.text('WG-PBK'), findsOneWidget); // peers[0].public_key
      expect(find.text('WG-PSK'), findsOneWidget); // peers[0].pre_shared_key
      expect(find.text('1420'), findsOneWidget); // mtu int
      expect(find.text('1,2,3'), findsOneWidget); // reserved [1,2,3] → 逗号 join
    });

    testWidgets('新建保存：reserved 数字数组 + peers[0] 落值 + 种子 mtu:1420/peers 占位 + 非法 reserved 256 拒存', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'wireguard'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'wg节点甲');
      await _fill(tester, '服务器', 'wg-new.example.com');
      await _fill(tester, '服务器端口', '51820');
      await _fill(tester, '本地地址 (CIDR)', '172.16.0.2/32');
      await _fill(tester, '私钥', 'WG-PRIV-NEW');
      await _fill(tester, '对端公钥', 'WG-PBK-NEW');
      await _fill(tester, '预共享密钥', 'WG-PSK-NEW');
      await _fill(tester, 'Reserved', '1, 2, 3');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(f.notifier.createCalls.single['type'], 'wireguard');
      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['address'], ['172.16.0.2/32']); // stringList → 数组
      expect(payload['private_key'], 'WG-PRIV-NEW');
      expect(payload['mtu'], 1420); // 种子默认值（未填也保留）
      final peers = payload['peers'] as List<dynamic>;
      expect(peers, hasLength(1));
      final p0 = peers[0] as Map<String, dynamic>;
      expect(p0['address'], 'wg-new.example.com');
      expect(p0['port'], 51820);
      expect(p0['public_key'], 'WG-PBK-NEW');
      expect(p0['pre_shared_key'], 'WG-PSK-NEW');
      expect(p0['reserved'], [1, 2, 3]); // integerList → 数字数组（0-255）
      expect(payload.containsKey('tls'), isFalse);
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);

      // 非法 reserved：'256' 越界 → validateProtocolForm 拒存（errorText '!'，非必填非星标）
      // （新开 fixture：同一 notifier 实例不能挂进第二个 ProviderContainer —— LateError）
      final f2 = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'wireguard'), fixture: f2);
      await _tapGo(tester);
      await _fill(tester, '配置名称', '越界检查');
      await _fill(tester, '服务器', 'wg-x.example.com');
      await _fill(tester, '私钥', 'WG-PRIV-X');
      await _fill(tester, 'Reserved', '256');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, 'Reserved'), '!'); // 非法标记（required=false ⇒ '!'）
      expect(f2.notifier.createCalls, isEmpty); // 拒存不落库
      expect(f2.notifications.errors, ['意外错误']);
    });
  });

  group('P2 字段级 1:1 · naive（_naiveSpec L699-717）', () {
    testWidgets('新建渲染：8 字段 + TLS 组复用 server* 词条 + https/quic 下拉', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'naive'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('naive'), findsOneWidget);
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget); // serverSNI 标 security
      for (final label in const ['服务器', '服务器端口', '用户名', '密码', '协议', '服务器名称指示', '证书 (链)', '并发连接数（不安全）']) {
        expect(find.text(label), findsOneWidget, reason: 'naive 缺字段 label：$label');
      }
      // 缺键反查默认档（writeValues 'https'→null 匹配 JSON 缺键）⇒ 新建显示 'https' 非「未设置」
      expect(find.text('https'), findsOneWidget);
      expect(find.text('未设置'), findsNothing);

      // 编辑模式检查（⋮ 菜单 + 编辑标题）单独开——本用例顺带断新建无 ⋮
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });

    testWidgets('编辑回显：quic:true → 下拉反查 "quic"；不勾框；TLS 叶子回显', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'naive', tag: 'naive节点', payloadJson: _naiveEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('naive · naive节点'), findsOneWidget);
      expect(find.text('n.example.com'), findsOneWidget);
      expect(find.text('443'), findsOneWidget);
      expect(find.text('nu'), findsOneWidget);
      expect(find.text('np'), findsOneWidget);
      expect(find.text('quic'), findsOneWidget); // writeValues 反查：quic:true → 'quic'
      expect(find.text('ns.example.com'), findsOneWidget);
      expect(find.text('NC-1'), findsOneWidget);
      expect(find.text('4'), findsOneWidget); // insecure_concurrency int
      // 缺键反查默认档 'https'（writeValues 'https'→null 匹配 JSON 缺键）⇒ 无「未设置」
      expect(find.text('未设置'), findsNothing);
    });

    testWidgets('新建保存：quic=true 落 bool；https 档 → 键整删（writeValues null 分支）；恒 TLS 种子', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'naive'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'naive节点甲');
      await _fill(tester, '服务器', 'naive-new.example.com');
      await _fill(tester, '服务器端口', '443');
      await _fill(tester, '用户名', 'nu2');
      await _fill(tester, '密码', 'np2');
      await _pickChoice(tester, label: '协议', option: 'quic');
      await _fill(tester, '服务器名称指示', 'ns-new.example.com');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(f.notifier.createCalls.single['type'], 'naive');
      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'naive-new.example.com');
      expect(payload['server_port'], 443);
      expect(payload['username'], 'nu2');
      expect(payload['password'], 'np2');
      expect(payload['quic'], true); // writeValues 'quic'→true
      final tls = payload['tls'] as Map<String, dynamic>;
      expect(tls['enabled'], true); // 种子键（naive 恒 TLS）
      expect(tls['server_name'], 'ns-new.example.com');
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);

      // https 档：writeValues['https']=null → 键整删（内核默认非 QUIC）
      // （新开 fixture：同一 notifier 实例不能挂进第二个 ProviderContainer —— LateError）
      final f2 = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'naive'), fixture: f2);
      await _tapGo(tester);
      await _fill(tester, '配置名称', 'naive节点乙');
      await _fill(tester, '服务器', 'naive-https.example.com');
      await _pickChoice(tester, label: '协议', option: 'https');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      final payload2 = jsonDecode(f2.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload2['server'], 'naive-https.example.com');
      expect(payload2.containsKey('quic'), isFalse); // null 分支 → _remove
      expect(f2.notifications.successes, ['节点已创建']);
    });
  });

  group('P2 收尾 · chain/config 入口 display 名 + 菜单顺序回归', () {
    testWidgets('菜单 17 项顺序 === kManualCreatableProtocols + display 名映射（hysteria 1/2 分列）', (tester) async {
      // 纯数据断言：菜单规格直接由 kManualCreatableProtocols 生成，顺序天然一致；
      // 断 display 名映射（NekoBox strings.xml action_*）与 17 项完整性。
      final menu = nkManualProtocolMenu();
      expect(menu, hasLength(17));
      expect(kManualCreatableProtocols, hasLength(17));
      for (var i = 0; i < menu.length; i++) {
        expect(menu[i].action, NkAddProfileAction.manualNode);
        expect(menu[i].protocol, kManualCreatableProtocols[i]);
      }
      // display 名映射（NekoBox action_*：大小写/专名原样；hysteria/hysteria2 分列 1/2）
      expect(manualProtocolDisplayName('socks'), 'SOCKS');
      expect(manualProtocolDisplayName('http'), 'HTTP');
      expect(manualProtocolDisplayName('shadowsocks'), 'Shadowsocks');
      expect(manualProtocolDisplayName('vmess'), 'VMess');
      expect(manualProtocolDisplayName('vless'), 'VLESS');
      expect(manualProtocolDisplayName('trojan'), 'Trojan');
      expect(manualProtocolDisplayName('mieru'), 'Mieru');
      expect(manualProtocolDisplayName('naive'), 'Naïve');
      expect(manualProtocolDisplayName('hysteria'), 'Hysteria 1');
      expect(manualProtocolDisplayName('hysteria2'), 'Hysteria 2');
      expect(manualProtocolDisplayName('tuic'), 'TUIC');
      expect(manualProtocolDisplayName('shadowtls'), 'ShadowTLS');
      expect(manualProtocolDisplayName('anytls'), 'AnyTLS');
      expect(manualProtocolDisplayName('ssh'), 'SSH');
      expect(manualProtocolDisplayName('wireguard'), 'WireGuard');
      expect(manualProtocolDisplayName('config'), 'Custom Config');
      expect(manualProtocolDisplayName('chain'), 'Proxy Chain');
    });

    testWidgets('chain/config 无表单 spec（protocolFormSpecFor 返回 null）——入口直达专用弹层，非 ProtocolFormModal', (tester) async {
      // 代码事实：_specs 无 chain/config 键 ⇒ protocolFormSpecFor 返回 null；
      // ① 链已测 ChainSettings/ConfigSettings 弹层（manual_node_flow_spec_test 用例 d/e），
      //    此处只固化「无表单」这一数据层不变量（表单 ✎ 入口不给的依据）。
      expect(protocolFormSpecFor('chain'), isNull);
      expect(protocolFormSpecFor('config'), isNull);
      expect(protocolFormSpecFor('trojan_go'), isNull); // 同因不移植
      // 15 个有表单协议的完整清单（17 - chain - config）
      for (final p in const ['socks', 'http', 'shadowsocks', 'vmess', 'vless', 'trojan', 'mieru', 'naive', 'hysteria', 'hysteria2', 'tuic', 'shadowtls', 'anytls', 'ssh', 'wireguard']) {
        expect(protocolFormSpecFor(p), isNotNull, reason: '$p 应有表单');
      }
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 代码（lib/features/proxy/data/protocol_form.dart + widget/protocol_form_modal.dart）
// 与规格矩阵（.workbuddy/spec-protocol-forms-tests.md §2）的 P2 相关差异 —— 全部以代码为准写测试：
//  1. socks：version 下拉 choices ['4','4a','5'] **无 writeValues** ⇒ JSON 落原串 '5'
//     （内核 SOCKSOutboundOptions.version 是 string）。矩阵未细写。
//  2. http：security 字段 id 与「传输层加密」词条复用 vless/trojan 的 security（:633）；
//     host/path 死字段未移植（V2RayFmt.kt:628-637 构建期不读）⇒ 表单无、payload 无（固化）；
//     ECH 两字段（:647-648，缺口已修）与 vless/trojan 同构 —— enableECH boolean→`tls.ech.enabled`、
//     echConfig stringList→`tls.ech.config`，HttpBean 同属 StandardV2RayBean 家族故 security 节可见。
//  3. shadowtls：version choices ['','2','3'] + writeValues {'2':2,'3':3} ⇒ 落 **int**；
//     矩阵 §2.13 描述一致（此处显式断 int 类型防回归）。
//  4. mieru：serverPort/serverProtocol 落 portBindings[0]（int 下标路径）；种子
//     portBindings:[{}] 占位；serverMTU 未纳入（内核 MieruOutboundOptions 无 mtu 键，
//     sing-box 严格解析拒未知键）—— 矩阵「缺口（有意）」固化。
//  5. wireguard：serverAddress→peers[0].address / localAddress→address（stringList 数组）/
//     reserved→peers[0].reserved（integerList 0-255 校验 + 数字数组）；种子 mtu:1420 +
//     peers:[{}]；MTU 词条 serverMTU 复用。validation：reserved '256' → errorText '!'（非必填）。
//  6. naive：serverProtocol choices ['','https','quic'] + writeValues {'https':null,'quic':true}
//     ⇒ https 档删 quic 键、quic 档落 true；读回反查（quic:true→'quic'，缺键→'https'）；
//     TLS 组复用 server* 词条（serverSNI/serverCertificates）；insecure_concurrency 词条
//     「并发连接数（不安全）」。
//  7. 菜单/入口：kManualCreatableProtocols 17 项（含 config/chain 两个非表单项）；
//     nkManualProtocolMenu 直序生成；chain/config 无 spec（编辑 ✎ 入口不给的依据）；
//     trojan_go 因 sing-box 1.13 无出站不移植（spec 与菜单均无）。
//  新坑（相对 P0/P1 六坑）：无新增 —— P2 六协议全部沿用既有 helper（_fill/_pickChoice/_toggle/
//  _errorTextOf）即可全覆盖，无需平台 gate / 特殊弹层。
// ─────────────────────────────────────────────────────────────────────────────
