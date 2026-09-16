// 「期望选中的节点」与「内核当前选中」的校准决策。
//
// ## 为什么需要校准（而不是"应用一次就清空"）
//
// NekoBox 的选中项能在重启后保持，靠的是**构建期**把它写进 selector 的 `default`：
// `fmt/ConfigBuilder.kt:471` `default_ = tagMap[proxy.id]`（`proxy` 就是
// `DataStore.selectedProxy` 指向的那个实体）。加上 `DataStore.kt:36`
// `var selectedProxy by configurationStore.long(Key.PROFILE_ID)` 是**持久偏好**，
// 于是"选中 → 重启 → 仍是它"是自然结果，服务侧不需要额外补一刀。
//
// hiddify 内核把 selector 的 `default` 写死成 `balance`（`v2/config/builder.go:311-341`：
// 多于一个节点时 `defaultSelect = balancer.Tag`，WARP 模式是 `urlTest.Tag`），
// **应用拿不到这个口子**（`enable_raw_config` 那条路会丢掉内核生成的 inbounds/dns/route，
// 见 docs/design/nekobox-parity.md §8.6.8）。所以只能在**每次内核 ready 之后**补一次
// `selectOutbound` —— 这一刀对应 NekoBox 的 `bg/BaseService.kt:184-193`（`reload()` 里
// 的 `box.selectOutbound(tag)` 热切换路径）。
//
// ## 两个方向（都照 NekoBox，缺一个就会变成机器人）
//
//   · **下发期望值** —— 内核当前停在它自己的默认（`balance` / `lowest` = 没人选过）
//     ⇒ 这就是"内核刚起来"的指纹，把期望值应用上去。
//   · **采纳内核的选中** —— 内核选中是个具体节点且与期望不同 ⇒ 那是**外部决定的**
//     （yacd / webui 等）。采纳并回写，等价于 NekoBox 的
//     `moe/matsuri/nb4a/NativeInterface.kt:84-105` `selector_OnProxySelected` →
//     `cbSelectorUpdate(id)` → `ui/MainActivity.kt:416-423` 回写 `DataStore.selectedProxy`。
//     不做这一步的话，用户从网页面板改一次就会被我们按回去。
//
// 纯 Dart（不 import drift/Flutter），可被 `dart run tool/check_selection_reconcile.dart` 校验。
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';

/// 校准时要做的动作。
enum SelectionReconcileAction {
  /// 什么都不做：还没选过 / 已经一致 / 这个节点不在内核当前配置里。
  none,

  /// 把期望值下发给内核（`SelectOutbound(groupTag: select, outboundTag: desired)`）。
  applyDesired,

  /// 内核的选中被外部改了 ⇒ 采纳它并回写偏好。
  adoptKernel,

  /// 期望值属于另一份订阅 ⇒ 等内核换成那份配置再动（内核一次只加载一份）。
  waitForProfile,
}

/// 内核"没人选过"时的默认选中值。
///
/// 依据 `v2/config/builder.go:311-331`：`len(tags) > 1` 时 `defaultSelect = balancer.Tag`
/// （`balance`）；WARP 模式下先插 `urlTest` 且 `defaultSelect = urlTest.Tag`（`lowest`）。
/// 只有一个节点时 default 就是那个节点本身，那时 `desired == kernelSelected`，走 [none]。
const kKernelDefaultSelectionTags = {kRuntimeBalanceTag, kRuntimeLowestTag};

/// 决定该做什么。**判断顺序即优先级**（都有断言覆盖）：
///
/// 1. 没有期望值 → [none]（内核的默认就是当前事实）
/// 2. 期望值属于别的订阅 → [waitForProfile]（先别下发，等内核换配置）
/// 3. 与内核当前选中一致 → [none]（幂等：所以每次事件都跑也不会重复下发）
/// 4. 内核的节点集合里没有这个 tag → [none]（还没加载到 / 已不存在，都只是等待）
/// 5. 内核停在它自己的默认值 → [applyDesired]
/// 6. 否则（内核选中是个具体节点）→ [adoptKernel]
SelectionReconcileAction decideSelectionReconcile({
  required String desiredTag,
  required String desiredProfileId,
  required String? activeProfileId,
  required String kernelSelectedTag,
  required Iterable<String> kernelNodeTags,
}) {
  if (desiredTag.isEmpty) return SelectionReconcileAction.none;

  if (desiredProfileId.isNotEmpty && desiredProfileId != activeProfileId) {
    return SelectionReconcileAction.waitForProfile;
  }

  if (kernelSelectedTag == desiredTag) return SelectionReconcileAction.none;

  if (!kernelNodeTags.contains(desiredTag)) return SelectionReconcileAction.none;

  if (kKernelDefaultSelectionTags.contains(kernelSelectedTag)) {
    return SelectionReconcileAction.applyDesired;
  }

  return SelectionReconcileAction.adoptKernel;
}
