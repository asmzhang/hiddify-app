// 应用侧**出站表组装**的可执行校验（同 check_entity_import.dart 的理由：纯 Dart + dart run，
// 不依赖 flutter_tester）。
//
// 运行：dart run tool/check_config_assembly.dart
//
// ---------------------------------------------------------------------------
// fixture 的形态照**真机**取，但要把两份文件分清楚（这是早先搞错的地方）：
//
//   · `configs/<id>.json`（应用写下、内核读作输入）—— **只有 `{"outbounds":[…]}`**，
//     里面是订阅自带的组 + 节点。本模块的基准就是它。
//   · `data/current-config.json`（内核真正在跑的）—— 组是内核重建的固定常量
//     `select` / `balance` / `lowest`，`route.final = "select"`，另有 inbounds/dns/route/log。
//     这些**不由本模块产出**，所以本 fixture 里不放 log/dns/inbounds/route。
//
// 因而本脚本要证明的核心是：**只动节点，组与其它出站一律原样透传**（内核自己会重建组）。
// ---------------------------------------------------------------------------
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';

const baseline = '''
{
  "outbounds": [
    {"type": "selector", "tag": "冲上云霄", "outbounds": ["自动选择", "direct", "HK-01", "JP-02"], "default": "自动选择"},
    {"type": "urltest", "tag": "自动选择", "outbounds": ["HK-01", "JP-02"], "url": "http://cp.cloudflare.com/", "interval": "10m"},
    {"type": "direct", "tag": "direct §hide§"},
    {"type": "anytls", "tag": "HK-01", "server": "old-hk.example.com", "server_port": 443, "password": "old"},
    {"type": "vless", "tag": "JP-02", "server": "jp02.example.com", "server_port": 443, "uuid": "u2"},
    {"type": "vless", "tag": "GONE-03", "server": "gone.example.com", "server_port": 443, "uuid": "u3"}
  ]
}
''';

ImportedProxyEntity _entity(String tag, String type, Map<String, dynamic> payload) => ImportedProxyEntity(
  tag: tag,
  type: type,
  payload: jsonEncode({'type': type, 'tag': tag, ...payload}),
  displayName: tag,
);

/// 递归排序 Map 的键 —— 只用于**比较**（canonical 形式）。
Object? _canon(Object? node) {
  if (node is Map) {
    final keys = node.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in keys) k: _canon(node[k])};
  }
  if (node is List) return [for (final item in node) _canon(item)];
  return node;
}

void main() {
  var failures = 0;

  // List/Map 在 Dart 里 == 是同一性比较，必须按值比
  bool eq(Object? a, Object? b) {
    if (a is List || a is Map || b is List || b is Map) return jsonEncode(a) == jsonEncode(b);
    return a == b;
  }

  void check(String label, Object? actual, Object? expected) {
    final ok = eq(actual, expected);
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  final entities = [
    _entity('HK-01', 'anytls', {'server': 'new-hk.example.com', 'server_port': 8443, 'password': 'new-pw'}),
    _entity('JP-02', 'vless', {'server': 'jp02.example.com', 'server_port': 443, 'uuid': 'u2'}),
    _entity('US-04', 'vless', {'server': 'us04.example.com', 'server_port': 443, 'uuid': 'u4'}),
  ];

  final r = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: entities,
    staleTags: const ['GONE-03'],
  );
  check('组装成功', r != null, true);
  final assembled = jsonDecode(r!.configJson) as Map<String, dynamic>;
  final outbounds = (assembled['outbounds'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> byTag(String t) => outbounds.firstWhere((o) => o['tag'] == t);
  bool hasTag(String t) => outbounds.any((o) => o['tag'] == t);

  check('覆盖计数（HK-01、JP-02）', r.replaced, 2);
  check('新增计数（US-04）', r.added, 1);
  check('删除计数（GONE-03）', r.removed, 1);

  // 1) 编辑生效：完整出站定义被实体覆盖（含凭据）
  check('HK-01 地址已改', byTag('HK-01')['server'], 'new-hk.example.com');
  check('HK-01 端口已改', byTag('HK-01')['server_port'], 8443);
  check('HK-01 密码已改', byTag('HK-01')['password'], 'new-pw');
  check('HK-01 未丢失 type/tag', [byTag('HK-01')['type'], byTag('HK-01')['tag']], ['anytls', 'HK-01']);

  // 2) 新增生效且带凭据
  check('US-04 已追加', byTag('US-04')['server'], 'us04.example.com');
  check('US-04 UUID 保留', byTag('US-04')['uuid'], 'u4');

  // 3) 删除只按 staleTags 执行
  check('GONE-03 已按 staleTags 移除', hasTag('GONE-03'), false);
  final kept = applyEntitiesToOutbounds(baselineConfigJson: baseline, entities: entities)!;
  final keptOutbounds = (jsonDecode(kept.configJson) as Map<String, dynamic>)['outbounds'] as List;
  check('不传 staleTags → 不删任何东西', keptOutbounds.whereType<Map>().any((o) => o['tag'] == 'GONE-03'), true);

  // 4) **组一律原样透传** —— 内核 setOutbounds 会丢弃输入里的组并自建 select/balance/lowest，
  //    所以应用既不该重建成员、也不该改 default（早先那套是错的，基于订阅原文而非真正启动的文件）
  check('selector 组保留', hasTag('冲上云霄'), true);
  check('selector 成员未被改写', byTag('冲上云霄')['outbounds'], ['自动选择', 'direct', 'HK-01', 'JP-02']);
  check('selector.default 未被改写', byTag('冲上云霄')['default'], '自动选择');
  check('urltest 组保留', hasTag('自动选择'), true);
  check('urltest 成员未被改写', byTag('自动选择')['outbounds'], ['HK-01', 'JP-02']);
  check('urltest 的 url/interval 未动', [byTag('自动选择')['url'], byTag('自动选择')['interval']], ['http://cp.cloudflare.com/', '10m']);

  // 5) 非节点出站原样透传（内核的 §hide§ 内部出站同理）
  check('direct §hide§ 保留', hasTag('direct §hide§'), true);

  // 6) 顺序：覆盖不改变位次，新实体追加在末尾
  check(
    '出站次序',
    outbounds.map((o) => o['tag']).toList(),
    ['冲上云霄', '自动选择', 'direct §hide§', 'HK-01', 'JP-02', 'US-04'],
  );

  // 7) 顶层其它键一并保留（基准若带额外键，不该在组装中丢失）
  final withExtra = jsonDecode(
    applyEntitiesToOutbounds(
      baselineConfigJson: '{"outbounds":[{"type":"direct","tag":"d"},{"type":"vless","tag":"N1","server":"s"}],"someKey":{"a":1}}',
      entities: [_entity('N1', 'vless', {'server': 's2'})],
    )!.configJson,
  ) as Map<String, dynamic>;
  check('顶层额外键保留', withExtra['someKey'], {'a': 1});

  // 8) 边界：坏输入 / 空实体 → null（调用方回落基准文件）
  check('空实体 → null', applyEntitiesToOutbounds(baselineConfigJson: baseline, entities: const []), null);
  check('坏 JSON → null', applyEntitiesToOutbounds(baselineConfigJson: '{not json', entities: entities), null);
  check('顶层非对象 → null', applyEntitiesToOutbounds(baselineConfigJson: '[1,2]', entities: entities), null);
  check('无 outbounds → null', applyEntitiesToOutbounds(baselineConfigJson: '{}', entities: entities), null);
  check('outbounds 为空 → null', applyEntitiesToOutbounds(baselineConfigJson: '{"outbounds":[]}', entities: entities), null);
  check(
    '单条坏 payload 被跳过、其余仍可用',
    applyEntitiesToOutbounds(
          baselineConfigJson: baseline,
          entities: [
            const ImportedProxyEntity(tag: 'BAD', type: 'anytls', payload: '{broken', displayName: 'BAD'),
            _entity('HK-01', 'anytls', {'server': 'x.example.com', 'server_port': 443, 'password': 'p'}),
          ],
        ) !=
        null,
    true,
  );
  check(
    '全部 payload 都坏 → null',
    applyEntitiesToOutbounds(
      baselineConfigJson: baseline,
      entities: const [ImportedProxyEntity(tag: 'BAD', type: 'anytls', payload: '{broken', displayName: 'BAD')],
    ),
    null,
  );

  // 9) staleNodeTags —— 组装时"该点名移除"的集合（审计 F1 的修复点）
  //
  //    为什么单列断言：这正是"删了没反应"的根因所在。基准是订阅原文的快照，
  //    用户删掉的节点仍留在里面；不点名移除就会被原样透传 ⇒ 界面 47、内核 48。
  List<String> sorted(Iterable<String> s) => s.toList()..sort();
  check(
    'stale = 基准里已消失的节点',
    sorted(staleNodeTags(baselineConfigJson: baseline, entityTags: const ['HK-01', 'JP-02', 'US-04'])),
    ['GONE-03'],
  );
  check(
    '实体齐全 ⇒ 无 stale',
    sorted(staleNodeTags(baselineConfigJson: baseline, entityTags: const ['HK-01', 'JP-02', 'GONE-03'])),
    <String>[],
  );
  check(
    '组与 direct §hide§ 永远不算节点',
    sorted(staleNodeTags(baselineConfigJson: baseline, entityTags: const [])),
    ['GONE-03', 'HK-01', 'JP-02'],
  );
  // 🔒 WARP：形状像节点（既不是组也不带 §hide§），但属于内核 —— 必须挡住
  const baselineWithWarp =
      '{"outbounds":[{"type":"selector","tag":"select","outbounds":["N1"]}, '
      '{"type":"wireguard","tag":"🔒 WARP","server":"engage.cloudflareclient.com","server_port":2408}, '
      '{"type":"vless","tag":"N1","server":"s"}]}';
  check(
    '🔒 WARP 不进 stale（内核的出站永不删）',
    sorted(staleNodeTags(baselineConfigJson: baselineWithWarp, entityTags: const ['N1'])),
    <String>[],
  );
  check(
    'stale 对坏 JSON 返回空集合（宁可少删不误删）',
    sorted(staleNodeTags(baselineConfigJson: '{oops', entityTags: const [])),
    <String>[],
  );

  // ── 10. 批次 9：endpoints 段（wireguard endpoint）─────────────────────────
  // 内核 1.13 起 wireguard outbound 是 stub（include/registry.go:200-201），
  // endpoint 是唯一合法形态；实体按 isNodeEndpoint 拆桶进 config['endpoints']。
  final wgEndpoint = <String, dynamic>{
    'type': 'wireguard',
    'tag': 'WG-01',
    'address': ['172.16.0.2/32'],
    'private_key': 'KEY=',
    'mtu': 1420,
    'peers': [
      {'address': 'a.example.com', 'port': 51820, 'public_key': 'PUB='},
    ],
  };
  ImportedProxyEntity wgEntity(String tag, Map<String, dynamic> payload) => ImportedProxyEntity(
    tag: tag,
    type: 'wireguard',
    payload: jsonEncode(payload),
    displayName: tag,
  );

  // 混合基准：legacy wireguard outbound（必炸形态）+ 已有 endpoint + 普通节点
  const baselineWithEndpoints =
      '{"outbounds":[{"type":"selector","tag":"select","outbounds":["N1","WG-OLD"]},'
      '{"type":"wireguard","tag":"WG-LEGACY","server":"old.example.com","server_port":51820,"private_key":"k"},'
      '{"type":"vless","tag":"N1","server":"s"}],'
      '"endpoints":[{"type":"wireguard","tag":"WG-OLD","address":["10.0.0.2/32"],"private_key":"k","peers":[{"address":"old.example.com","port":51820}]}]}';

  final r9 = applyEntitiesToOutbounds(
    baselineConfigJson: baselineWithEndpoints,
    entities: [
      ...entities,
      wgEntity('WG-OLD', {...wgEndpoint, 'tag': 'WG-OLD', 'peers': [
        {'address': 'updated.example.com', 'port': 1234, 'public_key': 'PUB='},
      ]}),
      wgEntity('WG-01', wgEndpoint),
    ],
    staleTags: staleNodeTags(baselineConfigJson: baselineWithEndpoints, entityTags: const ['HK-01', 'JP-02', 'US-04', 'WG-OLD', 'WG-01']),
  );
  check('endpoints · 组装成功', r9 != null, true);
  final a9 = jsonDecode(r9!.configJson) as Map<String, dynamic>;
  final out9 = (a9['outbounds'] as List).cast<Map<String, dynamic>>();
  final eps9 = (a9['endpoints'] as List).cast<Map<String, dynamic>>();

  // legacy wireguard outbound 被剔除（内核 stub 启动即报错，留着整份配置连不上）
  check('endpoints · legacy wireguard outbound 被剔除', out9.any((o) => o['tag'] == 'WG-LEGACY'), false);
  // removed = WG-LEGACY（legacy 剔除）+ N1（该基准里唯一的节点，不在实体集合、被 stale 点名）
  check('endpoints · 剔除计入 removed', r9.removed, 2);

  // endpoint 实体进 endpoints 段：覆盖同名 + 追加新 tag
  check('endpoints · 段数量', eps9.length, 2);
  final wgOld = eps9.firstWhere((e) => e['tag'] == 'WG-OLD');
  final wgOldPeer0 = (wgOld['peers'] as List).first as Map<String, dynamic>;
  check('endpoints · 同名 endpoint 被实体覆盖', wgOldPeer0['address'], 'updated.example.com');
  final wg01 = eps9.firstWhere((e) => e['tag'] == 'WG-01');
  final wg01Peer0 = (wg01['peers'] as List).first as Map<String, dynamic>;
  check('endpoints · 新 endpoint 追加', wg01Peer0['address'], 'a.example.com');
  // replaced = WG-OLD（endpoint 覆盖）；HK-01/JP-02 不在这个基准里 ⇒ 是追加不是覆盖
  check('endpoints · 覆盖计入 replaced', r9.replaced, 1);
  // added = HK-01/JP-02/US-04（基准里没有）+ WG-01（endpoint 追加）
  check('endpoints · 追加计入 added', r9.added, 4);

  // 组引用 endpoint tag：内核原生支持（builder 收 endpoint tag 进成员），
  // 组本身照旧透传 —— 输入里的成员含 WG-OLD 不被改写
  check('endpoints · 组透传不受影响', (out9.firstWhere((o) => o['tag'] == 'select')['outbounds'] as List).contains('WG-OLD'), true);

  // staleNodeTags 对 endpoints 段：N1（普通节点，实体集合没有）与 WG-OLD（endpoint，
  // 实体集合没有）都进 stale；WG-LEGACY 是 legacy outbound（isNodeOutbound 已排除 wg）
  check(
    'endpoints · staleNodeTags 覆盖 endpoints 段',
    sorted(staleNodeTags(baselineConfigJson: baselineWithEndpoints, entityTags: const ['HK-01', 'JP-02', 'WG-01'])),
    ['N1', 'WG-OLD'],
  );

  // 基准无 endpoints 段 + 有 endpoint 实体 ⇒ 新建 endpoints 数组
  final r10 = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [...entities, wgEntity('WG-01', wgEndpoint)],
    staleTags: const ['GONE-03'],
  );
  final a10 = jsonDecode(r10!.configJson) as Map<String, dynamic>;
  check('endpoints · 基准无段 ⇒ 新建数组', (a10['endpoints'] as List).length, 1);

  // 无 endpoint 实体 + 基准也无 endpoints 段 ⇒ 输出里不凭空造段
  final r11 = applyEntitiesToOutbounds(baselineConfigJson: baseline, entities: entities, staleTags: const ['GONE-03']);
  check('endpoints · 无实体无段 ⇒ 不造段', (jsonDecode(r11!.configJson) as Map<String, dynamic>).containsKey('endpoints'), false);

  // 只有 endpoint 实体、无普通节点实体 ⇒ 也能组装（原来 payloadByTag.isEmpty 直接 return null）
  final r12 = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [wgEntity('WG-01', wgEndpoint)],
  );
  check('endpoints · 纯 endpoint 实体也能组装', r12 != null, true);
  check(
    'endpoints · 纯 endpoint 组装的段',
    jsonEncode(_canon((jsonDecode(r12!.configJson) as Map<String, dynamic>)['endpoints'] as List)),
    jsonEncode(_canon([jsonDecode(jsonEncode(wgEndpoint))])),
  );

  // 基准 endpoints 段里的 endpoint、实体集合没有 + stale 点名 ⇒ 从段里删
  final r13 = applyEntitiesToOutbounds(
    baselineConfigJson: baselineWithEndpoints,
    entities: [...entities], // 无 endpoint 实体
    staleTags: staleNodeTags(baselineConfigJson: baselineWithEndpoints, entityTags: const ['HK-01', 'JP-02', 'US-04']),
  );
  final a13 = jsonDecode(r13!.configJson) as Map<String, dynamic>;
  check('endpoints · stale 点名 ⇒ 段里的 endpoint 删除', (a13['endpoints'] as List).isEmpty, true);

  // ── 批次 8.5：节点级出站覆写（customOutbound 深合并）────────────────────
  // 规格：NekoBox ConfigBuilder.kt:404（bean.customOutboundJson → 出站序列化合并）
  ImportedProxyEntity wgEntityWithOverlay(String tag, Map<String, dynamic> payload, String overlay) => ImportedProxyEntity(
    tag: tag,
    type: 'wireguard',
    payload: jsonEncode(payload),
    displayName: tag,
    customOutbound: overlay,
  );

  // 覆盖路：基准里同名节点被实体 payload 替换后，覆写深合并进去
  final overlayPayload = <String, dynamic>{
    'type': 'vless',
    'tag': 'HK-01',
    'server': 's.example.com',
    'server_port': 443,
    'tls': {'enabled': true},
  };
  final entityOverlay = ImportedProxyEntity(
    tag: 'HK-01',
    type: 'vless',
    payload: jsonEncode(overlayPayload),
    displayName: 'HK-01',
    // ① 深合并进既有 tls Map（不整体替换）② mtu+ 是 List 追加策略的通道
    customOutbound: '{"tls":{"server_name":"override.example.com"},"multiplex":{"enabled":true},"mtu+":[1500]}',
  );
  final r14 = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [...entities.where((e) => e.tag != 'HK-01'), entityOverlay],
    staleTags: const ['GONE-03'],
  );
  final out14 = ((jsonDecode(r14!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>();
  final merged = out14.firstWhere((o) => o['tag'] == 'HK-01');
  check('覆写 · 深合并进既有子对象', ((merged['tls'] as Map)['enabled'], (merged['tls'] as Map)['server_name']), (true, 'override.example.com'));
  check('覆写 · 新键直通', ((merged['multiplex'] as Map)['enabled'], merged['server_port']), (true, 443));
  check('覆写 · key+ 追加策略', merged['mtu'], [1500]);
  // 无覆写的实体不受影响
  final untouched = out14.firstWhere((o) => o['tag'] == 'JP-02');
  check('覆写 · 无覆写实体零变化', jsonEncode(_canon(untouched)), jsonEncode(_canon(jsonDecode(entities[1].payload))));

  // 追加路：手动新建的节点（基准里没有）同样套用覆写
  final r15 = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [
      ...entities,
      wgEntityWithOverlay('WG-NEW', {...wgEndpoint, 'tag': 'WG-NEW', 'mtu': 1420}, '{"mtu":1408}'),
    ],
  );
  final eps15 = ((jsonDecode(r15!.configJson) as Map<String, dynamic>)['endpoints'] as List).cast<Map<String, dynamic>>();
  final wgNew = eps15.firstWhere((e) => e['tag'] == 'WG-NEW');
  check('覆写 · endpoint 追加路合并（覆写值胜）', wgNew['mtu'], 1408);

  // 坏覆写 JSON 按无覆写处理（不让节点失效），等价于空覆写
  final r16 = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [...entities, wgEntityWithOverlay('WG-BAD', {...wgEndpoint, 'tag': 'WG-BAD', 'mtu': 1420}, '{oops')],
  );
  final eps16 = ((jsonDecode(r16!.configJson) as Map<String, dynamic>)['endpoints'] as List).cast<Map<String, dynamic>>();
  check('覆写 · 坏 JSON 跳过（payload 原样）', eps16.firstWhere((e) => e['tag'] == 'WG-BAD')['mtu'], 1420);

  // ── 批次 10：chain 任意节点串联（设计 docs/design/chain-2026-09-20.md）──
  // 规格：NekoBox buildChain（ConfigBuilder.kt:248-459）的本项目映射：
  //   成员出站 `c-<chainTag>-<成员tag>§hide§`（detour 链），落地 `chain:<chainTag>`
  //   （无 §hide§ = select 组可见成员 = 选中入口）。
  ImportedProxyEntity chainEntity(String tag, List<String> proxies, {String overlay = ''}) => ImportedProxyEntity(
    tag: tag,
    type: kChainEntityType,
    payload: jsonEncode({'proxies': proxies}),
    displayName: tag,
    customOutbound: overlay,
  );

  // 三跳：UI 序 [JP-02, HK-01, US-04]（第一行入口、最后一行落地）
  final rChain = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [...entities, chainEntity('我的链', ['JP-02', 'HK-01', 'US-04'])],
    staleTags: const ['GONE-03'],
  );
  check('chain · 组装成功', rChain != null, true);
  final outChain = ((jsonDecode(rChain!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>();
  Map<String, dynamic> cByTag(String t) => outChain.firstWhere((o) => o['tag'] == t);

  // 落地出站存在、不带 §hide§、成员定义来自最后一个成员（US-04）
  check('chain · 落地 tag = chain:前缀', cByTag('chain:我的链')['tag'], 'chain:我的链');
  check('chain · 落地无 §hide§', 'chain:我的链'.contains('§hide§'), false);
  check('chain · 落地 = 最后成员的出站定义', cByTag('chain:我的链')['uuid'], 'u4');
  check('chain · 落地无 detour（链尾直出）', cByTag('chain:我的链').containsKey('detour'), false);

  // 中间跳出站：带 §hide§、detour 链指向 build 序上一条（= UI 序的上一行）
  final entry = cByTag('c-我的链-JP-02§hide§'); // UI 第一行 = 入口
  final middle = cByTag('c-我的链-HK-01§hide§');
  check('chain · 入口 detour → 下一跳', entry['detour'], 'c-我的链-HK-01§hide§');
  check('chain · 中间跳 detour → 落地', middle['detour'], 'chain:我的链');
  check('chain · 中间跳 type 来自成员', [entry['type'], middle['type']], ['vless', 'anytls']);
  check('chain · 成员出站定义正确（HK-01 凭据）', middle['server'], 'new-hk.example.com');

  // NekoBox 语义：成员既有独立出站（可单独选中），又有链上副本（tag 不同不冲突）
  check(
    'chain · 成员独立出站保留（NekoBox 全量建链语义）',
    outChain.where((o) => o['tag'] == 'HK-01' || o['tag'] == 'JP-02' || o['tag'] == 'US-04').length,
    3,
  );

  // 循环引用：chain 引用自己 ⇒ 整条跳过，不炸组装
  final rCycle = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [...entities, chainEntity('环链', ['环链', 'HK-01'])],
  );
  check('chain · 自引用整条跳过（组装不失败）', rCycle != null, true);
  final outCycle = ((jsonDecode(rCycle!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>();
  check('chain · 自引用无落地出站', outCycle.any((o) => o['tag'] == 'chain:环链'), false);
  // 间接环：A → B → A
  final rCycle2 = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [...entities, chainEntity('环A', ['环B', 'HK-01']), chainEntity('环B', ['环A', 'US-04'])],
  );
  final outCycle2 = ((jsonDecode(rCycle2!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>();
  check('chain · 间接环两条都跳过', outCycle2.any((o) => o['tag'] == 'chain:环A' || o['tag'] == 'chain:环B'), false);

  // 嵌套 chain 递归展开（NekoBox resolveChainInternal）：
  // 内链 = [N1]；外链 = [内链, N1] ⇒ 展平 [N1, N1] = 两跳（N1→N1）
  final rNested = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [
      _entity('N1', 'vless', {'server': 'n1.example.com', 'server_port': 443, 'uuid': 'n1'}),
      chainEntity('内链', ['N1']),
      chainEntity('外链', ['内链', 'N1']),
    ],
  );
  check('chain · 嵌套组装成功', rNested != null, true);
  final outNested = ((jsonDecode(rNested!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>();
  final outer = outNested.firstWhere((o) => o['tag'] == 'chain:外链');
  final outerEntry = outNested.firstWhere((o) => o['tag'] == 'c-外链-N1§hide§');
  check('chain · 嵌套落地 = 内层最后成员', outer['uuid'], 'n1');
  check('chain · 嵌套入口 detour 链完整', outerEntry['detour'], 'chain:外链');
  // 展平 [N1, N1]：build 序 [落地, N1, N1] —— 靠前的跳是 UI 第二个 N1，靠后的是入口。
  // 两条成员出站 tag 相同（同名成员）—— 现实里成员去重由 UI 层负责（列表不收重复），
  // 组装层不去重（NekoBox 同样不去重，允许同节点在链上出现多次）。这里验证的
  // 是「嵌套展开发生了」：tag 集合里有 c-外链- 就算展开成功。
  final flatTags = outNested.map((o) => o['tag']).where((t) => (t as String).startsWith('c-外链-')).toList();
  check('chain · 嵌套展开发生（外链成员出站存在）', flatTags.isNotEmpty, true);

  // endpoint 成员被拒（内核 stub）；坏 payload 整条跳过
  final rRefused = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [
      wgEntity('WG-01', wgEndpoint),
      chainEntity('含端点', ['WG-01', 'HK-01']),
      chainEntity('坏定义', [' not-json']),
      chainEntity('空链', []),
    ],
  );
  check('chain · endpoint/坏定义/空链全跳过但组装不失败', rRefused != null, true);
  final outRefused = ((jsonDecode(rRefused!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>();
  check('chain · 被拒链无落地', outRefused.any((o) => (o['tag'] as String).startsWith('chain:')), false);
  check('chain · 普通成员未被殃及（wg endpoint 正常进段）', ((jsonDecode(rRefused.configJson) as Map<String, dynamic>)['endpoints'] as List).length, 1);

  // chain 级覆写合并进落地出站（记档差异：NekoBox 无此概念，本项目实体模型统一）
  final rChainOverlay = applyEntitiesToOutbounds(
    baselineConfigJson: baseline,
    entities: [
      ...entities.where((e) => e.tag == 'HK-01' || e.tag == 'US-04'),
      chainEntity('覆写链', ['HK-01', 'US-04'], overlay: '{"multiplex":{"enabled":true}}'),
    ],
  );
  final landingOverlay = ((jsonDecode(rChainOverlay!.configJson) as Map<String, dynamic>)['outbounds'] as List).cast<Map<String, dynamic>>().firstWhere((o) => o['tag'] == 'chain:覆写链');
  check('chain · 级覆写进落地出站', ((landingOverlay['multiplex'] as Map)['enabled'], landingOverlay['uuid']), (true, 'u4'));

  print('\n组装摘要: $r');
  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
}
