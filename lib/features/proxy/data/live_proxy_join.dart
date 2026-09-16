// 把内核的**实时数据**按「节点 tag」贴到展示用清单上。
//
// ## 为什么需要"贴"这一步（而不是直接显示内核的组）
//
// 内核返回的组是它自己重建的：`select` / `balance` / `lowest`（见 runtime_outbound_tags.dart）。
// 其中 `select` 的成员是 `[balance, lowest, …全部节点]` —— 它是一张**并集表**，不是用户
// 订阅里的那个分组。所以两组信息天然是两件事：
//
//   · **谁在列表里、什么顺序、叫什么名字** ← 数据层（本项目：实体 / 订阅清单）
//   · **每个节点的延迟、上下行、是否选中** ← 运行期（内核 `OutboundsInfo`）
//
// 这不是"双数据源缝合"，而是 NekoBox 的分工原样：
//   · NekoBox 的列表来自 DB（`ConfigBuilder.kt:131` 的 `proxyDao.getByGroup(group.id)`）
//   · 每节点实时值来自 `bg/proto/TrafficLooper.kt`（`idMap`/`tagMap` 双索引，按 tag 从
//     clash API 取，最后 `TrafficData(id = ent.id, …)` 广播给 UI）
//   · 选中来自 `DataStore.selectedProxy`（实体 id）
//
// **组 tag 不参与匹配** —— 内核的组名是常量，与订阅组名无关；只有**节点 tag** 两侧一致
// （因为配置里的节点就是我们写进去的实体）。
//
// 之前的做法（Phase 1）是"按组 tag 从内核清单里取那一组"，组 tag 永远对不上，
// 于是每次都落到 `liveGroups.first`（= `select`），把内核的并集表当成用户的组显示，
// `balance`/`lowest` 这两行还会当成节点出现。本模块取代它。
//
// 纯 Dart（只依赖生成的 pb），可被 `dart run tool/check_live_proxy_join.dart` 校验。
import 'package:dartx/dartx.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// 贴值的结果。
class LiveProxyJoin {
  const LiveProxyJoin({
    required this.group,
    required this.selectedTag,
    required this.matched,
    required this.missing,
  });

  /// 展示用清单（骨架来自 [skeleton]，实时值来自内核）。
  final OutboundGroup group;

  /// 内核主 selector 当前选中的**节点 tag**；拿不到则为空串。
  final String selectedTag;

  /// 命中实时数据的节点数 / 没命中的节点数（内核还没加载到这些节点时为多）。
  final int matched;
  final int missing;

  @override
  String toString() => 'LiveProxyJoin(matched=$matched, missing=$missing, selected=$selectedTag)';
}

/// 把 [liveGroups] 的实时数据贴到 [skeleton] 上，返回新的清单（不改动入参）。
///
/// - 列表内容、顺序、tag 完全以 [skeleton] 为准
/// - 每个**非组**条目按自己的 tag 取实时值（延迟 / 测速时间 / 上下行 / 端口 / 主机 / IP / TLS）
/// - `isSelected` = 该条目 tag 是否等于内核主 selector 的选中项
/// - 组类条目（`isGroup`）原样保留、不贴值、不参与选中判断
LiveProxyJoin joinLiveIntoGroup({
  required OutboundGroup skeleton,
  required List<OutboundGroup> liveGroups,
}) {
  // 节点 tag → 实时数据。跨所有内核组收集：节点只会以"组外成员"的形式出现，
  // 同一 tag 在多个组里出现时取第一份（`select` 的成员就是并集，取谁都是同一个对象）。
  final liveByTag = <String, OutboundInfo>{};
  for (final group in liveGroups) {
    for (final item in group.items) {
      if (item.isGroup) continue;
      if (isHiddenTag(item.tag)) continue;
      liveByTag.putIfAbsent(item.tag, () => item);
    }
  }

  // 选中：以内核主 selector（常量 tag）为准；退化时看哪个组的条目带 isSelected。
  final selector = liveGroups.where((g) => g.tag == kRuntimeSelectorTag).firstOrNull;
  var selectedTag = selector?.selected ?? '';
  if (selectedTag.isEmpty) {
    for (final group in liveGroups) {
      final picked = group.items.where((i) => i.isSelected && !i.isGroup).firstOrNull;
      if (picked != null) {
        selectedTag = picked.tag;
        break;
      }
    }
  }

  final group = OutboundGroup()
    ..tag = skeleton.tag
    ..type = skeleton.type
    ..selectable = skeleton.selectable
    ..isExpand = skeleton.isExpand;

  var matched = 0;
  var missing = 0;
  for (final item in skeleton.items) {
    final copy = item.deepCopy();
    final live = item.isGroup ? null : liveByTag[item.tag];
    if (item.isGroup) {
      // 组类条目保留但不贴运行期数据（内核的组 tag 与我们无关）
    } else if (live != null) {
      copy
        ..urlTestDelay = live.urlTestDelay
        ..upload = live.upload
        ..download = live.download
        ..isSecure = live.isSecure;
      if (live.hasUrlTestTime()) copy.urlTestTime = live.urlTestTime;
      if (live.hasIpinfo()) copy.ipinfo = live.ipinfo;
      if (live.port != 0) copy.port = live.port;
      if (live.host.isNotEmpty) copy.host = live.host;
      matched++;
    } else {
      missing++;
    }
    copy.isSelected = !item.isGroup && item.tag == selectedTag;
    group.items.add(copy);
  }
  group.selected = selectedTag;

  return LiveProxyJoin(group: group, selectedTag: selectedTag, matched: matched, missing: missing);
}
