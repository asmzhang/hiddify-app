import 'dart:convert';

import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

/// 离线清单的解析 —— **纯 Dart，不依赖 Flutter**。
///
/// 单独一个文件是为了能用 `dart run` 直接验证（`flutter test` 要起 flutter_tester，
/// 在受限环境里跑不起来）。解析逻辑本来也不需要 UI，拆出来更好测。

/// 把「一份订阅的配置」抽成**它唯一的分组**：组名 = 订阅名，成员 = 该订阅的全部节点。
///
/// ## 为什么不是"配置里的分组"（**以 NekoBox 为准**）
///
/// NekoBox 的组只有两种，且订阅内的分组**不成为分组**：
/// - `Constants.kt`：`object GroupType { BASIC = 0; SUBSCRIPTION = 1 }` —— 组类型**只有这两种**，
///   没有"自动选择 / urltest"这种分组；
/// - `group/RawUpdater.kt:768-787`：订阅内容是 sing-box 配置（`json.has("outbounds")`）时，
///   它把 `dns` / `block` / `direct` / `selector` / `urltest` **逐个过滤掉**，只留真节点
///   ⇒ 一份订阅产出**一个** group，成员是它的全部节点；
/// - 组名按 `database/ProxyGroup.kt` 的 `displayName()`（`name` 为空才用默认名）——
///   订阅组的名字就是**订阅名**。
///
/// 所以 `节点选择` / `自动选择` 这类配置内分组在 NekoBox 里根本不存在：它们既不做 Tab、
/// 也不出现在列表里。旧实现把它们当成"分组 Tab"，于是代理页凭空多出一栏 `自动选择` ——
/// 那是 hiddify/sing-box 的内部概念，不是用户的分组。
///
/// 解析失败、或过滤后没有可用节点时返回 null（由调用方决定如何提示，不抛异常）。
OutboundGroup? parseSubscriptionGroup(String configJson, {required String groupName, void Function(String)? log}) {
  void warn(String message) => log?.call(message);
  try {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final outbounds = (config['outbounds'] as List?)?.whereType<Map<String, dynamic>>();
    if (outbounds == null || outbounds.isEmpty) {
      warn("offline proxies: config has no outbounds (keys: ${config.keys.join(",")})");
      return null;
    }

    final group = OutboundGroup()
      ..tag = groupName
      ..type = 'Selector'
      // 选中是**独立于配置的持久偏好**（NekoBox `DataStore.selectedProxy`），
      // 由调用方按需补上；配置里的 `default` 不是它。
      ..selected = '';

    for (final outbound in outbounds) {
      final tag = outbound['tag'];
      final type = outbound['type'];
      if (tag is! String || type is! String) continue;
      // 组类出站不是节点（NekoBox 的 `selector` / `urltest`；`balancer` 是内核多出来的同类）
      if (kGroupOutboundTypes.contains(type)) continue;
      // NekoBox 的同一份过滤名单里还有这三个
      if (kInternalOutboundTypes.contains(type)) continue;
      // hiddify 侧的内部出站（`direct §hide§` 之类）不算节点
      if (isHiddenTag(tag)) continue;
      // 地址同样取自配置里的 server/server_port —— 与实体来源同一个口径
      // （节点卡第 2 行是"Bean 字段"，不是运行期，见 [displayAddress]）
      final server = outbound['server'];
      final serverPort = outbound['server_port'];
      group.items.add(
        outboundInfo(
          tag,
          type,
          false,
          host: server is String ? server : '',
          port: serverPort is int ? serverPort : 0,
        ),
      );
    }

    if (group.items.isEmpty) {
      warn("offline proxies: no usable outbound (types: ${outbounds.map((o) => o['type']).join(",")})");
      return null;
    }
    return group;
  } catch (e) {
    warn("offline proxies: parse failed");
    return null;
  }
}

/// 显示名规则，镜像核心 `proxy_info.go` 的 `TrimTagName`：
/// ```go
/// func TrimTagName(tag string) string { return strings.Trim(strings.Split(tag, "§")[0], " ") }
/// ```
String trimTagName(String tag) => tag.split('§').first.trim();

/// 构造一项，**必须同时填 `tagDisplay` 和 `isVisible`** ——
/// 它们是独立字段，不填的话列表会出现空名字、以及 direct/dns 这类内部项。
///
/// [displayName] 只在"实体行已经存了显示名"时传入（见 [buildGroupFromEntityNodes]）；
/// 从配置文本构造时按内核 `TrimTagName` 现场算。
/// [host] / [port] 是节点卡第 2 行的「地址」，来源见 [serverAddressOfPayload]。
/// [testDelayOverride] 是实体的测速结果编码（[encodeOfflineTestResult]），
/// 非零时覆盖默认的 0 —— 断开状态下的延迟/错误显示就是它。
OutboundInfo outboundInfo(
  String tag,
  String type,
  bool selected, {
  String? displayName,
  String host = '',
  int port = 0,
  int testDelayOverride = 0,
}) => OutboundInfo()
  ..tag = tag
  ..type = type
  ..tagDisplay = displayName ?? trimTagName(tag)
  ..isVisible = !isHiddenTag(tag)
  ..isGroup = kGroupOutboundTypes.contains(type)
  ..isSelected = selected
  ..host = host
  ..port = port
  // 未连接时没有实测延迟；0 在 UI 上就是"—"
  ..urlTestDelay = testDelayOverride;

/// 一条**实体行**里与构造清单有关的字段（纯 Dart，不与 drift 耦合）。
///
/// [status]/[ping]/[error] 是实体的测速结果列（NekoBox 同名三列，TCP ping /
/// 内核 urltest 的落点）；未测速时 status=0。构造清单时经 [encodeOfflineTestResult]
/// 编码进 `urlTestDelay`（见该函数的编码表）。
typedef EntityNodeRow
    = ({String tag, String type, String displayName, String payload, int status, int ping, String? error});

// ───────────────────────────────────────────────────────────────────────────
// 离线测速结果的显示编码。
//
// 为什么编码进 `urlTestDelay`：`OutboundInfo` 是生成的 protobuf（不加字段），
// 而节点卡的状态位只读它。约定：
//   0  = 未测速（显示 "—"）
//   >0 = 延迟 ms（正常三态显示）
//   <0 = 不可用，按错误分类编码（NekoBox `status>=2` 显示错误文案的对应物）：
//        -1 refused / -2 unreachable / -3 timeout / -4 domain_not_found / -5 其他
// 连接状态下实时贴值（`joinLiveIntoGroup`）会覆盖之 —— 与 NekoBox 的
// "连上后以内核测速为准" 一致。
// 纯函数，可被 dart run 校验（check_tcp_ping.dart）。
// ───────────────────────────────────────────────────────────────────────────

/// 实体测速三列 → `urlTestDelay` 编码。
int encodeOfflineTestResult({required int status, required int ping, String? error}) {
  if (status <= 0) return 0;
  if (status == 1) return ping;
  return switch (error) {
    'refused' => -1,
    'unreachable' => -2,
    'timeout' => -3,
    'domain_not_found' => -4,
    _ => -5,
  };
}

/// `urlTestDelay` 编码 → 本地化文案键（null = 不是错误编码）。
String? offlineTestErrorKey(int encodedDelay) => switch (encodedDelay) {
  -1 => 'testRefused',
  -2 => 'testUnreachable',
  -3 => 'testTimeout',
  -4 => 'testDomainNotFound',
  -5 => 'testUnreachable', // 未分类错误：NekoBox 对未知错误也归"不可用"一档
  _ => null,
};


/// 从实体 `payload` 里取服务器地址。
///
/// 为什么地址要来自实体而不是运行期：NekoBox 的节点卡第 2 行是
/// `proxyEntity.displayAddress()` → `AbstractBean.displayAddress()`
/// = `wrapIPV6Host(serverAddress) + ":" + serverPort`（**Bean 里的字段**，见
/// `fmt/AbstractBean.java`、`ktx/Nets.kt`）。内核的 `OutboundInfo` 不给 host/port
/// （实测：Clash API 的 `/proxies` 也只有 type/name/udp），照抄运行期就会显示成 `:0`。
///
/// 已知不含：`server_ports`（端口区间写法，hysteria2 的 range 形态）——
/// 本项目的真实订阅里 132 个节点全部是 `server` + `server_port`，暂不处理。
({String host, int port}) serverAddressOfPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is! Map) return (host: '', port: 0);
    final host = decoded['server'];
    final port = decoded['server_port'];
    return (host: host is String ? host : '', port: port is int ? port : 0);
  } catch (_) {
    return (host: '', port: 0);
  }
}

/// 地址行的文本 —— 镜像 NekoBox `AbstractBean.displayAddress()` + `ktx/Nets.kt` 的
/// `wrapIPV6Host`：IPv6 加方括号，其余原样（`isIpAddressV6` 这里用"含冒号"近似，
/// 域名不会带冒号，语义等价）。
String displayAddress(String host, int port) {
  final unwrapped = host.startsWith('[') && host.endsWith(']') ? host.substring(1, host.length - 1) : host;
  final wrapped = unwrapped.contains(':') ? '[$unwrapped]' : host;
  return '$wrapped:$port';
}

/// 由**实体行**构造展示用分组 —— 列表的另一个来源。
///
/// 对应 NekoBox `fmt/ConfigBuilder.kt:131` 的 `proxyDao.getByGroup(group.id)`：
/// **列表以数据库为准**。本项目把实体表当权威之后，"删除节点 / 编辑节点"才能立刻可见，
/// 而不是等下一轮订阅解析。与 [parseSubscriptionGroup] 产出的形状完全一致
/// （组名 = 订阅名、成员 = 全部节点、顺序照库里的 `userOrder`）。
///
/// 选中一律留空：选中是独立于列表来源的**持久偏好**（`SelectedProxyStore`），由调用方补。
OutboundGroup buildGroupFromEntityNodes({required String groupName, required List<EntityNodeRow> nodes}) {
  final group = OutboundGroup()
    ..tag = groupName
    ..type = 'Selector'
    ..selected = '';
  for (final node in nodes) {
    final address = serverAddressOfPayload(node.payload);
    group.items.add(
      outboundInfo(
        node.tag,
        node.type,
        false,
        displayName: node.displayName,
        host: address.host,
        port: address.port,
        // 断开状态下列表显示实体的测速结果（NekoBox 的 status/ping 列同样直接上屏）；
        // 连接状态下 joinLiveIntoGroup 用内核实时值覆盖。
        testDelayOverride: encodeOfflineTestResult(status: node.status, ping: node.ping, error: node.error),
      ),
    );
  }
  return group;
}

/// 按 tag 抽出**单条出站的原始 JSON**（节点卡「分享」动作的数据源）。
///
/// 为什么不做成"节点分享链接"：hiddify 侧只有"订阅链接 → 配置"的正向转换
/// （ray2sing），**没有**"出站 → 分享链接"的逆向转换。硬拼一个链接出来是伪造，
/// 所以这里给出的是可粘贴、可核对的出站定义本身。
///
/// 找不到该 tag、或配置不是合法 JSON 时返回 null，由调用方决定如何提示。
String? extractOutboundJson(String configJson, String tag) {
  try {
    final config = jsonDecode(configJson) as Map<String, dynamic>;
    final outbounds = (config['outbounds'] as List?)?.whereType<Map<String, dynamic>>();
    if (outbounds == null) return null;
    for (final outbound in outbounds) {
      if (outbound['tag'] == tag) return prettyOutboundJson(outbound);
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// 单条出站定义的**可读 JSON**（两个来源共用：配置文本抽出的对象 / 实体表的 `payload` 字符串）。
/// 输入非法时返回 null。
String? prettyOutboundJson(Object? raw) {
  if (raw == null) return null;
  try {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } catch (_) {
    return null;
  }
}
