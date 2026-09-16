# 全面逻辑审计（2026-09-15 · 按数据流，不按 diff）

> 起因：用户要求「梳理逻辑，全面审计**不止 diff**，下一步计划」。
> 因此本文不以"最近改了什么"为线索，而以**状态的所有权（谁是真源）+ 每一条链路的
> 正常路径与回落路径**为线索 —— diff 只用来证明"某条链路当前是这样连的"。
>
> 规格基准一律是 NekoBox 源码（`S:\test\NekoBoxForAndroid`），证据一律是本仓库与真机产物。

---

## 1. 逻辑梳理：五条链路

### L1 订阅导入/更新（写入侧）
```
用户加订阅 → ProfileRepositoryImpl.upsertRemote/addLocal/offlineUpdate
   → 写 configs/<id>.json（内核 Parse 归一化的产物）＋ profile_entries
   → _syncEntities(id) → ProxyEntityRepository.syncFromProfile
        → 读 configs/<id>.json（缺失才回落内核 Parse）
        → deriveProxyGroupFromConfig → 事务内认领/更新 proxy_groups（组名=订阅名）
        → 整组替换 proxy_entities（payload = 完整出站 JSON 含凭据）
   ★ 失败策略：只记日志，绝不抛出（实体是附加物）
```
启动时另有一次性补齐：`EntityBackfillNotifier` → `ensureEntitiesForProfiles`（幂等：只处理没有组的订阅）。

### L2 组装与启动（交给内核的那一份）
```
ConnectionRepository._start()
   → ProxyEntityRepository.assembleOutboundsForProfile(id)
        → 读 configs/<id>.json（基准）＋ 该组实体（按 user_order）
        → applyEntitiesToOutbounds（覆盖/追加；组一律透传）
        → 写 configs/<id>.entities.json
   → singbox.start(<id>.entities.json)
   ★ 三重回落：组装失败 / 无实体 / 启动失败 → 回落 configs/<id>.json（＝改动前行为）
   ★ 内核再把它构建成 data/current-config.json（重建 select/balance/lowest，route.final=select）
```

### L3 运行期取数（读取侧）
```
内核 outboundsInfo（bgClient）
   → HiddifyCoreService.watchGroups() / watchActiveGroups()
   → ProxyRepository.watchProxies()
   → ProxiesOverviewNotifier.build()：
        列表 = 骨架（实体 or 回落解析配置文本）
        实时值 = 按【节点 tag】从内核贴上（live_proxy_join.joinLiveIntoGroup）
        选中 = 内核 select 组的 selected（拿不到时用持久期望值兜底）
   ★ 内核的**组**是重建出来的并集表，不参与匹配（组 tag 恒为 select/balance/lowest）
```

### L4 选中（意图 → 运行期）
```
用户点节点 → changeProxy(): SelectedProxyStore.write(期望节点 + 归属订阅) → 立刻 selectOutbound('select', tag)
外部改选(yacd) → ActiveProxyNotifier 里 decideSelectionReconcile() → 一致/等待/下发/采纳并回写
```

### L5 接管（系统代理）
```
captureEnabled=true → setSystemProxyEnabled RPC
   → 失败（本内核无 command.sock，parity §8.6.10）
   → 兜底：重启内核 → 由 sing-box 自己写注册表（config 里 set-system-proxy=true）
```

---

## 2. 数据真源矩阵（审计的主工具：每块状态只能有一个主人）

| 状态 | 真源（唯一主人） | 副本/派生 | 现状 |
|---|---|---|---|
| 订阅元数据 | `profile_entries` | — | ✅ |
| 订阅内容（配置文本） | `configs/<id>.json` | — | ✅（内核 Parse 的产物） |
| **节点集合** | **`proxy_entities`（意图）** | `configs/<id>.json` **仍保留旧节点集合** | ⛔ **F1**：两者会背离 |
| 节点顺序 | `proxy_entities.user_order` | 列表排序偏好 `ProxiesSort` | ✅ |
| 分组（用户可见） | `proxy_groups`（由订阅派生） | 代理页 Tab | 🟡 手动建组未做（批次 3） |
| 分组（运行期） | 内核 `select`/`balance`/`lowest` | — | ✅ 应用不碰（`builder.go:130-371` 重建） |
| 选中 | `SelectedProxyStore`（偏好） | 内核 selector 的 `current` | ✅（校准幂等） |
| 接管/系统代理 | `Preferences.captureEnabled` + 内核 `set-system-proxy` | Windows 注册表 | ✅（靠兜底重启） |
| 内核实际配置 | `configs/<id>.entities.json` → `data/current-config.json` | — | ✅ |
| 运行期实时值（延迟/上下行） | 内核 `outboundsInfo` | — | ✅ 按节点 tag 贴 |

---

## 3. 发现清单

> **状态（2026-09-15 15:15 更新）**：批次 0 已实施并**真机验证** ——
> F1/F2/F3/F4/F5/F6 全部修复（下方每条都带 ✅ 与证据）；F7 仍为可选项未做。
> 真机端到端证据：删掉一个节点后启动，`entity assembly: replaced=47, added=0, removed=1`，
> 组装出的 `configs/<id>.entities.json` 从 51 条降为 **50 条**、被删 tag **不在其中**，
> 其余 50 条全部保留 ⇒「实体对节点段有最终裁量权」成立。测试数据已原样恢复（48 行）。

### F1 ⛔ P0（正确性）：删除的节点会被"订阅基准"复活

- **现象**：节点行 🗑 删掉一个节点后，**只有列表变了**；组装出来的配置里那个节点仍在，
  内核重启后依然是旧集合，于是"界面显示 47、内核实际 48"。
- **证据**：
  - `config_assembly.dart:74` —— `staleTags` 的默认值是 `const []`，即"不删任何出站"；
  - `proxy_entity_repository.dart:293-299`（调用处）**没有传 `staleTags`**；
  - 于是 `applied.removed` 恒为 0（真机日志正是 `removed=0`）。
- **为什么 NekoBox 没有这个问题**：它的配置由 DB **现场构建**
  （`fmt/ConfigBuilder.kt:131 proxyDao.getByGroup(...)`），DB 里没有的节点不会出现在配置里；
  本项目是"基准 + 覆盖"，基准里留着旧节点 ⇒ **基准成了第二真源**。
- **修法**：让实体对"节点那一段"有最终裁量权 ——
  `staleTags = 基准中"是节点出站"的 tag − 实体 tag`，并把"是不是节点"的判据**收敛到一处**（见 F3）。
  组与 `§hide§` 内部出站一律不动（内核所有）。
- **验收**：真机基准 48、实体 47 ⇒ `removed=1`，且该 tag 不出现在 `.entities.json`
  与 `data/current-config.json`；`tool/check_config_assembly.dart` 加断言
  （含"🔒 WARP / `direct §hide§` 不得被删"的反例）。

### F2 ⛔ P0（边界，与 F1 同源）：删空节点 ⇒ 全部复活

- `config_assembly.dart:76` 的 `if (entities.isEmpty) return null;` ⇒ 组装放弃 ⇒ 回落订阅基准
  ⇒ **所有节点复活**。需要一并定义"0 节点"的语义（见 §4 决策点 D1）。

### F3 ⚠️ P2（重复真源）：三处各写一份"什么算节点/组/隐藏出站"

| 判据 | 出现位置 |
|---|---|
| 组类型 | `config_assembly.dart:40 _groupTypes`、`offline_proxy_parser.dart:83 kGroupOutboundTypes` |
| 内部类型 | `offline_proxy_parser.dart:86 kInternalOutboundTypes` |
| `§hide§` | `runtime_outbound_tags.dart:58 isHiddenTag`、`offline_proxy_parser.dart:97 hiddenTag`（包了一层）、`proxy_entity.dart:32`、`traffic_split.dart:100`（直接写字符串） |

F1 的修复要用同一套判据，**必须先收敛**，否则"派生"与"删除"的边界会再次漂移。

### F4 🟡 P2（体验）：明知会失败的 RPC 仍等 3 秒

`command.sock` 在本内核上不存在（parity §8.6.10），但每次连接仍要走满 3 秒超时才兜底。
修法：先 `File('$workingDir/command.sock').existsSync()`，不存在直接走兜底重启。

### F5 🟡 P2（数据卫生）：删除订阅不清理实体与文件

`profiles_notifier.dart:52-80 deleteProfile` → `profile_data_source.dart:116-129 deleteById`
**只删 `profile_entries`**；`proxy_groups` / `proxy_entities` / `configs/<id>.entities.json` 全部留下。
后果：孤儿组污染 `syncedProfileIds()`、孤儿文件堆积。修法：删除后调实体仓库的清理 + 删文件。

### F6 🟡 P2（死代码）：`features/proxy/model/proxy_entity.dart` 已无消费者

`ProxyGroupEntity` / `ProxyItemEntity` 除自身与生成的 `.freezed.dart` 外 **0 处引用**
（本轮全库核对）；`hiddify_core_service.dart` 还有 67 行注释掉的旧实现。

### F7 💬 可选（**超出 NekoBox 对照范围，仅供选择**）：列表来源不可见

列表可能来自 `entities` 或回落 `config`（`offline_proxies.dart:62/73`），日志里有 `(from entities)`
但界面不体现。若希望"我删的节点到底生效没"一眼可判，可在设置页加一行实体层状态。
**这不是 NekoBox 项，标记为可选，未列入批次。**

---

## 4. 已验证无问题（避免重复排查）

| # | 项 | 证据 |
|---|---|---|
| V1 | 实体集合 = 订阅节点集合；无重复 tag、`user_order` 连续 | 真机：云霄 48/48、一分机场 36/36，type 全一致 |
| V2 | 组装幂等（无编辑时 `replaced=N, added=0, removed=0`） | 真机 `app.log` |
| V3 | `TaskEither` 体内 `rethrow` 已清零 | 余 6 处 `rethrow` 全在 `Stream`（`hiddify_core_service.dart:360/376/400/449` 等），非 Either |
| V4 | 内核 tag 判据正确（`select`/`balance`/`lowest`；`§hide§` 内部出站清单） | `builder.go:37-43`、真机 `current-config.json` |
| V5 | 选中校准幂等（含"不许把外部改选按回去"） | `check_selection_reconcile.dart` 15 项 |
| V6 | `ChangeHiddifySettings` 不重跑 builder ⇒ **无需加锁** | 本轮新核实：`buildconfighelper.go` 只反序列化 + 存库，无 `BuildConfig` 调用 |
| V7 | 内核未开放的项不重复投入（trafficSniffing 等） | parity §8.2 |

### 需拍板（不阻塞批次 1）
- **D1「0 节点」语义**：删到最后一个节点时，是（a）禁止删除该节点，还是（b）允许并显示"无可用节点"
  （需要验证内核在 0 节点配置下的行为）？
- **D2** 优先级文档里那两处：SN Link 逆向转换、路由规则管线的主从。

---

## 5. 下一步计划

### 批次 0 · 审计修正（✅ 已完成）

| 项 | 内容 | 状态与证据 |
|---|---|---|
| F3 | 判据收敛到 `runtime_outbound_tags.dart`（`kGroupOutboundTypes` / `kInternalOutboundTypes` / `isNodeOutbound`），其余文件改为引用；`offline_proxy_parser` 的 `hiddenTag` 包装与局部常量、`proxy_entity_import` 的两组局部常量全部删除 | ✅ 全库仅一处定义（另有 2 处裸 `§hide§` 判定留在 UI 统计侧，未在本批范围） |
| **F1 + F2** | `assembleOutboundsForProfile` 传 `staleTags`（由新增纯函数 `staleNodeTags()` 计算）；`🔒 WARP` 显式排除（双保险）；删空仍回落基准（避免产出 0 节点配置），UI 侧禁止删最后一个节点 | ✅ 真机：`removed=1`、`.entities.json` 51→50 且被删 tag 不在其中；新增 5 项断言（含"🔒 WARP 不进 stale"） |
| F5 | 新增 `ProxyEntityRepository.removeGroupForProfile()`（组 + 节点 + `<id>.entities.json`），在 `ProfileRepositoryImpl.deleteById` 调用；顺带修掉"配置文件不存在时整个删除报错" | ✅ 代码路径打通（真机删订阅待验） |
| F4 | `setSystemProxyEnabled` 先探测 `<workingDir>/command.sock`（仅桌面端），不存在直接返回 Left | ✅ 连接不再白等 3 秒超时 |
| F6 | 删除死文件 `features/proxy/model/proxy_entity.dart`（+ 生成的 freezed）；清 `hiddify_core_service` 的 4 段注释代码（含整段 `generateWarpConfig`） | ✅ analyze 0 issue |

**验收汇总**：6 个校验脚本全 ALL PASS（`check_config_assembly` 新增 5 项 `staleNodeTags` 断言，
共 32 项）、`flutter analyze --no-pub` 0 issue、release 构建通过、真机无新崩溃报告、DB 完整性复核通过。

### 批次 1 · 协议表单（P0，见 `nekobox-priority.md`）
规格已抽取完毕（字段/选择项/文案/内核 JSON key 四面对齐），实现顺序：
1. 字段规格模块（纯 Dart）+ 读写 helper
2. 校验脚本：真机 payload 逐节点核对"规格覆盖全部键"+"不改动时往返等价"
3. 表单 UI（行 + 弹窗，照 NekoBox 的 EditTextPreference/SwitchPreference/SimpleMenuPreference）
4. ✎ 接线：改 payload → 重组装 → `reconnect()` 重载（复用批次 0 修好的链路）
5. 自测：启动 → 点 ✎ → 改字段 → 查 DB 与 `current-config.json`

### 批次 2–6
见 `nekobox-priority.md`（其余 8 个协议表单 → 分组实体 + Group 页 → 路由/Assets → 分享导出 → 小功能三档）。

---

## 6. 本次审计用的手段（可复用）

1. **先画真源矩阵**（§2），再顺着五条链路走一遍，每走一步问"这块状态谁说了算"——
   F1 是这么找到的（`removed=0` 与"基准仍含旧节点"对上）。
2. **拿真机产物对账**：`db.sqlite` ↔ `configs/<id>.json` ↔ `data/current-config.json` 三方比对（V1）。
3. **读内核实现**而不是猜（V6：`ChangeHiddifySettings` 是否重跑 builder）。
4. **读 NekoBox 对应实现**判断"这算不算缺陷"：F1 的定性靠 `ConfigurationFragment.kt:1334-1341`
   （删除只写库、不 reload）＋ `ConfigBuilder.kt:131`（配置由 DB 现场构建，不存在"基准复活"）。
5. 启发式扫描：注释掉的代码、重复常量定义、`rethrow` 归属、无消费者的文件。

---

## 7. 这套审计思路凭什么可信 —— 以及它的边界

> 用户追问：「你是如何审计，确定你的审计思路没有问题」。本节是对方法本身的自审：
> 先写清自证机制（为什么不是"我觉得对"），再写清盲区（哪些结论只是"未证伪"）。

### 7.1 四条自证机制

| 机制 | 做法 | 本轮实例 |
|---|---|---|
| **结论必须是可证伪的具体命题** | 不写"可能存在双真源"，而写"`removed` 恒为 0" —— 能指向一个具体观察 | 真机 `app.log` 里恰好有 `removed=0` |
| **两条独立证据链交叉** | 静态（调用处从未传 `staleTags`）+ 动态（真机日志与"界面 47 / 内核 48"的背离）；**只有一条时不下 P0 结论** | F1 |
| **修复后同一观察必须反转** | 这是方法自证的关键：预测被验证，而不是"改完感觉好了" | `removed=0 → 1`；组装文件 `51 → 50` |
| **外部基准判定"算不算缺陷"** | 用 NekoBox 源码判定，而不是凭"我看着别扭" | `ConfigBuilder.kt:131`（配置由 DB 现场构建 ⇒ 不存在基准复活） |

此外还有一条"防过拟合"的机制：**反向清单**（§4 的 V1–V7）——只报问题会让人误以为别处没查，
所以明确列出"查过且没问题"的区域，既证明覆盖，也让后来者不重复排查。

### 7.2 已知盲区（**未证伪 ≠ 已验证**）

| # | 盲区 | 影响 |
|---|---|---|
| B1 | **静态为主**：本环境跑不了 `flutter test`，没有完整测试矩阵 | 竞态类问题只能靠日志/崩溃 dump 事后归因（注册表崩溃那次即是） |
| B2 | **真机数据覆盖面有限**：只有 2 份订阅 / 84 个节点 | 端口区间、WARP/chain、跨订阅同名 tag、0 节点等分支从未在真实数据里出现 ⇒ 只是"未证伪" |
| B3 | **只沿"有消费者的路径"遍历** | 完全无读者的孤儿逻辑不会被链路暴露（靠机械扫描补形状，语义仍可能漏） |
| B4 | **平台以桌面为主** | Android/iOS 管线只在代码层核对过 |
| B5 | **NekoBox 对照只读了相关文件** | "符合 NekoBox"仅限已读范围（分组/实体/配置构建/删除路径），未通读其 UI |
| B6 | **我自己的口径错误率不低** | 本轮前后共纠正 5 次（把 `.tmp.json` 当成启动文件、`transproxy`、`enable-tun-service`、4a 前提、`bypass-lan` 归属）⇒ **"读一个文件就下结论"是主要错误来源**，所以本节把"依据到 file:line"当硬要求 |

### 7.3 加固手段（把方法风险压下去）

1. **不变量变脚本**：已有 6 个 `tool/check_*.dart` + 真机 e2e 脚本。审计结论若不固化成断言，
   下一次改动就会重新漂移 —— 这是"思路长期没问题"的唯一保证。
2. **关键路径加可观测标记**：`(from entities)` / `(from config)`、`removed=N`、`replaced=N`
   —— 把"推断走了哪条路"换成"日志直接可读"。
3. **每个修复要求"改前可观察 + 改后同一观察反转"**，否则不算修完。
4. **未覆盖区域建待验证清单**（见 §7.4），而不是默认"没发现问题就是没问题"。

### 7.4 待验证清单（尚未证伪，按风险排序）

| 项 | 为什么还没验证 | 何时会暴露 |
|---|---|---|
| `server_ports` 端口区间（hysteria2 写法） | 你的订阅里没有该写法 | 遇到此类订阅即暴露 |
| WARP / chain 模式与实体组装共存 | 未在真机启用 | 打开 chain / extraSecurity 后启动 |
| 跨订阅同名 tag | 两份订阅没有重名节点 | 导入含重名节点的订阅 |
| 订阅本身 0 节点 | UI 已禁止删到 0，但"空订阅"这条路未测 | 导入空订阅 |
| 移动端管线 | 无设备，仅代码层核对 | 有 Android/iOS 设备时 |
| URL Test 在新链路下的实际测速 | 只验证了"下发参数正确"（空 tag → active） | 真机点一次测速并核延迟 |
