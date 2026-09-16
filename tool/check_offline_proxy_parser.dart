// 代理页「订阅 → 它的节点清单」解析 + 出站抽取的**可执行校验**
// （不是单元测试框架，见下方原因）。
//
// 运行：dart run tool/check_offline_proxy_parser.dart
//
// 为什么不用 test/ + flutter_test：flutter test 需要 flutter_tester，在受限环境
// （本仓库的换机/CI 场景）跑不起来；而这一层刻意做成纯 Dart（见
// lib/features/proxy/data/offline_proxy_parser.dart 的说明），所以用 dart run 直接校验。
//
// 覆盖：**一份订阅只产出一个分组**、组类与内部出站被过滤、显示名与可见性规则、
// 选中不由配置决定、出站 JSON 抽取的命中/未命中/坏输入、坏配置返回 null（不抛）。
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';

/// 仿内核 `Parse` 的产物：两个分组（selector / urltest）+ 一个 balancer + 三个节点 + 内部出站。
/// 结构照真机 `configs/<id>.json`（订阅自带的组名不是 `select`，而是"节点选择/自动选择"）。
const sample = '''
{
  "outbounds": [
    {"type": "selector", "tag": "节点选择", "outbounds": ["自动选择", "HK-01", "JP-02"], "default": "自动选择"},
    {"type": "urltest", "tag": "自动选择", "outbounds": ["HK-01", "JP-02"]},
    {"type": "balancer", "tag": "balance", "outbounds": ["HK-01", "JP-02"], "strategy": "round-robin"},
    {"type": "anytls", "tag": "HK-01 §2x", "server": "hk01.example.com", "server_port": 443, "password": "secret"},
    {"type": "vless", "tag": "JP-02", "server": "jp02.example.com", "server_port": 443, "uuid": "a1b2"},
    {"type": "hysteria2", "tag": "SG-03", "server": "sg03.example.com", "server_port": 8443},
    {"type": "direct", "tag": "direct §hide§"},
    {"type": "block", "tag": "block §hide§"},
    {"type": "dns", "tag": "dns-out §hide§"}
  ]
}
''';

void main() {
  var failures = 0;

  void check(String label, Object? actual, Object? expected) {
    final ok = '$actual' == '$expected';
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  // ---- 1) 一份订阅 ⇒ 一个分组，成员 = 它的全部节点（NekoBox RawUpdater.kt:768-787）----
  final group = parseSubscriptionGroup(sample, groupName: '一分机场');
  check('产出一个分组', group != null, true);
  check('组名 = 订阅名', group!.tag, '一分机场');
  check('组类型', group.type, 'Selector');
  check('成员 = 全部节点且保持配置顺序', group.items.map((e) => e.tag).join(','), 'HK-01 §2x,JP-02,SG-03');
  check('不含 selector 组（节点选择）', group.items.any((e) => e.tag == '节点选择'), false);
  check('不含 urltest 组（自动选择）', group.items.any((e) => e.tag == '自动选择'), false);
  check('不含 balancer 组（balance）', group.items.any((e) => e.tag == 'balance'), false);
  check('不含 direct', group.items.any((e) => e.type == 'direct'), false);
  check('不含 block', group.items.any((e) => e.type == 'block'), false);
  check('不含 dns', group.items.any((e) => e.type == 'dns'), false);
  check('不含带 §hide§ 的内部出站', group.items.any((e) => e.tag.contains('§hide§')), false);
  check('节点数', group.items.length, 3);

  // ---- 2) 显示名 / 可见性：镜像内核 proxy_info.go ----
  final byTag = {for (final e in group.items) e.tag: e};
  check('tagDisplay 取 § 之前并 trim', byTag['HK-01 §2x']!.tagDisplay, 'HK-01');
  check('无后缀时原样', byTag['JP-02']!.tagDisplay, 'JP-02');
  check('节点可见', byTag['JP-02']!.isVisible, true);
  check('节点不是组', byTag['JP-02']!.isGroup, false);
  check('未测速时延迟为 0', byTag['JP-02']!.urlTestDelay, 0);

  // ---- 3) 选中**不由配置决定**（选中是独立持久偏好，NekoBox DataStore.selectedProxy）----
  check('配置里的 default 不产生选中', group.selected, '');
  check('没有任何项被选中', group.items.every((e) => !e.isSelected), true);

  // ---- 4) 与「节点分享」同源：清单里每个 tag 都能抽出自己的 JSON ----
  final tags = group.items.map((e) => e.tag).toList();
  check('清单每个 tag 都能抽出 JSON', tags.every((t) => extractOutboundJson(sample, t) != null), true);

  final hk = extractOutboundJson(sample, 'HK-01 §2x');
  check('抽出的是该节点自己的 JSON', hk != null, true);
  final hkMap = jsonDecode(hk!) as Map<String, dynamic>;
  check('保留凭据字段', hkMap['password'], 'secret');
  check('不含别的节点', hk.contains('jp02.example.com'), false);
  check('未命中 tag → null', extractOutboundJson(sample, 'NOT-EXIST'), null);

  // ---- 5) 坏配置返回 null 而不是抛异常 ----
  check('not json', parseSubscriptionGroup('not json', groupName: 'x'), null);
  check('空对象', parseSubscriptionGroup('{}', groupName: 'x'), null);
  check('空 outbounds', parseSubscriptionGroup('{"outbounds": []}', groupName: 'x'), null);
  check(
    '只有组类与内部出站 → null（没有可用节点）',
    parseSubscriptionGroup(
      '{"outbounds":[{"type":"selector","tag":"节点选择","outbounds":[]},{"type":"direct","tag":"direct §hide§"}]}',
      groupName: 'x',
    ),
    null,
  );
  check('坏 JSON 抽 JSON → null', extractOutboundJson('{not json', 'HK-01'), null);

  // ---- 6) 另一个来源：**实体行** → 分组（列表以数据库为准，NekoBox proxyDao.getByGroup）----
  const hkPayload = '{"type":"anytls","tag":"HK-01 §2x","server":"hk01.example.com","server_port":443}';
  const jpPayload = '{"type":"vless","tag":"JP-02","server":"jp02.example.com","server_port":8443}';
  final fromEntities = buildGroupFromEntityNodes(
    groupName: '云霄',
    nodes: [
      (
        tag: 'HK-01 §2x',
        type: 'anytls',
        displayName: 'HK-01',
        payload: hkPayload,
        status: 1,
        ping: 120,
        error: null,
      ),
      (tag: 'JP-02', type: 'vless', displayName: 'JP-02', payload: jpPayload, status: 0, ping: 0, error: null),
    ],
  );
  check('实体来源：组名 = 订阅名', fromEntities.tag, '云霄');
  check('实体来源：顺序照库里 userOrder', fromEntities.items.map((e) => e.tag).join(','), 'HK-01 §2x,JP-02');
  check('实体来源：显示名用库里那一列', fromEntities.items.first.tagDisplay, 'HK-01');
  check('实体来源：不预置选中', fromEntities.selected, '');
  check('实体来源：没有选中项', fromEntities.items.every((e) => !e.isSelected), true);
  check('实体来源：都不是组', fromEntities.items.every((e) => !e.isGroup), true);
  check('实体来源：空清单 → 空组', buildGroupFromEntityNodes(groupName: 'x', nodes: const []).items.isEmpty, true);
  // 地址来自实体 payload（NekoBox `AbstractBean.displayAddress()`），不是运行期
  check('实体来源：地址行有值', displayAddress(fromEntities.items.first.host, fromEntities.items.first.port), 'hk01.example.com:443');
  check('实体来源：端口也是 int 保持', fromEntities.items.first.port, 443);
  // 测速结果列：status=1 → 延迟上屏；status=0 → "—"
  check('实体来源：status=1 延迟显示', fromEntities.items.first.urlTestDelay, 120);
  check('实体来源：status=0 显示为未测', fromEntities.items.last.urlTestDelay, 0);
  // 两个来源必须产出**同一形状**（含地址），否则"回落"会换掉列表长相
  final rebuilt = buildGroupFromEntityNodes(
    groupName: group.tag,
    nodes: [
      for (final e in group.items)
        (
          tag: e.tag,
          type: e.type,
          displayName: e.tagDisplay,
          payload: jsonEncode({'server': e.host, 'server_port': e.port}),
          status: 0,
          ping: 0,
          error: null,
        ),
    ],
  );
  check(
    '两个来源产出同一形状',
    rebuilt.items.map((e) => '${e.tag}|${e.type}|${e.tagDisplay}|${e.isVisible}|${e.isGroup}|${e.host}:${e.port}').join(','),
    group.items.map((e) => '${e.tag}|${e.type}|${e.tagDisplay}|${e.isVisible}|${e.isGroup}|${e.host}:${e.port}').join(','),
  );

  // ---- 6b) 地址行：镜像 NekoBox `AbstractBean.displayAddress()` + `ktx/Nets.kt` ----
  check('IPv4/域名 原样', displayAddress('hk01.example.com', 443), 'hk01.example.com:443');
  check('IPv6 加方括号', displayAddress('2001:4860:4860::8888', 443), '[2001:4860:4860::8888]:443');
  check('已带方括号不重复加', displayAddress('[2001:4860:4860::8888]', 443), '[2001:4860:4860::8888]:443');
  check('取 payload 里的 server/server_port', serverAddressOfPayload(hkPayload).host, 'hk01.example.com');
  check('取 payload 里的端口', serverAddressOfPayload(hkPayload).port, 443);
  check('payload 缺字段 → 空', serverAddressOfPayload('{"type":"x"}').host, '');
  check('payload 字段类型不对 → 空', serverAddressOfPayload('{"server":123,"server_port":"443"}').port, 0);
  check('坏 payload → 空', serverAddressOfPayload('{bad').host, '');
  check('非对象 payload → 空', serverAddressOfPayload('[1,2]').host, '');

  // ---- 7) 出站 JSON 美化（分享：两个来源共用）----
  check('字符串 payload 可美化', prettyOutboundJson('{"a":1}')!.contains('\n'), true);
  check('坏 payload → null', prettyOutboundJson('{bad'), null);
  check('null → null', prettyOutboundJson(null), null);

  print('');
  print(failures == 0 ? 'ALL PASS' : '$failures FAILED');
}
