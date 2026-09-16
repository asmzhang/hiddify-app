// 「实时值按节点 tag 贴到展示清单」的可执行校验（同 check_entity_import.dart 的理由：
// 纯 Dart + dart run，不依赖 flutter_tester）。
//
// 运行：dart run tool/check_live_proxy_join.dart
//
// 要证明的核心：**列表以骨架为准（组 tag 不参与匹配），实时值按节点 tag 逐个贴上，
// 选中取内核主 selector（常量 `select`）。**
//
// ignore_for_file: avoid_print — 校验脚本，print 就是它的输出方式
import 'dart:convert';

import 'package:fixnum/fixnum.dart';
import 'package:hiddify/features/proxy/data/live_proxy_join.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

OutboundInfo _item(String tag, {String? type, bool isGroup = false, int delay = 0, int up = 0, int down = 0}) {
  final info = OutboundInfo(tag: tag, type: type ?? 'anytls', isGroup: isGroup);
  if (delay != 0) info.urlTestDelay = delay;
  if (up != 0) info.upload = Int64(up);
  if (down != 0) info.download = Int64(down);
  return info;
}

/// 骨架 = 订阅解析出的组（`offline_proxy_parser` 的产物形状）。
OutboundGroup _skeleton() {
  final g = OutboundGroup(tag: '冲上云霄', type: 'selector', selectable: true)
    ..items.add(_item('自动选择', type: 'urltest', isGroup: true))
    ..items.add(_item('HK-01'))
    ..items.add(_item('JP-02'))
    ..items.add(_item('US-04'));
  // 骨架里预置一些"上一次的"实时值，用来验证：内核给了就覆盖、内核没给就保留。
  g.items[1].urlTestDelay = 999;
  return g;
}

/// 运行期 = 内核 `OutboundsInfo` 的产物形状：三个重建出来的组。
List<OutboundGroup> _liveGroups({String selected = 'JP-02', bool includeUs04 = false}) {
  OutboundInfo n(String tag, int delay, int up, int down) =>
      _item(tag, delay: delay, up: up, down: down);

  final nodes = <OutboundInfo>[
    n('HK-01', 120, 100, 200),
    n('JP-02', 45, 300, 400),
    if (includeUs04) n('US-04', 88, 10, 20),
  ];

  final selector = OutboundGroup(tag: kRuntimeSelectorTag, type: 'selector', selected: selected, selectable: true)
    ..items.add(_item(kRuntimeBalanceTag, type: 'balancer', isGroup: true))
    ..items.add(_item(kRuntimeLowestTag, type: 'balancer', isGroup: true))
    ..items.add(_item(kRuntimeDirectTag, type: 'direct'))
    ..items.addAll(nodes);

  final balance = OutboundGroup(tag: kRuntimeBalanceTag, type: 'balancer')..items.addAll(nodes);
  final lowest = OutboundGroup(tag: kRuntimeLowestTag, type: 'balancer')..items.addAll(nodes);

  return [selector, balance, lowest];
}

void main() {
  var failures = 0;

  void check(String label, Object? actual, Object? expected) {
    // List/Map 在 Dart 里 == 是同一性比较，必须按值比（本项目已踩过这个坑）
    bool eq(Object? a, Object? b) {
      if (a is List || a is Map || b is List || b is Map) return jsonEncode(a) == jsonEncode(b);
      return a == b;
    }

    final ok = eq(actual, expected);
    if (!ok) failures++;
    print('${ok ? "PASS" : "FAIL"}  $label${ok ? "" : "\n  expected: $expected\n  actual:   $actual"}');
  }

  // ---- 场景 1：内核已加载 HK-01 / JP-02，选出 JP-02；US-04 还没加载 ----
  final skeleton = _skeleton();
  final join = joinLiveIntoGroup(skeleton: skeleton, liveGroups: _liveGroups());
  final out = join.group;

  check('列表内容/顺序 = 骨架', out.items.map((e) => e.tag).toList(), ['自动选择', 'HK-01', 'JP-02', 'US-04']);
  check('组 tag 沿用骨架（不因内核组名而变）', out.tag, '冲上云霄');
  check('内核的 balance/lowest 不出现在列表里', out.items.any((e) => kRuntimeGroupTags.contains(e.tag)), false);
  check('隐藏出站不出现在列表里', out.items.any((e) => isHiddenTag(e.tag)), false);

  check('命中数（HK-01、JP-02）', join.matched, 2);
  check('未命中数（US-04）', join.missing, 1);

  check('HK-01 延迟被内核覆盖（旧值 999）', out.items[1].urlTestDelay, 120);
  check('HK-01 上行被内核覆盖', out.items[1].upload, Int64(100));
  check('JP-02 延迟', out.items[2].urlTestDelay, 45);
  check('US-04 内核没给 → 保留骨架值', out.items[3].urlTestDelay, 0);

  check('选中 tag 来自内核主 selector', join.selectedTag, 'JP-02');
  check('只有 JP-02 高亮', out.items.map((e) => e.isSelected).toList(), [false, false, true, false]);
  check('组条目不参与选中判断', out.items[0].isSelected, false);

  // ---- 场景 2：骨架不被修改（返回的是新对象） ----
  check('原骨架未被写坏', skeleton.items[1].urlTestDelay, 999);
  check('原骨架未被改选中', skeleton.selected, '');

  // ---- 场景 3：内核还没加载到 US-04 时，它仍然在列表里（内容由骨架决定） ----
  final partial = joinLiveIntoGroup(skeleton: _skeleton(), liveGroups: _liveGroups(includeUs04: true));
  check('内核加载后 US-04 被贴上', partial.group.items[3].urlTestDelay, 88);
  check('US-04 不再是 missing', partial.missing, 0);

  // ---- 场景 4：内核还没起来（空清单）→ 全未命中、无选中，但列表照旧 ----
  final none = joinLiveIntoGroup(skeleton: _skeleton(), liveGroups: const []);
  check('空内核 → 列表仍是骨架', none.group.items.map((e) => e.tag).toList(), ['自动选择', 'HK-01', 'JP-02', 'US-04']);
  check('空内核 → 无选中', none.selectedTag, '');
  check('空内核 → 全部未命中', [none.matched, none.missing], [0, 3]);
  check('空内核 → 无高亮', none.group.items.every((e) => !e.isSelected), true);

  // ---- 场景 5：`select` 组缺失 → 退化到"哪个条目带 isSelected" ----
  final weird = OutboundGroup(tag: 'something-else', type: 'selector')..items.add(_item('HK-01')..isSelected = true);
  final degraded = joinLiveIntoGroup(skeleton: _skeleton(), liveGroups: [weird]);
  check('退化：选中 tag 取带 isSelected 的条目', degraded.selectedTag, 'HK-01');

  // ---- 场景 6：组类 live 条目不被当作节点（即使 tag 相同也不贴值） ----
  final groupTrap = OutboundGroup(tag: kRuntimeSelectorTag, type: 'selector')
    ..items.add(_item('HK-01', isGroup: true, delay: 777))
    ..items.add(_item('自动选择', isGroup: true, delay: 555));
  final trap = joinLiveIntoGroup(skeleton: _skeleton(), liveGroups: [groupTrap]);
  check('isGroup 的 live 条目被忽略（骨架延迟保留）', trap.group.items[1].urlTestDelay, 999);

  print('\n摘要: $join');
  print(failures == 0 ? '\nALL PASS' : '\n$failures FAILED');
}
