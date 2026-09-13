import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

/// 离线清单解析测试。
///
/// 输入的 JSON 结构**照抄核心 `hiddify-core/v2/config/builder.go` 的产物**：
/// - `selector` 的 tag 固定是 `select`（`OutboundSelectTag`）
/// - 它的 `outbounds` 是**字符串数组**：`[urltest.Tag, balancer.Tag, ...节点tag]`
/// - `default` 是某个 tag，特殊情况下是字面量 `"§default§"`
/// - balancer/urltest 的 tag 分别是 `balance` / `lowest`
/// - 内部出站的 tag 带 `§hide§` 后缀（`OutboundDirectTag = "direct §hide§"`）
///
/// 显示规则照抄 `hiddify-core/v2/hcore/proxy_info.go`：
/// `TrimTagName` 取 `§` 之前并 trim；`IsVisible = !tag.contains("§hide§")`。
void main() {
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
      {
        'type': 'urltest',
        'tag': 'lowest',
        'outbounds': ['香港01', '日本 03'],
      },
      {'type': 'vmess', 'tag': '香港01', 'server': '1.2.3.4'},
      {'type': 'trojan', 'tag': '日本 03', 'server': '5.6.7.8'},
      {'type': 'direct', 'tag': 'direct §hide§'},
    ],
  });

  test('解析出全部分组（select + balancer + urltest）', () {
    final groups = parseOfflineProxyGroups(buildConfig());
    expect(groups.map((g) => g.tag), ['select', 'balance', 'lowest']);
    expect(groups.map((g) => g.type), ['Selector', 'Selector', 'URLTest']);
  });

  test('主分组 select 的成员与顺序照配置来', () {
    final select = parseOfflineProxyGroups(buildConfig()).first;
    expect(select.items.map((i) => i.tag), ['lowest', 'balance', '香港01', '日本 03', 'direct §hide§']);
  });

  test('显示名按 TrimTagName 规则去掉 § 后缀', () {
    final select = parseOfflineProxyGroups(buildConfig()).first;
    final byTag = {for (final item in select.items) item.tag: item};
    expect(byTag['direct §hide§']!.tagDisplay, 'direct');
    expect(byTag['香港01']!.tagDisplay, '香港01');
    expect(byTag['日本 03']!.tagDisplay, '日本 03');
  });

  test('内部出站标记为不可见，节点可见', () {
    final select = parseOfflineProxyGroups(buildConfig()).first;
    final byTag = {for (final item in select.items) item.tag: item};
    expect(byTag['direct §hide§']!.isVisible, isFalse);
    expect(byTag['香港01']!.isVisible, isTrue);
  });

  test('嵌套的分组成员被标成 group（UI 才能和不分组区分）', () {
    final select = parseOfflineProxyGroups(buildConfig()).first;
    final byTag = {for (final item in select.items) item.tag: item};
    expect(byTag['lowest']!.isGroup, isTrue);
    expect(byTag['balance']!.isGroup, isTrue);
    expect(byTag['香港01']!.isGroup, isFalse);
  });

  test('default 指向哪个 tag，哪一项就是选中态', () {
    final select = parseOfflineProxyGroups(buildConfig()).first;
    expect(select.selected, 'balance');
    expect(select.items.firstWhere((i) => i.tag == 'balance').isSelected, isTrue);
    expect(select.items.firstWhere((i) => i.tag == '香港01').isSelected, isFalse);
  });

  test('default 是字面量 §default§ 时当作没指定（builder.go 的标记）', () {
    final select = parseOfflineProxyGroups(buildConfig(selectorDefault: '§default§')).first;
    expect(select.selected, isEmpty);
    expect(select.items.every((i) => !i.isSelected), isTrue);
  });

  test('配置里没有任何分组时兜底平铺成一组（页面不能空）', () {
    final config = jsonEncode({
      'outbounds': [
        {'type': 'vmess', 'tag': 'A', 'server': '1.1.1.1'},
        {'type': 'trojan', 'tag': 'B', 'server': '2.2.2.2'},
        {'type': 'direct', 'tag': 'direct §hide§'},
      ],
    });
    final groups = parseOfflineProxyGroups(config);
    expect(groups.length, 1);
    expect(groups.first.items.map((i) => i.tag), ['A', 'B']);
  });

  test('垃圾输入返回空列表而不是抛异常', () {
    expect(parseOfflineProxyGroups('not json'), isEmpty);
    expect(parseOfflineProxyGroups('{}'), isEmpty);
    expect(parseOfflineProxyGroups('{"outbounds": []}'), isEmpty);
  });
}
