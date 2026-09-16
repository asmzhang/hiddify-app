# 功能逻辑层审计：为什么"功能对不上、像硬套"（2026-09-15）

> 触发：NekoBox 复刻完成后，用户反馈"细节总是不对""功能对不上，有硬套感"，并考虑删掉全部 UI 重写。
> 本文结论基于源码核对（应用侧 `lib/` + 内核侧 `hiddify-core/`），不是感受描述。

---

## 0. 结论

**不是 UI 的问题。** UI 骨架是三层里最健康的一层（主题 100%、壳/抽屉/Rail/Tab/卡片均已截图验证）。

问题在**功能逻辑层**，且已定位到一条主因——**双数据源**：

> 内核本来就把「全部组 + 组内全部节点 + 实时延迟/上下行/选中状态」一次性给出来（`OutboundsInfo`）。
> 是**应用自己的包装层把它砍成只剩一个组**（`.items.first`），然后又另写了一套「解析生成好的配置 JSON」来重建分组结构。
> 同一个东西于是有了两份模型，再加一层 `_mergeLive` 去缝它们 —— 难查的 bug 全长在这条缝上。

这不是内核能力不足，而是**应用侧自我制造的退化**。

---

## 1. 证据：内核给的东西 vs 应用用掉的东西

| 能力 | 内核实际提供 | 应用实际使用 | 位置 |
|---|---|---|---|
| **全部组** | `OutboundGroupList.items`，对每个 group 逐个 append（全量） | **只取第一组** | `hiddify_core_service.dart:313`（`event.items.isEmpty ? null : event.items.first`） |
| 组内全部成员 | `group.Items` 装 `iGroup.All()` 的每一项，逐项填 `IsSelected` | 只把 live 的延迟/用量"合并"进自建清单 | `hiddify-core/v2/hcore/proxy_info.go:144-156`；`proxies_overview_notifier.dart:178-203` |
| 每节点实时数据 | `Upload` / `Download` / `UrlTestDelay` / `Ipinfo` / `TagDisplay` / `IsGroup` / `GroupSelectedTag` | 同上（部分使用） | `hiddify-core/v2/hcore/proxy_info.go:52-78` |
| 分组结构（tag/type/selected） | `OutboundGroup.Tag/Type/Selectable/Selected/IsExpand` | **弃用**，改为解析 `generateConfig` 的 JSON 重建 | `proxy_info.go:128-142` ↔ `offline_proxy_parser.dart:19-82` |

**被丢弃的能力留下了明确痕迹**——全量版本是被注释掉的：

- `hiddify_core_service.dart:298-302`：`watchGroups()`（用 `outboundsInfo` 拿**全量** `event.items`）整段注释
- `proxy_repository.dart:13`、`:27-60`：仓储接口与实现里的全量版 `watchProxies()` 同样注释
- 现役 `watchGroup()` 用的是**同一个 RPC**，唯一差别就是末尾的 `.first`

也就是说：**要拿回全量分组，不需要动内核，改一行映射即可。**

---

## 2. 这条双源结构直接造成的病症

| 现象 | 机制 |
|---|---|
| 列表条目随"连接/断开"变化 | `_mergeLive` 把内核**第一个组**的数据缝进当前组的清单；用户在看的常常是另一个组（内核 `select` vs 订阅「节点选择」）→ 内核每次重启（开关接管会重启）条目就变一次 |
| `selectProxy` 会下发错组 | 内核只给第一组，`merged.tag` 必须人为改写成"订阅的 tag"才对得上 |
| 排序/高亮要人肉对齐 | 两份清单的 tag 口径靠代码保证一致，任何一边改名就错位 |
| 只有激活订阅有实时延迟 | 是 live 源被砍成一组的副产物（另一半原因才是"内核一次只加载一份配置"） |
| 分组概念处处要兜底 | 因为组不是从内核读的，而是从 JSON 里"猜"出来的：解析失败就平铺成一个假组 `select`（`offline_proxy_parser.dart:60-77`） |

---

## 3. 为模仿 NekoBox 手工造出的中间概念（清算清单）

| # | 概念 | 位置 | 它替 NekoBox 里的什么 | 起因 | 建议处置 |
|---|---|---|---|---|---|
| 1 | 复合键 `<profileId>::<groupTag>` + `groupKeyOf` / `parseGroupKey` | `offline_proxies.dart:75-86` | `DataStore.selectedGroup`（分组 **id**） | hiddify 无分组实体、组名会撞车 | 键可留（UI 需要横向切订阅），但**语义要重写**：分组身份应来自内核 |
| 2 | 字符串编码的排序偏好 `"key=sort;key=sort"` + 手写解析 | `proxies_overview_notifier.dart:45-80` | `ProxyGroup.order` 一列 | 无实体、无 schema 列 | 可保留在偏好层，但抽成通用 map 序列化，别手写分号解析 |
| 3 | `pending_proxy_group` / `pending_proxy_outbound` 落盘待应用 | `:90-99`、`:154-161`、`:349-351` | NekoBox **没有**这个概念 | 内核没跑时无处下发 | 保留（确实需要），但归属要明确成一个"选择意图"模块 |
| 4 | **`_mergeLive` 缝合层** | `:166-203` | NekoBox **没有**（单一数据源） | 双源结构 | **可删** —— 前提是先做 §5 阶段 1 |
| 5 | `changeProxy` 的"选了别的订阅 → 自动切激活订阅 → 连接重建" | `:321-362` | NekoBox 无（所有节点同库） | 内核一次只加载一份配置 | 保留（真模型限制），但必须显式提示用户"将切换到该订阅" |
| 6 | 解析 `generateConfig` JSON 重建分组 | `offline_proxy_parser.dart` 全文件 | 直接读 DB | 单组流不够用 | **可退役**（换成 `outboundsInfo` 全量组） |
| 7 | 注释掉的死代码 | `proxies_overview_notifier.dart:205-246,297-319`；`hiddify_core_service.dart:298-302,318-321`；`proxy_repository.dart:13,27-60`；`config_option_repository.dart:43,175,183` 等 | — | 反复试错残留 | 直接删 |

---

## 4. 真正属于「模型 / 内核」的墙（逻辑层改不动）

这几项是重写 UI **也解决不了**的，必须单独立项或明确放弃：

| 缺口 | 事实 | 影响 |
|---|---|---|
| 节点凭据 | `OutboundInfo` 只有展示字段（tag/type/host/port/延迟/用量/ipinfo），**无 uuid/password 等** | 屏4 节点编辑表单（审计 45%）必须动 core |
| 分组实体 | `db.dart` 只有 `ProfileEntries` + `AppProxyEntries` 两张表 | 手动分组 / 手动加节点 / `ungrouped` 分组做不了 |
| 配置项缺失 | core 无 sniffing 等选项（`config_option_repository.dart` 无对应项） | NekoBox 的「流量嗅探」这类开关无法移植 |
| 逆向转换 | `ray2sing` 只有「分享链接 → 配置」，没有反向 | 节点级"复制分享链接"只能降级为"复制出站 JSON" |

---

## 5. 建议的改造路径（不重写 UI）

**阶段 1 —— 单源化（改 3 个文件，是"功能对不上"的主要手术）**
1. 恢复全量：`watchGroup()` → `watchGroups()`（同一个 `outboundsInfo` RPC，去掉 `.first`）
2. 代理页 live 源改为「内核全量组」，静态清单（JSON 解析）退为"内核没跑时的占位"
3. 删除 `_mergeLive` —— 单源之后它没有存在理由

**阶段 2 —— 中间概念归拢**：把 §3 的 1/2/3 收进一个明确命名的适配模块，写清各自的语义边界（哪些是 UI 需要、哪些是内核限制逼出来的）

**阶段 3 —— 模型决策后再动 UI**：Tab 粒度、屏4、手动分组（这三项先拍板，再谈 UI 改哪些）

**验收**：用现成的 `app.log` 核对两条 —— ① 开关接管前后列表条目不变；② 未激活订阅也能列出节点。

---

## 6. 与「删掉 UI 重写」的关系

- 删掉那 78 个 UI 文件，**不会触及本文任何一条** —— 新 UI 接的还是同一套双源逻辑
- 真正的"功能对不上"，手术部位在 §5 阶段 1（3 个文件）+ §3 的处置列
- 若仍要"重写"，正确边界是几个逻辑文件，不是 UI 目录

---

## 7. 交互与数据模型的关系（按档位分解）

> 起因：用户反问「交互与视觉不就是功能吗，不要数据模型吗，还是要修改对吗」。
> 这个反问是对的 —— 上一版结论里「可抄交互、不可抄数据模型」说得太干净，本节把它改成分档表述。

**准确的说法是**：抄一个交互，必须先回答"它操作的对象在哪一层是一等公民"。hiddify 侧的对象分两处 ——
**内核里已经是一等公民**（分组 / 成员 / 选中 / 延迟 / 用量），**应用侧不是**（无节点与分组实体，只有订阅元数据）。

### 第 1 档：对象已在内核里，只需改「取数方式」（不改模型）

| NekoBox 交互 | hiddify 侧对应的既有能力 |
|---|---|
| 分组 Tab 清单 | `OutboundsInfo` 流**已返回全部组**（`OutboundGroupList.items`），被 `hiddify_core_service.dart:313` 的 `.first` 砍掉 |
| 组内成员、是否选中 | `OutboundGroup.items[]` + `OutboundInfo.is_selected` |
| 延迟 / 上下行 / ip / 端口 / 是否安全 | `OutboundInfo`：`url_test_delay` / `upload` / `download` / `ipinfo` / `port` / `host` / `is_secure` |
| 点节点热切换（不重启内核） | `SelectOutbound(groupTag, outboundTag)` |
| 测速 | `UrlTest(groupTag)` / `UrlTestActive()` |
| Tab 隐藏（<2 不画）、左右滑、标签、选中恢复 | 纯 UI + 偏好层 |
| 订阅的增删改、滑动删除、拖拽排序 | `ProfileEntries` 表（已有） |

**这一档覆盖 NekoBox 交互的绝大多数**，代价是 §5 阶段 1 的单源化，不是改模型。

### 第 2 档：对象存在，但「归属」要挪（改逻辑层状态归属，不动 schema）

- 每分组排序（现塞在 `proxies_sort_by_group` 字符串里）
- 选中持久化与 pending（现为两个偏好 + `<profileId>::<groupTag>` 复合键）
- 多订阅横向切：**未激活订阅拿不到 live 数据** —— `StartRequest.config_path` 决定内核**一次只加载一份配置**，其余订阅只能靠 `Parse` 回的配置文本（这也是 §3 第 5 项那个"跨订阅自动切激活"分支的根源）

### 第 3 档：对象在应用侧不是一等公民（必须改模型）

节点编辑、手动分组、手动节点、节点级删除 —— 这些需要 drift 加表，**并且要参与配置生成**。

**但有一个关键发现：实现这一档不需要改内核**，内核已经留好了口子：

1. `Parse`（`hiddify-core/v2/hcore/buildconfighelper.go:46-82`）返回的是**完整配置文本**（`ParseResponse.Content`），里面**含每个出站的完整定义（凭据）**。
   证据：应用现在就用它抽单条出站做「分享」动作（`extractOutboundJson`）——说明**凭据本来就是应用可得的**，只是没落库。
2. `Start` 的 `enable_raw_config`（`buildconfighelper.go:28-44`）：
   ```go
   readOpt := &config.ReadOptions{Content: in.ConfigContent, Path: in.ConfigPath}
   if !in.EnableRawConfig {
       return config.BuildConfig(ctx, static.HiddifyOptions, readOpt)  // 内核构建（现状）
   }
   return config.ReadSingOptions(ctx, readOpt)                          // 直接吃应用给的配置
   ```

也就是说：**第 3 档 = 把配置生成权从内核收回到应用**，这正是 NekoBox 里 `ConfigBuilder.kt` 扮演的角色。技术上不需要 fork 内核，只是应用侧要实体化 + 接管配置组装 —— 属立项级工作量，不是 UI 复刻。

### 结论（回答"还是要修改对吗"）

**对，必须改。** 但改成什么分三种量级，差一个数量级：

| 档位 | 要改什么 | 能拿到的交互 |
|---|---|---|
| 1 | 逻辑层单源化（3 个文件） | NekoBox 的 Tab / 选中 / 测速 / 显示 / 排序等绝大多数交互 |
| 2 | 逻辑层状态归属（几个偏好与复合键） | 加上每分组排序、跨订阅切换的正当实现 |
| 3 | 应用侧实体化 + 接管配置生成（drift 加表 + 自建 builder） | 加上节点编辑 / 手动分组 / 手动节点（= 变成 NekoBox 的数据模型） |

**第 1+2 档是"跟着 hiddify 能提供的数据走"；第 3 档是"把 hiddify 改造成 NekoBox 的架构"** —— 后者是一个明确的产品决策，而不是被 UI 拖着走的副产物。

