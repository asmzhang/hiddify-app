// ignore_for_file: avoid_print
//
// 离线清单解析的自检脚本。
//
// 为什么是脚本而不是 test：`flutter test` 要起 flutter_tester（受限环境里连不上），
// 而解析逻辑是纯 Dart 的，直接用 `dart run tool/offline_parse_check.dart` 就能验证。
//
// 输入结构照抄核心 `hiddify-core/v2/config/builder.go` 的产物；
// 显示规则照抄 `hiddify-core/v2/hcore/proxy_info.go`。
import 'dart:convert';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

int _failed = 0;

void check(String name, Object? actual, Object? expected) {
  final ok = '$actual' == '$expected';
  if (!ok) _failed++;
  print('${ok ? "  ok  " : "  FAIL"}  $name${ok ? "" : "\n         实际=$actual\n         期望=$expected"}');
}

String buildConfig({String selectorDefault = 'balance'}) => jsonEncode({
  'outbounds': [
    {
      'type': 'selector',
      'tag': 'select',
      'outbounds': ['lowest', 'balance', '香港01', '日本 03', 'direct §hide§'],
      'default': selectorDefault,
    },
    {
      'type': 'balancer',
      'tag': 'balance',
      'outbounds': ['香港01', '日本 03'],
      'strategy': 'round-robin',
    },
    {'type': 'urltest', 'tag': 'lowest', 'outbounds': ['香港01', '日本 03']},
    {'type': 'vmess', 'tag': '香港01', 'server': '1.2.3.4'},
    {'type': 'trojan', 'tag': '日本 03', 'server': '5.6.7.8'},
    {'type': 'direct', 'tag': 'direct §hide§'},
  ],
});

void main() {
  print('== 分组解析 ==');
  final groups = parseOfflineProxyGroups(buildConfig());
  check('分组 tag 列表', groups.map((g) => g.tag).join(','), 'select,balance,lowest');
  check('分组 type 列表', groups.map((g) => g.type).join(','), 'Selector,Selector,URLTest');

  print('== 主分组成员与顺序 ==');
  final select = groups.first;
  check('成员 tag 与顺序', select.items.map((i) => i.tag).join(','), 'lowest,balance,香港01,日本 03,direct §hide§');

  print('== tagDisplay（TrimTagName）==');
  final byTag = {for (final i in select.items) i.tag: i};
  check('direct §hide§ → display', byTag['direct §hide§']!.tagDisplay, 'direct');
  check('香港01 → display', byTag['香港01']!.tagDisplay, '香港01');
  check('日本 03 → display', byTag['日本 03']!.tagDisplay, '日本 03');

  print('== isVisible ==');
  check('内部出站不可见', byTag['direct §hide§']!.isVisible, false);
  check('节点可见', byTag['香港01']!.isVisible, true);

  print('== isGroup ==');
  check('lowest 是分组', byTag['lowest']!.isGroup, true);
  check('balance 是分组', byTag['balance']!.isGroup, true);
  check('香港01 不是分组', byTag['香港01']!.isGroup, false);

  print('== 选中态 ==');
  check('group.selected', select.selected, 'balance');
  check('balance 被选中', byTag['balance']!.isSelected, true);
  check('香港01 未被选中', byTag['香港01']!.isSelected, false);

  print('== §default§ 字面量当作没指定 ==');
  final marked = parseOfflineProxyGroups(buildConfig(selectorDefault: '§default§')).first;
  check('selected 为空', marked.selected, '');
  check('没有任何项被选中', marked.items.every((i) => !i.isSelected), true);

  print('== 兜底：配置里没有分组 ==');
  final flat = parseOfflineProxyGroups(
    jsonEncode({
      'outbounds': [
        {'type': 'vmess', 'tag': 'A', 'server': '1.1.1.1'},
        {'type': 'trojan', 'tag': 'B', 'server': '2.2.2.2'},
        {'type': 'direct', 'tag': 'direct §hide§'},
      ],
    }),
  );
  check('兜底出一组', flat.length, 1);
  check('兜底成员', flat.first.items.map((i) => i.tag).join(','), 'A,B');

  print('== 垃圾输入不抛异常 ==');
  check('not json', parseOfflineProxyGroups('not json').length, 0);
  check('空对象', parseOfflineProxyGroups('{}').length, 0);
  check('空 outbounds', parseOfflineProxyGroups('{"outbounds": []}').length, 0);

  print('');
  print(_failed == 0 ? '全部通过 ✓' : '$_failed 项失败 ✗');
}
