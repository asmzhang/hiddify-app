import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';

/// config 类型实体（批次 11，NekoBox `ConfigBean` 的对应物）组装测试。
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
}
