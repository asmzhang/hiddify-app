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
  check('规格 · 未知类型无表单', protocolFormSpecFor('wgtoolong'), null);
  check('规格 · trojan_go 不移植（内核无出站）', protocolFormSpecFor('trojan_go'), null);
  check('规格 · 大小写/空格归一', protocolFormSpecFor(' AnyTLS '), anytls);
  check('规格 · vmess 复用 v2ray 表单', protocolFormSpecFor('vmess'), vless);
  check('规格 · anytls 字段数', protocolFormFieldIds(anytls).length, 8);
  check('规格 · vless 字段数', protocolFormFieldIds(vless).length, 18);
  check('规格 · hysteria2 字段数', protocolFormFieldIds(hysteria2).length, 13);
  check('规格 · shadowsocks 字段数', protocolFormFieldIds(ss).length, 6);
  final socks = protocolFormSpecFor('socks')!;
  final ssh = protocolFormSpecFor('ssh')!;
  final tuic = protocolFormSpecFor('tuic')!;
  final shadowtls = protocolFormSpecFor('shadowtls')!;
  final mieru = protocolFormSpecFor('mieru')!;
  final naive = protocolFormSpecFor('naive')!;
  final trojan = protocolFormSpecFor('trojan')!;
  final hysteria = protocolFormSpecFor('hysteria')!;
  final wg = protocolFormSpecFor('wireguard')!;
  check('规格 · socks 字段数', protocolFormFieldIds(socks).length, 5);
  check('规格 · ssh 字段数', protocolFormFieldIds(ssh).length, 7);
  check('规格 · tuic 字段数', protocolFormFieldIds(tuic).length, 12);
  check('规格 · shadowtls 字段数', protocolFormFieldIds(shadowtls).length, 9);
  check('规格 · mieru 字段数', protocolFormFieldIds(mieru).length, 5);
  check('规格 · naive 字段数', protocolFormFieldIds(naive).length, 8);
  check('规格 · trojan 字段数（vless 18 - flow - packetEncoding = 16）', protocolFormFieldIds(trojan).length, 16);
  check('规格 · hysteria v1 字段数', protocolFormFieldIds(hysteria).length, 14);

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

  // ── 6.6 批次 6：trojan / hysteria v1 / hop_interval 后缀 ──────────────────
  // trojan = vless 减 flow/packetEncoding（NekoBox TrojanSettingsActivity 复用
  // standard_v2ray_preferences，uuid 字段改绑 bean.password）。
  const trojanWsReal =
      '{"type":"trojan","tag":"tj-ws","server":"t.example.com","server_port":443,'
      '"password":"pw8","transport":{"type":"ws","path":"/tj","headers":{"Host":"tj.example.com"}},'
      '"tls":{"enabled":true,"server_name":"sni.example.com","alpn":["h2","http/1.1"]}}';
  checkRoundTrip('trojan(ws)', trojan, trojanWsReal);
  final tjV = readProtocolFormValues(payload: decode(trojanWsReal), spec: trojan);
  check('读 · trojan 密码', tjV['password'], 'pw8');
  check('读 · trojan 传输方式', tjV['transport'], 'ws');
  check('读 · trojan ws host', tjV['host'], 'tj.example.com');
  check('读 · trojan 无 flow/packetEncoding 字段（与 vless 差异）', [
    tjV.containsKey('flow'),
    tjV.containsKey('packetEncoding'),
  ], [false, false]);

  const trojanReal = '{"type":"trojan","tag":"tj","server":"t2.example.com","server_port":443,"password":"pw","tls":{"enabled":true}}';
  checkRoundTrip('trojan(裸 tls)', trojan, trojanReal);
  // reality 语义与 vless 完全同构
  final tjRealitySet = decode(applyOk(trojan, trojanReal, {
    ...readProtocolFormValues(payload: decode(trojanReal), spec: trojan),
    'realityPubKey': 'PUB',
    'realityShortId': 'SID',
    'utlsFingerprint': 'chrome',
  }));
  check('改 · trojan reality/uTLS 与 vless 同构', (tjRealitySet['tls'] as Map)['reality'], {
    'enabled': true,
    'public_key': 'PUB',
    'short_id': 'SID',
  });
  // security 关 ⇒ 整个 tls 摘掉
  final tjTlsOff = decode(applyOk(trojan, trojanWsReal, {...tjV, 'security': 'false'}));
  check('改 · trojan security=false ⇒ 没有 tls', tjTlsOff.containsKey('tls'), false);
  check('改 · trojan transport 保留', tjTlsOff.containsKey('transport'), true);
  // 传输切 tcp ⇒ transport 消失
  final tjTcp = decode(applyOk(trojan, trojanWsReal, {...tjV, 'transport': 'tcp'}));
  check('改 · trojan 传输 tcp ⇒ 无 transport', tjTcp.containsKey('transport'), false);

  // 新建：种子不带 tls（security 默认关，与 vless 一致）
  check('新建 · trojan 种子为空', protocolSeedPayload(trojan), <String, dynamic>{});
  final tjCreated = decode(buildProtocolPayload(
    spec: trojan,
    tag: 'n',
    values: {'serverAddress': 'a.com', 'serverPort': '443', 'password': 'pw', 'security': 'true', 'sni': 'a.com'},
  )!);
  check('新建 · trojan 开 security ⇒ tls.enabled', (tjCreated['tls'] as Map)['enabled'], true);
  check('新建 · trojan 必填校验', validateProtocolForm(spec: trojan, values: {'serverAddress': '', 'password': ''}).toSet(), {
    'serverAddress',
    'password',
  }.toSet());

  // hysteria v1：auth 双框（顶替 NekoBox TYPE 下拉）、恒用 TLS、窗口键各归各位
  const hysteriaReal =
      '{"type":"hysteria","tag":"h1","server":"h.example.com","server_port":443,'
      '"auth_str":"pass123","up_mbps":100,"down_mbps":50,'
      '"obfs":"obfsPass","hop_interval":"30s",'
      '"tls":{"enabled":true,"server_name":"sni.example.com","insecure":true}}';
  checkRoundTrip('hysteria(v1)', hysteria, hysteriaReal);
  final h1V = readProtocolFormValues(payload: decode(hysteriaReal), spec: hysteria);
  check('读 · hysteria auth_str', h1V['serverAuthString'], 'pass123');
  check('读 · hysteria auth(base64) 缺键 ⇒ 空', h1V['serverAuthBase64'], '');
  check('读 · hysteria hop_interval 剥掉 s 后缀', h1V['hopInterval'], '30');

  // BASE64 认证走 auth 键
  const hysteriaB64 =
      '{"type":"hysteria","tag":"h1b","server":"h.example.com","server_port":443,"auth":"cGFzczEyMw=="}';
  checkRoundTrip('hysteria(base64 auth)', hysteria, hysteriaB64);
  check('读 · hysteria base64 auth', readProtocolFormValues(payload: decode(hysteriaB64), spec: hysteria)['serverAuthBase64'], 'cGFzczEyMw==');

  // 改字段：两窗口各写各键（修复 NekoBox HysteriaFmt.kt:299 的抄写 bug）
  final h1Edited = decode(applyOk(hysteria, hysteriaReal, {
    ...h1V,
    'serverStreamReceiveWindow': '65536',
    'serverConnectionReceiveWindow': '8388608',
  }));
  check('改 · hysteria recv_window_conn(流窗口)', h1Edited['recv_window_conn'], 65536);
  check('改 · hysteria recv_window(连接窗口)', h1Edited['recv_window'], 8388608);

  // hop_interval：裸数字自动补 "s"（内核 badoption.Duration 必须带单位）
  final h1Hop = decode(applyOk(hysteria, hysteriaReal, {...h1V, 'hopInterval': '45'}));
  check('改 · hysteria 裸数字 hop ⇒ 补 s', h1Hop['hop_interval'], '45s');
  // 已带单位的原文原样保留
  final h1HopUnit = decode(applyOk(hysteria, hysteriaReal, {...h1V, 'hopInterval': '2m'}));
  check('改 · hysteria 带单位 hop 原样', h1HopUnit['hop_interval'], '2m');
  // 清空 ⇒ 删键
  final h1HopCleared = decode(applyOk(hysteria, hysteriaReal, {...h1V, 'hopInterval': ''}));
  check('改 · hysteria 空 hop ⇒ 删键', h1HopCleared.containsKey('hop_interval'), false);

  // obfs（v1 明文串，非 salamander 容器）
  final h1ObfsCleared = decode(applyOk(hysteria, hysteriaReal, {...h1V, 'serverObfs': ''}));
  check('改 · hysteria 清混淆 ⇒ 删键', h1ObfsCleared.containsKey('obfs'), false);

  // 新建：种子带 tls.enabled（v1 恒用 TLS）
  check('新建 · hysteria 种子带 tls.enabled（构建期写死）', protocolSeedPayload(hysteria), {
    'tls': {'enabled': true},
  });
  final h1Created = decode(buildProtocolPayload(
    spec: hysteria,
    tag: 'n',
    values: {'serverAddress': 'a.com', 'serverPort': '443', 'serverAuthString': 'pw', 'hopInterval': '30'},
  )!);
  check('新建 · hysteria tls 来自种子', (h1Created['tls'] as Map)['enabled'], true);
  check('新建 · hysteria hop 补 s', h1Created['hop_interval'], '30s');
  check('新建 · hysteria 未填键不产生', h1Created.containsKey('obfs'), false);
  // 与 vless/trojan/ss 的 serverPort 同口径：地址必填，端口非必填但填了必须合法
  check('校验 · hysteria 必填(地址)', validateProtocolForm(spec: hysteria, values: {
    'serverAddress': '',
    'serverPorts': '443',
  }), ['serverAddress']);
  check('校验 · hysteria 端口非法要拦', validateProtocolForm(spec: hysteria, values: {
    'serverAddress': 'a.com',
    'serverPorts': '99999',
  }), ['serverPorts']);

  // hysteria2 的 hop_interval 同样获得后缀能力（批次 6 修复既有缺陷）
  check('规格 · hysteria2 hopInterval 带 valueSuffix', hysteria2.fields.firstWhere((f) => f.id == 'hopInterval').valueSuffix, 's');
  const hy2Hop =
      '{"type":"hysteria2","tag":"h2","server":"h.example.com","server_port":443,"hop_interval":"30s"}';
  final hy2V = readProtocolFormValues(payload: decode(hy2Hop), spec: hysteria2);
  check('读 · hysteria2 hop 剥 s', hy2V['hopInterval'], '30');
  check('改 · hysteria2 裸数字补 s', decode(applyOk(hysteria2, hy2Hop, {...hy2V, 'hopInterval': '60'}))['hop_interval'], '60s');

  // ── 6.5 批次 2：socks / ssh / tuic / shadowtls / mieru / naive ────────────
  const socksReal =
      '{"type":"socks","tag":"s","server":"127.0.0.1","server_port":1080,'
      '"version":"5","username":"u","password":"p"}';
  checkRoundTrip('socks', socks, socksReal);
  final socksV = readProtocolFormValues(payload: decode(socksReal), spec: socks);
  check('读 · socks 版本', socksV['serverProtocol'], '5');
  check('读 · socks 用户名', socksV['serverUsername'], 'u');
  const socksNoAuth =
      '{"type":"socks","tag":"s2","server":"10.0.0.1","server_port":1080}';
  checkRoundTrip('socks(无认证)', socks, socksNoAuth);
  check('读 · socks 无认证全空', [
    for (final id in ['serverProtocol', 'serverUsername', 'serverPassword'])
      readProtocolFormValues(payload: decode(socksNoAuth), spec: socks)[id],
  ], ['', '', '']);

  // private_key 是 text（PEM 含换行，拆行会毁掉密钥）。NekoBox Bean 存单串，
  // 表单写出单串；ray2sing 链接解析产出的是单元素数组 —— 内核 Listable[string]
  // 两者等价，表单会把它**归一成单串**（形状变化是有意的，见 protocol_form.dart 文档）。
  const sshReal =
      '{"type":"ssh","tag":"ssh-1","server":"host.example.com","server_port":22,'
      '"user":"root","private_key":"-----BEGIN OPENSSH PRIVATE KEY-----\\nabc\\n-----END OPENSSH PRIVATE KEY-----",'
      '"host_key":["ssh-ed25519 AAAA"],"password":"pw"}';
  checkRoundTrip('ssh', ssh, sshReal);
  final sshV = readProtocolFormValues(payload: decode(sshReal), spec: ssh);
  check('读 · ssh 用户', sshV['serverUsername'], 'root');
  check('读 · ssh 私钥含 PEM 头', (sshV['serverPrivateKey'] ?? '').startsWith('-----BEGIN OPENSSH PRIVATE KEY-----'), true);
  check('读 · ssh host_key', sshV['serverCertificates'], 'ssh-ed25519 AAAA');
  // 数组形状的 private_key（ray2sing 产出）：读得回来，写出归一成单串
  const sshArrayKey =
      '{"type":"ssh","tag":"ssh-2","server":"h","server_port":22,"private_key":["KEY"]}';
  final sshArrayRead = readProtocolFormValues(payload: decode(sshArrayKey), spec: ssh);
  check('读 · ssh 数组私钥读回', sshArrayRead['serverPrivateKey'], 'KEY');
  check('改 · ssh 数组私钥归一成单串(内核等价)', decode(applyOk(ssh, sshArrayKey, sshArrayRead))['private_key'], 'KEY');
  check('读 · ssh host_key', sshV['serverCertificates'], 'ssh-ed25519 AAAA');
  // 清空私钥 ⇒ 键删除（stringList 空串语义与文本一致）
  final sshKeyCleared = decode(applyOk(ssh, sshReal, {...sshV, 'serverPrivateKey': ''}));
  check('改 · ssh 清私钥 ⇒ 键删除', sshKeyCleared.containsKey('private_key'), false);
  check('改 · ssh 清私钥 ⇒ host_key 仍在', sshKeyCleared['host_key'], ['ssh-ed25519 AAAA']);

  const tuicReal =
      '{"type":"tuic","tag":"t","server":"t.example.com","server_port":443,'
      '"uuid":"u1","password":"p1","congestion_control":"bbr","udp_relay_mode":"quic",'
      '"zero_rtt_handshake":true,'
      '"tls":{"enabled":true,"server_name":"sni.example.com","alpn":["h3"],"disable_sni":true}}';
  checkRoundTrip('tuic', tuic, tuicReal);
  final tuicV = readProtocolFormValues(payload: decode(tuicReal), spec: tuic);
  check('读 · tuic uuid', tuicV['serverUsername'], 'u1');
  check('读 · tuic 拥塞控制', tuicV['serverCongestionController'], 'bbr');
  check('读 · tuic udp 模式', tuicV['serverUDPRelayMode'], 'quic');
  check('读 · tuic 0rtt', tuicV['serverReduceRTT'], 'true');
  check('读 · tuic disable_sni', tuicV['serverDisableSNI'], 'true');
  check('读 · tuic alpn 数组', tuicV['serverALPN'], 'h3');
  final tuicEdited = decode(applyOk(tuic, tuicReal, {...tuicV, 'serverCongestionController': 'cubic', 'serverUDPRelayMode': ''}));
  check('改 · tuic 拥塞切换', tuicEdited['congestion_control'], 'cubic');
  check('改 · tuic udp 模式清空 ⇒ 删键', tuicEdited.containsKey('udp_relay_mode'), false);
  check('改 · tuic 其余 tls 不动', (tuicEdited['tls'] as Map)['server_name'], 'sni.example.com');

  const shadowtlsReal =
      '{"type":"shadowtls","tag":"st","server":"st.example.com","server_port":443,'
      '"version":3,"password":"p",'
      '"tls":{"enabled":true,"server_name":"sni.example.com","utls":{"enabled":true,"fingerprint":"chrome"}}}';
  checkRoundTrip('shadowtls', shadowtls, shadowtlsReal);
  final stV = readProtocolFormValues(payload: decode(shadowtlsReal), spec: shadowtls);
  check('读 · shadowtls 版本(int→串)', stV['version'], '3');
  check('读 · shadowtls uTLS', stV['utlsFingerprint'], 'chrome');
  // 关键：version 经 writeValues 必须写回 int（内核 ShadowTLSOutboundOptions.Version 是 int）
  final stEdited = decode(applyOk(shadowtls, shadowtlsReal, {...stV, 'version': '2'}));
  check('改 · shadowtls 版本写回 int 而非字符串', stEdited['version'], 2);
  final stCreated = decode(buildProtocolPayload(
    spec: shadowtls,
    tag: 'n',
    values: {'serverAddress': 'a.com', 'serverPort': '443', 'version': '3', 'password': 'p', 'sni': 'a.com'},
  )!);
  check('新建 · shadowtls 种子带 tls.enabled', (stCreated['tls'] as Map)['enabled'], true);
  check('新建 · shadowtls 版本是 int', stCreated['version'], 3);
  check('新建 · shadowtls 未填 uTLS ⇒ 无空壳', (stCreated['tls'] as Map).containsKey('utls'), false);

  // mieru：端口/协议落 portBindings[0]（数组下标路径）
  const mieruReal =
      '{"type":"mieru","tag":"m","server":"m.example.com",'
      '"portBindings":[{"protocol":"TCP","port":6666}],'
      '"username":"user","password":"pass"}';
  checkRoundTrip('mieru', mieru, mieruReal);
  final mieruV = readProtocolFormValues(payload: decode(mieruReal), spec: mieru);
  check('读 · mieru 端口(数组内)', mieruV['serverPort'], '6666');
  check('读 · mieru 协议(数组内)', mieruV['serverProtocol'], 'TCP');
  final mieruEdited = decode(applyOk(mieru, mieruReal, {...mieruV, 'serverPort': '8888', 'serverProtocol': 'UDP'}));
  check('改 · mieru 端口写回数组', mieruEdited['portBindings'], [
    {'protocol': 'UDP', 'port': 8888},
  ]);
  final mieruCreated = decode(buildProtocolPayload(
    spec: mieru,
    tag: 'n',
    values: {'serverAddress': 'a.com', 'serverPort': '6666', 'serverProtocol': 'TCP', 'serverUsername': 'u', 'serverPassword': 'p'},
  )!);
  check('新建 · mieru portBindings 形状', mieruCreated['portBindings'], [
    {'protocol': 'TCP', 'port': 6666},
  ]);
  check('校验 · mieru 必填(用户/密码/端口)', validateProtocolForm(spec: mieru, values: {
    'serverAddress': 'a.com',
    'serverPort': '',
    'serverUsername': '',
    'serverPassword': '',
  }).toSet(), {'serverPort', 'serverUsername', 'serverPassword'}.toSet());

  // naive：proto → quic 布尔（writeValues 映射）
  const naiveReal =
      '{"type":"naive","tag":"n","server":"n.example.com","server_port":443,'
      '"username":"u","password":"p","quic":true,'
      '"tls":{"enabled":true,"server_name":"sni.example.com"}}';
  checkRoundTrip('naive', naive, naiveReal);
  final naiveV = readProtocolFormValues(payload: decode(naiveReal), spec: naive);
  check('读 · naive quic:true → quic', naiveV['serverProtocol'], 'quic');
  final naiveHttps = decode(applyOk(naive, naiveReal, {...naiveV, 'serverProtocol': 'https'}));
  check('改 · naive 选 https ⇒ quic 键删除(默认非quic)', naiveHttps.containsKey('quic'), false);
  check('读 · naive 缺 quic 键 → https(内核默认)', readProtocolFormValues(payload: naiveHttps, spec: naive)['serverProtocol'], 'https');
  final naiveEdited = decode(applyOk(naive, naiveReal, {...naiveV, 'serverInsecureConcurrency': '4'}));
  check('改 · naive 并发写入', naiveEdited['insecure_concurrency'], 4);
  final naiveCreated = decode(buildProtocolPayload(
    spec: naive,
    tag: 'n',
    values: {'serverAddress': 'a.com', 'serverPort': '443', 'serverProtocol': 'quic', 'serverUsername': 'u', 'serverPassword': 'p'},
  )!);
  check('新建 · naive 种子带 tls.enabled', (naiveCreated['tls'] as Map)['enabled'], true);
  check('新建 · naive quic → true', naiveCreated['quic'], true);

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
  check('新建 · tuic/shadowtls/naive 种子带 tls.enabled', [
    protocolSeedPayload(tuic),
    protocolSeedPayload(shadowtls),
    protocolSeedPayload(naive),
  ], [
    {
      'tls': {'enabled': true},
    },
    {
      'tls': {'enabled': true},
    },
    {
      'tls': {'enabled': true},
    },
  ]);
  check('新建 · mieru 种子占位 portBindings[0]', jsonEncode(_canon(protocolSeedPayload(mieru))), '{"portBindings":[{}]}');

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
    'socks',
    'shadowsocks',
    'vless',
    'trojan',
    'mieru',
    'naive',
    'hysteria',
    'hysteria2',
    'tuic',
    'shadowtls',
    'anytls',
    'ssh',
    'wireguard',
  ]);
  check('新建 · 协议显示名照 NekoBox strings', [
    for (final p in kManualCreatableProtocols) protocolDisplayName(p),
  ], [
    'SOCKS',
    'Shadowsocks',
    'VLESS',
    'Trojan',
    'Mieru',
    'Naïve',
    'Hysteria',
    'Hysteria',
    'TUIC',
    'ShadowTLS',
    'AnyTLS',
    'SSH',
    'WireGuard',
  ]);

  // ── 8. 批次 9：wireguard（endpoint 形态）────────────────────────────────
  // 字段清单照 `wireguard_preferences.xml`（proxy_cat 8 字段），产物按内核
  // `WireGuardEndpointOptions`：地址/端口/凭据落 `peers[0]`，本地地址是 CIDR 数组。
  check('规格 · wireguard 有表单', protocolFormSpecFor('wireguard'), wg);
  check('规格 · wireguard 字段数', protocolFormFieldIds(wg).length, 8);

  // 真机形状：内核 Parse 从 wg:// 订阅产出的 endpoint JSON
  const wgReal =
      '{"type":"wireguard","tag":"wg-hk","address":["172.16.0.2/32"],'
      '"private_key":"aBcD1234=","mtu":1420,'
      '"peers":[{"address":"hk.example.com","port":51820,"public_key":"PUBKEY=",'
      '"pre_shared_key":"PSK=","reserved":[1,2,3]}]}';
  checkRoundTrip('wireguard(endpoint)', wg, wgReal);
  final wgv = readProtocolFormValues(payload: decode(wgReal), spec: wg);
  // 取 peers[0]（显式 cast 避免 avoid_dynamic_calls）
  Map<String, dynamic> wgPeer0(Map<String, dynamic> m) => (m['peers'] as List).first as Map<String, dynamic>;
  check('读 · wg 地址(peers[0].address)', wgv['serverAddress'], 'hk.example.com');
  check('读 · wg 端口(peers[0].port)', wgv['serverPort'], '51820');
  check('读 · wg 本地地址(CIDR 数组)', wgv['localAddress'], '172.16.0.2/32');
  check('读 · wg 私钥', wgv['privateKey'], 'aBcD1234=');
  check('读 · wg 对端公钥', wgv['peerPublicKey'], 'PUBKEY=');
  check('读 · wg 预共享密钥', wgv['peerPreSharedKey'], 'PSK=');
  check('读 · wg mtu', wgv['serverMTU'], '1420');
  check('读 · wg reserved(数字数组→逗号串)', wgv['reserved'], '1,2,3');

  // 编辑：改地址/端口写回 peers[0]，其余键不动
  final wgEdited = decode(applyOk(wg, wgReal, {...wgv, 'serverAddress': 'new.example.com', 'serverPort': '1234'}));
  check('改 · wg peers[0] 地址端口', [wgPeer0(wgEdited)['address'], wgPeer0(wgEdited)['port']], ['new.example.com', 1234]);
  check('改 · wg 其余键不动', [
    wgEdited['address'],
    wgEdited['private_key'],
    wgPeer0(wgEdited)['public_key'],
    wgPeer0(wgEdited)['reserved'],
  ], [
    ['172.16.0.2/32'],
    'aBcD1234=',
    'PUBKEY=',
    [1, 2, 3],
  ]);

  // reserved：逗号/换行分隔数字 → 数组；非法值被校验器和写回双双拦截
  final wgRes = decode(applyOk(wg, wgReal, {...wgv, 'reserved': '7, 8 ,9'}));
  check('改 · wg reserved 逗号分隔(带空格)', wgPeer0(wgRes)['reserved'], [7, 8, 9]);
  check('校验 · wg reserved 非数字要拦', validateProtocolForm(spec: wg, values: {...wgv, 'reserved': '1,a,3'}), ['reserved']);
  check('校验 · wg reserved 越界要拦', validateProtocolForm(spec: wg, values: {...wgv, 'reserved': '1,256,3'}), ['reserved']);
  check('校验 · wg reserved 合法 ⇒ 空', validateProtocolForm(spec: wg, values: {...wgv, 'reserved': '0,255'}), <String>[]);
  check('边界 · wg reserved 非数字写回 ⇒ null', applyProtocolForm(payloadJson: wgReal, spec: wg, values: {...wgv, 'reserved': 'x'}), null);
  final wgResCleared = decode(applyOk(wg, wgReal, {...wgv, 'reserved': ''}));
  check('改 · wg reserved 清空 ⇒ peers[0] 删键', wgPeer0(wgResCleared).containsKey('reserved'), false);

  // 新建：种子 mtu=1420 + peers[0] 占位。
  // mtu 留空会被"空值=删键"语义拿掉 —— 内核默认 1408
  //（transport/wireguard/endpoint.go:103-104 `if options.MTU == 0`），合法且有依据。
  check('新建 · wireguard 种子', jsonEncode(_canon(protocolSeedPayload(wg))), '{"mtu":1420,"peers":[{}]}');
  final wgCreated = decode(buildProtocolPayload(
    spec: wg,
    tag: 'n',
    values: {
      'serverAddress': 'a.example.com',
      'serverPort': '51820',
      'localAddress': '172.16.0.2/32',
      'privateKey': 'KEY=',
      'peerPublicKey': 'PUB=',
      'reserved': '9,9,9',
    },
  )!);
  check('新建 · wg 形状完整（mtu 留空 ⇒ 内核默认 1408）', jsonEncode(_canon(wgCreated)),
      '{"address":["172.16.0.2/32"],"peers":[{"address":"a.example.com","port":51820,"public_key":"PUB=","reserved":[9,9,9]}],"private_key":"KEY=","tag":"n","type":"wireguard"}');
  final wgCreatedMtu = decode(buildProtocolPayload(
    spec: wg,
    tag: 'n',
    values: {
      'serverAddress': 'a.example.com',
      'privateKey': 'KEY=',
      'serverMTU': '1420',
    },
  )!);
  check('新建 · wg 填 mtu ⇒ 写入', wgCreatedMtu['mtu'], 1420);
  check('新建 · wg 必填(地址/私钥)', validateProtocolForm(spec: wg, values: {
    'serverAddress': '',
    'privateKey': '',
  }).toSet(), {'serverAddress', 'privateKey'}.toSet());

  print('');
  print('passed: $_passed   failed: $_failed');
  print(_failed == 0 ? 'ALL PASS' : 'SOME FAILED');
  if (_failed != 0) throw StateError('$_failed assertion(s) failed');
}
