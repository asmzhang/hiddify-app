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

import 'package:hiddify/core/utils/json_merge.dart';
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
///
/// endpoints 段（批次 9）：基准里的 wireguard **endpoint** 同样要纳入点名
///（订阅更新后下线的 wg 节点不该残留），判据用 [isNodeEndpoint]。返回的集合
/// 与 outbounds 段的 stale 合并使用（组装函数按段分别匹配）。
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
    // endpoints 段：wireguard endpoint 的 stale（同判据思路，`isNodeEndpoint`）
    final rawEndpoints = decoded['endpoints'];
    if (rawEndpoints is List) {
      for (final endpoint in rawEndpoints.whereType<Map>()) {
        final tag = endpoint['tag'];
        final type = endpoint['type'];
        if (tag is! String || type is! String) continue;
        if (!isNodeEndpoint(type)) continue;
        if (!entities.contains(tag)) stale.add(tag);
      }
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
/// ## endpoints 段（批次 9，`docs/design/wireguard-endpoint-2026-09-18.md` §3.2）
///
/// 实体按 [isNodeEndpoint] 拆两桶：普通节点走 outbounds 段（上述规则），
/// endpoint 实体（type=wireguard）走 `config['endpoints']` —— 内核 1.13 起 wireguard
/// outbound 是 stub，endpoint 是唯一合法形态，且内核 `setOutbounds` 会原样处理
/// `input.Endpoints`（`builder.go:220-257`）。endpoint 实体的覆盖/追加/删除判据与
/// outbounds 段完全同构。基准 outbounds 里若有 legacy `type==wireguard`（K1：留着
/// 这份配置必炸），一律剔除（计入 removed）—— 这是"剔除救活订阅"，不是数据丢失。
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

  // 实体拆两桶：普通节点 → outbounds 段；endpoint 类 → endpoints 段
  // （判据只有一处：`runtime_outbound_tags.isNodeEndpoint`，与派生/解析同一份）
  final nodeEntities = <ImportedProxyEntity>[];
  final endpointEntities = <ImportedProxyEntity>[];
  for (final entity in entities) {
    if (isNodeEndpoint(entity.type)) {
      endpointEntities.add(entity);
    } else {
      nodeEntities.add(entity);
    }
  }

  // 普通节点的 tag → 完整出站定义
  final payloadByTag = <String, Map<String, dynamic>>{};
  for (final entity in nodeEntities) {
    try {
      final decoded = jsonDecode(entity.payload);
      if (decoded is Map<String, dynamic>) payloadByTag[entity.tag] = decoded;
    } catch (_) {
      // 单条坏 payload 不该毁掉整份配置：跳过它
    }
  }
  final entityTags = nodeEntities.map((e) => e.tag).where(payloadByTag.containsKey).toList();

  // 节点级**出站覆写**（切片 8.5，NekoBox `ConfigBuilder.kt:404`
  // `_hack_custom_config = bean.customOutboundJson`）：深合并进该节点的出站 JSON。
  // 合并失败（坏 JSON）按无覆写处理 —— 覆写不该让节点整个失效；
  // `tag` 由本模块管理（NekoBox 同样在合并前把 tag 写进 `_hack_config_map`），覆写里写了也不影响。
  // 普通节点与 endpoint 实体各一份索引（两段同构套用）。
  Map<String, Map<String, dynamic>> overlayIndexFor(List<ImportedProxyEntity> bucket) {
    final index = <String, Map<String, dynamic>>{};
    for (final entity in bucket) {
      final raw = entity.customOutbound.trim();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) index[entity.tag] = decoded;
      } catch (_) {
        // 坏覆写：跳过（等价于停用），不记进组装结果
      }
    }
    return index;
  }

  final outboundOverlayByTag = overlayIndexFor(nodeEntities);
  final endpointOverlayByTag = overlayIndexFor(endpointEntities);

  // endpoint 实体的 tag → 完整 endpoint 定义（判据与 outbounds 段同构）
  final endpointPayloadByTag = <String, Map<String, dynamic>>{};
  for (final entity in endpointEntities) {
    try {
      final decoded = jsonDecode(entity.payload);
      if (decoded is Map<String, dynamic>) endpointPayloadByTag[entity.tag] = decoded;
    } catch (_) {}
  }
  final endpointEntityTags = endpointEntities.map((e) => e.tag).where(endpointPayloadByTag.containsKey).toList();

  final isEndpointsOnly = payloadByTag.isEmpty && endpointPayloadByTag.isNotEmpty;
  if (payloadByTag.isEmpty && !isEndpointsOnly) return null;

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
    // legacy wireguard outbound 必剔除：内核 1.13 的 stub 启动即报错（K1），
    // 留着 = 整份配置连不上。endpoint 实体已在 endpoints 段接管 wireguard。
    if (tag is String && kEndpointOutboundTypes.contains(type)) {
      removed++;
      continue;
    }
    if (tag is String && payloadByTag.containsKey(tag)) {
      final payload = payloadByTag[tag]!;
      final overlay = outboundOverlayByTag[tag];
      // 覆写合并（切片 8.5）：在 payload 替换基准之后做（NekoBox 的合并发生在
      // Bean → 出站序列化时，等价于"节点定义完成后的最后一步"）。deepMergeJson
      // 就地修改 payload —— payloadByTag 的值是本函数私有解码产物，无副作用。
      if (overlay != null) deepMergeJson(payload, overlay);
      result.add(payload);
      replaced++;
      continue;
    }
    if (tag is String && stale.contains(tag)) {
      removed++;
      continue;
    }
    result.add(outbound);
  }

  // 基准里没有的节点实体 → 追加（内核按输入顺序收集 tag，所以新节点排在末尾）
  final presentTags = {for (final o in result) o['tag']};
  var added = 0;
  for (final tag in entityTags) {
    if (!presentTags.contains(tag)) {
      final payload = payloadByTag[tag]!;
      // 追加的实体同样套用出站覆写（手动新建的节点都在这里，覆写却常用在它们身上）
      final overlay = outboundOverlayByTag[tag];
      if (overlay != null) deepMergeJson(payload, overlay);
      result.add(payload);
      added++;
    }
  }

  config['outbounds'] = result;

  // ── endpoints 段 ──
  // 覆盖/删除按 tag（与 outbounds 段同构）；基准没有的 endpoint 实体追加在末尾。
  // 基准无 endpoints 段且有 endpoint 实体 ⇒ 新建数组；反之基准段原样保留。
  final rawEndpoints = config['endpoints'];
  final existingEndpoints = rawEndpoints is List ? rawEndpoints.whereType<Map<String, dynamic>>().toList() : <Map<String, dynamic>>[];
  final endpointResult = <Map<String, dynamic>>[];
  for (final endpoint in existingEndpoints) {
    final tag = endpoint['tag'];
    final type = endpoint['type'];
    // 删除判据与 stale 同思路：基准里的 wireguard endpoint，实体集合没有 ⇒ 删。
    // （订阅更新后 wg endpoint 下线的对应物。）
    if (tag is String && type is String && isNodeEndpoint(type)) {
      if (!endpointPayloadByTag.containsKey(tag) && stale.contains(tag)) {
        removed++;
        continue;
      }
    }
    if (tag is String && endpointPayloadByTag.containsKey(tag)) {
      final payload = endpointPayloadByTag[tag]!;
      // endpoint 实体的覆写同构套用（批次 8.5）
      final overlay = endpointOverlayByTag[tag];
      if (overlay != null) deepMergeJson(payload, overlay);
      endpointResult.add(payload);
      replaced++;
      continue;
    }
    endpointResult.add(endpoint);
  }
  final presentEndpointTags = {for (final e in endpointResult) e['tag']};
  for (final tag in endpointEntityTags) {
    if (!presentEndpointTags.contains(tag)) {
      final payload = endpointPayloadByTag[tag]!;
      final overlay = endpointOverlayByTag[tag];
      if (overlay != null) deepMergeJson(payload, overlay);
      endpointResult.add(payload);
      added++;
    }
  }
  if (endpointResult.isNotEmpty || rawEndpoints is List) {
    config['endpoints'] = endpointResult;
  }

  return ConfigAssemblyResult(
    configJson: jsonEncode(config),
    replaced: replaced,
    added: added,
    removed: removed,
  );
}
