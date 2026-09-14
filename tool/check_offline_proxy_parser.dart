// 离线节点清单 / 出站抽取的**可执行校验**（不是单元测试框架，见下方原因）。
//
// 运行：dart run tool/check_offline_proxy_parser.dart
//
// 为什么不用 test/ + flutter_test：flutter test 需要 flutter_tester，在受限环境
// （本仓库的换机/CI 场景）跑不起来；而这一层刻意做成纯 Dart（见
// lib/features/proxy/data/offline_proxy_parser.dart 的说明），所以用 dart run 直接校验。
//
// 覆盖：分组解析、tag 与列表一致性、出站 JSON 抽取的命中/未命中/坏输入。
import 'dart:convert';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

const sample = '''
{
  "outbounds": [
    {"type": "selector", "tag": "select", "outbounds": ["HK-01", "JP-02"], "default": "HK-01"},
    {"type": "anytls", "tag": "HK-01", "server": "hk01.example.com", "server_port": 443, "password": "secret"},
    {"type": "vless", "tag": "JP-02", "server": "jp02.example.com", "server_port": 443, "uuid": "a1b2"},
    {"type": "direct", "tag": "direct §hide§"}
  ]
}
''';

void main() {
  var failures = 0;

  void check(String label, Object? actual, Object? expected) {
    final ok = actual == expected;
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  // 1) 命中：抽出的是该节点自己的 JSON（含凭据字段），且可再解析
  final hk = extractOutboundJson(sample, 'HK-01');
  check('HK-01 非空', hk != null, true);
  final hkMap = jsonDecode(hk!) as Map<String, dynamic>;
  check('HK-01 type', hkMap['type'], 'anytls');
  check('HK-01 保留凭据字段', hkMap['password'], 'secret');
  check('HK-01 不含别的节点', hk!.contains('jp02.example.com'), false);

  final jp = extractOutboundJson(sample, 'JP-02')!;
  check('JP-02 type', (jsonDecode(jp) as Map<String, dynamic>)['type'], 'vless');

  // 2) 组出站也能抽（tag=select）
  check('select 组可抽', extractOutboundJson(sample, 'select')!.contains('"selector"'), true);

  // 3) 未命中 / 非法输入 → null（不抛）
  check('未知 tag → null', extractOutboundJson(sample, 'NOT-EXIST'), null);
  check('空配置 → null', extractOutboundJson('{"outbounds": []}', 'HK-01'), null);
  check('无 outbounds → null', extractOutboundJson('{}', 'HK-01'), null);
  check('坏 JSON → null', extractOutboundJson('{not json', 'HK-01'), null);

  // 4) 与离线清单同源：列表里出现的 tag，抽取必然命中
  final groups = parseOfflineProxyGroups(sample);
  final tags = groups.expand((g) => g.items).map((e) => e.tag).toList();
  check('清单解析出成员', tags.isNotEmpty, true);
  check('清单每个 tag 都能抽出 JSON', tags.every((t) => extractOutboundJson(sample, t) != null), true);
  print('清单 tags: $tags');

  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
}
