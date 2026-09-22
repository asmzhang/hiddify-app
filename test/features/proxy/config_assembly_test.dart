import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';

/// config 类型实体（批次 11，NekoBox `ConfigBean` 的对应物）组装测试。
///
/// 另覆盖（审计 D 2026-09-23 补齐——detour 方向曾是内核级验证才抓出的 bug）：
/// - chain 展开（批次 10，NekoBox `fmt/ConfigBuilder.kt:86-124, 248-459`）：
///   递归展平/防环/`§hide§` tag/detour 方向/重复成员 #N/覆写合并；
/// - endpoints 两桶（批次 9，内核 `builder.go:220-257`）：段新建/覆盖/追加/
///   stale 删除/legacy wireguard outbound 剔除（K1）。
///
/// 规格来源是 **NekoBox**（以它为准）：
/// - `proxy/config/ConfigBean.java`：`type=0`（完整配置替代）与 `type=1`（仅出站）
///   双形态；`displayType()` 按 `json.has("type")` 区分展示；
/// - `fmt/ConfigBuilder.kt:66-78`：type=0 在 `buildConfig` 顶端直接返回 `bean.config`
///   作为 ConfigBuildResult（旁路全部拼装）；
/// - `fmt/ConfigBuilder.kt:339`：type=1 走 `CustomSingBoxOption(bean.config)`
///   当普通出站参与拼装；`:402` `_hack_config_map["tag"] = tagOut` 构建期注入 tag。
void main() {
  const baseline = '''
{
  "log": {"level": "info"},
  "outbounds": [
    {"type": "selector", "tag": "select", "outbounds": []},
    {"type": "vmess", "tag": "sub-node", "server": "1.2.3.4", "server_port": 443}
  ]
}
''';

  Map<String, dynamic> decode(String json) => jsonDecode(json) as Map<String, dynamic>;

  group('isConfigOutboundPayload（形态判据）', () {
    test('顶层有 type 键的 JSON 对象 = outbound 形态', () {
      expect(isConfigOutboundPayload('{"type":"vmess","server":"1.2.3.4"}'), isTrue);
    });

    test('顶层无 type 键 = full 形态（false）', () {
      expect(isConfigOutboundPayload('{"log":{"level":"info"},"outbounds":[]}'), isFalse);
      expect(isConfigOutboundPayload('{"server":"1.2.3.4"}'), isFalse);
    });

    test('type 不是字符串 = false（full）', () {
      expect(isConfigOutboundPayload('{"type":123}'), isFalse);
    });

    test('非 JSON 对象（数组/标量）= false', () {
      expect(isConfigOutboundPayload('[1,2,3]'), isFalse);
      expect(isConfigOutboundPayload('"vmess"'), isFalse);
    });

    test('坏 JSON = false', () {
      expect(isConfigOutboundPayload('{oops'), isFalse);
      expect(isConfigOutboundPayload(''), isFalse);
    });
  });

  group('assembleConfigEntityConfig（full 形态旁路）', () {
    test('恰好一个 full 实体 ⇒ payload 就是启动配置本体', () {
      const fullConfig = '{"log":{"level":"warn"},"outbounds":[{"type":"direct","tag":"direct"}]}';
      final result = assembleConfigEntityConfig([
        const ImportedProxyEntity(
          tag: 'my-config', type: kConfigEntityType, payload: fullConfig, displayName: 'my-config',
        ),
        const ImportedProxyEntity(
          tag: 'sub-node', type: 'vmess', payload: '{"type":"vmess","server":"1.2.3.4"}', displayName: 'sub-node',
        ),
      ]);
      expect(result, isNotNull);
      expect(decode(result!), decode(fullConfig));
    });

    test('零个 full 实体 ⇒ null（回落常规组装）', () {
      final result = assembleConfigEntityConfig([
        const ImportedProxyEntity(
          tag: 'sub-node', type: 'vmess', payload: '{"type":"vmess","server":"1.2.3.4"}', displayName: 'sub-node',
        ),
      ]);
      expect(result, isNull);
    });

    test('outbound 形态的 config 实体不算 full ⇒ null', () {
      final result = assembleConfigEntityConfig([
        const ImportedProxyEntity(
          tag: 'my-outbound', type: kConfigEntityType, payload: '{"type":"vmess","server":"1.2.3.4"}',
          displayName: 'my-outbound',
        ),
      ]);
      expect(result, isNull);
    });

    test('多个 full 实体 = 冲突 ⇒ null（绝不静默选一个）', () {
      final result = assembleConfigEntityConfig([
        const ImportedProxyEntity(
          tag: 'config-a', type: kConfigEntityType, payload: '{"log":{"level":"info"}}', displayName: 'config-a',
        ),
        const ImportedProxyEntity(
          tag: 'config-b', type: kConfigEntityType, payload: '{"log":{"level":"warn"}}', displayName: 'config-b',
        ),
      ]);
      expect(result, isNull);
    });

    test('full 实体 payload 不是 JSON 对象 ⇒ null', () {
      final result = assembleConfigEntityConfig([
        const ImportedProxyEntity(tag: 'bad', type: kConfigEntityType, payload: '[1,2]', displayName: 'bad'),
      ]);
      expect(result, isNull);
    });
  });

  group('applyEntitiesToOutbounds（outbound 形态进 outbounds 段）', () {
    test('outbound 形态 config 实体照普通节点替换基准同名出站，tag 构建期注入', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: baseline,
        entities: const [
          // 用户 JSON 故意写了错误的 tag —— 组装期必须以实体 tag 覆盖
          // （NekoBox `_hack_config_map["tag"] = tagOut` 语义）
          ImportedProxyEntity(
            tag: 'my-outbound', type: kConfigEntityType,
            payload: '{"type":"vmess","tag":"wrong","server":"9.9.9.9","server_port":1}', displayName: 'my-outbound',
          ),
        ],
      );
      expect(result, isNotNull);
      final outbounds = decode(result!.configJson)['outbounds'] as List<dynamic>;
      final mine = outbounds.whereType<Map<String, dynamic>>().where((o) => o['tag'] == 'my-outbound').toList();
      expect(mine, hasLength(1));
      expect(mine.single['type'], 'vmess');
      expect(mine.single['server'], '9.9.9.9');
    });

    test('基准里没有的 outbound 形态 config 实体照常追加（手动新建场景）', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: baseline,
        entities: const [
          ImportedProxyEntity(
            tag: 'fresh-outbound', type: kConfigEntityType,
            payload: '{"type":"socks","server":"127.0.0.1","server_port":1080}', displayName: 'fresh-outbound',
          ),
          // full 形态实体不进 outbounds 段（由 assembleConfigEntityConfig 单独处理）
          ImportedProxyEntity(tag: 'full-one', type: kConfigEntityType, payload: '{"log":{}}', displayName: 'full-one'),
        ],
      );
      expect(result, isNotNull);
      final outbounds = decode(result!.configJson)['outbounds'] as List<dynamic>;
      expect(outbounds.whereType<Map<String, dynamic>>().where((o) => o['tag'] == 'fresh-outbound'), hasLength(1));
      expect(outbounds.whereType<Map<String, dynamic>>().where((o) => o['tag'] == 'full-one'), isEmpty);
    });

    test('full 形态实体缺席时常规组装照常工作（出站节点不受影响）', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: baseline,
        entities: const [
          // 普通（非 config）节点的 payload 契约必带 tag —— `buildProtocolPayload`
          // 的种子就写 `'tag': tag`，订阅导入的 payload 来自完整出站定义同样带 tag。
          ImportedProxyEntity(
            tag: 'sub-node', type: 'vmess',
            payload: '{"type":"vmess","tag":"sub-node","server":"5.6.7.8","server_port":8443}',
            displayName: 'sub-node',
          ),
        ],
      );
      expect(result, isNotNull);
      final outbounds = decode(result!.configJson)['outbounds'] as List<dynamic>;
      final replaced = outbounds.whereType<Map<String, dynamic>>().where((o) => o['tag'] == 'sub-node').toList();
      expect(replaced, hasLength(1));
      expect(replaced.single['server'], '5.6.7.8');
    });
  });

  group('buildChainOutbounds（chain 展开，批次 10）', () {
    // 两跳链成员：入口 entry（UI 第一行）→ 落地 landing（UI 第二行）
    const entry = ImportedProxyEntity(
      tag: 'entry', type: 'vmess', payload: '{"type":"vmess","tag":"entry","server":"1.1.1.1","server_port":1}',
      displayName: 'entry',
    );
    const landing = ImportedProxyEntity(
      tag: 'landing', type: 'trojan', payload: '{"type":"trojan","tag":"landing","server":"2.2.2.2","server_port":2}',
      displayName: 'landing',
    );
    ImportedProxyEntity chain(String tag, List<String> proxies) => ImportedProxyEntity(
          tag: tag,
          type: kChainEntityType,
          payload: jsonEncode({'proxies': proxies}),
          displayName: tag,
        );

    test('两跳链：落地穿过入口侧成员，UI 首行入口无 detour 直连', () {
      final built = buildChainOutbounds(
        chainEntity: chain('my-chain', ['entry', 'landing']),
        entityByTag: {'entry': entry, 'landing': landing, 'my-chain': chain('my-chain', [])},
      );
      expect(built, isNotNull);
      // UI 序 [entry, landing] → build 序 [landing, entry]（落地在 build index 0）
      expect(built!.landingOutbound['tag'], 'chain:my-chain');
      expect(built.landingOutbound['type'], 'trojan');
      // 落地穿过更靠入口的成员（NekoBox ConfigBuilder.kt:311 靠落地侧穿过靠入口侧）
      expect(built.landingOutbound['detour'], 'c-my-chain-entry§hide§');
      // 成员（入口 = UI 首行）：§hide§ tag + 无 detour 直连
      expect(built.memberOutbounds, hasLength(1));
      final member = built.memberOutbounds.single;
      expect(member['tag'], 'c-my-chain-entry§hide§');
      expect(member['detour'], isNull);
      expect(member['type'], 'vmess');
      // 成员 payload 深拷贝：实体 payload 的原 tag 保留在定义里无关紧要，outbound['tag'] 已换
      expect(member['server'], '1.1.1.1');
    });

    test('detour 方向（v1 曾接反的 bug 锚点）：落地侧穿过入口侧，UI 首行直连', () {
      // 三跳：a → b → c（UI 序），流量 client→a→b→c→目标。build 序 = c,b,a。
      const a = ImportedProxyEntity(tag: 'a', type: 'vmess', payload: '{"type":"vmess","tag":"a","server":"a","server_port":1}', displayName: 'a');
      const b = ImportedProxyEntity(tag: 'b', type: 'vmess', payload: '{"type":"vmess","tag":"b","server":"b","server_port":1}', displayName: 'b');
      const c = ImportedProxyEntity(tag: 'c', type: 'trojan', payload: '{"type":"trojan","tag":"c","server":"c","server_port":1}', displayName: 'c');
      final built = buildChainOutbounds(
        chainEntity: chain('t', ['a', 'b', 'c']),
        entityByTag: {'a': a, 'b': b, 'c': c},
      );
      expect(built, isNotNull);
      // 拨号链（sing-box DialerOptions：本出站穿过 detour 指向的出站）：
      // c(落地) 穿过 b，b 穿过 a，a(入口/UI 首行) 直连 ⇒ 流量 a→b→c。
      final byTag = {for (final o in built!.memberOutbounds) o['tag'] as String: o};
      expect(byTag['c-t-b§hide§']!['detour'], 'c-t-a§hide§');
      expect(byTag['c-t-a§hide§']!['detour'], isNull);
      expect(built.landingOutbound['tag'], 'chain:t');
      expect(built.landingOutbound['detour'], 'c-t-b§hide§');
    });

    test('嵌套 chain 递归展平（成员引用另一条 chain）', () {
      const inner = ImportedProxyEntity(tag: 'x', type: 'vmess', payload: '{"type":"vmess","tag":"x","server":"x","server_port":1}', displayName: 'x');
      const y = ImportedProxyEntity(tag: 'y', type: 'trojan', payload: '{"type":"trojan","tag":"y","server":"y","server_port":1}', displayName: 'y');
      final innerChain = chain('inner', ['x', 'y']);
      final built = buildChainOutbounds(
        chainEntity: chain('outer', ['inner', 'y']), // outer = 经 inner 链再到 y
        entityByTag: {'x': inner, 'y': y, 'inner': innerChain},
      );
      expect(built, isNotNull);
      // 展平后 UI 序 [x, y, y]（inner 的落地 y 成为中间跳），落地 = outer 直引的 y
      expect(built!.landingOutbound['tag'], 'chain:outer');
      expect(built.landingOutbound['type'], 'trojan');
      // memberOutbounds 按 build 序（落地最前）排列：y 在 x 前
      final memberTags = built.memberOutbounds.map((o) => o['tag']).toList();
      expect(memberTags, ['c-outer-y§hide§', 'c-outer-x§hide§']);
    });

    test('环引用 ⇒ null（整条跳过，宁缺毋炸）', () {
      final chainA = chain('a', ['b']); // a 引用 b
      final chainB = chain('b', ['a']); // b 引用 a —— 环
      const node = ImportedProxyEntity(tag: 'n', type: 'vmess', payload: '{"type":"vmess","tag":"n","server":"n","server_port":1}', displayName: 'n');
      final built = buildChainOutbounds(
        chainEntity: chainA,
        entityByTag: {'a': chainA, 'b': chainB, 'n': node},
      );
      expect(built, isNull);
    });

    test('自引用 ⇒ null', () {
      final selfChain = chain('self', ['self']);
      final built = buildChainOutbounds(
        chainEntity: selfChain,
        entityByTag: {'self': selfChain},
      );
      expect(built, isNull);
    });

    test('成员实体不存在（被删）⇒ null', () {
      final built = buildChainOutbounds(
        chainEntity: chain('ghost', ['entry', 'landing']),
        entityByTag: {'entry': entry}, // landing 缺席
      );
      expect(built, isNull);
    });

    test('endpoint 成员拒绝（wireguard 不能做跳点）', () {
      const wg = ImportedProxyEntity(
        tag: 'wg-node', type: 'wireguard',
        payload: '{"type":"wireguard","tag":"wg-node","server":"3.3.3.3","server_port":3}',
        displayName: 'wg-node',
      );
      final built = buildChainOutbounds(
        chainEntity: chain('with-wg', ['wg-node', 'landing']),
        entityByTag: {'wg-node': wg, 'landing': landing},
      );
      expect(built, isNull);
    });

    test('内置类型与组类型成员拒绝', () {
      const direct = ImportedProxyEntity(tag: 'direct', type: 'direct', payload: '{"type":"direct","tag":"direct"}', displayName: 'direct');
      const selector = ImportedProxyEntity(
        tag: 'some-group', type: 'selector',
        payload: '{"type":"selector","tag":"some-group","outbounds":[]}', displayName: 'some-group',
      );
      expect(
        buildChainOutbounds(chainEntity: chain('c1', ['direct', 'landing']), entityByTag: {'direct': direct, 'landing': landing}),
        isNull,
      );
      expect(
        buildChainOutbounds(chainEntity: chain('c2', ['some-group', 'landing']), entityByTag: {'some-group': selector, 'landing': landing}),
        isNull,
      );
    });

    test('full 形态 config 实体拒绝做跳点（outbound 形态可以）', () {
      const fullCfg = ImportedProxyEntity(tag: 'full', type: kConfigEntityType, payload: '{"log":{}}', displayName: 'full');
      const outCfg = ImportedProxyEntity(
        tag: 'out', type: kConfigEntityType,
        payload: '{"type":"socks","server":"9.9.9.9","server_port":9}', displayName: 'out',
      );
      expect(
        buildChainOutbounds(chainEntity: chain('c1', ['full', 'landing']), entityByTag: {'full': fullCfg, 'landing': landing}),
        isNull,
      );
      final built = buildChainOutbounds(
        chainEntity: chain('c2', ['out', 'landing']),
        entityByTag: {'out': outCfg, 'landing': landing},
      );
      expect(built, isNotNull);
      expect(built!.memberOutbounds.single['type'], 'socks');
    });

    test('同一成员出现两次 ⇒ 第二次加 #2 后缀（内核拒收重复 tag 的防撞）', () {
      // UI 序 [entry, entry, landing]：entry 两次都在中间跳位（若放在末位它就是
      // 落地，落地 tag 固定 `chain:<tag>` 不带 c- 前缀，不构成重复成员）。
      final built = buildChainOutbounds(
        chainEntity: chain('dup', ['entry', 'entry', 'landing']),
        entityByTag: {'entry': entry, 'landing': landing},
      );
      expect(built, isNotNull);
      final memberTags = built!.memberOutbounds.map((o) => o['tag'] as String).toList();
      expect(memberTags.where((t) => t.startsWith('c-dup-entry§hide§')), hasLength(2));
      expect(memberTags.contains('c-dup-entry§hide§'), isTrue);
      expect(memberTags.contains('c-dup-entry§hide§#2'), isTrue);
      // 拨号链（落地穿过入口侧）：landing→#1，#1→#2，#2（UI 首行）直连
      final first = built.memberOutbounds.firstWhere((o) => o['tag'] == 'c-dup-entry§hide§');
      final second = built.memberOutbounds.firstWhere((o) => o['tag'] == 'c-dup-entry§hide§#2');
      expect(built.landingOutbound['detour'], 'c-dup-entry§hide§');
      expect(first['detour'], 'c-dup-entry§hide§#2');
      expect(second['detour'], isNull);
    });

    test('成员 customOutbound 覆写深合并进成员出站；chain 级覆写进落地', () {
      const entryWithOverlay = ImportedProxyEntity(
        tag: 'entry', type: 'vmess', payload: '{"type":"vmess","tag":"entry","server":"1.1.1.1","server_port":1}',
        displayName: 'entry', customOutbound: '{"mux":{"enabled":true}}',
      );
      final chainWithOverlay = ImportedProxyEntity(
        tag: 'ov', type: kChainEntityType, payload: jsonEncode({'proxies': ['entry', 'landing']}),
        displayName: 'ov', customOutbound: '{"tls":{"enabled":true}}',
      );
      final built = buildChainOutbounds(
        chainEntity: chainWithOverlay,
        entityByTag: {'entry': entryWithOverlay, 'landing': landing},
      );
      expect(built, isNotNull);
      expect(built!.memberOutbounds.single['mux'], {'enabled': true});
      expect(built.landingOutbound['tls'], {'enabled': true});
      expect(built.landingOutbound['server'], '2.2.2.2'); // 覆写只加键，不清 payload
    });

    test('空链 / 坏 proxies payload ⇒ null', () {
      expect(
        buildChainOutbounds(chainEntity: chain('empty', []), entityByTag: {'entry': entry}),
        isNull,
      );
      const badPayload = ImportedProxyEntity(tag: 'bad', type: kChainEntityType, payload: 'not json', displayName: 'bad');
      expect(
        buildChainOutbounds(chainEntity: badPayload, entityByTag: {'entry': entry}),
        isNull,
      );
    });
  });

  group('applyEntitiesToOutbounds（endpoints 两桶，批次 9）', () {
    const wgBaseline = '''
{
  "outbounds": [
    {"type": "selector", "tag": "select", "outbounds": []},
    {"type": "wireguard", "tag": "legacy-wg", "server": "7.7.7.7", "server_port": 7}
  ],
  "endpoints": [
    {"type": "wireguard", "tag": "wg-old", "address": "10.0.0.1/32"}
  ]
}
''';
    ImportedProxyEntity wgEntity(String tag, {String payload = '', String overlay = ''}) => ImportedProxyEntity(
          tag: tag,
          type: 'wireguard',
          payload: payload.isEmpty ? '{"type":"wireguard","tag":"$tag","address":"10.0.0.2/32"}' : payload,
          displayName: tag,
          customOutbound: overlay,
        );

    test('legacy wireguard outbound 从基准剔除（K1：留着必炸），endpoint 实体进 endpoints 段', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: wgBaseline,
        entities: [wgEntity('wg-new')],
      );
      expect(result, isNotNull);
      final config = decode(result!.configJson);
      final outbounds = config['outbounds'] as List<dynamic>;
      expect(outbounds.whereType<Map<String, dynamic>>().any((o) => o['type'] == 'wireguard'), isFalse);
      final endpoints = config['endpoints'] as List<dynamic>;
      final tags = endpoints.whereType<Map<String, dynamic>>().map((e) => e['tag']).toList();
      expect(tags, contains('wg-new'));
      expect(result.removed, 1); // legacy-wg 被剔除
      expect(result.added, 1); // wg-new 追加
    });

    test('endpoint 实体覆盖基准同名 endpoint，基准段原样保留其他成员', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: wgBaseline,
        entities: [wgEntity('wg-old', payload: '{"type":"wireguard","tag":"wg-old","address":"10.9.9.9/32"}')],
      );
      expect(result, isNotNull);
      final endpoints = decode(result!.configJson)['endpoints'] as List<dynamic>;
      final replaced = endpoints.whereType<Map<String, dynamic>>().where((e) => e['tag'] == 'wg-old').toList();
      expect(replaced, hasLength(1));
      expect(replaced.single['address'], '10.9.9.9/32');
      expect(result.replaced, 1);
    });

    test('stale 的 endpoint 实体从基准段删除（订阅更新下线 wg）', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: wgBaseline,
        entities: [wgEntity('wg-fresh')],
        staleTags: const ['wg-old'],
      );
      expect(result, isNotNull);
      final endpoints = decode(result!.configJson)['endpoints'] as List<dynamic>;
      expect(endpoints.whereType<Map<String, dynamic>>().map((e) => e['tag']), isNot(contains('wg-old')));
      expect(result.removed, 2); // legacy-wg + wg-old
    });

    test('endpoint 覆写（customOutbound）深合并进 endpoint 定义', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: wgBaseline,
        entities: [wgEntity('wg-ov', overlay: '{"mtu":1380}')],
      );
      expect(result, isNotNull);
      final endpoints = decode(result!.configJson)['endpoints'] as List<dynamic>;
      final mine = endpoints.whereType<Map<String, dynamic>>().firstWhere((e) => e['tag'] == 'wg-ov');
      expect(mine['mtu'], 1380);
    });

    test('基准无 endpoints 段且无 endpoint 实体 ⇒ 不新建空段', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: baseline, // 无 endpoints 键
        entities: const [
          ImportedProxyEntity(
            tag: 'sub-node', type: 'vmess',
            payload: '{"type":"vmess","tag":"sub-node","server":"5.6.7.8","server_port":8443}', displayName: 'sub-node',
          ),
        ],
      );
      expect(result, isNotNull);
      expect(decode(result!.configJson).containsKey('endpoints'), isFalse);
    });

    test('endpoint 坏 payload 跳过不毁整份配置', () {
      final result = applyEntitiesToOutbounds(
        baselineConfigJson: wgBaseline,
        entities: [
          wgEntity('wg-bad', payload: '{oops'),
          wgEntity('wg-good'),
        ],
      );
      expect(result, isNotNull);
      final endpoints = decode(result!.configJson)['endpoints'] as List<dynamic>;
      final tags = endpoints.whereType<Map<String, dynamic>>().map((e) => e['tag']).toList();
      expect(tags, isNot(contains('wg-bad')));
      expect(tags, contains('wg-good'));
    });
  });
}
