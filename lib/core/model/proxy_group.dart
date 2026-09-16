// 分组实体的两个枚举。
//
// 规格来源：NekoBoxForAndroid
//   · `GroupType`（`database/ProxyGroup.kt`）      —— BASIC / SUBSCRIPTION
//   · `GroupOrder`（`database/ProxyGroup.kt`，见 `ui/ConfigurationFragment.kt` 的排序菜单）
//                                                   —— ORIGIN / BY_NAME / BY_DELAY
//
// 放在 `core/model/` 是因为 drift 表要用它（照 `profile_type.dart` /
// `per_app_proxy_mode.dart` 的先例：db 需要的枚举下沉到 core，features 层保留 export）。
//
// 差异说明：NekoBox 用 `Int` 存这两个值；这里用 drift 的 `textEnum`（存枚举名），
// 语义相同、可读性更好，也与本项目既有表（`ProfileEntries.type`、`AppProxyEntries.mode`）一致。

/// 分组类型。对应 NekoBox `GroupType`。
enum ProxyGroupType {
  /// 手动新建的分组（NekoBox `GroupType.BASIC`）。
  basic,

  /// 由订阅创建的分组（NekoBox `GroupType.SUBSCRIPTION`）。
  subscription,
}

/// 分组内的节点排序方式。对应 NekoBox `GroupOrder`。
///
/// 注意：NekoBox 把它存在**分组**上（每个分组各自一个排序），本项目此前把它存在
/// preferences 的 `proxies_sort_by_group` 里（`"<groupKey>=<sortName>"` 串联）。
/// 有了实体之后应当迁到这里（见 docs/design/nekobox-parity.md §8.6）。
enum ProxyGroupOrder {
  /// 保持订阅给的原始顺序（NekoBox `GroupOrder.ORIGIN`，默认值）。
  origin,

  /// 按名称（`GroupOrder.BY_NAME`）。
  byName,

  /// 按延迟，未测速的排最后（`GroupOrder.BY_DELAY`）。
  byDelay,
}
