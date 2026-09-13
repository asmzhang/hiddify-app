import 'dart:convert';

import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// 离线清单的解析 —— **纯 Dart，不依赖 Flutter**。
///
/// 单独一个文件是为了能用 `dart run` 直接验证（`flutter test` 要起 flutter_tester，
/// 在受限环境里跑不起来）。解析逻辑本来也不需要 UI，拆出来更好测。

/// 从"生成好的配置"里抽出**所有可切换的分组**（select / urltest / 面板分组）。
///
/// 输入结构照 `hiddify-core/v2/config/builder.go` 的产物：
/// - 主分组固定是 `{type: selector, tag: "select", outbounds: [<tag>...], default: <tag>}`
/// - balancer / urltest 的 tag 分别是 `balance` / `lowest`，会被插到节点前面
/// - 内部出站的 tag 带 `§hide§` 后缀（`OutboundDirectTag = "direct §hide§"`）
///
/// **解析失败会兜底而不是直接放弃**：一个分组都找不到时，把所有像节点的 outbound
/// 平铺成一个组 —— 少一层分组概念，总好过代理页空着（空着就等于"必须先连接"）。
List<OutboundGroup> parseOfflineProxyGroups(String configJson, {void Function(String)? log}) {
  void warn(String message) => log?.call(message);
  try {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final outbounds = (config['outbounds'] as List?)?.whereType<Map<String, dynamic>>().toList();
    if (outbounds == null || outbounds.isEmpty) {
      warn("offline proxies: config has no outbounds (keys: ${config.keys.join(",")})");
      return const [];
    }

    final byTag = <String, Map<String, dynamic>>{
      for (final outbound in outbounds)
        if (outbound['tag'] is String) outbound['tag'] as String: outbound,
    };

    const groupTypes = {'selector', 'urltest', 'balancer'};
    final groups = <OutboundGroup>[];
    for (final outbound in outbounds) {
      final type = outbound['type'];
      final tag = outbound['tag'];
      if (type is! String || tag is! String || !groupTypes.contains(type)) continue;

      // builder.go 在特定情况下会写入字面量 "§default§"（那是标记、不是真 tag）
      final defaultTag = (outbound['default'] as String?) ?? '';
      final group = OutboundGroup()
        ..tag = tag
        ..type = type == 'urltest' ? 'URLTest' : 'Selector'
        ..selected = defaultTag.contains('§') ? '' : defaultTag;

      for (final member in (outbound['outbounds'] as List?)?.whereType<String>() ?? const <String>[]) {
        // 成员本身可能又是一个分组（builder 会把 urltest/balancer 塞进 select），
        // 保留 isGroup 标记让 UI 能区分"节点"和"分组"。
        group.items.add(outboundInfo(member, (byTag[member]?['type'] as String?) ?? 'unknown', member == group.selected));
      }
      if (group.items.isNotEmpty) groups.add(group);
    }

    if (groups.isNotEmpty) return groups;

    // 兜底：没有任何分组 ⇒ 把所有"像节点"的 outbound 平铺成一个组
    final flat = OutboundGroup()
      ..tag = 'select'
      ..type = 'Selector'
      ..selected = '';
    for (final outbound in outbounds) {
      final tag = outbound['tag'];
      final type = outbound['type'];
      if (tag is! String || type is! String || hiddenTag(tag)) continue;
      if (type == 'direct' || type == 'block' || type == 'dns') continue;
      flat.items.add(outboundInfo(tag, type, false));
    }
    if (flat.items.isEmpty) {
      warn("offline proxies: no usable outbound (types: ${outbounds.map((o) => o['type']).join(",")})");
      return const [];
    }
    warn("offline proxies: no group found, fell back to flat node list");
    return [flat];
  } catch (e) {
    warn("offline proxies: parse failed");
    return const [];
  }
}

/// 显示名规则，镜像核心 `proxy_info.go` 的 `TrimTagName`：
/// ```go
/// func TrimTagName(tag string) string { return strings.Trim(strings.Split(tag, "§")[0], " ") }
/// ```
String trimTagName(String tag) => tag.split('§').first.trim();

/// 内部出站标记，镜像核心 `proxy_info.go`：`IsVisible = !strings.Contains(tag, "§hide§")`
bool hiddenTag(String tag) => tag.contains('§hide§');

/// 构造一项，**必须同时填 `tagDisplay` 和 `isVisible`** ——
/// 它们是独立字段，不填的话列表会出现空名字、以及 direct/dns 这类内部项。
OutboundInfo outboundInfo(String tag, String type, bool selected) => OutboundInfo()
  ..tag = tag
  ..type = type
  ..tagDisplay = trimTagName(tag)
  ..isVisible = !hiddenTag(tag)
  ..isGroup = type == 'selector' || type == 'urltest' || type == 'balancer'
  ..isSelected = selected
  // 未连接时没有实测延迟；0 在 UI 上就是"—"
  ..urlTestDelay = 0;
