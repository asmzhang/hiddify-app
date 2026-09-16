// 应用侧组装**出站表**：把实体（节点）套用到内核生成的基准配置上。
//
// ---------------------------------------------------------------------------
// 实测依据（`%APPDATA%\Hiddify\hiddify\data\current-config.json`，内核真正在跑的那份）：
//
//   {
//     "log":…, "dns":{…}, "experimental":{…},
//     "inbounds":[ mixed 'mixed-in::1' …, direct 'dns-in::1' … ],
//     "outbounds":[
//        {selector  tag:"select",  outbounds:["balance","lowest",…48 节点], default:"balance"},
//        {balancer  tag:"balance", outbounds:[…48 节点], strategy:"round-robin"},
//        {balancer  tag:"lowest",  outbounds:[…48 节点], strategy:"lowest-delay"},
//        {direct tag:"direct §hide§"}, {direct tag:"direct-fragment §hide§"}, …48 节点 ],
//     "route":{ "final":"select", rules:[…] }
//   }
//
// 而应用写下的 `<id>.json` **只有 `{"outbounds":[...]}`** —— 它是"喂给内核的输入"，
// 不是最终配置。内核 `v2/config/builder.go` 的 `setOutbounds`（:130-371）会：
//   1. 从输入里**丢掉所有组**（selector/urltest/balancer，:154-164）、丢掉 direct/bypass/block
//      与预定义 tag（:142、:169），**只留下节点**（:178-183 顺便收集非 `§hide§` 的 tag）；
//   2. **自己重建**两个 balancer（`balance` = opt.BalancerStrategy，`lowest` = lowest-delay）
//      与一个 selector（tag 固定 = `OutboundSelectTag` = `"select"`，default = `balance`）；
//   3. `setRoutingOptions` 再把 `route.final` 设成同一个常量。
//
// 结论（这条推翻了本文件早先的写法）：
//   · **组不是应用该管的事** —— 内核每次都会重建，写进去也会被丢。所以本模块**不重建成员、
//     不设 default、不识别"主 selector"**；那些早先的逻辑基于订阅原文（`<id>.tmp.json`），
//     而那不是真正被启动的文件。
//   · 应用要负责的**只有节点出站那一段** —— 这也正是"节点可编辑"所需要的最小权限。
//   · 组 tag 是内核固定常量（`select`/`balance`/`lowest`），**与订阅里的组名无关**；
//     分组显示名属于实体层（`proxy_groups.name`），不该从配置 tag 反推。
//
// 纯 Dart（不 import drift/Flutter），可被 `dart run tool/check_config_assembly.dart` 校验。
// ---------------------------------------------------------------------------
import 'dart:convert';

import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';

/// 组装结果。
class ConfigAssemblyResult {
  const ConfigAssemblyResult({
    required this.configJson,
    required this.replaced,
    required this.added,
    required this.removed,
  });

  /// 组装后的配置（与基准同形，`{"outbounds":[…]}`）。
  final String configJson;

  /// 被实体覆盖 / 新增 / 移除的节点出站数。
  final int replaced;
  final int added;
  final int removed;

  @override
  String toString() => 'ConfigAssemblyResult(replaced=$replaced, added=$added, removed=$removed)';
}

/// 组装时要**点名移除**的节点 tag —— 基准里"是节点"、但实体集合里已经不存在的那些。
///
/// ## 为什么必须有这个函数（审计 F1，P0）
///
/// 内核读的是「基准 + 覆盖」：基准 `configs/<id>.json` 是**订阅原文的快照**，里面留着
/// 已被用户删除的节点。如果组装时不点名移除，它们会被"原样透传" ⇒ 用户删了节点，
/// **内核里还在**（界面 47、内核 48），重启后依旧 —— 这正是"删了没反应"的机制。
///
/// NekoBox 不存在这个问题：它的配置由 DB 现场构建（`fmt/ConfigBuilder.kt:131`
/// `proxyDao.getByGroup`），DB 里没有的节点不可能进配置。本项目是"基准 + 覆盖"，
/// 所以**基准里那一段必须由实体说了算**。
///
/// ## 判据
///
/// 用 [isNodeOutbound]（与"派生实体""解析列表"同一份，见 `runtime_outbound_tags.dart`）。
/// 只读**基准文件**，因此天然不会碰到内核后加的出站（如 `🔒 WARP` 只存在于运行期配置里，
/// 基准里没有）—— 这是"按判据删"与"按形状猜"的关键区别。
Set<String> staleNodeTags({required String baselineConfigJson, required Iterable<String> entityTags}) {
  final stale = <String>{};
  final entities = entityTags.toSet();
  try {
    final decoded = jsonDecode(baselineConfigJson);
    if (decoded is! Map) return stale;
    final raw = decoded['outbounds'];
    if (raw is! List) return stale;
    for (final outbound in raw.whereType<Map>()) {
      final tag = outbound['tag'];
      final type = outbound['type'];
      if (tag is! String || type is! String) continue;
      if (!isNodeOutbound(tag: tag, type: type)) continue;
      // **内核自己的出站永不删**（双保险）：`🔒 WARP` 既不是组也不带 `§hide§`，
      // 形状上和节点一样，但它属于内核（`Warp.EnableWarp` 时才由 `builder.go` 加）。
      // 正常它不会出现在基准里，这里显式挡一道，避免将来基准换代时被误删。
      if (tag == kRuntimeWarpTag) continue;
      if (!entities.contains(tag)) stale.add(tag);
    }
  } catch (_) {
    // 基准不可解析 ⇒ 返回空集合（宁可少删，也不误删）
  }
  return stale;
}

/// 把 [entities] 套用到 [baselineConfigJson]（内核生成的出站表基准）上。
///
/// 规则：
/// - 实体**覆盖**同名节点出站（用 `payload`，即含凭据的完整定义）；基准里没有的实体**追加**在末尾
/// - [staleTags] 里的 tag **移除**（只按调用方给的集合，绝不按"看起来像节点"推断）
/// - 其余出站（组、`§hide§` 内部出站、订阅自带的 helper）**原样透传**
///
/// 解析失败返回 null —— 调用方应回落到基准文件（不因组装失败而无法连接）。
ConfigAssemblyResult? applyEntitiesToOutbounds({
  required String baselineConfigJson,
  required List<ImportedProxyEntity> entities,
  Iterable<String> staleTags = const [],
}) {
  if (entities.isEmpty) return null;

  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> outbounds;
  try {
    final decoded = jsonDecode(baselineConfigJson);
    if (decoded is! Map<String, dynamic>) return null;
    config = decoded;
    final raw = config['outbounds'];
    if (raw is! List) return null;
    outbounds = raw.whereType<Map<String, dynamic>>().toList();
    if (outbounds.isEmpty) return null;
  } catch (_) {
    return null;
  }

  // 实体的 tag → 完整出站定义
  final payloadByTag = <String, Map<String, dynamic>>{};
  for (final entity in entities) {
    try {
      final decoded = jsonDecode(entity.payload);
      if (decoded is Map<String, dynamic>) payloadByTag[entity.tag] = decoded;
    } catch (_) {
      // 单条坏 payload 不该毁掉整份配置：跳过它
    }
  }
  if (payloadByTag.isEmpty) return null;
  final entityTags = entities.map((e) => e.tag).where(payloadByTag.containsKey).toList();

  final stale = staleTags.toSet();
  final result = <Map<String, dynamic>>[];
  var replaced = 0;
  var removed = 0;
  for (final outbound in outbounds) {
    final tag = outbound['tag'];
    final type = outbound['type'];
    if (tag is String && kGroupOutboundTypes.contains(type)) {
      // 组由内核重建，本模块不碰
      result.add(outbound);
      continue;
    }
    if (tag is String && payloadByTag.containsKey(tag)) {
      result.add(payloadByTag[tag]!);
      replaced++;
      continue;
    }
    if (tag is String && stale.contains(tag)) {
      removed++;
      continue;
    }
    result.add(outbound);
  }

  // 基准里没有的实体 → 追加（内核按输入顺序收集 tag，所以新节点排在末尾）
  final presentTags = {for (final o in result) o['tag']};
  var added = 0;
  for (final tag in entityTags) {
    if (!presentTags.contains(tag)) {
      result.add(payloadByTag[tag]!);
      added++;
    }
  }

  config['outbounds'] = result;

  return ConfigAssemblyResult(
    configJson: jsonEncode(config),
    replaced: replaced,
    added: added,
    removed: removed,
  );
}
