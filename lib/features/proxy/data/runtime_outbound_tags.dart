// 内核重建出来的出站 tag —— **常量**，与订阅里的组名无关。
//
// 依据 `hiddify-core/v2/config/builder.go:37-43`：
//   OutboundDirectTag         = "direct §hide§"
//   OutboundBypassTag         = "bypass §hide§"
//   OutboundBlockTag          = "block §hide§"
//   OutboundSelectTag         = "select"
//   OutboundURLTestTag        = "lowest"
//   OutboundRoundRobinTag     = "balance"
//   OutboundDNSTag            = "dns-out §hide§"
//   OutboundDirectFragmentTag = "direct-fragment §hide§"
//   WARPConfigTag             = "🔒 WARP"
//
// ## 为什么需要这个文件
//
// 内核每次启动都会**丢弃输入里的所有组**（`builder.go:154-164`），只用节点，然后自建一个
// selector（tag = `select`）与两个 balancer（`balance` / `lowest`），并把 `route.final`
// 设成 `select`。所以应用要"对内核说话"时必须用这些常量，而不是订阅里的组名：
//
//   · 切节点 ⇒ `SelectOutboundRequest(groupTag: select, outboundTag: <节点tag>)`。
//     传订阅组名会被拒：`commands.go` 的 `SelectOutbound` 实现是
//     `box.Outbound().Outbound(in.GroupTag)`，找不到就返回 `selector not found: <组名>`。
//   · 测整组 ⇒ `UrlTestRequest(tag: "")`，内核自己在 `in.Tag == ""` 时走 `UrlTestActive`
//     （内部硬编码用 `select`）。传组名会被当成**节点 tag** 去 `monitor.TestNow(组名)`。
//   · 测单节点 ⇒ `UrlTestRequest(tag: <节点tag>)`。
//
// ## 与 NekoBox 的对应
//
// NekoBox 的等价物是 `fmt/ConfigBuilder.kt:44` 的常量 `TAG_PROXY = "proxy"`，配上
// `ConfigBuildResult.profileTagMap`（实体 id → 配置 tag）—— 映射在**构建期**产出、随配置
// 一起携带，运行期靠它把 `DataStore.selectedProxy`（实体 id）翻译成 `selectOutbound(tag)`。
// 一句话：**映射不靠 tag 相等，靠构建期建立的绑定。** 本项目直接沿用内核自己的常量，
// 不另造名字。
//
// 纯 Dart（不 import drift/Flutter），可被 `dart run` 校验。

/// 主 selector（内核 `OutboundSelectTag`）。`route.final` 指向它，切节点也发给它。
const kRuntimeSelectorTag = 'select';

/// urltest balancer（内核 `OutboundURLTestTag`，strategy = `lowest-delay`）。
const kRuntimeLowestTag = 'lowest';

/// round-robin balancer（内核 `OutboundRoundRobinTag`，strategy = `opt.BalancerStrategy`）。
const kRuntimeBalanceTag = 'balance';

/// 隐藏出站（tag 里带 `§hide§`，不出现在内核的 tag 列表里）。
const kRuntimeDirectTag = 'direct §hide§';
const kRuntimeDirectFragmentTag = 'direct-fragment §hide§';
const kRuntimeDnsOutTag = 'dns-out §hide§';

/// WARP 端点（`Warp.EnableWarp` 为真时内核才加）。
const kRuntimeWarpTag = '🔒 WARP';

/// 内核**自己重建**的组 tag —— 它们不是用户能选的节点。
const kRuntimeGroupTags = {kRuntimeSelectorTag, kRuntimeLowestTag, kRuntimeBalanceTag};

/// tag 里带 `§hide§` 表示"不出现在组内列表"（内核 `builder.go:178`、`:252`）。
bool isHiddenTag(String tag) => tag.contains('§hide§');

// ---------------------------------------------------------------------------
// 「什么算一个节点」—— **唯一判据**（NekoBox `group/RawUpdater.kt:768-787` 的过滤名单）
//
// 这一份判据有三个消费者，必须完全一致，否则"派生出哪些节点"与"该删哪些节点"会漂移：
//   · 派生实体（`proxy_entity_import.deriveProxyGroupFromConfig`）
//   · 从配置文本解析列表（`offline_proxy_parser.parseSubscriptionGroup`）
//   · 组装时的删除判据（`config_assembly.staleNodeTags`，见审计 F1）
// 所以定义放在这里一处，别处一律引用。
// ---------------------------------------------------------------------------

/// 组类出站：内核每次启动都会丢弃输入里的组并重建（`builder.go:154-164`）。
const kGroupOutboundTypes = {'selector', 'urltest', 'balancer'};

/// 内置出站类型：不是订阅节点（NekoBox 的同一份过滤名单里也排除它们）。
const kInternalOutboundTypes = {'dns', 'block', 'direct'};

/// **endpoint 类出站**（批次 9，`docs/design/wireguard-endpoint-2026-09-18.md`）：
///
/// 内核 1.13 起 wireguard outbound 是 stub（`include/registry.go:200-201` 注册为
/// `StubOptions`，启动即报错指向 endpoint）—— 配置里 `type=="wireguard"` 的条目
/// **只可能活在 `endpoints` 段**（`WireGuardEndpointOptions`），不该再被当成
/// outbounds 节点派生/透传。
///
/// 与 NekoBox 的差异（记档）：NekoBox 那份 `buildSingBoxOutboundWireguardBean`
/// 产 legacy `Outbound_WireGuardOptions`（outbound 形态），pin 的是旧内核；
/// 本项目按**内核现实**走 endpoint 形态（同 mieru `portBindings[0]` 的处理先例）。
const kEndpointOutboundTypes = {'wireguard'};

/// 这条出站**是不是订阅节点** —— 也就是"实体层该管的那一段"。
///
/// 判据 = 不是组、不是内置类型、不是 endpoint 类、tag 不带 `§hide§`。
/// ⚠️ 不要改用"看起来像节点"的其他启发式：内核会加 `🔒 WARP` 这类
/// 既不是组、也不带 `§hide§` 的出站（`WARPConfigTag`），按形状猜会误删它。
bool isNodeOutbound({required String tag, required String type}) =>
    !isHiddenTag(tag) &&
    !kGroupOutboundTypes.contains(type) &&
    !kInternalOutboundTypes.contains(type) &&
    !kEndpointOutboundTypes.contains(type);

/// 这条配置条目**是不是一个 endpoint 节点**（[isNodeOutbound] 的姊妹判据）。
///
/// `endpoints` 段里的条目没有 outbounds 的组/内置类型概念，判据只需 type。
/// endpoint tag 同样能被内核的 selector/balancer 收编
///（`adapter.Endpoint` 内嵌 `Outbound`；`outbound/manager.go:201-209` 回落 `endpoint.Get`）。
bool isNodeEndpoint(String type) => kEndpointOutboundTypes.contains(type);
