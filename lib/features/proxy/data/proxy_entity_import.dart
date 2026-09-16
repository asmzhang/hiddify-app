// 实体导入：把「生成好的配置」派生为 NekoBox 式的分组 + 节点实体。
//
// 规格来源：NekoBoxForAndroid 的实体模型
//   · `database/ProxyGroup.kt`   —— id/name/type(GroupType.BASIC|SUBSCRIPTION)/
//                                    order/isSelector/ungrouped/frontProxy/landingProxy
//   · `database/ProxyEntity.kt`  —— id/groupId/type/userOrder/tx/rx/status/ping/uuid/error
//                                    + 每个协议一个 Bean（序列化整条出站定义）
//   · `ktx/Formats.kt:106 parseProxies` —— NekoBox 导入订阅时**逐行解析分享链接**
//   · 全代码不引用 `proxy-groups` ⇒ **订阅内的分组不占实体**，分组只有两种来源：
//     订阅（= 一个 group）与手动新建
//
// hiddify 侧的做法（复用既有能力，不新造解析器）：内核 `Parse` 返回的配置文本里
// 含每个出站的完整定义（凭据在内），从它派生实体即可 —— 这正是节点卡「复制出站 JSON」
// 已经在用的那条链路（`extractOutboundJson`）。序列化用 JSON 而非 NekoBox 的 Kryo，
// 语义相同（一对一承载 Bean 的内容）。
//
// 本文件是 8.4（实体层）的第一步：**先证明凭据与结构可落库**，再动 drift schema。
import 'dart:convert';

import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';

/// 一条**节点实体**（对应 NekoBox `ProxyEntity` 的一行）。
///
/// 只保留与"从配置派生"有关的部分：tag 即 NekoBox 的 `uuid`/name 字段位
/// （NekoBox 用 `uuid` 列存显示名），`payload` 对应它的协议 Bean。
class ImportedProxyEntity {
  const ImportedProxyEntity({required this.tag, required this.type, required this.payload, required this.displayName});

  /// 出站 tag（配置里的唯一标识）。
  final String tag;

  /// 出站类型（anytls / vless / hysteria2 / …），对应 NekoBox 的 `type:Int` + Bean 种类。
  final String type;

  /// **完整出站 JSON（含凭据）** —— 对应 NekoBox 的协议 Bean。
  final String payload;

  /// 显示名（去掉 `§` 后缀），对应 NekoBox 的 `displayName()`。
  final String displayName;

  @override
  String toString() => 'ImportedProxyEntity($type, $tag)';
}

/// 一个**分组实体**（对应 NekoBox `ProxyGroup` 的一行）。
///
/// 派生规则照 NekoBox：**一份订阅 = 一个 group**（`GroupType.SUBSCRIPTION`）。
/// 配置里的 selector/urltest/balancer **不产生 group** —— NekoBox 里那是
/// `ConfigBuilder` 依据 `group.isSelector` 生成出来的，不是用户可见的分组。
class ImportedProxyGroup {
  const ImportedProxyGroup({required this.name, required this.isSubscription, required this.isSelector, required this.entities});

  final String name;

  /// true = 订阅派生（NekoBox `GroupType.SUBSCRIPTION`）；false = 手动新建（`BASIC`）。
  final bool isSubscription;

  /// 是否把该组建成 selector（`ConfigBuilder` 据它生成 selector 出站）。
  final bool isSelector;

  final List<ImportedProxyEntity> entities;

  @override
  String toString() => 'ImportedProxyGroup($name, ${entities.length} entities)';
}

/// `proxy_groups.subscription` 这段 JSON 的读写口径。
///
/// 为什么把 `profileId` 记在这里：NekoBox 的订阅信息整体存在 `SubscriptionBean` 里，
/// 本项目仍保留 `ProfileEntries` 作为订阅源，所以需要一个"这份订阅 ↔ 哪个分组"的反查键。
/// 放在这段 JSON 里就不必为了一个外键再动一次 schema。
///
/// 这两个函数刻意放在**纯 Dart** 的这一层（不 import drift）—— 与
/// `offline_proxy_parser.dart` 同样的理由：能被 `dart run` 直接校验。
String encodeSubscriptionPayload({required String profileId, required String profileName, DateTime? lastUpdate}) =>
    jsonEncode({
      'profileId': profileId,
      'name': profileName,
      if (lastUpdate != null) 'lastUpdate': lastUpdate.toIso8601String(),
    });

/// 从 `subscription` JSON 里取 `profileId`；不是订阅派生的分组、或格式不对时返回 null。
String? profileIdOfSubscription(String? subscriptionJson) {
  if (subscriptionJson == null || subscriptionJson.isEmpty) return null;
  try {
    final decoded = jsonDecode(subscriptionJson);
    if (decoded is! Map) return null;
    final id = decoded['profileId'];
    return id is String && id.isNotEmpty ? id : null;
  } catch (_) {
    return null;
  }
}

// ───────────────────────────────────────────────────────────────────────────
// 去重判重键（NekoBox `Protocols.Deduplication.hash()` 的等价物，
// `moe/matsuri/nb4a/Protocols.kt`）：
//   NekoBox 口径 = `serverAddress + serverPort + type`（名字不参与，凭据不参与 ——
//   同地址同端口换密码在它那里也算重复）。hiddify 的对应物是出站 JSON 的
//   `server` + `server_port` + 实体 `type`。分隔符用 `|` 防"1.2.3.4"+"5" 与
//   "1.2.3"+"45" 这类字符串拼接撞车。
// 刻意留在纯 Dart 层（同 [encodeSubscriptionPayload] 的理由）：能被 dart run 直接校验。
// ───────────────────────────────────────────────────────────────────────────

/// 节点的判重键；payload 解析不出地址/端口时返回 null（判重时放行，不误删）。
String? dedupKeyOf({required String payload, required String type}) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map<String, dynamic>) return null;
    final server = decoded['server'];
    final port = decoded['server_port'];
    if (server is! String || server.isEmpty || port is! int) return null;
    return "$server|$port|$type";
  } catch (_) {
    return null;
  }
}

/// 背景补齐实体时**需要同步哪些订阅**（保持 [allIds] 的入参顺序）。
///
/// 为什么需要它：实体落库挂在"订阅写入"这条咽喉上（见 `proxy_entity_repository.dart`），
/// 所以**在实体表存在之前就已导入的订阅**不会自己长出实体 —— 表是空的，第 3/4 步
/// 整条链路实际上没被走过。回填就是在应用启动后把这些订阅补一遍。
///
/// 判据只有一条：**库里已有该订阅的分组 ⇒ 跳过**。于是它是幂等的，第二次运行就是一次
/// 廉价的 DB 读（NekoBox 的 `GroupManager` 同样是"有组就不重建"）。
///
/// 刻意放在纯 Dart 层：它能被 `dart run` 直接校验（同 `encodeSubscriptionPayload`）。
List<String> missingEntityProfileIds({required Iterable<String> allIds, required Set<String> synced}) {
  final missing = <String>[];
  final seen = <String>{};
  for (final id in allIds) {
    if (id.isEmpty) continue;
    if (synced.contains(id)) continue;
    if (!seen.add(id)) continue; // 入参重复时不重复产出
    missing.add(id);
  }
  return missing;
}

/// 从**生成好的配置**派生「一个订阅分组 + 它的节点实体」。
///
/// 排除规则与 `parseOfflineProxyGroups` 一致，且照 NekoBox 的口径：
/// - 分组类出站（selector/urltest/balancer）不成为实体（它们由 `isSelector` 生成）
/// - `direct` / `block` / `dns` 不是节点
/// - tag 含 `§hide§` 的内部出站（如 `direct §hide§`）不是节点
///
/// 解析失败或无可用节点时返回 null（由调用方决定提示，不抛异常）。
ImportedProxyGroup? deriveProxyGroupFromConfig({
  required String profileName,
  required String configJson,
  bool isSelector = true,
}) {
  try {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final outbounds = (config['outbounds'] as List?)?.whereType<Map<String, dynamic>>().toList();
    if (outbounds == null || outbounds.isEmpty) return null;

    final entities = <ImportedProxyEntity>[];
    for (final outbound in outbounds) {
      final tag = outbound['tag'];
      final type = outbound['type'];
      if (tag is! String || type is! String) continue;
      // 「是不是节点」只有一处判据（`runtime_outbound_tags.isNodeOutbound`）——
      // 派生、解析列表、组装时删除三处必须用同一份，否则边界会漂移（审计 F1/F3）。
      if (!isNodeOutbound(tag: tag, type: type)) continue;
      entities.add(
        ImportedProxyEntity(
          tag: tag,
          type: type,
          // 整条出站原样留存 —— 凭据（password/uuid/private_key/TLS 等）都在里面
          payload: jsonEncode(outbound),
          displayName: trimTagName(tag),
        ),
      );
    }
    if (entities.isEmpty) return null;

    return ImportedProxyGroup(
      name: profileName,
      isSubscription: true,
      isSelector: isSelector,
      entities: entities,
    );
  } catch (_) {
    return null;
  }
}
