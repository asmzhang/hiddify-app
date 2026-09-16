// 实体导入的**可执行校验**（不是单元测试框架 —— 同 check_offline_proxy_parser.dart 的理由：
// flutter test 需要 flutter_tester，在换机/CI 环境跑不起来，这层刻意做成纯 Dart）。
//
// 运行：dart run tool/check_entity_import.dart
//
// 这是 8.4（NekoBox 实体层）的第一步：**先证明"配置文本 → 分组 + 节点实体（含凭据）"可行**，
// 再动 drift schema。规格见 docs/design/nekobox-parity.md §8.6。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';

/// 仿内核 `Parse` 的产物结构：一个 selector 组 + 两个真节点 + 内部出站（隐藏）。
const sample = '''
{
  "outbounds": [
    {"type": "selector", "tag": "select", "outbounds": ["节点选择", "direct §hide§"], "default": "节点选择"},
    {"type": "urltest", "tag": "自动选择", "outbounds": ["HK-01", "JP-02"]},
    {"type": "anytls", "tag": "HK-01", "server": "hk01.example.com", "server_port": 443,
     "password": "s3cret", "tls": {"server_name": "hk01.example.com", "utls": {"enabled": true, "fingerprint": "chrome"}}},
    {"type": "vless", "tag": "JP-02", "server": "jp02.example.com", "server_port": 443,
     "uuid": "a1b2c3d4-0000-1111-2222-333344445555", "flow": "xtls-rprx-vision"},
    {"type": "direct", "tag": "direct §hide§"}
  ]
}
''';

/// Dart 的 `==` 对 List/Map 是**同一性**比较，直接拿来比会恒为 false。
/// 统一按 JSON 规范化后比较（校验脚本的既有约定，见 skill `dart-pure-verification`）。
bool _sameValue(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List || b is List || a is Map || b is Map) {
    try {
      return jsonEncode(a) == jsonEncode(b);
    } catch (_) {
      return false;
    }
  }
  return a == b;
}

void main() {
  var failures = 0;

  void check(String label, Object? actual, Object? expected) {
    final ok = _sameValue(actual, expected);
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  final group = deriveProxyGroupFromConfig(profileName: '一分机场', configJson: sample);
  check('能派生出分组', group != null, true);
  check('分组名 = 订阅名', group!.name, '一分机场');
  check('分组类型 = 订阅派生', group.isSubscription, true);
  check('分组 isSelector', group.isSelector, true);

  // 1) 实体集合：只含真节点 —— 分组类出站、direct、隐藏 tag 都不算
  final tags = group.entities.map((e) => e.tag).toList();
  check('实体数（排除组/direct/隐藏）', group.entities.length, 2);
  check('含 HK-01', tags.contains('HK-01'), true);
  check('含 JP-02', tags.contains('JP-02'), true);
  check('不含 selector 组', tags.contains('select'), false);
  check('不含 urltest 组', tags.contains('自动选择'), false);
  check('不含 direct', tags.contains('direct §hide§'), false);

  // 2) 凭据完整落库（这是 8.4 的前提，也是 NekoBox 与本项目的根本差别）
  final hk = group.entities.firstWhere((e) => e.tag == 'HK-01');
  final hkPayload = jsonDecode(hk.payload) as Map<String, dynamic>;
  check('HK-01 type', hk.type, 'anytls');
  check('HK-01 密码保留', hkPayload['password'], 's3cret');
  check('HK-01 TLS 配置保留', (hkPayload['tls'] as Map)['server_name'], 'hk01.example.com');
  check('HK-01 uTLS 指纹保留', ((hkPayload['tls'] as Map)['utls'] as Map)['fingerprint'], 'chrome');
  check('HK-01 端口保留', hkPayload['server_port'], 443);

  final jp = group.entities.firstWhere((e) => e.tag == 'JP-02');
  final jpPayload = jsonDecode(jp.payload) as Map<String, dynamic>;
  check('JP-02 UUID 保留', jpPayload['uuid'], 'a1b2c3d4-0000-1111-2222-333344445555');
  check('JP-02 flow 保留', jpPayload['flow'], 'xtls-rprx-vision');

  // 3) payload 是**完整出站**（可原地拼回配置）
  check('payload 含 type 字段', hkPayload['type'], 'anytls');
  check('payload 含 tag 字段', hkPayload['tag'], 'HK-01');

  // 4) 显示名去 § 后缀规则
  check('displayName 去后缀', hk.displayName, 'HK-01');

  // 5) 边界：无节点 / 空 / 坏 JSON → null（不抛）
  check('只有组 → null', deriveProxyGroupFromConfig(profileName: 'x', configJson: '{"outbounds":[{"type":"selector","tag":"s","outbounds":[]}]}'), null);
  check('空 outbounds → null', deriveProxyGroupFromConfig(profileName: 'x', configJson: '{"outbounds":[]}'), null);
  check('无 outbounds → null', deriveProxyGroupFromConfig(profileName: 'x', configJson: '{}'), null);
  check('坏 JSON → null', deriveProxyGroupFromConfig(profileName: 'x', configJson: '{not json'), null);

  // 6) 订阅 ↔ 分组的反查键（存在 proxy_groups.subscription 里，不必动 schema）
  final payload = encodeSubscriptionPayload(
    profileId: 'e2d4f850',
    profileName: '一分机场',
    lastUpdate: DateTime.utc(2026, 9, 15),
  );
  check('payload 里的 profileId 可读回', profileIdOfSubscription(payload), 'e2d4f850');
  check('payload 保留最后更新时间', payload.contains('2026-09-15'), true);
  check('无 lastUpdate 也能编码', profileIdOfSubscription(encodeSubscriptionPayload(profileId: 'abc', profileName: 'x')), 'abc');
  check('null → null', profileIdOfSubscription(null), null);
  check('空串 → null', profileIdOfSubscription(''), null);
  check('坏 JSON → null', profileIdOfSubscription('{not json'), null);
  check('非对象 JSON → null', profileIdOfSubscription('[1,2,3]'), null);
  check('缺 profileId → null', profileIdOfSubscription('{"name":"x"}'), null);
  check('空 profileId → null', profileIdOfSubscription('{"profileId":""}'), null);
  check('profileId 非字符串 → null', profileIdOfSubscription('{"profileId":123}'), null);

  // 7) 回填判据：哪些订阅还缺实体（新表对既有数据的补齐，必须幂等且保序）
  check(
    '全部已有分组 → 无需回填',
    missingEntityProfileIds(allIds: ['a', 'b'], synced: {'a', 'b'}),
    <String>[],
  );
  check(
    '只挑缺的且保持入参顺序',
    missingEntityProfileIds(allIds: ['a', 'b', 'c', 'd'], synced: {'c'}),
    ['a', 'b', 'd'],
  );
  check('空集合 → 全部要补', missingEntityProfileIds(allIds: ['a'], synced: <String>{}), ['a']);
  check('无订阅 → 空', missingEntityProfileIds(allIds: [], synced: <String>{}), <String>[]);
  check('入参重复只产出一次', missingEntityProfileIds(allIds: ['a', 'a', 'b'], synced: <String>{}), ['a', 'b']);
  check('空 id 被忽略', missingEntityProfileIds(allIds: ['', 'a'], synced: <String>{}), ['a']);
  // 幂等：把上一轮的结果写进「已有分组」后，再问一次必须是空
  final firstPass = missingEntityProfileIds(allIds: ['a', 'b', 'c'], synced: <String>{});
  check('回填后再问一次 → 空（幂等）', missingEntityProfileIds(allIds: ['a', 'b', 'c'], synced: firstPass.toSet()), <String>[]);
  // 多出来的 synced（库里存在已删除订阅的分组）不该影响结果
  check('多余的 synced 被忽略', missingEntityProfileIds(allIds: ['a'], synced: {'zzz'}), ['a']);

  print('\n实体摘要：');
  for (final e in group.entities) {
    print('  · ${e.type.padRight(10)} ${e.tag}');
  }
  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
}
