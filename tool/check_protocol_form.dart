// 「协议编辑表单」的可执行校验（与 check_config_assembly.dart 同理：纯 Dart + `dart run`，
// 不依赖 flutter_tester）。
//
// 运行：dart run tool/check_protocol_form.dart
//
// 要证明的核心：
//  1. **往返幂等** —— 读出来再原样写回，payload 逐字节等价（这条一旦成立，就等价于
//     "表单没有管理的键全部原样保留"，是真机 84 个节点安全的前提）。
//  2. 表单管理的字段能改，且改一个不动别的。
//  3. 容器语义（清空 uTLS 指纹 ⇒ 没有 `tls.utls`；传输方式选 tcp ⇒ 没有 `transport`；
//     security 关 ⇒ 没有 `tls`）与 NekoBox 的构建行为一致。
//
// ignore_for_file: avoid_print
// ignore_for_file: missing_whitespace_between_adjacent_strings
//
// （前者：print 就是本脚本的输出方式。后者：下面的真机 payload 常量按行拼接，
//   JSON 里相邻片段之间本来就没有空格可加。）
import 'dart:convert';

import 'package:hiddify/features/proxy/data/protocol_form.dart';

var _passed = 0;
var _failed = 0;

/// 递归排序 Map 的键 —— 只用于**比较**。
/// Dart 的 `jsonEncode` 保序，而"改过 payload"必然打乱键序，不排序会误报 FAIL。
Object? _canon(Object? node) {
  if (node is Map) {
    final keys = node.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(node[k])};
  }
  if (node is List) return [for (final item in node) _canon(item)];
  return node;
}

/// 比较用的表示：List/Map 递归排序后编码（Dart 的 `==` 是同一性，直接用会误报 FAIL）；
/// String/num/bool/null 原样；其他对象（如规格实例）只做同一性比较，不做编码。
String _repr(Object? node) {
  if (node is String) return node;
  if (node == null || node is num || node is bool) return '$node';
  try {
    return jsonEncode(_canon(node));
  } catch (_) {
    return '$node';
  }
}

void check(String label, Object? actual, Object? expected) {
  if (identical(actual, expected)) {
    _passed++;
    return;
  }
  final a = _repr(actual);
  final b = _repr(expected);
  if (a == b) {
    _passed++;
  } else {
    _failed++;
    print('FAIL  $label');
    print('      actual   = $a');
    print('      expected = $b');
  }
}

Map<String, dynamic> decode(String s) => jsonDecode(s) as Map<String, dynamic>;

/// 一份真机形状的 anytls payload（照 `%APPDATA%\Hiddify\hiddify\db.sqlite` 的实测样本）。
const _anytlsReal =
    '{"type":"anytls","tag":"🇭🇰 Hong Kong RLT","server":"hongkong.game.3333399.xyz",'
    '"server_port":443,"tls":{"enabled":true,"server_name":"www.amazon.com",'
    '"utls":{"enabled":true,"fingerprint":"chrome"},'
    '"reality":{"enabled":true,"public_key":"3JY00TvwFWoWbpGdjyg6Pja2wsxWJ-v9VkKENm-APyw","short_id":"b40b33a8"}},'
    '"password":"ec1fdc91-239d-40e5-8ade-ee1ca8f6dc10"}';

const _vlessWsReal =
    '{"type":"vless","tag":"🇯🇵日本-移动专属1号","server":"3bd9.55dca.e048.yfjcs.com","server_port":443,'
    '"uuid":"103cd797-ad1f-4225-a75d-247467374462","flow":"xtls-rprx-vision",'
    '"tls":{"enabled":true,"server_name":"osxapps.itunes.apple.com",'
    '"utls":{"enabled":true,"fingerprint":"chrome"},'
    '"reality":{"enabled":true,"public_key":"egq3FRi4oqkJ-iJ40r-pk10g7tawGg6o9c4UDGOPDU4","short_id":"9824e11ad3a632f8"}},'
    '"packet_encoding":"xudp",'
    '"transport":{"type":"ws","path":"/yfjc/us1","headers":{"Host":"yfjc-us1.wangpan.shop"},'
    '"max_early_data":2048,"early_data_header_name":"Sec-WebSocket-Protocol"}}';

const _vlessTcpReal =
    '{"type":"vless","tag":"JP-tcp","server":"a.example.com","server_port":443,'
    '"uuid":"103cd797-ad1f-4225-a75d-247467374462","flow":"xtls-rprx-vision",'
    '"tls":{"enabled":true,"server_name":"osxapps.itunes.apple.com"},'
    '"packet_encoding":"xudp"}';

const _hysteria2Real =
    '{"type":"hysteria2","tag":"🇯🇵 Japan UDP B","server":"bing.tyo.444407.xyz","server_port":443,'
    '"password":"ec1fdc91-239d-40e5-8ade-ee1ca8f6dc10",'
    '"tls":{"enabled":true,"server_name":"s0.awsstatic.com","insecure":true},'
    '"stream_receive_window":0,"connection_receive_window":0}';

const _shadowsocksReal =
    '{"type":"shadowsocks","tag":"ss-1","server":"127.0.0.1","server_port":1080,'
    '"method":"aes-256-gcm","password":"ec1fdc91-239d-40e5-8ade-ee1ca8f6dc10"}';

String applyOk(ProtocolFormSpec spec, String payload, Map<String, String> values) {
  final result = applyProtocolForm(payloadJson: payload, spec: spec, values: values);
  if (result == null) throw StateError('applyProtocolForm returned null');
  return result;
}

/// 读出 → 原样写回 → 必须与原 payload 等价。
void checkRoundTrip(String label, ProtocolFormSpec spec, String payload) {
  final values = readProtocolFormValues(payload: decode(payload), spec: spec);
  check('$label · 往返幂等', decode(applyOk(spec, payload, values)), decode(payload));
}

void main() {
  final anytls = protocolFormSpecFor('anytls')!;
  final vless = protocolFormSpecFor('vless')!;
  final hysteria2 = protocolFormSpecFor('hysteria2')!;
  final ss = protocolFormSpecFor('shadowsocks')!;

  // ── 0. 规格查表 ────────────────────────────────────────────────────────────
  check('规格 · 未知类型无表单', protocolFormSpecFor('wireguard'), null);
  check('规格 · 大小写/空格归一', protocolFormSpecFor(' AnyTLS '), anytls);
  check('规格 · vmess 复用 v2ray 表单', protocolFormSpecFor('vmess'), vless);
  check('规格 · anytls 字段数', protocolFormFieldIds(anytls).length, 8);
  check('规格 · vless 字段数', protocolFormFieldIds(vless).length, 18);
  check('规格 · hysteria2 字段数', protocolFormFieldIds(hysteria2).length, 13);
  check('规格 · shadowsocks 字段数', protocolFormFieldIds(ss).length, 6);

  // ── 1. 读值 ───────────────────────────────────────────────────────────────
  final av = readProtocolFormValues(payload: decode(_anytlsReal), spec: anytls);
  check('读 · anytls server', av['serverAddress'], 'hongkong.game.3333399.xyz');
  check('读 · anytls port（整数转字符串）', av['serverPort'], '443');
  check('读 · anytls sni', av['sni'], 'www.amazon.com');
  check('读 · anytls allowInsecure 缺键 ⇒ 空', av['allowInsecure'], '');
  check('读 · anytls utls 指纹', av['utlsFingerprint'], 'chrome');
  check('读 · anytls alpn 缺键 ⇒ 空', av['alpn'], '');
  // 关键：`tls.reality` 不在 anytls 表单里，读的时候不该混进任何字段
  check('读 · anytls 表单不含 reality', av.containsKey('realityPubKey'), false);

  final vv = readProtocolFormValues(payload: decode(_vlessWsReal), spec: vless);
  check('读 · vless uuid', vv['uuid'], '103cd797-ad1f-4225-a75d-247467374462');
  check('读 · vless flow（表单 key 是 encryption）', vv['flow'], 'xtls-rprx-vision');
  check('读 · vless security 由 tls.enabled 推导', vv['security'], 'true');
  check('读 · vless 传输方式', vv['transport'], 'ws');
  check('读 · vless ws host（进 headers.Host）', vv['host'], 'yfjc-us1.wangpan.shop');
  check('读 · vless ws path', vv['path'], '/yfjc/us1');
  check('读 · vless ws max_early_data', vv['wsMaxEarlyData'], '2048');
  check('读 · vless packet_encoding', vv['packetEncoding'], 'xudp');
  check('读 · vless reality 公钥', vv['realityPubKey'], 'egq3FRi4oqkJ-iJ40r-pk10g7tawGg6o9c4UDGOPDU4');

  final vt = readProtocolFormValues(payload: decode(_vlessTcpReal), spec: vless);
  check('读 · 无 transport 的 vless ⇒ 传输方式回落 tcp（含 host/path 都空）', [vt['transport'], vt['host'], vt['path']], ['', '', '']);

  final hv = readProtocolFormValues(payload: decode(_hysteria2Real), spec: hysteria2);
  check('读 · hysteria2 密码', hv['serverPassword'], 'ec1fdc91-239d-40e5-8ade-ee1ca8f6dc10');
  check('读 · hysteria2 收窗口 0 也要读出来（不是"没设置"）', hv['serverStreamReceiveWindow'], '0');
  check('读 · hysteria2 insecure', hv['serverAllowInsecure'], 'true');
  check('读 · hysteria2 obfs 缺键 ⇒ 空', hv['serverObfs'], '');

  final sv = readProtocolFormValues(payload: decode(_shadowsocksReal), spec: ss);
  check('读 · ss method', sv['method'], 'aes-256-gcm');
  check('读 · ss 插件缺键 ⇒ 空', [sv['pluginName'], sv['pluginConfig']], ['', '']);

  // ── 2. 往返幂等（本文件最重要的一条）──────────────────────────────────────
  checkRoundTrip('anytls(reality 版)', anytls, _anytlsReal);
  checkRoundTrip('vless(ws+reality)', vless, _vlessWsReal);
  checkRoundTrip('vless(无 transport)', vless, _vlessTcpReal);
  checkRoundTrip('hysteria2', hysteria2, _hysteria2Real);
  checkRoundTrip('shadowsocks', ss, _shadowsocksReal);

  // 带 alpn 数组的（NekoBox 表单是文本、sing-box 是数组，最容易写坏的一处）
  const anytlsAlpn =
      '{"type":"anytls","tag":"t","server":"a.com","server_port":443,"password":"p",'
      '"tls":{"enabled":true,"alpn":["h3","h2"]}}';
  checkRoundTrip('anytls(带 alpn 数组)', anytls, anytlsAlpn);

  // ── 3. 改字段 ─────────────────────────────────────────────────────────────
  final edited = decode(
    applyOk(anytls, _anytlsReal, {...av, 'serverAddress': 'new.example.com', 'serverPort': '8443'}),
  );
  check('改 · anytls server/port 生效', [edited['server'], edited['server_port']], ['new.example.com', 8443]);
  check('改 · anytls 其余键不动', [
    edited['tag'],
    edited['password'],
    (edited['tls'] as Map)['server_name'],
    // 表单不管理的 tls.reality 必须原样留着
    jsonEncode(_canon((edited['tls'] as Map)['reality'])),
  ], [
    '🇭🇰 Hong Kong RLT',
    'ec1fdc91-239d-40e5-8ade-ee1ca8f6dc10',
    'www.amazon.com',
    jsonEncode(_canon((decode(_anytlsReal)['tls'] as Map)['reality'])),
  ]);

  // 布尔 false ⇒ 删键（不是写 false）
  final insecureOff = decode(applyOk(anytls, _anytlsReal, {...av, 'allowInsecure': 'false'}));
  check('改 · allowInsecure=false ⇒ 键被删掉', (insecureOff['tls'] as Map).containsKey('insecure'), false);
  final insecureOn = decode(applyOk(anytls, _anytlsReal, {...av, 'allowInsecure': 'true'}));
  check('改 · allowInsecure=true ⇒ 写 true', (insecureOn['tls'] as Map)['insecure'], true);

  // 清空 uTLS 指纹 ⇒ `tls.utls` 整个消失（不留 `{enabled:true}` 空壳）
  final utlsCleared = decode(applyOk(anytls, _anytlsReal, {...av, 'utlsFingerprint': ''}));
  check('改 · 清 uTLS ⇒ tls.utls 消失', (utlsCleared['tls'] as Map).containsKey('utls'), false);
  final utlsSet = decode(applyOk(anytls, _anytlsReal, {...av, 'utlsFingerprint': 'safari'}));
  check('改 · 设 uTLS ⇒ {enabled:true, fingerprint}', (utlsSet['tls'] as Map)['utls'], {'enabled': true, 'fingerprint': 'safari'});

  // 清空 sni ⇒ 只删 server_name，reality/utls 不受影响
  final sniCleared = decode(applyOk(anytls, _anytlsReal, {...av, 'sni': ''}));
  check('改 · 清 sni ⇒ 只删 server_name', [
    (sniCleared['tls'] as Map).containsKey('server_name'),
    (sniCleared['tls'] as Map).containsKey('reality'),
    (sniCleared['tls'] as Map).containsKey('utls'),
  ], [false, true, true]);

  // alpn：逗号/换行都接受，写成数组
  final alpnSet = decode(applyOk(anytls, anytlsAlpn, {...readProtocolFormValues(payload: decode(anytlsAlpn), spec: anytls), 'alpn': 'h3\nh2'}));
  check('改 · alpn 换行分隔 ⇒ 数组', (alpnSet['tls'] as Map)['alpn'], ['h3', 'h2']);

  // ── 4. 容器语义（vless）───────────────────────────────────────────────────
  final toTcp = decode(applyOk(vless, _vlessWsReal, {...vv, 'transport': 'tcp'}));
  check('改 · 传输方式选 tcp ⇒ 没有 transport', toTcp.containsKey('transport'), false);
  check('改 · 传输方式选 tcp ⇒ 节点其余键保留', [
    toTcp['flow'],
    toTcp['packet_encoding'],
    ((toTcp['tls'] as Map)['reality'] as Map)['public_key'],
  ], [
    'xtls-rprx-vision',
    'xudp',
    'egq3FRi4oqkJ-iJ40r-pk10g7tawGg6o9c4UDGOPDU4',
  ]);

  final toWs = decode(applyOk(vless, _vlessTcpReal, {...vt, 'transport': 'ws', 'host': 'h.example.com', 'path': '/p'}));
  check('改 · 从无 transport 建 ws', toWs['transport'], {
    'type': 'ws',
    'path': '/p',
    'headers': {'Host': 'h.example.com'},
  });

  // ws 的 host 清空 ⇒ headers 里的 Host 删掉，且空的 headers 也一并清掉
  final wsHostCleared = decode(applyOk(vless, _vlessWsReal, {...vv, 'host': ''}));
  check('改 · ws host 清空 ⇒ headers 不留空壳', (wsHostCleared['transport'] as Map).containsKey('headers'), false);
  check('改 · ws host 清空 ⇒ path/type 仍在', [
    (wsHostCleared['transport'] as Map)['type'],
    (wsHostCleared['transport'] as Map)['path'],
  ], ['ws', '/yfjc/us1']);

  // security 关 ⇒ 整个 tls 摘掉（NekoBox `buildSingBoxOutboundTLS` 返回 null）
  final tlsOff = decode(applyOk(vless, _vlessWsReal, {...vv, 'security': 'false'}));
  check('改 · security=false ⇒ 没有 tls', tlsOff.containsKey('tls'), false);
  check('改 · security=false ⇒ 节点其余键保留', [tlsOff['uuid'], tlsOff['flow'], tlsOff['transport'] is Map], ['103cd797-ad1f-4225-a75d-247467374462', 'xtls-rprx-vision', true]);

  // reality 公钥清空 ⇒ reality 整个摘掉，但 tls.utls 留着
  final realityCleared = decode(applyOk(vless, _vlessWsReal, {...vv, 'realityPubKey': ''}));
  check('改 · 清 reality 公钥 ⇒ reality 消失', (realityCleared['tls'] as Map).containsKey('reality'), false);
  check('改 · 清 reality 公钥 ⇒ utls 仍在', (realityCleared['tls'] as Map)['utls'], {'enabled': true, 'fingerprint': 'chrome'});

  // reality 公钥存在 ⇒ 兄弟键 enabled=true 一并写入
  final realitySet = decode(
    applyOk(vless, _vlessTcpReal, {...vt, 'realityPubKey': 'PUB', 'realityShortId': 'SID'}),
  );
  check('改 · 设 reality ⇒ {enabled:true, public_key, short_id}', (realitySet['tls'] as Map)['reality'], {
    'enabled': true,
    'public_key': 'PUB',
    'short_id': 'SID',
  });

  // ── 5. 容器语义（hysteria2 / ss）──────────────────────────────────────────
  final obfsSet = decode(applyOk(hysteria2, _hysteria2Real, {...hv, 'serverObfs': 'secret'}));
  check('改 · hysteria2 设混淆 ⇒ {type:salamander, password}', obfsSet['obfs'], {'type': 'salamander', 'password': 'secret'});
  final obfsCleared = decode(applyOk(hysteria2, _hysteria2Real, {...hv, 'serverObfs': ''}));
  check('改 · hysteria2 清混淆 ⇒ 没有 obfs', obfsCleared.containsKey('obfs'), false);
  final recvSet = decode(applyOk(hysteria2, _hysteria2Real, {...hv, 'serverStreamReceiveWindow': '4194304'}));
  check('改 · hysteria2 收窗口写入（0 是合法值，另一条也必须留着）', [
    recvSet['stream_receive_window'],
    recvSet['connection_receive_window'],
  ], [4194304, 0]);

  final ssEdited = decode(applyOk(ss, _shadowsocksReal, {...sv, 'method': 'chacha20-ietf-poly1305', 'pluginName': 'v2ray-plugin', 'pluginConfig': 'tls'}));
  check('改 · ss method/plugin/plugin_opts', [ssEdited['method'], ssEdited['plugin'], ssEdited['plugin_opts']], [
    'chacha20-ietf-poly1305',
    'v2ray-plugin',
    'tls',
  ]);
  check('改 · ss 密码保留', ssEdited['password'], 'ec1fdc91-239d-40e5-8ade-ee1ca8f6dc10');

  // ── 6. 边界 ───────────────────────────────────────────────────────────────
  check('边界 · payload 不是 JSON ⇒ null', applyProtocolForm(payloadJson: '{oops', spec: anytls, values: av), null);
  check('边界 · payload 是数组 ⇒ null', applyProtocolForm(payloadJson: '[]', spec: anytls, values: av), null);
  check('边界 · 端口填了非数字 ⇒ null', applyProtocolForm(payloadJson: _anytlsReal, spec: anytls, values: {...av, 'serverPort': 'abc'}), null);
  check('边界 · 整数字段留空 ⇒ 删键', decode(applyOk(hysteria2, _hysteria2Real, {...hv, 'serverStreamReceiveWindow': ''})).containsKey('stream_receive_window'), false);
  check('边界 · tag 不因编辑而变化', decode(applyOk(anytls, _anytlsReal, {...av, 'serverAddress': 'x'}) )['tag'], '🇭🇰 Hong Kong RLT');

  // 校验器
  check('校验 · 必填缺失', validateProtocolForm(spec: vless, values: {...vv, 'uuid': ''}), ['uuid']);
  check('校验 · 端口越界', validateProtocolForm(spec: anytls, values: {...av, 'serverPort': '99999'}), ['serverPort']);
  check('校验 · 端口非数字', validateProtocolForm(spec: anytls, values: {...av, 'serverPort': 'x'}), ['serverPort']);
  check('校验 · 全部合法 ⇒ 空', validateProtocolForm(spec: vless, values: vv), <String>[]);
  check('校验 · 数字类非端口字段可以越界（照 NekoBox 只校验端口）', validateProtocolForm(spec: hysteria2, values: {...hv, 'serverStreamReceiveWindow': '99999999'}), <String>[]);

  // ── 7. 从零新建（NekoBox Manual Settings 的保存）────────────────────────
  //
  // 这一节证明"新建"与"编辑"共用同一套写入语义 —— 区别只在原文的起点
  // （新建用种子、编辑用现有 payload），所以不存在第二条会写坏配置的路径。
  check('新建 · anytls 种子带 tls.enabled（构建期写死）', protocolSeedPayload(anytls), {
    'tls': {'enabled': true},
  });
  check('新建 · hysteria2 同 anytls', protocolSeedPayload(hysteria2), {
    'tls': {'enabled': true},
  });
  check('新建 · vless 种子不带 tls（security 默认 none）', protocolSeedPayload(vless), <String, dynamic>{});
  check('新建 · shadowsocks 种子为空', protocolSeedPayload(ss), <String, dynamic>{});

  final created = decode(
    buildProtocolPayload(
      spec: anytls,
      tag: '我的节点',
      values: {
        'serverAddress': 'a.example.com',
        'serverPort': '443',
        'password': 'pw',
        'sni': 'a.example.com',
        'allowInsecure': 'true',
        'utlsFingerprint': 'chrome',
      },
    )!,
  );
  check('新建 · tag / type 由调用方给', [created['tag'], created['type']], ['我的节点', 'anytls']);
  check('新建 · tls.enabled 来自种子（表单没有这个字段）', (created['tls'] as Map)['enabled'], true);
  check('新建 · 填了的字段写入', [
    created['server'],
    created['server_port'],
    (created['tls'] as Map)['server_name'],
    (created['tls'] as Map)['insecure'],
    (created['tls'] as Map)['utls'],
  ], [
    'a.example.com',
    443,
    'a.example.com',
    true,
    {'enabled': true, 'fingerprint': 'chrome'},
  ]);
  check('新建 · 没填的字段一个键都不产生', [
    created.containsKey('alpn'),
    created.containsKey('certificate'),
    (created['tls'] as Map).containsKey('certificate'),
  ], [false, false, false]);

  final createdVless = decode(
    buildProtocolPayload(
      spec: vless,
      tag: 'v',
      values: {'serverAddress': 'a.example.com', 'serverPort': '443', 'uuid': 'u', 'security': 'false'},
    )!,
  );
  check('新建 · vless 关 tls ⇒ 连种子里的 tls 都不留', createdVless.containsKey('tls'), false);
  check('新建 · vless 必填 uuid 缺失会被校验拦下', validateProtocolForm(spec: vless, values: {
    'serverAddress': 'a.example.com',
    'uuid': '',
  }), ['uuid']);

  check('新建 · 手动菜单顺序照 NekoBox add_profile_menu', kManualCreatableProtocols, [
    'shadowsocks',
    'vless',
    'hysteria2',
    'anytls',
  ]);
  check('新建 · 协议显示名照 NekoBox strings', [
    protocolDisplayName('shadowsocks'),
    protocolDisplayName('vless'),
    protocolDisplayName('hysteria2'),
    protocolDisplayName('anytls'),
  ], ['Shadowsocks', 'VLESS', 'Hysteria', 'AnyTLS']);

  print('');
  print('passed: $_passed   failed: $_failed');
  print(_failed == 0 ? 'ALL PASS' : 'SOME FAILED');
  if (_failed != 0) throw StateError('$_failed assertion(s) failed');
}
