// P1 批次（⑤规格 §3 批次 2）：协议表单「字段级 1:1」widget 测试
// —— vmess / trojan / hysteria / tuic / ssh 五协议，每协议三用例：
//   ① 新建渲染（showProtocolCreateSheet）：zh 字段 label 全在树、分节标题正确、
//      boolean=SwitchListTile、choice 空值=「未设置」、required 星标
//      （星标只在「保存拦截后」以内层 TextField errorText='*' 呈现，非装饰常显）；
//   ② 编辑回显（showProtocolFormSheet）：payload 各键按 _stringify 规则回显
//      （int→toString / List→逗号 join / 嵌套 Map 取叶子值 / hop_interval 剥 's' 后缀）；
//   ③ 新建保存：payload 关键 path 落值（种子键 / siblings 写父级 / 容器摘除 / 空值删键 /
//      choice writeValues 原串写入）。
// 判定基准：zh-CN 词表（assets/translations/zh-CN.i18n.json 的 pages.proxies.form.*）；
// 字段清单以代码 lib/features/proxy/data/protocol_form.dart 为准
// （vmess 独立 _vmessSpec:316（21 字段 = vless 减 flow 加 alterId/encryption）/
//   trojan _trojanSpec:452（18 字段含 ECH，种子 tls.enabled=true）/
//   hysteria _hysteriaSpec:548 / tuic _tuicSpec:689（四字段 zh 词条已补）/
//   ssh _sshSpec:669）。
// 与 .workbuddy/spec-protocol-forms-tests.md §2 矩阵的差异见文件尾「矩阵差异」注。
// 基建与六坑纪律照抄 P0 样板 test/features/proxy/protocol_form_fields_p0_spec_test.dart：
//   ① fake notifier build() 给现成 Stream、不挂 disposeDelay ⇒ 无 pending Timer；
//   ② 不注入 proxyEntityRepository ⇒ 无 drift 真异步 ⇒ pumpAndSettle 全程可用；
//   ③ 不设 debugDefaultTargetPlatformOverride（本链路不读 PlatformUtils）；
//   ④ zh 词表 runAsync 预构建 + translationsProvider.overrideWith + pre-warm future；
//   ⑤ 视口 1080x2400 / dpr 1.0（vmess 21 字段一次全建出）；
//   ⑥ TextFormField 无 decoration getter，断 errorText 用内层 TextField。
// 「同文案分节+字段 findsNWidgets(2)」坑排查结论：P1 五协议的分节标题
// （服务器设置/WebSocket 设置/TLS 安全设置）与任何字段 label 都不同文案，
// 无双渲染场景；多同文案文本只来自多个 choice 空值「未设置」（findsNWidgets(2)/(3)）。
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
  // 弹层高 0.75 视口 + ListView 懒构建：放大视口保证 vmess 21 字段（配置名称 →
  // Reality 短 ID）一次全部建出，find 不漏。
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

/// 编辑回显素材：int 用 JSON number（断 toString 回显）、数组断逗号 join、
/// 嵌套对象（tls.utls / tls.reality / transport.headers）断叶子值。
const _vmessEditPayload =
    '{"type":"vmess","tag":"vm节点","server":"vm.example.com","server_port":443,"uuid":"u-vm",'
    '"flow":"xtls-rprx-vision","packet_encoding":"xudp",'
    '"transport":{"type":"ws","headers":{"Host":"hvm.example.com"},"path":"/vmpath",'
    '"max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"},'
    '"tls":{"enabled":true,"server_name":"svm.example.com","insecure":false,"alpn":["h2","h3"],'
    '"certificate":"VM-CERT","utls":{"enabled":true,"fingerprint":"edge"},'
    '"reality":{"enabled":true,"public_key":"VM-PBK","short_id":"ef01"}}}';

const _trojanEditPayload =
    '{"type":"trojan","tag":"tj节点","server":"t.example.com","server_port":443,"password":"tj-pw",'
    '"transport":{"type":"grpc","service_name":"svc-name"},'
    '"tls":{"enabled":true,"server_name":"st.example.com","insecure":true,"alpn":["h2"],'
    '"certificate":"TJ-CERT","utls":{"enabled":true,"fingerprint":"safari"},'
    '"reality":{"enabled":true,"public_key":"TJ-PBK","short_id":"a1b2"}}}';

const _hysteriaEditPayload =
    '{"type":"hysteria","tag":"h1节点","server":"h1.example.com","server_port":36712,'
    '"obfs":"ob-plain","auth_str":"pw-str","auth":"cHctYjY0",'
    '"tls":{"enabled":true,"server_name":"sh1.example.com","insecure":true,"alpn":["h3"],"certificate":"H1-CERT"},'
    '"up_mbps":100,"down_mbps":500,"recv_window_conn":65536,"recv_window":8388608,"hop_interval":"30s"}';

const _tuicEditPayload =
    '{"type":"tuic","tag":"tu节点","server":"tu.example.com","server_port":443,"uuid":"tu-1","password":"tp-1",'
    '"tls":{"enabled":true,"alpn":["h2","h3"],"certificate":"TC-1","disable_sni":true,'
    '"server_name":"t.example.com","insecure":false},'
    '"udp_relay_mode":"native","congestion_control":"cubic","zero_rtt_handshake":true}';

const _sshEditPayload =
    '{"type":"ssh","tag":"ssh节点","server":"s.example.com","server_port":22,"user":"root",'
    '"password":"ssh-pw","private_key":"AAAAB3NzaC1yc2EAAAAKEY","private_key_passphrase":"phrase-1",'
    '"host_key":["hk-1","hk-2"]}';

/// private_key 实验素材：数据层 text 不拆行也不拆逗号；UI 单行 TextField 会把
/// enterText 注入的换行剥掉（新建保存用含逗号原串断「不拆数组」—— 与 host_key 对照）。
const _sshKeyRaw = 'AAAAB3NzaC1yc2EAAAAKEY,SAMPLE-BODY';

void main() {
  group('P1 字段级 1:1 · vmess（独立 _vmessSpec：vless 减 flow 加 alterId/encryption）', () {
    testWidgets('新建渲染：21 字段 + 三分节 + 替代 ID/加密 补齐（原缺口已修）+ flow 不渲染 + 4 处「未设置」', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'vmess'), fixture: f);
      await _tapGo(tester);

      // 头部：新建标题 + 原始 type 副标题；新建才有配置名称；⋮ 菜单只在编辑模式
      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('vmess'), findsOneWidget);
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      // 分节：proxy / ws / security 三节标题
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('WebSocket 设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget);
      // 字段 label 全列（serverAddress → echConfig，与独立 _vmessSpec 逐一对齐）
      for (final label in const [
        '服务器', '服务器端口', '用户ID', '替代 ID', '加密', '包编码', '传输协议', 'HTTP 主机', 'HTTP 路径',
        '最大早期数据', '早期数据头名称', '传输层加密', '服务器名称指示', '允许不安全的连接', '应用层协议协商',
        '证书 (链)', 'uTLS 指纹', 'Reality 公钥', 'Reality 短 ID', '启用 ECH', 'ECH 配置',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'vmess 缺字段 label：$label');
      }
      // 内核 VMessOutboundOptions 无 flow 键 ⇒ vmess 不渲染流控（vless 专属）
      expect(find.text('流控'), findsNothing);
      // 形态：布尔 ×3（security + allowInsecure + enableECH）；
      // choice ×4（加密/包编码/传输协议/uTLS）空值 = 未设置
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.text('未设置'), findsNWidgets(4));
      // 加密是 NekoBox 同款下拉（arrays.xml:295-301 五档+空档）
      expect(find.widgetWithText(ListTile, '加密'), findsOneWidget);

      // 必填星标：serverAddress + uuid
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '用户ID'), '*');
      expect(_errorTextOf(tester, '替代 ID'), isNull); // alterId 非必填
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：int→toString / List→逗号 join / ws→headers.Host / utls+reality 叶子值 / payload flow 键无字段读取', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'vmess', tag: 'vm节点', payloadJson: _vmessEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('vmess · vm节点'), findsOneWidget);
      expect(find.text('配置名称'), findsNothing); // 编辑无配置名称
      expect(find.byType(PopupMenuButton<String>), findsOneWidget); // ⋮ 菜单只在编辑

      expect(find.text('vm.example.com'), findsOneWidget);
      expect(find.text('443'), findsOneWidget); // int → toString
      expect(find.text('u-vm'), findsOneWidget);
      // payload 里的 flow 键在独立 _vmessSpec 下无字段读取 ⇒ 不回显（xtls flow 是 vless 专属）
      expect(find.text('xtls-rprx-vision'), findsNothing);
      expect(find.text('xudp'), findsOneWidget); // 包编码 trailing 当前取值
      expect(find.text('ws'), findsOneWidget); // 传输协议 trailing 当前取值
      // pathByChoice：transport=ws ⇒ host 从 transport.headers.Host 读
      expect(find.text('hvm.example.com'), findsOneWidget);
      expect(find.text('/vmpath'), findsOneWidget);
      expect(find.text('2048'), findsOneWidget); // int → toString
      expect(find.text('Sec-WebSocket-Protocol'), findsOneWidget);
      expect(find.text('svm.example.com'), findsOneWidget);
      expect(find.text('h2,h3'), findsOneWidget); // alpn 数组 join
      expect(find.text('VM-CERT'), findsOneWidget);
      expect(find.text('edge'), findsOneWidget); // utls.fingerprint 叶子值
      expect(find.text('VM-PBK'), findsOneWidget); // reality.public_key 叶子值
      expect(find.text('ef01'), findsOneWidget); // reality.short_id 叶子值
      // 素材无 alter_id/security 键 ⇒ 替代 ID 空框、加密下拉「未设置」
      expect(find.text('未设置'), findsOneWidget); // 仅加密一处（其余 choice 均有值）
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '传输层加密')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value, isFalse);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '启用 ECH')).value, isFalse);
      expect(f.notifier.updatePayloadCalls, isEmpty); // 只回显，未保存不落库
    });

    testWidgets('新建保存：独立 spec.type=vmess + alterId→alter_id + encryption→security + security 开→tls.enabled + utls siblings', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'vmess'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'vm节点甲');
      await _fill(tester, '服务器', '5.6.7.8');
      await _fill(tester, '服务器端口', '443');
      await _fill(tester, '用户ID', 'u-vm');
      await _fill(tester, '替代 ID', '2'); // alterId → 根级 alter_id
      await _pickChoice(tester, label: '加密', option: 'aes-128-gcm'); // encryption → 根级 security
      await _pickChoice(tester, label: '包编码', option: 'xudp');
      await _pickChoice(tester, label: '传输协议', option: 'ws');
      await _fill(tester, 'HTTP 主机', 'hvm.example.com');
      await _fill(tester, 'HTTP 路径', '/vmpath');
      await _fill(tester, '最大早期数据', '2048');
      await _fill(tester, '早期数据头名称', 'Sec-WebSocket-Protocol');
      await _toggle(tester, '传输层加密');
      await _fill(tester, '服务器名称指示', 'svm.example.com');
      await _pickChoice(tester, label: 'uTLS 指纹', option: 'edge');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final call = f.notifier.createCalls.single;
      expect(call['groupId'], 7);
      expect(call['tag'], 'vm节点甲');
      expect(call['type'], 'vmess');
      final payload = jsonDecode(call['payload']! as String) as Map<String, dynamic>;
      expect(payload['type'], 'vmess'); // 种子 type 也是 vmess（独立 spec，无特判）
      expect(payload['uuid'], 'u-vm');
      expect(payload['alter_id'], 2); // 补齐的缺口：alterId integer → alter_id（内核默认 0 缺省键）
      expect(payload['security'], 'aes-128-gcm'); // 补齐的缺口：加密下拉 → 根级 security（内核默认 auto）
      expect(payload['packet_encoding'], 'xudp');
      expect(payload.containsKey('flow'), isFalse); // vmess 无 flow 字段
      final transport = payload['transport']! as Map<String, dynamic>;
      expect(transport['type'], 'ws'); // 非 tcp ⇒ transport 容器保留
      expect((transport['headers']! as Map<String, dynamic>)['Host'], 'hvm.example.com'); // ws → headers.Host
      expect(transport['path'], '/vmpath');
      expect(transport['max_early_data'], 2048);
      expect(transport['early_data_header_name'], 'Sec-WebSocket-Protocol');
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls['enabled'], true); // vmess 种子无 tls —— 全靠 security 开关写出
      expect(tls['server_name'], 'svm.example.com');
      expect(tls['utls'], {'enabled': true, 'fingerprint': 'edge'}); // siblings 写父级 enabled:true
      expect(tls.containsKey('insecure'), isFalse); // 布尔 false → 不写键
      expect(tls.containsKey('alpn'), isFalse); // 空值删键
      expect(tls.containsKey('certificate'), isFalse);
      expect(tls.containsKey('reality'), isFalse); // realityPubKey 空 ⇒ 容器整摘
      expect(tls.containsKey('ech'), isFalse); // ECH 未动 ⇒ 整摘
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing); // 保存后关弹层
    });
  });

  group('P1 字段级 1:1 · trojan（_trojanSpec，18 字段含 ECH；种子 tls.enabled=true）', () {
    testWidgets('新建渲染：18 字段 + 三分节 + 密码必填 + ECH 两字段 + 种子 TLS 默认开（对齐 NekoBox）+ 2 处「未设置」', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'trojan'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('trojan'), findsOneWidget);
      // 分节：proxy / ws / security 三节标题（= vless 减 flow/packetEncoding）
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('WebSocket 设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget);
      for (final label in const [
        '服务器', '服务器端口', '密码', '传输协议', 'HTTP 主机', 'HTTP 路径', '最大早期数据', '早期数据头名称',
        '传输层加密', '服务器名称指示', '允许不安全的连接', '应用层协议协商', '证书 (链)', 'uTLS 指纹',
        'Reality 公钥', 'Reality 短 ID', '启用 ECH', 'ECH 配置',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'trojan 缺字段 label：$label');
      }
      // trojan 无 flow / 包编码 字段（内核 TrojanOutboundOptions 无对应键）
      expect(find.text('流控'), findsNothing);
      expect(find.text('包编码'), findsNothing);
      // 形态：布尔 ×3（security + allowInsecure + enableECH）；choice ×2（传输协议/uTLS）空值 = 未设置
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.text('未设置'), findsNWidgets(2));
      // 种子 tls.enabled=true（StandardV2RayBean.java:83-89 security 空白⇒TrojanBean 写死 "tls"）
      // ⇒ security 开关默认**开**
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '传输层加密')).value, isTrue);

      // 必填星标：serverAddress + password（NekoBox trojan 密码即 uuid 字段，必填）
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '密码'), '*');
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：grpc→service_name 路径切换 + reality/utls 叶子值 + 开关状态（ECH 关）', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'trojan', tag: 'tj节点', payloadJson: _trojanEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('trojan · tj节点'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);

      expect(find.text('t.example.com'), findsOneWidget);
      expect(find.text('443'), findsOneWidget); // int → toString
      expect(find.text('tj-pw'), findsOneWidget);
      expect(find.text('grpc'), findsOneWidget); // 传输协议 trailing 当前取值
      // pathByChoice：transport=grpc ⇒ path 从 transport.service_name 读（host 无 grpc 分支 ⇒ 空）
      expect(find.text('svc-name'), findsOneWidget);
      expect(find.text('st.example.com'), findsOneWidget);
      expect(find.text('h2'), findsOneWidget); // 单元素数组 join
      expect(find.text('TJ-CERT'), findsOneWidget);
      expect(find.text('safari'), findsOneWidget); // utls.fingerprint 叶子值
      expect(find.text('TJ-PBK'), findsOneWidget); // reality.public_key 叶子值
      expect(find.text('a1b2'), findsOneWidget); // reality.short_id 叶子值
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '传输层加密')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '启用 ECH')).value, isFalse); // 素材无 ech 键
      expect(f.notifier.updatePayloadCalls, isEmpty);
    });

    testWidgets('新建保存：种子 TLS 默认开（不动 security ⇒ payload 带 tls.enabled=true，对齐 NekoBox）+ ws transport 成形', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'trojan'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'tj节点甲');
      await _fill(tester, '服务器', 'tj.example.com');
      await _fill(tester, '服务器端口', '443');
      await _fill(tester, '密码', 'tj-pw');
      await _pickChoice(tester, label: '传输协议', option: 'ws');
      await _fill(tester, 'HTTP 主机', 'htj.example.com');
      await _fill(tester, 'HTTP 路径', '/tjpath');
      await _fill(tester, '最大早期数据', '4096');
      // 不碰「传输层加密」直接保存 —— 种子 tls.enabled=true（NekoBox TrojanBean 默认
      // security="tls"，StandardV2RayBean.java:83-89）⇒ 默认 TLS 开，对齐修复原缺口
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final call = f.notifier.createCalls.single;
      expect(call['type'], 'trojan');
      final payload = jsonDecode(call['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'tj.example.com');
      expect(payload['server_port'], 443);
      expect(payload['password'], 'tj-pw');
      final transport = payload['transport']! as Map<String, dynamic>;
      expect(transport['type'], 'ws');
      expect((transport['headers']! as Map<String, dynamic>)['Host'], 'htj.example.com'); // ws → headers.Host
      expect(transport['path'], '/tjpath');
      expect(transport['max_early_data'], 4096);
      expect(transport.containsKey('early_data_header_name'), isFalse); // 空值删键
      // 缺口修复后的行为：种子 tls 保留 ⇒ 新建 trojan 默认带 TLS（NekoBox 同款）
      expect(payload['tls'], {'enabled': true}); // 除种子键外无别的 TLS 值 ⇒ 不含 server_name 等
      expect(payload.containsKey('flow'), isFalse); // trojan 无此二字段
      expect(payload.containsKey('packet_encoding'), isFalse);
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P1 字段级 1:1 · hysteria（v1，_hysteriaSpec:562）', () {
    testWidgets('新建渲染：14 字段 + 单分节 + authType 下拉以双文本框替代（代码事实）+ 无 choice', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'hysteria'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('hysteria'), findsOneWidget);
      // 分节：代码里 hysteria 只有 serverAddress 标 proxy 节 —— TLS 组没有独立标题
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsNothing);
      expect(find.text('WebSocket 设置'), findsNothing);
      for (final label in const [
        '服务器', '服务器端口', '混淆密码', '认证密码（字符串）', '认证密码（base64）', '服务器名称指示',
        '允许不安全的连接', '应用层协议协商', '证书 (链)', '最大上行 (Mbps)', '最大下行 (Mbps)',
        'QUIC 流接收窗口', 'QUIC 连接接收窗口', '端口跳跃间隔(秒)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'hysteria 缺字段 label：$label');
      }
      // 形态：唯一布尔 serverAllowInsecure；无 choice 字段 ⇒ 无「未设置」
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('未设置'), findsNothing);
      // 代码事实：authType 下拉不移植 —— 双文本框顶替，填了就写（矩阵 §2.9 已裁定）
      expect(find.widgetWithText(TextField, '认证密码（字符串）'), findsOneWidget);
      expect(find.widgetWithText(TextField, '认证密码（base64）'), findsOneWidget);
      // 代码事实：hopInterval 是 text 文本框（矩阵写 integer，以代码为准）
      expect(find.widgetWithText(TextField, '端口跳跃间隔(秒)'), findsOneWidget);

      // 必填星标：仅 serverAddress
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '混淆密码'), isNull);
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：hop_interval 剥 s 后缀 / 双窗口各归各键 / alpn join / 布尔开关', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'hysteria', tag: 'h1节点', payloadJson: _hysteriaEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('hysteria · h1节点'), findsOneWidget);
      expect(find.text('h1.example.com'), findsOneWidget);
      expect(find.text('36712'), findsOneWidget); // serverPorts int → toString
      expect(find.text('ob-plain'), findsOneWidget); // v1 obfs 直键字符串
      expect(find.text('pw-str'), findsOneWidget); // auth_str
      expect(find.text('cHctYjY0'), findsOneWidget); // auth（base64）
      expect(find.text('sh1.example.com'), findsOneWidget); // 嵌套 tls.server_name 叶子值
      expect(find.text('h3'), findsOneWidget); // 单元素数组 join
      expect(find.text('H1-CERT'), findsOneWidget);
      expect(find.text('100'), findsOneWidget); // up_mbps int → toString
      expect(find.text('500'), findsOneWidget); // down_mbps int → toString
      expect(find.text('65536'), findsOneWidget); // recv_window_conn → 流接收窗口框
      expect(find.text('8388608'), findsOneWidget); // recv_window → 连接接收窗口框
      expect(find.text('30'), findsOneWidget); // hop_interval '30s' → 剥纯数字后缀显示 '30'
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value, isTrue);
      expect(f.notifier.updatePayloadCalls, isEmpty);
    });

    testWidgets('新建保存：种子 tls.enabled + recv_window_conn/recv_window 各归各键（防回归 NekoBox 抄写 bug）+ obfs v1 直键 + hop_interval 补 s', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'hysteria'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'h1节点甲');
      await _fill(tester, '服务器', 'h1-new.example.com');
      await _fill(tester, '服务器端口', '36712');
      await _fill(tester, '混淆密码', 'ob-plain');
      await _fill(tester, '认证密码（字符串）', 'pw-str');
      await _fill(tester, '认证密码（base64）', 'cHctYjY0');
      await _fill(tester, '服务器名称指示', 'sh1-new.example.com');
      await _toggle(tester, '允许不安全的连接');
      await _fill(tester, '应用层协议协商', 'h3');
      await _fill(tester, '最大上行 (Mbps)', '100');
      await _fill(tester, 'QUIC 流接收窗口', '65536');
      await _fill(tester, 'QUIC 连接接收窗口', '8388608');
      await _fill(tester, '端口跳跃间隔(秒)', '30');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'h1-new.example.com');
      expect(payload['server_port'], 36712); // serverPorts 落 server_port（单数）
      expect(payload['obfs'], 'ob-plain'); // v1 obfs 直键字符串（非 v2 的 salamander 对象）
      expect(payload['auth_str'], 'pw-str'); // 双文本框各写各键
      expect(payload['auth'], 'cHctYjY0');
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls['enabled'], true); // 种子键（hysteria v1 恒 TLS）原样保留
      expect(tls['server_name'], 'sh1-new.example.com');
      expect(tls['insecure'], true);
      expect(tls['alpn'], ['h3']); // stringList → 数组
      expect(tls.containsKey('certificate'), isFalse); // 空值删键
      expect(payload['up_mbps'], 100);
      // 防回归：流窗口→recv_window_conn、连接窗口→recv_window（修 NekoBox HysteriaFmt 298-300 抄写 bug）
      expect(payload['recv_window_conn'], 65536);
      expect(payload['recv_window'], 8388608);
      expect(payload['hop_interval'], '30s'); // 纯数字 → 补 's'（内核 badoption.Duration 必须带单位）
      expect(payload.containsKey('down_mbps'), isFalse); // 空值删键
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P1 字段级 1:1 · tuic（_tuicSpec，四字段 zh 词条已补 + SNI 置灰联动）', () {
    testWidgets('新建渲染：12 字段 + 单分节 + 四字段中文标签（缺口已修）+ 3 开关 + 2 下拉 + SNI 初始可用', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'tuic'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('tuic'), findsOneWidget);
      // 分节：只有 serverAddress 标 proxy —— 单节
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsNothing);
      for (final label in const [
        '服务器', '服务器端口', '用户名', '密码', '应用层协议协商', '证书 (链)',
        // 缺口收口后：四字段走 _fieldLabel 新 case + zh 词条（原来直接显示英文 id）
        'UDP 转发模式', '拥塞控制', '禁用 SNI', '启用 0-RTT QUIC 握手',
        '服务器名称指示', '允许不安全的连接',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'tuic 缺字段 label：$label');
      }
      // 旧英文 id 原文不再出现（缺口已修，避免回退）
      for (final id in const ['serverUDPRelayMode', 'serverCongestionController', 'serverDisableSNI', 'serverReduceRTT']) {
        expect(find.text(id), findsNothing, reason: 'tuic 字段仍是英文 id 原文：$id');
      }
      // 形态：布尔 ×3（disableSNI + reduceRTT + allowInsecure）；choice ×2 空值 = 未设置
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.text('未设置'), findsNWidgets(2));
      // 禁用 SNI 未勾 ⇒ SNI 输入框可用（disabledBy 联动）
      expect(tester.widget<TextField>(find.widgetWithText(TextField, '服务器名称指示')).enabled, isTrue);

      // 必填星标：仅 serverAddress
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '用户名'), isNull);
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：下拉当前值 + 中文标签下 disableSNI/reduceRTT 开关状态 + SNI 因置灰不可交互 + alpn join', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'tuic', tag: 'tu节点', payloadJson: _tuicEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('tuic · tu节点'), findsOneWidget);
      expect(find.text('tu.example.com'), findsOneWidget);
      expect(find.text('443'), findsOneWidget); // int → toString
      expect(find.text('tu-1'), findsOneWidget); // serverUsername → uuid 键回显
      expect(find.text('tp-1'), findsOneWidget);
      expect(find.text('native'), findsOneWidget); // UDP 转发模式 下拉 trailing 当前取值
      expect(find.text('cubic'), findsOneWidget); // 拥塞控制 下拉 trailing 当前取值
      expect(find.text('h2,h3'), findsOneWidget); // alpn 数组 join
      expect(find.text('TC-1'), findsOneWidget);
      expect(find.text('t.example.com'), findsOneWidget);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '禁用 SNI')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '启用 0-RTT QUIC 握手')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value, isFalse);
      // 素材 tls.disable_sni=true ⇒ SNI 输入框置灰（照 TuicSettingsActivity.kt:55-61）
      expect(tester.widget<TextField>(find.widgetWithText(TextField, '服务器名称指示')).enabled, isFalse);
      expect(find.text('未设置'), findsNothing);
      expect(f.notifier.updatePayloadCalls, isEmpty);
    });

    testWidgets('新建保存：种子 tls.enabled + disable_sni/zero_rtt_handshake + 下拉原串写值 + 未选下拉不写键', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'tuic'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'tu节点甲');
      await _fill(tester, '服务器', 'tu-new.example.com');
      await _fill(tester, '服务器端口', '8443');
      await _fill(tester, '用户名', 'tu-uid');
      await _fill(tester, '密码', 'tu-pw');
      await _fill(tester, '应用层协议协商', 'h3');
      await _pickChoice(tester, label: 'UDP 转发模式', option: 'quic');
      // serverCongestionController 不选 —— 断「空 = 不写键」
      // 顺序陷阱：先填 SNI（此时输入框仍可用），再勾「禁用 SNI」——置灰后 enterText 打不进去
      await _fill(tester, '服务器名称指示', 'stu.example.com');
      await _toggle(tester, '禁用 SNI');
      await tester.pump();
      expect(tester.widget<TextField>(find.widgetWithText(TextField, '服务器名称指示')).enabled, isFalse); // 联动生效
      expect(find.text('stu.example.com'), findsOneWidget); // 置灰不清值
      await _toggle(tester, '启用 0-RTT QUIC 握手');
      await _toggle(tester, '允许不安全的连接');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'tu-new.example.com');
      expect(payload['server_port'], 8443);
      expect(payload['uuid'], 'tu-uid'); // serverUsername 落 uuid 键
      expect(payload['password'], 'tu-pw');
      expect(payload['udp_relay_mode'], 'quic'); // 下拉原串写入（无 writeValues）
      expect(payload.containsKey('congestion_control'), isFalse); // 空 = 删键
      expect(payload['zero_rtt_handshake'], true); // serverReduceRTT 直写最终出站键
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls, {
        'enabled': true, // 种子键（tuic 恒 TLS）
        'disable_sni': true, // 落 tls.disable_sni
        'server_name': 'stu.example.com',
        'insecure': true,
        'alpn': ['h3'],
      });
      expect(tls.containsKey('certificate'), isFalse); // 空值删键
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P1 字段级 1:1 · ssh（_sshSpec:700）', () {
    testWidgets('新建渲染：7 字段 + 单分节 + 无开关无下拉 + 私钥/证书都是文本框', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'ssh'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('ssh'), findsOneWidget);
      // 分节：只有 serverAddress 标 proxy —— 单节；ssh 无 TLS 字段
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsNothing);
      for (final label in const ['服务器', '服务器端口', '用户名', '密码', '私钥', '私钥口令', '证书 (链)']) {
        expect(find.text(label), findsOneWidget, reason: 'ssh 缺字段 label：$label');
      }
      // 形态：无布尔、无 choice ⇒ 无开关、无「未设置」；无 authType 下拉（不移植，双字段都给）
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('未设置'), findsNothing);
      expect(find.widgetWithText(TextField, '私钥'), findsOneWidget); // serverPrivateKey = text
      expect(find.widgetWithText(TextField, '证书 (链)'), findsOneWidget); // serverCertificates = stringList 也是文本框

      // 必填星标：仅 serverAddress
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '私钥'), isNull);
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：user 路径 + host_key 数组逗号 join + 私钥原样', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'ssh', tag: 'ssh节点', payloadJson: _sshEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('ssh · ssh节点'), findsOneWidget);
      expect(find.text('s.example.com'), findsOneWidget);
      expect(find.text('22'), findsOneWidget); // int → toString
      expect(find.text('root'), findsOneWidget); // serverUsername → user 键回显
      expect(find.text('ssh-pw'), findsOneWidget);
      expect(find.text('AAAAB3NzaC1yc2EAAAAKEY'), findsOneWidget); // private_key 原样单串
      expect(find.text('phrase-1'), findsOneWidget); // private_key_passphrase
      expect(find.text('hk-1,hk-2'), findsOneWidget); // host_key 数组 → 逗号 join
      expect(f.notifier.updatePayloadCalls, isEmpty);
    });

    testWidgets('新建保存：private_key 多行单串不拆行 + host_key 数组 + 私钥/密码双写（sing-box 兜底语义）+ 无 tls', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'ssh'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', 'ssh节点甲');
      await _fill(tester, '服务器', 'ssh-new.example.com');
      await _fill(tester, '服务器端口', '22');
      await _fill(tester, '用户名', 'root');
      await _fill(tester, '密码', 'ssh-pw');
      await _fill(tester, '私钥', _sshKeyRaw); // 含逗号原串 —— 断不按逗号拆数组
      await _fill(tester, '私钥口令', 'key-phrase');
      await _fill(tester, '证书 (链)', 'hk-a, hk-b');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'ssh-new.example.com');
      expect(payload['server_port'], 22);
      expect(payload['user'], 'root'); // serverUsername 落 user 键（非 username）
      expect(payload['password'], 'ssh-pw');
      // 代码事实：private_key 是 text 单串，含逗号也不拆数组（对照：host_key 才拆）；
      // PEM 换行在 UI 单行框（maxLines=1）注入时被剥掉 —— 原样保留的是剥换行后的串
      expect(payload['private_key'], _sshKeyRaw);
      expect(payload['private_key_passphrase'], 'key-phrase');
      // authType 下拉不移植：密码+私钥都填 ⇒ 两键都写（sing-box 先试公钥再试密码）
      expect(payload['host_key'], ['hk-a', 'hk-b']); // stringList → 数组（SSHFmt listByLineOrComma 等价）
      expect(payload.containsKey('tls'), isFalse); // ssh 无 TLS 字段、无种子键
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 代码（lib/features/proxy/data/protocol_form.dart + widget/protocol_form_modal.dart）
// 与规格矩阵（.workbuddy/spec-protocol-forms-tests.md §2）的 P1 相关差异 —— 全部以代码为准写测试：
//  1. vmess **已有独立 spec**（_vmessSpec:316，21 字段 = _vlessSpec 减 flow、加 alterId/encryption），
//     原「共用 _vlessSpec 特判换 type」的写法与「vmess 无 alterId/encryption」缺口均已修复：
//     alterId integer→`alter_id`（内核 VMessBean 默认 0），encryption choice→根级 `security`
//     （choices 首位空档 = 未设置不写键 ⇒ 内核默认 auto，V2RayFmt.kt:662）。
//     flow 仍是 vless/vmess 共用的差异点：矩阵 §2.1 写 choice('',xtls-rprx-vision)，代码是 text
//     （同 P0 差异 #2）；但 vmess 不再渲染该字段（内核 VMessOutboundOptions 无 flow 键）。
//  2. trojan 新建种子**带 tls**（protocolSeedPayload:1207-1209，对齐 NekoBox
//     `StandardV2RayBean.java:83-89` security 空白 ⇒ TrojanBean 写死 "tls"）：不勾开关保存也
//     ⇒ payload 有 `tls.enabled=true`（原「无 tls 键」缺口已修，开关仍可关掉）。
//  3. tuic 四字段**已有中文标签**（_fieldLabel:616-619 + zh 词条 :252-255）：
//     serverUDPRelayMode=UDP 转发模式 / serverCongestionController=拥塞控制 /
//     serverDisableSNI=禁用 SNI / serverReduceRTT=启用 0-RTT QUIC 握手（原英文 id 原文缺口已修）。
//     并断 disabledBy 联动：勾「禁用 SNI」⇒ SNI 输入框 enabled=false（仍可见、不清值；
//     照 `TuicSettingsActivity.kt:55-61` 的 isEnabled 语义）—— 保存用例有顺序陷阱：先填后勾。
//  4. ECH（vless/trojan/http）：enableECH boolean→`tls.ech.enabled` + echConfig stringList→
//     `tls.ech.config`（`standard_v2ray_preferences.xml:173-185` 多行文本框 ⇒ 行数组）。
//     P1 覆盖面 = trojan 新建渲染（18 字段含两 ECH label、SwitchListTile 3 个）+ 编辑回显
//     ECH 开关为关；vless 两 ECH 字段的渲染/落值在 P0 文件（protocol_form_fields_p0_spec_test.dart）。
//  5. hysteria hopInterval：代码 text + valueSuffix 's'（:567），矩阵 §2.9 写 integer。
//     serverCertificates 代码 text（:561，写 JSON 原串不做数组转换），矩阵「TLS 组 同 vless」
//     按 stringList 描述。serverPorts 出站键 ['server_port'] 单数。
//  6. hysteria 双窗口键名（与矩阵一致的固化点，非差异）：serverStreamReceiveWindow →
//     recv_window_conn、serverConnectionReceiveWindow → recv_window（有意修 NekoBox
//     HysteriaFmt 298-300 抄写 bug）—— 测试双向断言防回归。
//  7. ssh：无 privateKeyPath 字段（矩阵亦无；最接近的是 private_key_passphrase=serverPassword1）。
//     private_key=text 单串不拆行不拆逗号（:676）、host_key=stringList（serverCertificates 复用
//     「证书 (链)」词表实际写 host_key，:678）；authType 下拉不移植 —— 私钥/密码双文本框
//     填了都写（sing-box 先钥后密兜底）。测试额外发现（UI 行为，非数据层）：单行
//     TextField（maxLines=1）会把 enterText 注入的换行剥掉 ⇒ 多行 PEM 经 UI 保存后变单行串。
// ─────────────────────────────────────────────────────────────────────────────
