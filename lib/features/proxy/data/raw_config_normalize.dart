// raw 通道 selector 归一化：把用户配置裸键 `outbounds` 整体替换掉契约组后的
// 「切节点永不生效」事故修在合并完成之后，而不是去猜测用户会写什么。
//
// ---------------------------------------------------------------------------
// 目的
//
// raw 通道（custom_config 全局自定义配置）启动时，用户配置若用裸键 `outbounds`
// （List）会整体替换出站列表 → 内核契约组 tag=`select`（[kRuntimeSelectorTag]）
// 消失，route.final 指向用户自己的 selector（tag 常是订阅原名，如「节点选择」）
// → 应用切节点发 `SelectOutbound(groupTag: "select")` 报 "selector not found"
// → 点选永不生效。
//
// 修法（已定案）：**合并完成后归一化 selector 标签** —— 把 route.final 指向的
// （或首个）selector 改名为 `select` 并重写全部引用，恢复运行时契约。
//
// 设计文档：docs/design/custom-config-2026-09-18.md §8.3（启动管线接入）。
//
// 纯 Dart（不 import drift/Flutter），可被 `dart analyze` 直接校验。
// ---------------------------------------------------------------------------
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';

/// 归一化合并后 raw 配置的 selector 标签，恢复 [kRuntimeSelectorTag] 运行时契约。
///
/// **就地修改** [config]，返回被改名的旧 tag；无需改名（或形态不符）返回 null。
///
/// 规则（严格按序）：
/// 1. `outbounds` 不是非空 List → null；
/// 2. 任一元素 `tag == 'select'` → null（契约已满足，route.final 指向别处是用户意图）；
/// 3. 候选 = `type == 'selector'`、tag 为非空 String、tag 不含 `§hide§`；无候选 → null；
/// 4. `route.final` 是 String 且等于某个候选 tag → 选它，否则选第一个候选；
/// 5. 目标改名 `select`，并只在**精确相等**旧 tag 时重写引用：
///    `route.final`、`route.rules[].outbound`、`outbounds[].outbounds[]`、
///    `outbounds[].default`、`outbounds[].detour`。
String? normalizeRawConfigSelector(Map<String, dynamic> config) {
  final outbounds = config['outbounds'];
  if (outbounds is! List || outbounds.isEmpty) return null;

  // 契约已满足：不动用户配置（route.final 指向别处可能是用户有意为之）。
  for (final entry in outbounds) {
    if (entry is Map<String, dynamic> && entry['tag'] == kRuntimeSelectorTag) {
      return null;
    }
  }

  // 收集候选 selector（组类出站里只有 selector 承担"主切换入口"的角色）。
  final candidates = <Map<String, dynamic>>[];
  for (final entry in outbounds) {
    if (entry is Map<String, dynamic> && entry['type'] == 'selector') {
      final tag = entry['tag'];
      if (tag is String && tag.isNotEmpty && !tag.contains('§hide§')) {
        candidates.add(entry);
      }
    }
  }
  if (candidates.isEmpty) return null;

  // 选目标：route.final 指向哪个候选就改哪个；指向非候选（urltest/节点）或未写
  // route 时改第一个候选（它就是列表里的第一个用户 selector）。
  var target = candidates.first;
  final route = config['route'];
  if (route is Map<String, dynamic>) {
    final finalTag = route['final'];
    if (finalTag is String) {
      for (final candidate in candidates) {
        if (candidate['tag'] == finalTag) {
          target = candidate;
          break;
        }
      }
    }
  }

  final oldTag = target['tag'] as String;
  target['tag'] = kRuntimeSelectorTag;

  // 引用重写：全部只在精确相等 oldTag 时改。
  if (route is Map<String, dynamic>) {
    if (route['final'] == oldTag) {
      route['final'] = kRuntimeSelectorTag;
    }
    final rules = route['rules'];
    if (rules is List) {
      for (final rule in rules) {
        if (rule is Map<String, dynamic> && rule['outbound'] == oldTag) {
          rule['outbound'] = kRuntimeSelectorTag;
        }
      }
    }
  }
  for (final entry in outbounds) {
    if (entry is! Map<String, dynamic>) continue;
    final members = entry['outbounds'];
    if (members is List) {
      for (var i = 0; i < members.length; i++) {
        if (members[i] == oldTag) {
          members[i] = kRuntimeSelectorTag;
        }
      }
    }
    if (entry['default'] == oldTag) {
      entry['default'] = kRuntimeSelectorTag;
    }
    if (entry['detour'] == oldTag) {
      entry['detour'] = kRuntimeSelectorTag;
    }
  }

  return oldTag;
}
