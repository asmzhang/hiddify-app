# NekoBox 对照 · 实施优先级（大功能先行）

> 2026-09-15 建。**这是执行顺序表，不是新规格** —— 每一项的字段/菜单/文案仍以
> `docs/design/nekobox-parity.md`（规格源 = `S:\test\NekoBoxForAndroid` 源码）为准。
> 用户要求：**先大功能、再小功能，轻重缓急对照 NekoBox**。

---

## 0. 什么算「大功能」——三条判据，都取自 NekoBox 的信息架构

1. **在 NekoBox 里独立成「一页」或「一个能力块」**：抽屉 10 项（`res/menu/main_drawer_menu.xml`）、
   节点页工具栏 32 项里的 4 个能力块（`add_profile_menu.xml`）。
2. **它操作的对象在 NekoBox 里是 DB 一等公民**（`ProxyEntity` / `ProxyGroup` / `RuleEntity` / `Asset`）。
   ⇒ 这类功能一律要过**实体层**，是体量的来源。
3. 单点接线 / 单个开关 / 单个菜单项 = **小功能**。

判据 2 的解释力最强：NekoBox 强的那一栏（本地节点库、手动分组、协议表单）全部长在
"DB 是配置真源"这个前提上 —— 所以**大功能 = 实体层能力**，顺序由实体层的依赖决定，而不是由"哪个好做"决定。

---

## 1. 前置：实体层已完工（这是所有大功能的地基，已自测通过）

| 环节 | 状态 | 证据 |
|---|---|---|
| drift v7 两表（`ProxyGroups` / `ProxyEntities`，payload 含凭据） | ✅ | `478e9ff9`，schema 导出含 4 表 |
| 订阅写入 → 派生实体落库（导入管线） | ✅ | `fb5fb9b6` |
| 对既有订阅回填 | ✅ | `5f74a74d`，真机 DB 84 行（云霄 48 + 一分机场 36） |
| 出站表组装（实体覆盖基准）→ 内核按此启动 | ✅ | `4075077d` + 自测 `replaced=48, added=0, removed=0` |
| 列表以实体为准（NekoBox `proxyDao.getByGroup`） | ✅ | `16dfdc49` |
| 节点删除 + 撤销（`removeNode` / `restoreNode`） | ✅ | `16dfdc49` + 自测 DB 47→46→47 |
| 分组模型定案（一份订阅 = 一个分组 = 一个 Tab） | ✅ | `bcb95c64`，真机截图无「自动选择」 |

**⇒ 现在缺的只是「写入口」和「非订阅分组」。** 这正是下面 P0、P1 的位置。

---

## 2. 大功能（按建议顺序）

### 批次 0 · P0-pre：审计修正（✅ 已完成，见 `docs/audit/2026-09-15-full-logic-audit.md` §3/§5）

| 项 | 内容 |
|---|---|
| F3 | "什么算节点/组/隐藏出站"的判据收敛到 `runtime_outbound_tags.dart` 一处（现散在 3 个文件 + 2 处裸字符串） |
| **F1 + F2** | **删除的节点会被订阅基准"复活"**：`assembleOutboundsForProfile` 从未传 `staleTags`（默认 `const []`），于是 `removed` 恒为 0、内核里那个节点还在。修法 = 让实体对节点段有最终裁量权（`staleTags = 基准里的节点 tag − 实体 tag`，组与 `§hide§` 不动）；同时定义"删空"的语义 |
| F5 | 删除订阅时清理 `proxy_groups` / `proxy_entities` / `<id>.entities.json`（现只删 `profile_entries`） |
| F4 | 系统代理 RPC 明知会失败（本内核无 `command.sock`）仍等 3 秒 → 先探测 socket 再决定是否直走兜底 |
| F6 | 删死文件 `lib/features/proxy/model/proxy_entity.dart`（0 消费者）；清 `hiddify_core_service` 的注释块 |

**为什么必须在批次 1 之前**：F1 与"编辑"是同一机制 —— 不先修，表单做出来会"改了没反应"（删除现在就是这个症状）。

### 批次 1 · P0：节点编辑表单（协议表单第一批 4 个）—— ✅ **第一刀已完成**（2026-09-15）

| 项 | 状态 |
|---|---|
| **表单数据层**（`lib/features/proxy/data/protocol_form.dart`，纯 Dart 可校验） | ✅ 4 份规格：anytls / vless（含 vmess 复用）/ hysteria2 / shadowsocks ⇒ **真机 84 节点 100%**。字段、顺序、分节（`PreferenceCategory`）全部取自 NekoBox `res/xml/*_preferences.xml`；下拉取值照 `res/values/arrays.xml` 原样抄（utls 11 / ss 加密 18 / packet_encoding 3 / networks 6） |
| **表单 UI**（`lib/features/proxy/widget/protocol_form_modal.dart`） | ✅ 规格驱动：文本 / 数字 / 开关 / 下拉 / 列表五种形态，按分节渲染。差异：NekoBox 是独立全屏 Activity，这里用底部弹窗 |
| **节点行 ✎ 接线** | ✅ `proxy_tile.dart` 补齐 `edit → share → remove`（顺序照 `layout_profile.xml`），`editEnabled = !(已选中 && 正在使用)` 照 `ConfigurationFragment.kt:1624-1625` |
| **写回链路** | ✅ 表单值 → 新出站 JSON → `proxy_entities.payload`（`updateNodePayload`）→ invalidate 列表 → `reconnect()` 重载内核（契约＝只动内核、不动接管状态） |
| **校验** | ✅ `tool/check_protocol_form.dart` **69 项断言 ALL PASS**；7 个脚本全 PASS；`flutter analyze` 0 issue；release 构建通过 |
| **最重要的不变量** | **往返幂等**：读出来原样写回，payload 逐字节等价 —— 也就证明了「表单没管理的键（`tls.reality` / `stream_receive_window` / `tls.utls.enabled` …）全部原样保留」。这条用真机 4 种协议的实测 payload 逐条断言 |

**本条未纳入的（如实列出，不是"完成"）**：
- **改名**（NekoBox `name_preferences.xml`）：`tag` 是节点身份（内核配置 / 选中偏好 / `staleNodeTags` 基线三处都用它），改名要跨这三处迁移 ⇒ 属独立改动，不混进编辑表单。
- **ECH**（`anytls` / `v2ray` 表单的 `enableECH` + `echConfig`）：sing-box 侧是 `tls.ech.config` 数组，真机 0 个节点用到 ⇒ 留待需要时补。
- **shadowsocks 的 `sUoT`**：sing-box 侧是 `udp_over_tcp:{enabled,version}` 对象，NekoBox 表单只给一个布尔（版本无从选），真机 0 节点用到。
- **hysteria2 的 `protocolVersion` / `serverProtocol` / `serverAuthType` / `serverDisableMtuDiscovery`**：前三个是 v1 概念或纯 UI 选择项，第四个被 NekoBox 自己注释掉（`HysteriaFmt.kt:334`）。
- **其余 8 份协议表单**（socks / ssh / tuic / shadowtls / mieru / naive / trojan_go / wireguard）⇒ 批次 2，照同一套规格结构补数据即可（框架已就位）。

**验收（已自测）**：改一个节点的 server/端口 → 实体 payload 变 → 内核 `current-config.json` 里该出站跟着变 → 列表地址行跟着变。

### 批次 2 · P0b：协议表单剩余 8 个 + 自定义配置

`socks` / `ssh` / `tuic` / `shadowtls` / `mieru` / `naive` / `trojan_go` / `wireguard`（对应 8 份 XML）
＋ `config_preferences.xml`（自定义配置）＋ `balancer_preferences.xml`（负载均衡组）。

每个表单都能独立交付，按你订阅里出现的协议先后补即可。

### 批次 3 · P1：分组实体能力 + Group 页 —— ✅ **第一刀已完成**（2026-09-15）

| 项 | 状态 |
|---|---|
| **① 组不再必然绑定订阅** | ✅ `ProxyGroupType.basic` 用上了：`createGroup` / `ensureUngroupedGroup` / `renameGroup` / `removeGroup` / `groupWithNodes` / `createNode`（`proxy_entity_repository.dart`），默认值逐项照 NekoBox `ProxyGroup.kt:14-25` |
| **② Group 页** | ✅ `lib/features/proxy/overview/groups_page.dart` = `GroupFragment` + `add_group_menu` 的"创建分组"；列表项照 `LayoutGroupItem`（组名 + `group_status_empty`「空」/`group_status_proxies`「N 个配置」/ `group_status_empty_subscription`「从未更新」 + ✎ + 🗑）。导航项 `nav_group` 已加（顺序照抽屉：配置 → **分组** → 路由 → 设置） |
| **③ 手动新建节点** | ✅ NekoBox 节点页 ＋ → **Manual Settings**（`add_profile_menu.xml:25-78`）→ 选协议（4 项，顺序照它的子菜单）→ 协议表单**新建模式**（多一个"配置名称"字段 = NekoBox 的 `profile_name`）→ 落组。协议表单的"从零构造"种子键见下 |
| **④ 组作为 Tab** | ✅ 手动分组与订阅分组统一进 `proxyGroupTabsProvider`；**空的未分组组不进 Tab**（照 `ConfigurationFragment.kt:923-924`/`:1031`） |
| **⑤ 手动节点进内核** | ✅ `assembleOutboundsForProfile` 追加手动组节点（NekoBox 全库一份配置；本项目是"一份订阅一份配置"，所以要把手动节点合并进去）。tag 撞车时**订阅侧优先并告警** |
| 未做 | ~~分组动作菜单（分享/导出/清空）~~ ✅ 已做（groups_page ⋮ 菜单）、~~分组排序拖拽~~ ✅ 已做（2026-09-16：groups_page ReorderableListView + repo `moveGroups` 整表重算 userOrder；NekoBox `GroupFragment.move` 的语义结果 = 界面序即权威序，`tool/check_group_reorder.dart` 17 项校验；NekoBox 的 from>to 列表缺陷不移植，我们落库走最终序无此问题）、前后置代理（等 chain 术语定案，见 §7 与 parity §5）、`group_preferences.xml` 的完整 11 项表单（本批只做了 name/新建/删除；type/order/isSelector/front/landing 的编辑表单未做） |

**验收（已自测）**：手动建一个 anytls 节点 → 落到「未分组」→ 该组作为 Tab 出现 → 节点可选中/编辑/删除，
内核 `.entities.json` 里出现该出站且**原有 48 个节点一个不少**。

**本批新增的两个设计要点（不是细节）**：
1. **`ProtocolFormSpec` 需要"种子键"**（`protocolSeedPayload`）。编辑时 `tls.enabled` 这类键靠
   "原样保留"活下来；新建时没有"原样"可保留 ⇒ 必须显式给，否则内核会拒。
   取值只取自 NekoBox 构建函数里写死的部分（anytls/hysteria2 的 `tls.enabled = true`；
   vless 的 `security` 默认空 ⇒ **不带** tls）。**新建与编辑共用同一条写入路径**
   （`buildProtocolPayload` 内部就是 `applyProtocolForm`），所以不存在第二条会写坏配置的路。
2. **手动节点的 Tab 键与选择归属**：Tab 键用 `#group:<id>`（与订阅的 `<uuid>::<名>` 天然不冲突，
   且 `parseGroupKey` 对它返回 null ⇒ `changeProxy` 的"要不要切订阅"判据自然落到"不用切"）。
   选中的**所有权**：手动节点被追加进每一份配置，所以选中它以 `profileId: ''` 落盘 ——
   `decideSelectionReconcile` 对空 `desiredProfileId` 不做 `waitForProfile`，
   于是切订阅后它仍然生效（这正是手动节点该有的语义）。

### 批次 4 · P2：路由实体编辑 + Assets 管理

| 项 | 内容 |
|---|---|
| NekoBox 规格 | `res/xml/route_preferences.xml`（9 字段：routeName/serverConfig/routePackages/routeDomain/routeIP/routePort/routeSource/routeSourcePort/routeNetwork/routeProtocol/routeOutbound）＋ `ui/RouteSettingsActivity` ＋ `ui/AssetsActivity`（geo 资源管理）＋ `global_preferences.xml` 的 `rulesProvider` |
| 现状 | §1 `nav_route` ✅ 已有规则模型与预设规则（`RuleEntity` 对应 `RuleEntity` ✅，hiddify 版更细：domain/ip/port）；缺 ① 新建/编辑的 9 字段表单 ② **Assets 源选择与资源更新** |
| 备注 | 这是 NekoBox 与 hiddify **差异最大的一块**（hiddify 有独立 DNS/路由选项，NekoBox 走规则集），要做到"完全对照"需要先定：是补 NekoBox 的规则集管线，还是保留 hiddify 的规则模型 + 补它的编辑 UI |

### 批次 5 · P3：订阅/分组的分享与导出

| 项 | 内容 |
|---|---|
| NekoBox 规格 | `res/menu/profile_share_menu.xml`（9 项：QR→Group/Standard/SN Link、Export→Clipboard/File、Configuration→Clipboard/File）＋ `group_action_menu.xml` |
| 现状 | §3.2/§3.3 全 ❌：只有**节点级**「复制出站 JSON」（`extractOutboundJson`），没有订阅级分享 |
| 依赖/风险 | **SN Link 需要逆向转换**（出站 → 分享链接）。hiddify 只有正向 `ray2sing`，没有反向 ⇒ 要么新写，要么这一项退化为"导出标准链接 + JSON"。**这是要你拍板的一处**（见 §5） |

### 批次 6 · P4：小功能（可随时插空，不阻塞大功能）

| 档 | 内容 | 说明 |
|---|---|---|
| A 立即可做 | `TCPing`、清空测速结果、清除不可用节点、去重、日志清空/导出、导入文件、扫码可用性确认、仪表盘连接项菜单（复制名称/包名、打开应用/设置） | 纯 app 侧，多数是单点实现；"清空测速结果"需先确认统计来源（`hcore_service.proto` **无 clear 类 RPC**） |
| B 需 Android 管线 | `speedInterval`(通知速率)、`showDirectSpeed`、`showGroupInNotification`、`alwaysShowAddress`、`meteredNetwork`、`acquireWakeLock`、订阅 TLS 下限/跳过证书检查、快捷方式三动作、磁贴 `TileService`、`BootReceiver` 开机自启、导出用 `FileProvider` | 桌面端多数无意义；按平台分支做 |
| C 内核卡住（不做） | `trafficSniffing`、`appendHttpProxy`、`domain_strategy_for_server`、`networkChangeResetConnections`/`wakeResetConnections`、clear 类 RPC | `builder.go` 里被注释或全库 0 命中；要做需先动内核（见 parity §8.2） |

**设置面收尾**：`global_preferences.xml` 的 29 项里，`bypassLanInCore` 已完成（`d672db7e`）；
`serviceMode` 已实质对齐（NekoBox 的 `transproxy` 是资源里的死项，代码只分支 vpn/proxy，parity §8.5）；
其余缺口都在上表 A/B/C 三档里。

---

## 3. 为什么是这个顺序（依赖链，不是偏好）

```
实体层（已完成）
   ├─→ 批次 1/2  协议表单  ← 只依赖"订阅组的实体行"（已就绪）⇒ 可以立刻做
   ├─→ 批次 3    分组/Group 页 ← 需要"组不再绑定订阅"（新模型能力）⇒ 必须先于手动新建节点
   │                └─→ 手动新建节点（Manual Settings 15 项）
   ├─→ 批次 4    路由/Assets ← 与上面并行不冲突（不同实体）
   └─→ 批次 5    分享导出   ← 需要"稳定的实体集合"（删除/编辑后仍能导出）⇒ 排在编辑之后
小功能（批次 6）不依赖任何大功能，可穿插；但**不要先做小功能**：
它们是 32 项工具栏/29 项设置里的单点，做完用户仍会觉得"节点不能编辑 = 功能不全"。
```

---

## 4. 判断"缓急"的一条硬标准（本项目特有）

**凡是要"对内核说话"的地方，先读 kernel 实现再动手**（parity §10 规程）。本项目已被这条救回过多次：

- `SelectOutbound(groupTag)` 必须传运行期常量 `select`，不是订阅组名（`commands.go`）
- `UrlTest` 只在 `Tag == ""` 时测 active（`commands.go`）
- 组由内核 `setOutbounds` 重建（tag 恒为 `select`/`balance`/`lowest`），应用只该管**节点那一段**
- `enable_raw_config` 不可用（会丢掉内核生成的 inbounds/dns/route），`GenerateConfig` RPC 是注释掉的
- 内核注册表**不可重入** ⇒ 会重建注册表的 RPC 必须在应用侧串行化（`67647b8d`）
- 系统代理链路依赖 `command.sock`，而内核**没有启动**命令服务器 ⇒ 靠"重启内核让 sing-box 自己设"兜底

⇒ 每个批次动手前，第一件事是确认**该功能依赖的内核能力是否存在**（存在=直做；不存在=先决定改内核还是降级）。

---

## 5. 需要你拍板的两处（其余按上表自走）

1. **批次 5 的 SN Link**：hiddify 没有"出站 → 分享链接"的逆向转换。是（a）新写一个转换器，
   还是（b）这一项退化为"导出标准链接 + 出站 JSON"？
2. **批次 4 的规则管线**：补 NekoBox 的规则集（`rulesProvider` + Assets），还是保留 hiddify
   现有的细粒度规则模型、只补它的编辑 UI？（两者可以共存，但**谁是主**要定一个）

---

## 6. 执行纪律（沿用既有约定）

- 规格**只从 NekoBox 源码取**，不自行发明字段/文案（parity 文档 §10）
- 每批收尾三件：`dart run tool/check_*.dart` 断言全过 + `flutter analyze --no-pub` 0 issue + `flutter build windows --release` 通过
- UI/数据链路改动用 `windows-gui-self-test` skill **自己跑一遍再交**（截图 + DB 计数），不要推给用户
- 状态回写到本文件与 `nekobox-parity.md`；推翻先前判断要留"口径纠正"记录

---

## 7. 逻辑梳理：第五类「功能重叠可融合」14 项落到哪一批

> 来源：`docs/audit/2026-09-15-nekobox-function-matrix.md` §7。本节只做一件事 ——
> **把"可融合"翻译成"它属于哪一批、前置是什么"**，因为融合的前提是"那个页面/数据已经存在"，
> 与批次顺序强相关。它们**不该单独占一个批次**（否则又变成"并列两套"）。

| # | 融合项 | 并入 | 前置（现在有没有） |
|---|---|---|---|
| M5 | 磁贴由"硬充"变可用 | 批次 6-A（平台组件） | ✅ `ShortcutActivity` + `toggleConnection()` 都在；成本≈接状态回调 |
| M2 | 备份加"配置/规则/设置"三勾选 | 批次 6-A | ✅ 备份 tab 与 JSON 导出已在 |
| M7 | 测速三项合一个菜单（URL Test / TCPing / 清空结果） | 批次 6-A | 🟡 TCPing 纯应用侧；清空结果要应用侧自记（内核无 clear RPC） |
| M1 | 统计页把"连接"做成可展开列表 + 4 个连接动作 | 批次 6-A（也能升为独立小批） | ✅ `singbox_stats` 本来就有 `connections` —— 不必引入 yacd webview |
| M6 | 分享统一成"粒度 × 形式"一个面板 | **批次 5**（与它同批） | ✅ 扫/显两个 QR 组件已在；导出走 FilePicker |
| M3 | Assets 做成 Route 页的"规则资源"入口 | **批次 4**（与它同批） | 🟡 规则模型已有引用；资源文件管理需新增 |
| M8 | 两个 Bypass LAN 在 UI 上互为说明 | 批次 4 收尾 | ✅ 两边实现都在（`bypassLanInCore` 已做） |
| M11 / M12 | 两个 JSON 编辑器共用一个外壳 | **批次 3 之后**（手动节点建出来后才有"节点级 JSON"的场景） | ✅ `json_editor` + `extractOutboundJson` 已在 |
| M4 | 快捷方式三动作共用一个 Activity | 批次 6-B（Android 管线） | ✅ |
| M9 / M10 / M14 | 不新建（已在代理页 / 应用页 / 无需中转表覆盖） | —— | —— |
| M13 | yacd 面板：选 (a) 融合（＝M1）还是 (b) 引入 webview | **待拍板**（与 D2 同批） | 🟡 (b) 要打包 yacd 资源 |

**一句话**：14 项里 **11 项能把"完全漏/硬充"降级为"在已有页面扩一段"**，但它们**一律不改变批次顺序** ——
它们全部依附于"那个页面先存在"（统计页 / 备份 tab / Route 页 / 分享面板）。所以顺序仍然是 §2 的批次表。

---

## 8. 下一步（现状 + 三个候选，判据已给）

### 8.1 现在的状态（一句话）

**实体层已完工 + 表单基础设施已就位** ⇒ NekoBox 那条"应用侧把配置当真源"的线上，
缺的已经不是"能不能写"，而是**"往哪儿写"**：现在只能改**订阅派生出来的**节点，
还不能**新建**节点/分组 —— 因为组目前必然绑定订阅（`syncFromProfile` 认领的组）。

### 8.2 三个候选

| 候选 | 内容 | 判据 | 成本 | 依赖拍板 |
|---|---|---|---|---|
| **A. 批次 3（分组实体 + 手动建组/节点）** | 组不再必然绑定订阅（用上 `type=basic` / `ungrouped`）；Group 页；分组动作菜单；前后置代理 | **它才是"大功能"**（NekoBox 里 Group 是独立一页、`ProxyGroup` 是 DB 一等公民）；且**它解锁 Manual Settings 15 项**——而手动建出来的节点马上就能用刚做好的表单编辑 | 大 | 不需要 |
| B. 批次 2（其余 8 份协议表单） | socks / ssh / tuic / shadowtls / mieru / naive / trojan_go / wireguard | 现在只补数据（框架已就位），但**真机 0 个节点用这些协议** ⇒ 纯 parity 完整性，无即时收益 | 小 | 不需要 |
| C. 批次 6-A 的低成本项 | M5 磁贴 / M2 备份勾选 / M7 测速三项 / M1 统计页连接列表 | 性价比最高，但按你定的规矩「**不要先做小功能**」——做完用户仍会觉得"节点不能新建 = 功能不全" | 小 | 不需要 |

**建议顺序：A → C（穿插）→ B**。理由：A 是唯一还能"解锁一整块能力"的项，
且它刚好吃到本批的红利 —— **规格驱动的表单天然支持"新建"模式**（空 payload + 默认值），
所以 A 里"手动新建节点"这一步比原先估计便宜得多。

### 8.3 做 A 之前必须先定的两件（都是技术前提，不是偏好）

1. **`ProtocolFormSpec` 需要 `defaultPayload`（每个协议的"从零构造"种子）**。
   现在表单是"改已有 payload"，`tls.enabled` / `transport.type` 这类**不在表单里但必须存在**的键
   是靠"原样保留"活下来的。从零新建时没有"原样"可保留 ⇒ 必须显式给出种子
   （例：anytls 种子里 `tls:{enabled:true}`；vless `security=tls` 时 `tls:{enabled:true}`）。
   这也顺带把"哪些键是协议必需的"从注释变成数据。
2. **手动节点的 `tag` 怎么来**（= §8.4 的改名问题）。NekoBox 用 `displayName()`（用户填的名字），
   而 `tag` 是内核配置里的身份 ⇒ 新建时一次性定，之后改名仍走批次 1 的"未纳入"那条路。
   **结论：改名应该和"新建"一起做**（同一套 tag 迁移机制），否则手动节点建出来就再也改不了名。

### 8.4 仍待你拍板的两处（不改判据，只是提醒）

1. **D1 · SN Link（批次 5）**：hiddify 没有"出站 → 分享链接"的逆向转换。
   (a) 新写转换器，还是 (b) 退化为"导出标准链接 + 出站 JSON"？
2. **D2 · 规则管线（批次 4）**：补 NekoBox 的规则集（`rulesProvider` + Assets），
   还是保留 hiddify 现有的细粒度规则模型、只补它的编辑 UI？**谁是主**要定一个。（两者可共存）
   - 附：**M13（yacd 面板）**与此同批 —— 选 (a) 融合进统计页（＝M1）可省掉一整个 webview 模块。

