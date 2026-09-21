// 「用户路由规则 → 内核 JSON 契约」的可执行校验（与 check_config_assembly.dart 同理：
// 纯 Dart + `dart run`，不依赖 flutter_tester）。
//
// 运行：dart run tool/check_route_rule_json.dart
//
// 要证明的核心（与 hiddify-core v2/config/route_rules_test.go 隔空呼应）：
//  1. **顶层键 = "rules"**（kebab fieldRename 后直通 Go json tag）——旧实现发
//     "route-rule" + proto3 JSON，Go unmarshal 静默丢弃（批次 13 修复的根因）。
//  2. 规则键用 route_rule.pb.go 的 **复数 json tag**（rule_sets/package_names/…）。
//  3. **枚举发数字**（outbound/network/protocols）——proto3 JSON 发枚举名，Go 拒收。
//  4. 空字段不发键；禁用规则照发（Go 侧自行跳过），空列表发 "rules": []。
//  5. 往返：coreJsonToRules 能无损读回转换器产物（导入流复用）。
//
// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:hiddify/features/route_rules/data/route_rule_json.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';

var _passed = 0;
var _failed = 0;

void check(String label, Object? actual, Object? expected) {
  final a = jsonEncode(_canon(actual));
  final b = jsonEncode(_canon(expected));
  if (a == b) {
    _passed++;
  } else {
    _failed++;
    print('FAIL  $label');
    print('      actual   = $a');
    print('      expected = $b');
  }
}

Object? _canon(Object? node) {
  if (node is Map) {
    final keys = node.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(node[k])};
  }
  if (node is List) return [for (final item in node) _canon(item)];
  return node;
}

Rule rule({
  int listOrder = 0,
  bool enabled = true,
  String name = '',
  Outbound? outbound,
  Network? network,
  List<String> ruleSets = const [],
  List<String> packageNames = const [],
  List<String> processNames = const [],
  List<String> processPaths = const [],
  List<String> portRanges = const [],
  List<String> sourcePortRanges = const [],
  List<Protocol> protocols = const [],
  List<String> ipCidrs = const [],
  List<String> sourceIpCidrs = const [],
  List<String> domains = const [],
  List<String> domainSuffixes = const [],
  List<String> domainKeywords = const [],
  List<String> domainRegexes = const [],
}) {
  final r = Rule();
  r.listOrder = listOrder;
  r.enabled = enabled;
  if (name.isNotEmpty) r.name = name;
  if (outbound != null) r.outbound = outbound;
  if (network != null) r.network = network;
  r.ruleSets.addAll(ruleSets);
  r.packageNames.addAll(packageNames);
  r.processNames.addAll(processNames);
  r.processPaths.addAll(processPaths);
  r.portRanges.addAll(portRanges);
  r.sourcePortRanges.addAll(sourcePortRanges);
  r.protocols.addAll(protocols);
  r.ipCidrs.addAll(ipCidrs);
  r.sourceIpCidrs.addAll(sourceIpCidrs);
  r.domains.addAll(domains);
  r.domainSuffixes.addAll(domainSuffixes);
  r.domainKeywords.addAll(domainKeywords);
  r.domainRegexes.addAll(domainRegexes);
  return r;
}

void main() {
  // ── 1. 全字段规则：键名与枚举形态逐一对齐 Go 契约 ────────────────────────
  final full = routeRuleToCoreJson([
    rule(
      listOrder: 1,
      name: 'cn-direct',
      outbound: Outbound.direct,
      ruleSets: ['https://raw.example.com/geosite-cn.srs'],
      domainSuffixes: ['.cn', '.中国'],
    ),
  ]);
  check('顶层键只有 rules', full.keys.toList(), ['rules']);
  final fullRule = (full['rules'] as List).first as Map;
  check('规则键集合（复数 tag + 数字枚举形态）', fullRule, {
    'list_order': 1,
    'enabled': true,
    'name': 'cn-direct',
    'outbound': 1, // Outbound.direct = 1（数字，非 "direct"）
    'rule_sets': ['https://raw.example.com/geosite-cn.srs'],
    'domain_suffixes': ['.cn', '.中国'],
  });

  // ── 2. 枚举值锚定（pb.go 定义，勿漂移）───────────────────────────────────
  check('Outbound 枚举序', [Outbound.proxy.value, Outbound.direct.value, Outbound.direct_with_fragment.value, Outbound.block.value], [0, 1, 2, 3]);
  check('Network 枚举序', [Network.all.value, Network.tcp.value, Network.udp.value], [0, 1, 2]);
  check('Protocol 枚举序', [
    Protocol.tls.value,
    Protocol.http.value,
    Protocol.quic.value,
    Protocol.stun.value,
    Protocol.dns.value,
    Protocol.bittorrent.value,
  ], [0, 1, 2, 3, 4, 5]);

  // network=all 不发键（Go 零值语义，发了也无害但不洁）；tcp/udp 发数字
  check('network all 不发键', routeRuleToCoreJson([rule(network: Network.all)])['rules'][0].containsKey('network'), false);
  check('network udp = 2', routeRuleToCoreJson([rule(network: Network.udp)])['rules'][0]['network'], 2);

  // ── 3. 空字段不发键（对齐 omitempty，Go unmarshal 后零值等价）────────────
  // 注意：list_order 是显式赋值的标量（默认 0 也算 set），转换器照发 —— Go 侧
  // ListOrder 本就不参与路由（makeUserRouteRules 用循环序），发 0 无害。
  final minimal = routeRuleToCoreJson([rule(name: 'only-name', outbound: Outbound.block)])['rules'][0] as Map;
  check('最小规则不含空字段键', minimal.keys.where((k) => k != 'list_order').toList()..sort(), ['enabled', 'name', 'outbound']);
  check('protocols 空不发键', minimal.containsKey('protocols'), false);

  // ── 4. 禁用规则照发（Go makeUserRouteRules 跳过 !Enabled）────────────────
  final disabled = routeRuleToCoreJson([
    rule(listOrder: 0, enabled: false, name: 'off', outbound: Outbound.proxy),
  ])['rules'][0] as Map;
  check('enabled=false 显式不发 true 键', disabled.containsKey('enabled'), false);
  check('禁用规则仍在 rules 数组里', (routeRuleToCoreJson([rule(enabled: false, name: 'off')])['rules'] as List).length, 1);

  // ── 5. 空列表 ⇒ "rules": []（清空语义显式化）────────────────────────────
  check('空规则列表', routeRuleToCoreJson(const []), {'rules': []});

  // ── 6. 往返：coreJsonToRules 读回转换器产物无损 ──────────────────────────
  final roundTripSource = [
    rule(
      listOrder: 2,
      name: 'block-ads',
      outbound: Outbound.block,
      network: Network.tcp,
      domains: ['ads.example.com'],
      protocols: [Protocol.http, Protocol.quic],
      portRanges: ['1000-2000'],
    ),
    rule(listOrder: 3, name: 'wg-app', outbound: Outbound.proxy, packageNames: ['com.example.app'], ipCidrs: ['10.0.0.0/8']),
  ];
  final jsonForm = routeRuleToCoreJson(roundTripSource);
  final back = coreJsonToRules(jsonForm);
  check('往返条数', back.length, 2);
  check('往返 #1 name/outbound', [back[0].name, back[0].outbound.value], ['block-ads', 3]);
  check('往返 #1 复数列表', [back[0].domains.toList(), back[0].portRanges.toList()], [
    ['ads.example.com'],
    ['1000-2000'],
  ]);
  check('往返 #1 枚举列表', back[0].protocols.map((p) => p.value).toList(), [1, 2]);
  check('往返 #1 network', back[0].network.value, 1);
  check('往返 #2 包名/IP', [back[1].packageNames.toList(), back[1].ipCidrs.toList()], [
    ['com.example.app'],
    ['10.0.0.0/8'],
  ]);

  // 往返后再正向转换 = 幂等（第二次转换结果与第一次逐字节等价）
  final jsonAgain = routeRuleToCoreJson(back);
  check('往返幂等', jsonEncode(_canon(jsonAgain)), jsonEncode(_canon(jsonForm)));

  // ── 7. 坏输入防御：coreJsonToRules 不炸 ──────────────────────────────────
  check('非 rules 键 → 空', coreJsonToRules({'nope': 1}), <Rule>[]);
  check('rules 非数组 → 空', coreJsonToRules({'rules': 'x'}), <Rule>[]);
  check('条目非 Map 跳过', coreJsonToRules({'rules': ['bad', {'name': 'ok'}]}).length, 1);
  check('未知枚举数字忽略', coreJsonToRules({'rules': [{'outbound': 99, 'name': 'k'}]})[0].hasOutbound(), false);

  // ── 8. 与 Go 测试 fixture 的契约互验：route_rules_test.go 的 payload 能被读回 ──
  // （同一形状反向证明：我们的输出在 Go json.Unmarshal 下会还原出等价规则——
  //   Go 侧测试钉 unmarshal，这里钉 Dart 序列化，两端夹住契约。）
  final goFixtureShape = {
    'rules': [
      {'list_order': 1, 'enabled': true, 'name': 'cn-direct', 'outbound': 1, 'rule_sets': ['https://x/cn.srs'], 'domain_suffixes': ['example.cn']},
      {'list_order': 2, 'enabled': true, 'name': 'block-ads', 'outbound': 3, 'domains': ['ads.example.com'], 'protocols': [1, 2], 'network': 2, 'port_ranges': ['1000-2000']},
    ],
  };
  final fromGo = coreJsonToRules(goFixtureShape);
  check('Go fixture 读回 #1', [fromGo[0].name, fromGo[0].outbound.value, fromGo[0].ruleSets.toList()], ['cn-direct', 1, ['https://x/cn.srs']]);
  check('Go fixture 读回 #2', [fromGo[1].name, fromGo[1].outbound.value, fromGo[1].network.value], ['block-ads', 3, 2]);

  // ── 9. 批次 14 后半新字段：outbound_tag（19）+ config（20）────────────────
  // 只发显式赋值字段；字符串直通 Go json tag（outbound_tag/config）。
  final tagged = routeRuleToCoreJson([
    rule(name: 'to-node', outbound: Outbound.direct),
  ])['rules'][0] as Map;
  check('未选节点不发 outbound_tag', tagged.containsKey('outbound_tag'), false);
  check('无覆写不发 config', tagged.containsKey('config'), false);

  final r = Rule();
  r.name = 'tagged';
  r.enabled = true;
  r.outbound = Outbound.direct;
  r.outboundTag = 'my-node';
  r.config = '{"domain_suffix":["x.example.org"]}';
  final taggedJson = routeRuleToCoreJson([r])['rules'][0] as Map;
  check('outbound_tag 直通', taggedJson['outbound_tag'], 'my-node');
  check('config 直通', taggedJson['config'], '{"domain_suffix":["x.example.org"]}');

  final taggedBack = coreJsonToRules(routeRuleToCoreJson([r]));
  check('outbound_tag 往返', taggedBack[0].outboundTag, 'my-node');
  check('config 往返', taggedBack[0].config, '{"domain_suffix":["x.example.org"]}');

  print(failures());
}

String failures() => _failed == 0 ? '\nALL PASS ($_passed checks)' : '\n$_failed FAILED / $_passed passed';
