# 连接模型与三个真机 bug 的逻辑梳理

> 2026-09-15。来源：用户真机报的三条现象（切换分组无效 / 开了关不了 / 刷新不要自动）。
> 结论均已回到内核与 riverpod 的实际机制核对，不依赖试错。

## 一、连接的三个量（模型本身正确）

设计照 nekoray：**内核常驻**，**接管流量是独立开关**，两者不合并成一个「连接」概念。

| 量 | 定义 | 谁在 watch |
|---|---|---|
| `coreRunningProvider` | 内核活着吗（`watchStatus()` 流 == started） | 代理页延迟列、测速 |
| `Preferences.captureEnabled` | 用户开关（落盘） | `capturingProvider` |
| `capturingProvider` | 流量被接管吗：TUN = coreUp；系统代理 = coreUp && capture；仅代理 = false | `ConnectionNotifier`、状态栏、统计 |

对外状态由 `ConnectionNotifier` 映射：

```dart
Connected() => capturing ? const Connected() : const Disconnected(),
```

即：**内核在跑但没接管时，界面就该显示「未连接」**——这是有意的，不是 bug。

桌面端默认 `ServiceMode.systemProxy`（`singbox_config_enum.dart:21`），所以 `capturing = coreUp && captureEnabled`。

## 二、代理页按订阅切换（已实现）

### 起因：数据源只看激活订阅

查你机器上的真实数据（`%APPDATA%\Hiddify\hiddify\`）：

| 订阅 | 配置里的分组 |
|---|---|
| 云霄（激活，`e2d4f850`） | 48 个 outbounds，**0 个分组** |
| 一分机场（`0a34c1c6`） | 39 个 outbounds，**2 个分组**：`节点选择`(selector)、`自动选择`(urltest) |

原来的 `offlineProxyGroupsProvider` **只看激活订阅**，而激活的"云霄"配置里没有分组 ⇒ `parseOfflineProxyGroups` 走兜底，把 48 个节点平铺成一个 tag 写死为 `select` 的组 ⇒ 页面只有一个组、不画 Tab。盘上那笔 `selected_proxy_group = '节点选择'` 其实来自另一份订阅，永远匹配不上。

### 实现

- **清单来源**改为 [offlineAllProfilesProxyGroupsProvider]：遍历**全部订阅**，每份各自 `generateConfig` + 解析。`generateFullConfigByPath` 走 core 的 parse RPC（配置解析，不要求内核处于 running），所以未激活订阅同样能列出节点。
- **Tab** = 每份订阅的每个分组。标签规则：多订阅时 `订阅名 · 组名`；该订阅走了兜底平铺（组名是解析器写死的 `select`）时直接用**订阅名**代替。
- **选中键**改为复合键 `<profileId>::<groupTag>`（`groupKeyOf` / `parseGroupKey`）。必须带订阅 id —— 两份订阅都可能有 `select`，只存组名无法区分。旧格式（纯组名）解析失败 → 回落到第一个 Tab，与 notifier 一致，高亮和列表不会对不上。
- **延迟**：只有**激活订阅**那份能拿内核实时数据（内核一次只加载一份配置），其余订阅显示纯离线清单（延迟列为 —）。
- **选其他订阅的节点**：先把该订阅设为激活（`selectActiveProfile` → 现有逻辑会自动重连），选择本身照旧**落盘 pending**，等新内核 ready 时由 `build()` 的 `asyncMap` 应用。这样"切订阅"和"选择"复用同一条既有链路。

### 顺带删掉的

主动订阅那版名单（`offlineProxyGroupsProvider`）已无人使用，删除；`ProfileGroupSet` 之类中间产物没有引入。

## 三、bug 2：开了关不了

**根因是三处实现破坏了自己的模型，叠加后互相放大：**

1. **`ConnectionNotifier.build()` 无条件复位**
   ```dart
   Future.microtask(() => ref.read(Preferences.captureEnabled.notifier).update(false));
   ```
   意图是「每次应用启动都从不接管开始」。但它挂在 `build()` 上，而 `capturingProvider` 被 `build()` watch——`captureEnabled` 一被用户打开就触发重建，重建又把它复位。**用户操作被自己的副作用清掉。**

2. **`setCapture()` 用 `captureEnabled` 做幂等判断**
   ```dart
   if (ref.read(Preferences.captureEnabled) == enabled) return;
   ```
   开关已被 (1) 清成 false 时，`setCapture(false)`（关闭）**直接 return，什么都不做**——关闭动作静默失效。

3. **`watchStatus()` 不重放当前状态**（`hiddify_core_service.dart:462`）
   ```dart
   yield* statusController.stream;   // 裸 controller.stream，没有 startWith
   ```
   `capturingProvider` 变化导致重建后，新捕获的 `capturing` 值要等**下一次内核状态事件**才生效；内核稳定时该流不再发射，界面就停在旧映射上。

**时序**：点连接 → captureEnabled=true → notifier 重建 → 微任务复位 false → reconnect 读到 false（系统代理不设 / 状态映射回未连接）→ 再点关闭 → 幂等判断直接 return。表现为「状态乱跳 + 关不掉」。

**另有一条确定性失效路径（TUN 模式）**：`capturing = coreUp`，`captureEnabled` 与它无关。此时 `setCapture(false)` 只会重启内核，内核回来 `coreUp` 仍为 true → 永远「已连接」，且 `/api` 侧早退也可能直接 no-op。**TUN 下「关」必须落实为停内核。**

**修法（已实施）**：

- 「启动复位」从 `build()` 里移到**只做一次**（实例字段 `_captureResetDone`；riverpod notifier 实例跨重建保留，已由复现验证）。不再挂在每次重建上。
- `setCapture` 的幂等判断改为 **`capturingProvider` 与 `captureEnabled` 一起确认**，避免只看落盘开关时「关闭」被静默吞掉。
- 新增 **TUN 分支**：`capturing == coreUp`，开关对它无意义 → 「关」= `_disconnect()`（停内核），「开」= 内核没跑才 `_connect()`。

**尚未处理**：`watchStatus()` 缺 `startWith` ⇒ 重建后不重放当前状态，新映射要等下一次内核事件才生效。属体验瑕疵（状态可能滞一拍），已记录待评估。

## 四、「自动刷新」的真正来源

用户的原始表述是「刷新不要自动」和「为什么总是自动测速排列，测速是单独开关」。查下来是**三处独立行为**，其中第一处才是「总是自动测速排列」的正主：

| 来源 | 机制 | 处理 |
|---|---|---|
| **排序默认值 `ProxiesSort.delay`** | 列表**天生就按延迟排**。而内核 `url-test-interval` 默认 10 分钟自动测一轮、**每次内核启动也会测一次**，延迟一变整张表就重排 → 看起来像"总是自动测速刷新" | **已改**：默认 `unsorted`，保持订阅给的原始顺序。测速回归为纯手动动作（菜单「测试全部」），不再决定列表顺序 |
| `IpInfoNotifier` | `autoCheckIp` 默认 true → 接管后自动查；查完再挂 10s 定时器 `invalidateSelf`，把结果**自动刷成空白** | **已改**：默认 false；10s 定时器与 `_idle` 机制整体删除 |
| `ProxiesOverviewNotifier` 每秒重发 | 内核按字节数推送 → 列表每秒重建 | **保留**（只更新数值，不再引起重排） |
| `StatsNotifier` | 连接时内核推送速率，底部状态栏每秒跳动 | **保留**（正常行为） |

对应到用户的两句话：

- **「进入不要自动刷新」**：进页面只是订阅内核流（数值更新）；IP 卡此前会自动查，已关掉。
- **「点击连接不要自动刷新」**：点连接 → 内核重启并做一次初始测速 → 延迟从 0 变成有值。以前排序是 delay，于是**一连接列表就重排**；现在默认不排序，连接不再改变顺序。

> 应用层**没有**任何自动测速代码：`urlTest` 的全项目调用只有菜单「测试全部」和 `ActiveProxyNotifier.urlTest`（手动）。自动测速来自内核的 `url-test-interval`，它是设置项「URL 测试间隔」（`config_option_repository.dart:160`，默认 10 分钟），需要时可在设置里调。

## 五、复现工具

`tool/riverpod_repro_test.dart` —— 用项目同版本 riverpod 验证 notifier 的异步行为。

**这个脚本第一版给出过错误结论，教训值得记住**：假 notifier 不落盘时，autoDispose provider 会在重建窗口被销毁，重建只能读到默认值，看起来就像"依赖不生效"。**必须同时具备两个条件才能得到可信结果：① 状态真落盘 ② 有持续的订阅者**（真实项目里这两条都天然成立：`PreferencesNotifier` 真写盘，页面一直 watch）。

保留的三条已验证结论：

- `await` 之后的 `ref.watch` 在真实条件下同样能拿到新依赖值 → **watch 位置不是 bug 1 的根因**
- Notifier 重建时**实例字段保留**（`_coreStarted`、`_autoStartAttempted` 这类字段跨重建有效）
- autoDispose StateNotifier 的 `update()` 能正常传播给多个订阅者

## 六、与 NekoBox for Android 的对照

对照源码：`S:\test\NekoBoxForAndroid`（Java/Kotlin）。关键位置：

| 文件 | 作用 |
|---|---|
| `ui/ConfigurationFragment.kt` | **节点页**：ViewPager2 + TabLayout，每分组一页 |
| `ConfigurationFragment.kt:1037` 嵌套 `GroupFragment` | 某分组的节点列表（与顶层 `ui/GroupFragment.kt` 是两个不同的类，别混淆） |
| `ConfigurationFragment.kt:911-956` `GroupPagerAdapter.reload` | 分组清单来源 + 选中恢复 + `hideTab` |
| `ConfigurationFragment.kt:1110-1155` `checkOrderMenu` | 排序菜单，写 `proxyGroup.order` |
| `ConfigurationFragment.kt:1427-1464` `reloadProfiles` | 按 `proxyGroup.order` 排序 |
| `ConfigurationFragment.kt:1499-1514` | 点节点 → `DataStore.selectedProxy` + 内核热切换 |
| `database/ProxyGroup.kt` | 分组实体：`type` / `ungrouped` / `isSelector` / `order` / `userOrder` |
| `database/GroupManager.kt:82` | `createGroup` —— 只在**导入订阅**（`MainActivity:211`）与手动新建时调用 |

### 逐项对照

| 维度 | NekoBox for Android | 本实现 | 状态 |
|---|---|---|---|
| **分组粒度** | 一份订阅 = 一个分组 = 一个 Tab；订阅内的 clash proxy-group **不占 Tab** | 订阅 × 每个 `selector`/`urltest` 组各占一个 Tab | ⚠️ 唯一未对齐项 |
| Tab 隐藏条件 | `groupList.size < 2`（947-948） | `tabs.length > 1` | ✅ |
| 选中分组持久化 | `DataStore.selectedGroup`（分组 **id**） | `selected_proxy_group` = `profileId::groupTag` | ✅ 等价 |
| 选中回落 | 无效 → 第一个分组（`DataStore.currentGroupId`） | 无效 → 第一个 Tab | ✅ |
| **排序作用域** | **每个分组独立**（`ProxyGroup.order` 随分组存库） | 原为全局 → **已改为每分组独立** | ✅ 本轮对齐 |
| 排序默认 | `GroupOrder.ORIGIN`（订阅原始顺序） | `ProxiesSort.unsorted` | ✅ |
| BY_DELAY 排序 | `status==1 ? ping : 114514`（未测速排最后） | 未测速时回落按 tag —— 效果等价 | ✅ |
| 切换方式 | ViewPager2 **可左右滑动**切页 + 点 Tab | 仅点 Tab | 次要差异 |
| 点节点 | 写 `DataStore.selectedProxy`，内核**热切换不重启** | 落盘 pending + `selectProxy`，同样不重启 | ✅ 等价 |
| 分组实体 | DB 表 `proxy_groups`；节点靠 `ProxyEntity.groupId` 归属 | 无实体，每次从订阅配置解析 | 架构差异（hiddify 侧无分组表） |
| 空分组 | 自动建 `ungrouped` 分组；它为空时从 Tab 移除 | 无分组则报错提示 | 差异（hiddify 无「手动加节点」） |

### 结论

**已按 NekoBox 定案**（2026-09-15，见 `nekobox-parity.md` §8.6.12）：Tab 粒度 = **一份订阅一个 Tab**，
组名就是订阅名。其余行为已与 NekoBox 一致：Tab 隐藏条件、选中持久化与回落、排序作用域与默认值、
点节点不重启内核。

先前那条"待定"的分歧点（NekoBox 里订阅内的 proxy-group 不是可切换维度，而 hiddify 内核**真的能切组**
`selectProxy(groupTag, ...)`）已按 **NekoBox 为准**裁决：配置内的 selector/urltest **不成为分组**
（`Constants.kt` 的 `GroupType` 只有 BASIC/SUBSCRIPTION；`RawUpdater.kt:768-787` 更新订阅时把
`selector/urltest/direct/block/dns` 全过滤掉）。内核能切组这件事仍然成立，但那是**运行期的内部机制**
（内核自己重建的那个 `select`），不是用户可见的分组。

## 七、列表不该随「连接」变化（已修）

用户实测："为什么按钮开关之后列表都有变化"。日志显示开关都会**重启内核**
（`capture enabled/disabled - restarting core to apply it`，约 2 秒），
于是 `coreRunningProvider` 变两次，列表 notifier 跟着重建。

重建本身没问题，问题在 `_mergeLive` 里这段：

```dart
// 内核里有、订阅清单里没有的（面板临时加的之类）也带上，别丢东西
for (final extra in byTag.values) { ... merged.items.add(extra); }
```

**内核只暴露它的第一个组**（`watchGroup()` → `items.first`），与用户正在看的组往往不是同一个
（内核的 `select` vs 订阅的 `节点选择`），两份清单根本不是一回事 → 那批 extra 被塞进列表，
**每次连接/断开条目就变一次**。

修正：

- **列表内容 100% 由订阅决定** —— 谁在列表里、什么顺序都以 `base` 为准，内核只补
  「跑起来才知道」的延迟/用量/选中三个字段，**不新增也不删减条目**。
- `merged.tag` 由「内核的组 tag」改成**订阅的组 tag** —— 它既是用户正在看的组，
  也是 `selectProxy(groupTag, ...)` 该下发的目标；用内核的会指向第一个组，看第二个组时下发错组。

## 八、按钮文案（已改）

- 代理页 FAB 未连接时的 tooltip：「点击连接」→ **「连接」**。这个按钮是连接**开关**，
  不是一个一次性动作，文案应当是动作名。
- `ConnectionStatus.present()` 里 `Disconnected` 由「点击连接」→ **「未连接」**：状态显示用状态词，
  动作提示才用动作词（这处同时影响系统托盘的 tooltip）。

## 九、接管的三档，以及能不能免重启

三档接管的本质区别在「**谁把流量送到内核的入站端口**」：

| 档位 | 谁送 | 界面语义 |
|---|---|---|
| **仅代理**（`proxy`） | 没人送，用户自己在程序里填 `127.0.0.1:mixedPort` | `capturing` 恒为 false |
| **系统代理**（`systemProxy`） | 操作系统：改系统代理设置，遵循该设置的应用自动走 | `coreUp && captureEnabled` |
| **TUN**（`tun`） | 操作系统：建虚拟网卡 + 改路由表，全机流量（含 UDP）都被导入 | `coreUp`（内核在跑即接管） |

系统代理 vs TUN 的取舍（这也是为什么用户会觉得"连了但有的东西没走代理"）：

- **系统代理**：只覆盖遵循系统设置的应用、基本只有 TCP（UDP/QUIC/游戏语音不走）、普通用户权限即可
- **TUN**：覆盖全机所有应用且应用无感、TCP/UDP/ICMP 全走，但要管理员权限 + 驱动，且与其它 VPN/杀软易冲突

### 结论：系统代理**不必重启内核**

core 留了运行时接口（`hiddify_core_service.dart:225/237`）：

```dart
getSystemProxyStatus()                  // gRPC GetSystemProxyStatus
setSystemProxyEnabled(bool enabled)     // gRPC SetSystemProxyEnabled
```

所以 `setCapture` 现在分两条路走：

- **系统代理**：优先调 `setSystemProxyEnabled`，**运行时刻生效** —— 内核继续跑、连接不断、延迟不清空。
  调用失败则**自动回落到下面那条重启路径**兜底，行为不会比原来更差。
- **TUN**：只能重启内核（网卡和路由必须在内核启动时建）；「关」还要落实为**停内核**，
  否则内核一回来就又是接管中。
- **仅代理**：`capturing` 恒 false，这个开关对连接没有意义。

### 附：三层依赖（获取订阅 / 测速 到底要不要内核）

三个层级必须分开，它们不是一回事：

1. **core 进程** —— `core.setup()` 起（`connection_repository.dart:58`，首次连接时调），提供配置解析/生成（`fgClient.parse`）
2. **内核运行** —— `core.start(...)` 起（`_autoStartOnce` 会自动做），提供 gRPC 的 `urlTest` / `outboundsInfo` / `selectOutbound`
3. **接管流量** —— 见上面三档

| 动作 | core 进程 | 内核运行 | 接管流量 |
|---|---|---|---|
| 下载订阅内容 | 不用 | 不用 | 不用 |
| 生成节点清单 / 配置 | **要** | 不用 | 不用 |
| 测速（延迟测试） | **要** | **要** | 不用 |
| 流量真的走代理 | 要 | 要 | **要** |

关键事实：

- **下载订阅完全不碰内核**：`ProfileParser` 用自己的 `DioHttpClient`（`profile_parser.dart:158/217`），所以首次导入订阅一定能成功，与内核状态无关。
- **测速要求内核在运行**（要真去连节点），但**不要求接管** —— 这正是"内核常驻、不接管也能测速"的设计依据。
- **桌面端 `bgClient` 与 `fgClient` 是同一个客户端**（`core_interface_desktop.dart:106`：`bgClient = fgClient = CoreClient(...)`）；只有移动端才拆成两个进程（`core_interface_mobile.dart:81/89`）。所以桌面端"解析配置 / 测速 / 选节点 / 看清单"共用同一条 core 连接。
- 前两层**由应用自动完成**（有订阅就 `_autoStartOnce`），所以用户体感上"什么都不用开"。推论：**没订阅时内核不会起来，此时测速按钮自然没反应**；而订阅下载失败一定与内核无关（是网络/链接问题）。
