// P0 批次（⑤规格 §3 批次 1）：协议表单「字段级 1:1」widget 测试
// —— anytls / vless / hysteria2 / shadowsocks 四协议，每协议三用例：
//   ① 新建渲染（showProtocolCreateSheet）：zh 字段 label 全在树、分节标题正确、
//      boolean=SwitchListTile、choice 空值=「未设置」、required 星标
//      （星标只在「保存拦截后」以内层 TextField errorText='*' 呈现，非装饰常显）；
//   ② 编辑回显（showProtocolFormSheet）：payload 各键按 _stringify 规则回显
//      （int→toString / List→逗号 join / 嵌套 Map 取叶子值 / hopInterval 剥 's' 后缀）；
//   ③ 新建保存：payload 关键 path 落值（种子键 / siblings 写父级 / 容器摘除 / 空值删键）。
// 判定基准：zh-CN 词表（assets/translations/zh-CN.i18n.json 的 pages.proxies.form.*）。
// 字段清单以代码 lib/features/proxy/data/protocol_form.dart 的 spec 为准；
// 与 .workbuddy/spec-protocol-forms-tests.md §2 矩阵的差异见文件尾「矩阵差异」注。
// 基建照抄 test/features/proxy/protocol_form_modal_spec_test.dart，六坑纪律同：
//   ① fake notifier build() 给现成 Stream、不挂 disposeDelay ⇒ 无 pending Timer；
//   ② 不注入 proxyEntityRepository ⇒ 无 drift 真异步 ⇒ pumpAndSettle 全程可用；
//   ③ 不设 debugDefaultTargetPlatformOverride（本链路不读 PlatformUtils）；
//   ④ zh 词表 runAsync 预构建 + translationsProvider.overrideWith + pre-warm future；
//   ⑤ 视口 1080x2400 / dpr 1.0，保证 vless 20 字段一次全建出；
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
  // 弹层高 0.75 视口 + ListView 懒构建：放大视口保证 vless 20 字段（配置名称 →
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
/// 嵌套对象（tls.utls / tls.reality / obfs）断叶子值。
const _anytlsEditPayload =
    '{"type":"anytls","tag":"旧节点","server":"1.1.1.1","server_port":8443,"password":"pw-1",'
    '"tls":{"enabled":true,"server_name":"old.example.com","insecure":true,'
    '"alpn":["h2","http/1.1"],"certificate":"CERT-1","utls":{"enabled":true,"fingerprint":"chrome"}}}';

const _vlessEditPayload =
    '{"type":"vless","tag":"v2节点","server":"v.example.com","server_port":443,"uuid":"u-123",'
    '"flow":"xtls-rprx-vision","packet_encoding":"xudp",'
    '"transport":{"type":"ws","headers":{"Host":"h.example.com"},"path":"/wspath",'
    '"max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"},'
    '"tls":{"enabled":true,"server_name":"s.example.com","insecure":false,"alpn":["h2","h3"],'
    '"certificate":"PEM-1","utls":{"enabled":true,"fingerprint":"firefox"},'
    '"reality":{"enabled":true,"public_key":"PBK-1","short_id":"abcd"}}}';

const _hysteria2EditPayload =
    '{"type":"hysteria2","tag":"hy2节点","server":"h.example.com","server_port":36712,"password":"hy-pass",'
    '"tls":{"enabled":true,"server_name":"hs.example.com","insecure":true,"alpn":["h3"],"certificate":"HY-CERT"},'
    '"obfs":{"type":"salamander","password":"ob-pw"},"up_mbps":100,"down_mbps":500,"hop_interval":"30s"}';

const _shadowsocksEditPayload =
    '{"type":"shadowsocks","tag":"ss节点","server":"ss.example.com","server_port":8388,'
    '"method":"aes-256-gcm","password":"ss-pass",'
    '"plugin":"obfs-local","plugin_opts":"obfs=http;obfs-host=b.example.com"}';

void main() {
  group('P0 字段级 1:1 · anytls', () {
    testWidgets('新建渲染：8 字段全在树 + 两分节 + 布尔/下拉形态 + 必填星标（password 非必填=代码事实）', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'anytls'), fixture: f);
      await _tapGo(tester);

      // 头部：新建标题 + 协议副标题；新建才有配置名称；⋮ 菜单只在编辑模式
      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('anytls'), findsOneWidget);
      expect(find.text('配置名称'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
      // 分节（sni 字段标 security ⇒ TLS 安全设置；无 ws 节）
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget);
      expect(find.text('WebSocket 设置'), findsNothing);
      // 字段 label 全列（zh-CN 词表 pages.proxies.form.*）
      for (final label in const ['服务器', '服务器端口', '密码', '服务器名称指示', '允许不安全的连接', '应用层协议协商', '证书 (链)', 'uTLS 指纹']) {
        expect(find.text(label), findsOneWidget, reason: 'anytls 缺字段 label：$label');
      }
      // 形态：唯一布尔 allowInsecure = SwitchListTile；唯一下拉 utlsFingerprint 空值 = 未设置
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('未设置'), findsOneWidget);

      // required 星标：填名后保存被拦，唯一必填字段（serverAddress）标 '*'；
      // 代码事实：anytls password 未标 required（矩阵 §2.7 写 required —— 差异，以代码为准）
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '密码'), isNull);
      expect(f.notifications.errors, ['意外错误']);
      expect(f.notifier.createCalls, isEmpty); // 拦截不落库
    });

    testWidgets('编辑回显：int→toString / List→逗号 join / 嵌套 Map 叶子值 / 开关与下拉当前值', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'anytls', tag: '旧节点', payloadJson: _anytlsEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('anytls · 旧节点'), findsOneWidget);
      expect(find.text('配置名称'), findsNothing); // 编辑无配置名称
      expect(find.byType(PopupMenuButton<String>), findsOneWidget); // ⋮ 菜单只在编辑

      expect(find.text('1.1.1.1'), findsOneWidget); // text 原样回显
      expect(find.text('8443'), findsOneWidget); // int → toString
      expect(find.text('pw-1'), findsOneWidget);
      expect(find.text('old.example.com'), findsOneWidget); // 嵌套 tls.server_name 叶子值
      expect(find.text('h2,http/1.1'), findsOneWidget); // alpn 数组 → 逗号 join
      expect(find.text('CERT-1'), findsOneWidget);
      expect(find.text('chrome'), findsOneWidget); // 下拉 trailing 当前取值
      expect(
        tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value,
        isTrue, // tls.insecure=true → 开
      );
      expect(f.notifier.updatePayloadCalls, isEmpty); // 只回显，未保存不落库
    });

    testWidgets('新建保存：payload 关键 path 落值（种子 tls.enabled + utls siblings 写父级 + alpn 数组形状）', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'anytls'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', '节点甲');
      await _fill(tester, '服务器', '5.6.7.8');
      await _fill(tester, '服务器端口', '8443');
      await _fill(tester, '密码', 'pw-9');
      await _toggle(tester, '允许不安全的连接');
      await _fill(tester, '服务器名称指示', 's.example.com');
      await _fill(tester, '应用层协议协商', 'h2,http/1.1');
      await _pickChoice(tester, label: 'uTLS 指纹', option: 'chrome');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final call = f.notifier.createCalls.single;
      expect(call['groupId'], 7);
      expect(call['tag'], '节点甲');
      expect(call['type'], 'anytls');
      final payload = jsonDecode(call['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], '5.6.7.8');
      expect(payload['server_port'], 8443); // integer → JSON number
      expect(payload['password'], 'pw-9');
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls['enabled'], true); // 种子键（AnyTLS 恒 TLS）原样保留
      expect(tls['server_name'], 's.example.com'); // 嵌套 path 落叶子
      expect(tls['insecure'], true); // 开关开 → 写键
      expect(tls['alpn'], ['h2', 'http/1.1']); // stringList → 数组
      expect(tls.containsKey('certificate'), isFalse); // 空值删键
      expect(tls['utls'], {'enabled': true, 'fingerprint': 'chrome'}); // siblings 写父级 enabled:true
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing); // 保存后关弹层
    });
  });

  group('P0 字段级 1:1 · vless', () {
    testWidgets('新建渲染：20 字段 + 三分节 + flow 是文本框（矩阵写 choice，以代码为准）+ ECH 两字段 + 3 处「未设置」', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'vless'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('vless'), findsOneWidget);
      // 分节：proxy / ws / security 三节标题
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('WebSocket 设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsOneWidget);
      // 字段 label 全列（serverAddress → echConfig，与代码 _vlessSpec 逐一对齐）
      for (final label in const [
        '服务器', '服务器端口', '用户ID', '流控', '包编码', '传输协议', 'HTTP 主机', 'HTTP 路径',
        '最大早期数据', '早期数据头名称', '传输层加密', '服务器名称指示', '允许不安全的连接', '应用层协议协商',
        '证书 (链)', 'uTLS 指纹', 'Reality 公钥', 'Reality 短 ID', '启用 ECH', 'ECH 配置',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'vless 缺字段 label：$label');
      }
      // 形态：布尔 ×3（security + allowInsecure + enableECH）；
      // choice ×3（包编码/传输协议/uTLS）空值 = 未设置
      expect(find.byType(SwitchListTile), findsNWidgets(3));
      expect(find.text('未设置'), findsNWidgets(3));
      // 代码事实：flow 是 text 自由文本框，不是矩阵 §2.1 说的 choice 下拉
      expect(find.widgetWithText(TextField, '流控'), findsOneWidget);
      expect(find.widgetWithText(ListTile, '流控'), findsNothing);

      // 必填星标：serverAddress + uuid（vless 种子无 tls，security 默认关）
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '用户ID'), '*');
      expect(_errorTextOf(tester, '流控'), isNull); // flow 非必填
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：transport=ws 时 host 读 headers.Host + reality/utls 叶子值 + 双开关状态', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'vless', tag: 'v2节点', payloadJson: _vlessEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('vless · v2节点'), findsOneWidget);
      expect(find.byType(PopupMenuButton<String>), findsOneWidget);

      expect(find.text('v.example.com'), findsOneWidget);
      expect(find.text('443'), findsOneWidget); // int → toString
      expect(find.text('u-123'), findsOneWidget);
      expect(find.text('xtls-rprx-vision'), findsOneWidget); // flow 文本框回显
      expect(find.text('xudp'), findsOneWidget); // 包编码 trailing 当前取值
      expect(find.text('ws'), findsOneWidget); // 传输协议 trailing 当前取值
      // pathByChoice：transport=ws ⇒ host 从 transport.headers.Host 读
      expect(find.text('h.example.com'), findsOneWidget);
      expect(find.text('/wspath'), findsOneWidget);
      expect(find.text('2048'), findsOneWidget); // int → toString
      expect(find.text('Sec-WebSocket-Protocol'), findsOneWidget);
      expect(find.text('s.example.com'), findsOneWidget);
      expect(find.text('h2,h3'), findsOneWidget); // alpn 数组 join
      expect(find.text('PEM-1'), findsOneWidget);
      expect(find.text('firefox'), findsOneWidget); // utls.fingerprint 叶子值
      expect(find.text('PBK-1'), findsOneWidget); // reality.public_key 叶子值
      expect(find.text('abcd'), findsOneWidget); // reality.short_id 叶子值
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '传输层加密')).value, isTrue);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value, isFalse);
    });

    testWidgets('新建保存：transport 对象成形（ws→headers.Host）+ security 开→tls.enabled + reality/utls 空整摘', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'vless'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', '节点乙');
      await _fill(tester, '服务器', 'v.example.com');
      await _fill(tester, '服务器端口', '443');
      await _fill(tester, '用户ID', 'u-123');
      await _fill(tester, '流控', 'xtls-rprx-vision');
      await _pickChoice(tester, label: '包编码', option: 'xudp');
      await _pickChoice(tester, label: '传输协议', option: 'ws');
      await _fill(tester, 'HTTP 主机', 'h.example.com');
      await _fill(tester, 'HTTP 路径', '/wspath');
      await _fill(tester, '最大早期数据', '2048');
      await _fill(tester, '早期数据头名称', 'Sec-WebSocket-Protocol');
      await _toggle(tester, '传输层加密');
      await _fill(tester, '服务器名称指示', 's.example.com');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final call = f.notifier.createCalls.single;
      expect(call['type'], 'vless');
      final payload = jsonDecode(call['payload']! as String) as Map<String, dynamic>;
      expect(payload['uuid'], 'u-123');
      expect(payload['flow'], 'xtls-rprx-vision'); // flow 直写根级 flow 键
      expect(payload['packet_encoding'], 'xudp');
      final transport = payload['transport']! as Map<String, dynamic>;
      expect(transport['type'], 'ws'); // 非 tcp ⇒ transport 容器保留
      expect((transport['headers']! as Map<String, dynamic>)['Host'], 'h.example.com'); // ws → headers.Host
      expect(transport['path'], '/wspath');
      expect(transport['max_early_data'], 2048);
      expect(transport['early_data_header_name'], 'Sec-WebSocket-Protocol');
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls['enabled'], true); // vless 种子无 tls —— 全靠 security 开关写出
      expect(tls['server_name'], 's.example.com');
      expect(tls.containsKey('insecure'), isFalse); // 布尔 false → 不写键
      expect(tls.containsKey('utls'), isFalse); // 无控制器容器：受管字段全空 ⇒ 整摘
      expect(tls.containsKey('reality'), isFalse); // realityPubKey 空 ⇒ 容器整摘
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });

  group('P0 字段级 1:1 · hysteria2', () {
    testWidgets('新建渲染：13 字段 + 单分节（无 TLS 安全设置标题）+ obfs/hopInterval 是文本框', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'hysteria2'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('hysteria2'), findsOneWidget);
      // 分节：代码里 hysteria2 只有 serverAddress 标 proxy 节 —— TLS 组没有独立标题
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('TLS 安全设置'), findsNothing);
      expect(find.text('WebSocket 设置'), findsNothing);
      for (final label in const [
        '服务器', '服务器端口', '密码', '服务器名称指示', '允许不安全的连接', '应用层协议协商', '证书 (链)',
        '混淆密码', '最大上行 (Mbps)', '最大下行 (Mbps)', 'QUIC 流接收窗口', 'QUIC 连接接收窗口', '端口跳跃间隔(秒)',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'hysteria2 缺字段 label：$label');
      }
      // 形态：唯一布尔 serverAllowInsecure；无 choice 字段 ⇒ 无「未设置」
      expect(find.byType(SwitchListTile), findsOneWidget);
      expect(find.text('未设置'), findsNothing);
      // 代码事实：serverObfs / hopInterval 都是 text 文本框（矩阵写 integer，以代码为准）
      expect(find.widgetWithText(TextField, '混淆密码'), findsOneWidget);
      expect(find.widgetWithText(TextField, '端口跳跃间隔(秒)'), findsOneWidget);

      // 必填星标：仅 serverAddress
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '密码'), isNull);
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：obfs 叶子值 / alpn join / hop_interval 剥 s 后缀 / up_mbps toString', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'hysteria2', tag: 'hy2节点', payloadJson: _hysteria2EditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('hysteria2 · hy2节点'), findsOneWidget);
      expect(find.text('h.example.com'), findsOneWidget);
      expect(find.text('36712'), findsOneWidget); // int → toString
      expect(find.text('hy-pass'), findsOneWidget);
      expect(find.text('hs.example.com'), findsOneWidget); // 嵌套 tls.server_name 叶子值
      expect(find.text('h3'), findsOneWidget); // 单元素数组 join
      expect(find.text('HY-CERT'), findsOneWidget);
      expect(find.text('ob-pw'), findsOneWidget); // 嵌套 obfs.password 叶子值（兄弟键 type 不回显）
      expect(find.text('100'), findsOneWidget); // up_mbps int → toString
      expect(find.text('500'), findsOneWidget); // down_mbps int → toString
      expect(find.text('30'), findsOneWidget); // hop_interval '30s' → 剥纯数字后缀显示 '30'
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '允许不安全的连接')).value, isTrue);
    });

    testWidgets('新建保存：obfs{type:salamander} siblings + hop_interval 补 s 后缀 + 未填键不写', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'hysteria2'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', '节点丙');
      await _fill(tester, '服务器', 'h.example.com');
      await _fill(tester, '服务器端口', '36712');
      await _fill(tester, '密码', 'hy-pass');
      await _fill(tester, '服务器名称指示', 'hs.example.com');
      await _toggle(tester, '允许不安全的连接');
      await _fill(tester, '混淆密码', 'ob-pw');
      await _fill(tester, '最大上行 (Mbps)', '100');
      await _fill(tester, '端口跳跃间隔(秒)', '30');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'h.example.com');
      expect(payload['server_port'], 36712);
      expect(payload['password'], 'hy-pass');
      expect(payload['obfs'], {'type': 'salamander', 'password': 'ob-pw'}); // siblings 写父级 type
      final tls = payload['tls']! as Map<String, dynamic>;
      expect(tls['enabled'], true); // 种子键（hysteria2 恒 TLS）
      expect(tls['server_name'], 'hs.example.com');
      expect(tls['insecure'], true);
      expect(payload['up_mbps'], 100);
      expect(payload['hop_interval'], '30s'); // 纯数字 → 补 's'（内核 badoption.Duration 必须带单位）
      expect(payload.containsKey('down_mbps'), isFalse); // 空值删键
      expect(payload.containsKey('stream_receive_window'), isFalse);
      expect(payload.containsKey('connection_receive_window'), isFalse);
      expect(f.notifications.successes, ['节点已创建']);
    });
  });

  group('P0 字段级 1:1 · shadowsocks', () {
    testWidgets('新建渲染：6 字段 + 插件分节（标题与字段 label 同文案各一处）+ method 下拉空值未设置', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'shadowsocks'), fixture: f);
      await _tapGo(tester);

      expect(find.text('新建节点'), findsOneWidget);
      expect(find.text('shadowsocks'), findsOneWidget);
      // 分节：proxy + plugin；「插件」既是分节标题又是 pluginName 字段 label ⇒ 各一处
      expect(find.text('服务器设置'), findsOneWidget);
      expect(find.text('插件'), findsNWidgets(2));
      expect(find.text('TLS 安全设置'), findsNothing);
      for (final label in const ['服务器', '服务器端口', '加密方式', '密码', '设置…']) {
        expect(find.text(label), findsOneWidget, reason: 'shadowsocks 缺字段 label：$label');
      }
      // 形态：无布尔字段；唯一下拉 method 空值 = 未设置（choices 不含空串也显示未设置）
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.text('未设置'), findsOneWidget);

      // 必填星标：仅 serverAddress
      await _fill(tester, '配置名称', '星标检查');
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(_errorTextOf(tester, '服务器'), '*');
      expect(_errorTextOf(tester, '密码'), isNull);
      expect(f.notifier.createCalls, isEmpty);
    });

    testWidgets('编辑回显：method 下拉当前值 + plugin/plugin_opts 文本', (tester) async {
      final f = _Fixture();
      await _pump(
        tester,
        open: (context) => showProtocolFormSheet(type: 'shadowsocks', tag: 'ss节点', payloadJson: _shadowsocksEditPayload, groupId: 7),
        fixture: f,
      );
      await _tapGo(tester);

      expect(find.text('编辑节点'), findsOneWidget);
      expect(find.text('shadowsocks · ss节点'), findsOneWidget);
      expect(find.text('ss.example.com'), findsOneWidget);
      expect(find.text('8388'), findsOneWidget); // int → toString
      expect(find.text('aes-256-gcm'), findsOneWidget); // method 下拉 trailing 当前取值
      expect(find.text('ss-pass'), findsOneWidget);
      expect(find.text('obfs-local'), findsOneWidget); // plugin
      expect(find.text('obfs=http;obfs-host=b.example.com'), findsOneWidget); // plugin_opts
    });

    testWidgets('新建保存：method 下拉选中值 + plugin/plugin_opts 落值 + 无 TLS', (tester) async {
      final f = _Fixture();
      await _pump(tester, open: (context) => showProtocolCreateSheet(groupId: 7, type: 'shadowsocks'), fixture: f);
      await _tapGo(tester);

      await _fill(tester, '配置名称', '节点丁');
      await _fill(tester, '服务器', 'ss.example.com');
      await _fill(tester, '服务器端口', '8388');
      await _pickChoice(tester, label: '加密方式', option: 'aes-256-gcm');
      await _fill(tester, '密码', 'ss-pass');
      await _fill(tester, '插件', 'obfs-local');
      await _fill(tester, '设置…', 'obfs=http;obfs-host=b.example.com');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      final payload = jsonDecode(f.notifier.createCalls.single['payload']! as String) as Map<String, dynamic>;
      expect(payload['server'], 'ss.example.com');
      expect(payload['server_port'], 8388);
      expect(payload['method'], 'aes-256-gcm'); // choice 原串写入（无 writeValues）
      expect(payload['password'], 'ss-pass');
      expect(payload['plugin'], 'obfs-local');
      expect(payload['plugin_opts'], 'obfs=http;obfs-host=b.example.com');
      expect(payload.containsKey('tls'), isFalse); // shadowsocks 无种子键、无 TLS 字段
      expect(f.notifications.successes, ['节点已创建']);
      expect(find.text('新建节点'), findsNothing);
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// 代码（lib/features/proxy/data/protocol_form.dart）与规格矩阵
// （.workbuddy/spec-protocol-forms-tests.md §2）的差异 —— 全部以代码为准写测试：
//  1. anytls password（L188）：矩阵 §2.7 写 text(required)，代码未标 required
//     ⇒ 新建空密码可保存（仅 serverAddress 必填）。
//  2. vless flow（L218）：矩阵 §2.1 写 choice('',xtls-rprx-vision)，代码是
//     text 自由文本框（无 choices）。
//  3. certificates（anytls L192 / vless L263 / hysteria2 L304）：矩阵写
//     stringList，代码是 text（写 JSON 原串，不做数组转换；alpn 才是 stringList）。
//  4. hysteria2 hopInterval（L318）：矩阵 §2.8 写 integer(valueSuffix 's')，
//     代码是 text + valueSuffix 's'（允许 2m/500ms 等其它内核单位）。
//  5. shadowsocks pluginName（L468）：矩阵 §2.3 写 choice('',obfs-local,
//     v2ray-plugin)，代码是 text（与 pluginConfig 拆两字段直写 plugin/plugin_opts）。
//  6. method 默认值：矩阵写默认 aes-128-gcm，代码新建无默认 ⇒ 空值显示「未设置」。
//  7. 渲染差异：hysteria2 的 TLS 组（serverSNI/serverAllowInsecure/serverALPN/
//     serverCertificates）在代码里未标 security 分节 ⇒ 无「TLS 安全设置」标题，
//     全部落在「服务器设置」一节（矩阵把它描述为「TLS 组 · 同 vless」）。
// ─────────────────────────────────────────────────────────────────────────────
