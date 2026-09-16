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

  print('\n组装摘要: $r');
  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
}
