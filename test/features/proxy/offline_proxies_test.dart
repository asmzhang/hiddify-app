import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

/// 代理页「订阅 → 它的节点清单」解析测试。
///
/// 规格来源是 **NekoBox**（以它为准）：
/// - `Constants.kt`：`GroupType` 只有 `BASIC` / `SUBSCRIPTION` —— 没有"自动选择"这种组
/// - `group/RawUpdater.kt:768-787`：订阅是 sing-box 配置时，把 `dns` / `block` / `direct` /
///   `selector` / `urltest` 全部过滤掉，只留真节点 ⇒ **一份订阅产出恰好一个分组**
/// - `database/ProxyGroup.kt` 的 `displayName()`：组名就是订阅名
///
/// 输入的 JSON 结构照真机 `configs/<id>.json`（订阅自带的组名不是 `select`，
/// 而是"节点选择 / 自动选择"这类机场自定的名字）。
///
/// 显示规则照抄 `hiddify-core/v2/hcore/proxy_info.go`：
/// `TrimTagName` 取 `§` 之前并 trim；`IsVisible = !tag.contains("§hide§")`。
void main() {
  const config = '''
{
  "outbounds": [
    {"type": "selector", "tag": "节点选择", "outbounds": ["自动选择", "香港01"], "default": "自动选择"},
    {"type": "urltest", "tag": "自动选择", "outbounds": ["香港01", "日本 03"]},
    {"type": "balancer", "tag": "balance", "outbounds": ["香港01", "日本 03"]},
    {"type": "vmess", "tag": "香港01 §2x", "server": "1.2.3.4"},
    {"type": "trojan", "tag": "日本 03", "server": "5.6.7.8"},
    {"type": "direct", "tag": "direct §hide§"},
    {"type": "dns", "tag": "dns-out §hide§"}
  ]
}
''';

  test('一份订阅只产出一个分组，组名是订阅名', () {
    final group = parseSubscriptionGroup(config, groupName: '云霄');
    expect(group, isNotNull);
    expect(group!.tag, '云霄');
    expect(group.type, 'Selector');
  });

  test('成员是全部节点，顺序照配置', () {
    final group = parseSubscriptionGroup(config, groupName: '云霄')!;
    expect(group.items.map((i) => i.tag), ['香港01 §2x', '日本 03']);
  });

  test('组类出站（selector / urltest / balancer）不成为节点', () {
    final group = parseSubscriptionGroup(config, groupName: '云霄')!;
    final tags = group.items.map((i) => i.tag);
    expect(tags, isNot(contains('节点选择')));
    expect(tags, isNot(contains('自动选择')));
    expect(tags, isNot(contains('balance')));
    expect(group.items.every((i) => !i.isGroup), isTrue);
  });

  test('direct / dns / 隐藏出站不是节点', () {
    final group = parseSubscriptionGroup(config, groupName: '云霄')!;
    expect(group.items.any((i) => i.type == 'direct'), isFalse);
    expect(group.items.any((i) => i.type == 'dns'), isFalse);
    expect(group.items.any((i) => i.tag.contains('§hide§')), isFalse);
  });

  test('显示名按 TrimTagName 规则去掉 § 后缀', () {
    final group = parseSubscriptionGroup(config, groupName: '云霄')!;
    final byTag = {for (final i in group.items) i.tag: i};
    expect(byTag['香港01 §2x']!.tagDisplay, '香港01');
    expect(byTag['日本 03']!.tagDisplay, '日本 03');
    expect(byTag['日本 03']!.isVisible, isTrue);
  });

  test('选中不由配置决定（选中是独立持久偏好）', () {
    final group = parseSubscriptionGroup(config, groupName: '云霄')!;
    expect(group.selected, isEmpty);
    expect(group.items.every((i) => !i.isSelected), isTrue);
  });

  test('坏配置返回 null 而不是抛异常', () {
    expect(parseSubscriptionGroup('not json', groupName: 'x'), isNull);
    expect(parseSubscriptionGroup('{}', groupName: 'x'), isNull);
    expect(parseSubscriptionGroup('{"outbounds": []}', groupName: 'x'), isNull);
    expect(
      parseSubscriptionGroup(
        jsonEncode({
          'outbounds': [
            {'type': 'selector', 'tag': '节点选择', 'outbounds': <String>[]},
          ],
        }),
        groupName: 'x',
      ),
      isNull,
    );
  });
}
