# 代理/分组模型的根源性修复（设计）

> 2026-09-15。配套审计：`docs/audit/2026-09-15-logic-layer-audit.md`（问题定位）、`docs/design/core-architecture-comparison.md`（与 NekoBox 的底层差异）。
> 本文只讲**怎么改才叫根源修复**，以及分阶段与验收。

---

## 1. 根源（两条）

### 根源 1：双数据源（运行期数据结构被重建了两次）

- 内核 `OutboundsInfo` **本来就返回全量分组**，每组带全部成员 + 实时数据
  （`hiddify-core/v2/hcore/proxy_info.go:128-161`：对每个 group 全量 append；`:144-156` 装 `group.All()` 并逐项标 `IsSelected`）
- 应用侧把它砍成一个组：`hiddify_core_service.dart:313` 的 `.items.first`
- 于是分组结构改为**解析 `generateConfig` 的 JSON** 重建（`features/proxy/data/offline_proxy_parser.dart` 全文）
- 两份模型之间再加一层 `_mergeLive`（`proxies_overview_notifier.dart:166-203`）缝合

**所有难查的现象都长在这条缝上**：列表随连接变化、`selectProxy` 下发错组、排序/高亮要靠人肉对齐。

### 根源 2：应用侧没有实体（功能无处落脚）

drift 只有 `ProfileEntries` + `AppProxyEntries`（`lib/core/db/db.dart:12`）：节点与分组在应用侧**不是一等公民**。
所以协议级编辑表单、手动分组、手动节点、节点级删除全都无处安放 —— 这是"NekoBox 功能更强"的真实来源（见对照文档 §7）。

---

## 2. 目标架构：三个真源，各管各的

| 真源 | 归谁 | 管什么 | 现状 |
|---|---|---|---|
| **运行期数据** | **内核**（`OutboundsInfo`） | 分组、成员、选中、延迟、上下行、ipinfo | ⚠️ 被 `.first` 砍掉，靠 JSON 重建 |
| **可切换范围** | **订阅**（离线 `generateConfig` + 解析） | 有哪些订阅、每份订阅里有哪些组（**跨订阅只有它能给**，因为内核一次只加载一份配置） | ✅ 合理，保留 |
| **用户意图** | **应用偏好层**（落盘） | 当前订阅/分组、每分组排序、待应用的选择 | ⚠️ 三件混在代理页 notifier 里，Phase 2 归拢 |
| **用户资产**（可选） | **应用 DB** | 手动节点、手动分组、用户覆盖 | ❌ 不存在，Phase 3 |

**原则一句话**：
> **同一份运行期数据只能有一个来源。** 内核供给"当前激活配置的运行期状态"，订阅供给"可切换范围"，应用只存"用户的意图与资产"—— 应用不再自己重建内核的数据结构。

### 为什么 Tab 清单继续来自订阅，不算双源？

因为那是**另一件事**：Tab 要展示"所有订阅的所有组"，而内核一次只加载一份配置，跨订阅的信息它给不出来。
所以这不是重复来源，而是**职责不同的两个数据面**：

- 当前组的内容 → 内核（活数据）
- 可切换的组清单 → 订阅（范围）

`_mergeLive` 之所以错，就是因为它把这两个面混在一起缝。

---

## 3. 分阶段

### Phase 1 —— 单源化（本次实施，3 个文件）

目标：**当前组的内容 100% 来自内核**，`_mergeLive` 消失。

| 文件 | 改动 |
|---|---|
| `lib/hiddifycore/hiddify_core_service.dart` | 恢复 `watchGroups()`（`outboundsInfo` 全量）；删除 `watchGroup()` 的 `.first` 版本与死注释 |
| `lib/features/proxy/data/proxy_repository.dart` | `watchProxies()` 改为 `Stream<Either<ProxyFailure, List<OutboundGroup>>>`；清理注释死代码 |
| `lib/features/proxy/overview/proxies_overview_notifier.dart` | live 分支改为"从内核全量清单里按 tag 取当前组"，**删除 `_mergeLive`**；清理注释死代码 |

**对外契约不变**：notifier 状态仍是 `OutboundGroup?`（当前组）→ **UI 零改动**。

### Phase 2 —— 意图层归拢（不改 schema）

把三件仿制概念收进一个明确命名的模块（`ProxyIntent` 之类），写清语义边界：

- `pending_proxy_group` / `pending_proxy_outbound`（选择意图，内核没跑时无处下发）
- `selected_proxy_group` 复合键 `<profileId>::<groupTag>`
- `proxies_sort_by_group` 字符串编码排序偏好（应换成结构化序列化）

并明确"未激活订阅"的降级语义：清单来自订阅、延迟只能显示 `—`。

### Phase 3 —— 实体化（可选，需产品拍板）

只有当"节点编辑 / 手动分组 / 手动节点"确实是需求时才做。技术上**不需要 fork 内核**：

1. 凭据来源：`Parse` 返回**完整配置文本**（`buildconfighelper.go:46-82`），含每个出站的完整定义 —— 应用现在就用它抽单条出站做分享（`extractOutboundJson`）
2. 配置提交：`Start` 的 `enable_raw_config`（`buildconfighelper.go:28-44`）允许**应用自己生成配置**喂给内核
3. 代价：应用要长期维护一套配置组装逻辑（等价于 NekoBox 的 `ConfigBuilder.kt`），并与内核 builder 的差异保持对齐

---

## 4. 验收标准

**Phase 1**
1. `flutter analyze --no-pub` 0 issue；release 构建通过
2. 真机：开关接管（会重启内核）**前后列表条目与顺序不变**
3. 真机：切换分组 Tab 后，列表内容与该组在内核里的成员一致
4. 真机：点节点 → 高亮跟随；`SelectOutbound` 下发的是**当前组的 tag**
5. 真机：未激活订阅仍能列出节点（走静态分支）

**反例（修好前）**：`_mergeLive` 会把内核"第一个组"的数据缝进当前组，所以上面第 2、4 条必失败。

---

## 5. 连带发现

### 5.1 订阅内容更新后内核不重载 —— **已修**

统一到"运行期数据来自内核"之后，**内核里的那份配置是否新鲜**就成了关键。原来的链路：

- 更新订阅：`profile_notifier.dart:139 updateProfile` → 若该订阅是激活的，调 `connectionNotifierProvider.notifier.reconnect(profile)`（`:154-158`）
- 但 `ConnectionNotifier.reconnect` **第一行就 early-return**：`if (state case AsyncData(:value) when value == Connected())` —— 即**只在"接管中"才重连**

于是"内核常驻但未接管"（桌面默认 `captureEnabled=false`）时：更新订阅内容、切换激活订阅，**都不会让内核换配置**。后果有两层——列表滞后于订阅（限 Phase 1 之后），以及"选择了别的订阅的节点"落盘的 pending 永远等不到新内核来应用。

**修法（已实施）**：`reconnect()` 的契约改成 **"只动内核，不动接管状态"**：

| 情形 | 行为 |
|---|---|
| 内核没跑（`!_coreStarted`） | 什么都不做 —— 下次启动自然读新配置 |
| 内核在跑 + 接管中 | 重载 + 记 `startedByUser`（原行为） |
| 内核在跑 + 未接管 | **也重载**；不碰 `captureEnabled`、不写 `startedByUser` |

❌ 旧的错误处理：失败时无条件 `state = AsyncError` —— 未接管时那是由内核状态流驱动且当前就是 `Disconnected`，抢着写会让界面闪。现在只在接管中才写 `AsyncError`，两种情况都弹错误对话框。

**这替换了一条更早的决定**（"更新订阅是纯数据操作，不 restart 不 start"）。那条的理由是"列表直接来自数据层所以立刻就变"—— 而 Phase 1 之后列表来自内核，这个前提不成立了。**两个决定必须一起改，否则自相矛盾。**

### 5.2 pending 选择的错内核竞态 —— **已修**

`proxies_overview_notifier` 的 `changeProxy` 在"选的是别的订阅"时：

```dart
await selectActiveProfile(targetProfileId);   // 触发内核重载（重启）
_pendingGroup.write(groupTag);                // 重载还没完成就先写盘
_pendingOutbound.write(outboundTag);
```

而 pending 的**应用条件是"内核流一发事件就应用"**（`build()` 的 `asyncMap`），不校验"当前内核加载的是不是那笔 pending 所属的订阅"。窗口内旧内核若恰好还在推事件，就会把这笔选择应用到**旧内核**上（组名碰巧存在就静默生效并被清空），新内核起来后用的还是它自己的默认选择。

**修法（已实施）**：给 pending 加第三个字段 `pending_proxy_profile`（这笔选择属于哪份订阅），应用前校验：

```dart
final ready = pendingProfile.isEmpty || pendingProfile == activeProfile?.id;
```

- 匹配 → 下发并清空三个字段
- 不匹配 → 只打日志、**保留**这笔 pending，等内核换成那份订阅的配置后的下一次事件再应用
- 空串 → 不校验（历史行为，用于组 key 解析不出订阅 id 的情形）

`build()` 里 watch 了 `activeProfileProvider`，所以切订阅会让本 provider 重建、闭包里的 `activeProfile` 自然更新到新值。

### 5.3 本次不做（记录在案）

- ~~Tab 粒度（订阅 × 组 vs 一订阅一 Tab）~~ —— **已按 NekoBox 定案：一订阅一 Tab**
  （2026-09-15，见 `nekobox-parity.md` §8.6.12。配置内的 selector/urltest 不成为分组。）
- 协议级表单 —— Phase 3
- `changeProxy` 的"跨订阅 → 自动切激活订阅"分支本身是对的（内核一次只加载一份配置所迫），Phase 2 可以给它加显式提示


