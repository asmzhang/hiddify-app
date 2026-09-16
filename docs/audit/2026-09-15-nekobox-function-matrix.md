# NekoBox 功能审计 · 四分类矩阵（2026-09-15）

> 用户要求：**对照 `S:\test\NekoBoxForAndroid` 做功能审计**，把每一项分成四类：
> **1:1 完成 / 硬充（有壳无实或同名不同物）/ 没有完成（部分）/ 完全漏（0）**。
>
> 本文件与 `nekobox-parity.md` 的分工：parity 是**规格与现状清单**（✅/🟡/❌），
> 本文件是**按"是否真能用/是否真是 NekoBox 那个东西"重判**的结果 —— 两者结论不同的地方在 §4 逐条说明。
> 判定依据一律给到 file:line 或源码行；**没能逐条核对的项会明确标注"按 parity 归类（未复核）"**。

---

## 0. 先把四类的边界定死（否则判定不可复现）

| 类别 | 定义 | 反例（为什么不算） |
|---|---|---|
| **1:1 完成** | 语义、操作对象、行为都与 NekoBox 一致，只是实现栈不同（Kotlin/View ↔ Dart/Flutter） | —— |
| **硬充** | **有入口、有壳，但不是 NekoBox 那个东西**：骨架注册了却没实现、名字相同而语义不同、用别的功能顶上 | manifest 注册了磁贴服务但 Dart 实现全被注释 ⇒ 用户点了没反应 |
| **没有完成** | 方向对、已有部分：字段缺一段、只覆盖一支、形态有差异导致少功能 | 备份只有"匿名/全部"两档，缺 NekoBox 的"配置/规则/设置"分类勾选 |
| **完全漏** | NekoBox 有、这里 0 命中 / 无入口 / 无对应表 | 12 份协议表单 |
| 🅝 不移植 | 用户既有约定（推广位、文档页） | —— |

---

## 1. 汇总

| 区域 | 1:1 | 硬充 | 没有完成 | 完全漏 |
|---|---|---|---|---|
| 导航页（8 个可移植项） | 5 | 1（Dashboard） | 1（代理页缺 ✎） | 1（Group 页） |
| 节点页工具栏（32 项归并 25 项） | 10 | 1（Proxy Chain） | 1（自定义配置） | 13 |
| 动作菜单（7 份） | 2 | 0 | 1 | 4 |
| 设置（29 项） | 10 | 1（Auto Connect） | 1（Bypass LAN） | 17 |
| 协议表单（12 份） | **4** | 0 | 0 | **8** |
| 平台组件（可移植 12 项） | 7 | 2（磁贴 / 开机自启） | 2（快捷方式 / 备份） | 2（Assets / yacd） |
| 数据实体（6 项） | 5 | 0 | 0 | 1（TempDatabase，无功能影响） |
| **合计** | **43** | **5** | **6** | **46** |

> **2026-09-15 更新（批次 1 第一刀）**：anytls / standard_v2ray（VLESS）、hysteria、shadowsocks
> **4 份协议表单已 1:1 完成**（+ 节点行 ✎ 接线），覆盖真机 84 个节点的 100%。
> ⇒ 协议表单 完全漏 12→8、合计 1:1 39→43 / 完全漏 50→46。
> 逐项证据见 `docs/design/nekobox-priority.md` §2 批次 1（含未纳入字段的如实清单）。
> 另：本文 §2.1 的「代理页缺 ✎」已随之由 **没有完成 → 1:1**（但未从合计里加回，因为"代理页"整行
> 还含其他子项；这是保守计数）。

> 另有两类不在上表：**hiddify 特有 18 项**（NekoBox 没有，见 §6）与
> **功能重叠可融合 14 项**（不该新建，应融进已有页面，见 §7 —— 其中 11 项能把"完全漏/硬充"降级为"扩一处"）。

---

## 2. 逐项矩阵

### 2.1 导航页（规格：`res/menu/main_drawer_menu.xml`）

| 功能 | NekoBox 规格源 | 当前状态（证据） | 判定 |
|---|---|---|---|
| Configuration 代理页 | `ui/ConfigurationFragment.kt`（1482 行） | 列表/卡片/状态栏/排序/测速/删除撤销都在；**节点行 ✎ 已补齐**（`protocol_form_modal.dart`，4 协议覆盖真机 84 节点 100%，2026-09-15） | **1:1** |
| Group 分组页 | `ui/GroupFragment.kt` + `group_preferences.xml` | 无页面；`proxy_groups` 表只有订阅派生组（`db.dart`），**无手动建组 UI**（`createGroup` 仅 1 处命中，是建表注释） | **完全漏** |
| Route 路由页 | `ui/RouteFragment.kt` + `route_preferences.xml` | `rule_page.dart` + `generic_list_page.dart`：domain/ip/port/source/network/protocol/outbound 全在，含预设规则 | **1:1**（规则集/Assets 另计） |
| Settings 设置页 | `ui/SettingsFragment.kt` | `settings_page.dart`（五类内联 + 子页 dns/inbound/tls-tricks/chain） | **1:1**（缺项见 2.4） |
| Logs | `ui/LogcatFragment.kt` | `logs_page.dart`：分享内核/应用日志、清空（`:36/:45/:77`） | **1:1** |
| sing-box Dashboard | `ui/WebviewFragment.kt` + `assets/yacd.zip` | `stats_overview_page.dart`：自研"连接统计/实时/总计"卡片；**无连接列表、无按连接菜单、无规则创建、无面板 URL** | **硬充** ⚠️ |
| Tools | `ui/ToolsFragment.kt` = 网络 tab + 备份 tab | `tools_page.dart`：`_NetworkTab`（STUN，`:46-95`）+ `_BackupTab`（`:117-181`） | **1:1**（结构一致） |
| About | `ui/AboutFragment.kt` | `about_page.dart` | **1:1** |
| Ads / Document | `nav_tuiguang` / `nav_faq` | —— | 🅝 |

### 2.2 节点页工具栏（规格：`res/menu/add_profile_menu.xml`，32 项）

| 功能 | 当前状态 | 判定 |
|---|---|---|
| Update all subscriptions | `profiles_page` 批量更新 | 1:1 |
| Add Profile / Import Clipboard / Import file / Scan QR | `fix_btns.dart:29/40/60/75`：剪贴板、文件（`FilePicker`）、扫码（`showQrCodeScanner()`）、手动链接 | **1:1** |
| Scan QR code（可用性） | 旧文件 `qr_code_scanner_screen.dart` 里 403 行前的实现**全被注释**，但底部 `QrCodeScannerDialog`（`:403-464`）是活的且已接线 | 1:1（旧实现是"未完成"的残留） |
| Update current group's subscription | 详情页/订阅页更新 | 1:1 |
| Order → Origin / By Name / By Delay | `ProxiesSort`（+ hiddify 多的 usage） | 1:1 |
| URL Test | 菜单"测试全部"→ 空 tag 走 active（对齐 `commands.go`） | 1:1 |
| **Manual Settings（15 个协议新建）** | 0 命中（`newProxy/addProxy/manualNode` 全无） | **完全漏** |
| **Create group** | 无 UI | **完全漏** |
| **Custom Config（新建自定义配置）** | 无"新建"入口；`profile_details_page` 的 `json_editor.dart` 是**订阅级**编辑 | **没有完成** |
| **Proxy Chain** | `chain_options_page.dart` 是 hiddify 自己的 WARP/Psiphon 前置链（`extraSecurity`/`unblocker`），**不是 NekoBox 的 front/landing 代理** | **硬充** ⚠️ |
| Clear traffic statistics | 无（且内核无 clear 类 RPC） | 完全漏 |
| Remove duplicate servers | 0 命中 | 完全漏 |
| TCPing | 0 命中 | 完全漏 |
| Clear test results | 0 命中 | 完全漏 |
| Clear unavailable | 0 命中 | 完全漏 |

### 2.3 动作菜单（`res/menu/*.xml`）

| 菜单 | 内容 | 当前状态 | 判定 |
|---|---|---|---|
| `profile_config_menu` | Remove/Apply/Move/Create Shortcut/Custom outbound JSON/Custom config JSON | Remove/Apply/Move 有；Create Shortcut 部分（Android）；两个 Custom 缺 | **没有完成** |
| `profile_share_menu`（9 项） | QR(组/标准/SN Link)、导出剪贴板/文件、配置导出 | 0 命中（`shareSubscription/exportProfile/snLink`） | **完全漏** |
| `group_action_menu`（6 项） | 分组分享/导出/清空 | 无分组页 ⇒ 无从谈起 | **完全漏** |
| `traffic_item_menu`（4 项） | 复制名称/包名、打开应用/设置、创建规则 | 0 命中 | **完全漏** |
| `app_list_menu` / `per_app_proxy_menu` | 反选/清空/导出剪贴板/导入剪贴板 | `per_app_proxy_page.dart:163-212`：导入（剪贴板/文件）、导出（剪贴板/文件）、清空全部、清空自动选择 | **1:1**（比 NekoBox 更全） |
| `logcat_menu` | Update / Export debug info / Clear | 分享+清空有；"导出调试信息"以分享日志近似 | **1:1** |
| `yacd_menu` | 设置面板 URL / 关闭 | 无内嵌面板 | **完全漏** |
| `route menu` | Create Route / Reset / Manage Route Assets | 规则增删有；**Assets 管理缺** | **1:1**（Assets 另计） |

### 2.4 设置（`res/xml/global_preferences.xml` 29 项）

**1:1（10）**：`appTheme` / `nightTheme` / `serviceMode` / `tunImplementation` / `mtu` / `logLevel` /
`proxyApps`（每应用代理）/ `resolveDestination` / `ipv6Mode` / `bypassLanInCore`（本批 `720255f0` 刚修）

**硬充（1）**：`isAutoConnect` —— hiddify 是 `silent_start` + 启动即起内核，语义不同。

**没有完成（1）**：`bypassLan` —— NekoBox 是应用侧分流开关，hiddify 走"预设规则 → Bypass LAN"。

**完全漏（17）**：
`speedInterval` / `showDirectSpeed` / `showGroupInNotification` / `alwaysShowAddress` / `meteredNetwork` /
`acquireWakeLock` / `globalCustomConfig` / `profileTrafficStatistics`（只有展示无独立开关）/
`rulesProvider`（Assets 源） / `appTLSVersion` / `globalAllowInsecure` / `allowInsecureOnRequest` /
`trafficSniffing`※ / `appendHttpProxy`※ / `domain_strategy_for_server`※ /
`networkChangeResetConnections`※ / `wakeResetConnections`※ 　（※ = 内核也未开放，属 C 组，见 parity §8.2）

### 2.5 协议表单（`res/xml/*_preferences.xml`）

**12 份协议表单（anytls/shadowtls/shadowsocks/standard_v2ray/trojan_go/tuic/hysteria/mieru/naive/socks/ssh/wireguard）
＋ config / balancer / group / route / name 五份表单**

| 判定 | 说明 |
|---|---|
| **1:1（4 份，2026-09-15 批次 1）** | `anytls` / `standard_v2ray`（VLESS；VMess 复用同一规格）/ `hysteria`（v2）/ `shadowsocks`。规格源 `res/xml/*_preferences.xml` + `ui/profile/*SettingsActivity` + `fmt/*/*Fmt.kt` 三方对齐；真机 84 节点 100% 覆盖。证据：`lib/features/proxy/data/protocol_form.dart` + `tool/check_protocol_form.dart`（69 项断言） |
| **完全漏（8 份协议表单）** | `socks` / `ssh` / `tuic` / `shadowtls` / `mieru` / `naive` / `trojan_go` / `wireguard` —— 框架已就位（补规格数据即可），见 `nekobox-priority.md` 批次 2 |
| **完全漏（4 份）** | `config_preferences`（自定义配置）/ `balancer_preferences` / `group_preferences` / `name_preferences`（备注名；改名要动 `tag`，与"手动新建节点"同一套机制） |
| **没有完成（1 份）** | `route_preferences`（9 字段）：规则模型有了，但"新建规则表单"未按它的字段结构对齐 |

### 2.6 平台组件（`AndroidManifest.xml`）

| 组件 | NekoBox | hiddify 现状（证据） | 判定 |
|---|---|---|---|
| MainActivity / VPNService / ProxyService | 有 | `AndroidManifest.xml:44/108/122`（接管机制不同，语义等价） | 1:1 |
| ScannerActivity | 扫码页 | `QrCodeScannerDialog`（`qr_code_scanner_screen.dart:403-464`） | 1:1 |
| AppListActivity / AppManagerActivity | 应用列表/管理 | `per_app_proxy_page` + `android_apps_page` + `auto_apps_selection_modal` | 1:1 |
| StunActivity / NetworkFragment | STUN | `tools_page._NetworkTab` + `stun_client.dart` | 1:1 |
| ProfileSelectActivity / SwitchActivity | 选择器（复用 ConfigurationFragment） | 代理页本身即可切节点 | 1:1 |
| FileProvider（导出用） | 有 | 走 `FilePicker` / 导出文件，能力等价 | 1:1 |
| **QuickToggle/Enable/Disable 三个快捷方式** | 3 个 | `shortcuts.xml` 只有 **1 个（toggle）**；`shortcut_wrapper.dart` | **没有完成** |
| **TileService（快捷磁贴）** | 无此项（hiddify 独有） | manifest 已注册 `.bg.TileService` + `TOGGLEABLE_TILE`，但 `android_quick_settings_tile.dart` **57 行全部被注释** ⇒ 点了没反应 | **硬充** ⚠️ |
| **BootReceiver（开机自启）** | 有 | 无 receiver；靠 `SUPPORTS_ALWAYS_ON` 元数据 + `autoStart` 设置替代 | **硬充** ⚠️ |
| **BackupFragment（备份/恢复）** | 勾选"配置/规则/设置"→ 导出；导入后重启；重置设置 | `tools_page._BackupTab`：匿名/全部导出（文件/剪贴板）+ 导入（文件/剪贴板）+ 重置 | **没有完成** |
| **AssetsActivity（geo 资源管理）** | 导入/更新/删除规则集文件 | 0 命中（只有预设规则写死 `ruleSets`，`predefined_rules_modal.dart:75/84） | **完全漏** |
| GroupSettingsActivity | 分组设置 | 无 | **完全漏** |
| WebviewFragment（yacd 面板） | 内嵌客户端面板 | 无 | **完全漏** |
| BlankActivity / VpnRequestActivity / ThemedActivity / ToolbarFragment / SettingsPreferenceFragment / NamedFragment | 框架基类 | —— | 不计（不是功能面） |

### 2.7 数据实体（`database/`）

| 实体 | 现状 | 判定 |
|---|---|---|
| `ProxyEntity`（含凭据） | `proxy_entities`（drift v7，payload 含凭据，真机 84 行） | 1:1 |
| `ProxyGroup` | `proxy_groups`（type/ungrouped/order/userOrder/isSelector/front/landing） | 1:1（**仅订阅派生那一支在用**；手动/ungrouped 未用） |
| `RuleEntity` | hiddify 自己的规则模型（更细） | 1:1 |
| `SubscriptionBean` | `profile_entries`（+ 自动更新间隔） | 1:1 |
| `DataStore`（PublicDatabase） | shared_preferences | 1:1 |
| `TempDatabase` | 未移植（导入走内存） | 完全漏（无功能影响） |

---

## 3. 最危险的六项：「看起来有，其实没有」（硬充）

| # | 项 | 为什么危险 | 证据 | 建议 |
|---|---|---|---|---|
| 1 | **快捷磁贴** | manifest 注册了服务 ⇒ 系统设置里能看到磁贴，**点它没有任何反应** | `android_quick_settings_tile.dart` 1-57 行全注释；manifest`.bg.TileService` + TOGGLEABLE_TILE | 要么实现（接 `toggleConnection()`），要么撤掉注册 |
| 2 | **Dashboard** | 用户以为有 sing-box 面板；实际没有连接列表，也就无法"按连接操作/建规则" | `stats_overview_page.dart`（90 行，3 张统计卡）vs NekoBox `WebviewFragment` + `assets/yacd.zip` | 明确降级为"流量统计"，不宣称为面板 |
| 3 | **Proxy Chain** | 同名不同物：hiddify 的 chain = WARP/Psiphon 前置；NekoBox 的 chain = 前置/落地代理 | `chain_options_page.dart` / `extraSecurity` / `unblocker` vs `group_preferences.xml` 的 front/landing | 术语上分开叫，避免"配置了却没有落地代理"的错觉 |
| 4 | **开机自启** | 设置项看起来有，机制不同 | 无 `BootReceiver`；`autoStart` 设置 + always-on 元数据 | 在设置页注明依赖系统 always-on VPN |
| 5 | **Custom Config** | 有 JSON 编辑器 ⇒ 像是能做自定义配置；实际只能改**订阅**的配置 | `json_editor.dart`（订阅详情页）vs `config_preferences.xml`（新建自定义配置） | 属批次 2 的 `config_preferences` 表单 |
| 6 | **Auto Connect** | 语义不同 | `silent_start` + 启动即起内核 | 低优先，注明差异 |

---

## 4. 对 parity 文档的口径纠正（本轮新查出的）

1. **磁贴**：parity §6 记为 `❌` —— 实物是 **manifest 已注册 + Dart 全注释** ⇒ 应记为「硬充」，与"完全没有"是两种修法。
2. **备份/恢复**：parity §6 的组件表**漏了 `BackupFragment`**；实际 hiddify 在 Tools 页有备份 tab（结构与 NekoBox 一致：网络 + 备份两 tab），只是备份项**少了按类别勾选**。
3. **`NamedFragment` / `ToolbarFragment` / `ThemedActivity` / `SettingsPreferenceFragment` / `BlankActivity` / `VpnRequestActivity`**：是框架基类，**不是功能面**，不应计入"页面数"。
4. **`SwitchActivity` / `ProfileSelectActivity`**：只是"唤起 ConfigurationFragment 的选择模式"，hiddify 的代理页本身即覆盖 ⇒ 不是独立功能缺口。
5. **`NetworkFragment`**：是 Tools 的"网络"tab（STUN），不是网络设置页。
6. **扫码**：parity §2.1 记 `🟡 需确认可用性` —— 已确认**可用且已接线**（`fix_btns.dart:60-67`），旧文件里被注释的是同一功能的历史实现。
7. **Tools 页**：parity §1 记 ✅ 但没说明它=网络+备份两 tab（与 NekoBox 结构相同）。

> 这 7 条里有 6 条是**parity 抽取阶段的口径问题**（把框架类当页面、漏了 BackupFragment、把"注册了壳"当"没有"），
> 已在下文修正；parity 文档本身也一并更新。

---

## 5. 结论

**真缺的三大块（按体量）**：
1. **节点编辑/新建** —— 编辑**部分完成**（4 协议表单 + ✎，2026-09-15）；**新建（Manual Settings 15 项）仍未做**，
   卡在"节点必须有归属组"⇒ 与第 2 块同源。
2. **分组实体能力**（Group 页 + 手动建组 + front/landing）—— 完全漏，且解锁"手动节点"
3. **分享/导出 + 规则资源**（订阅分享 9 项、group 菜单、AssetsActivity）—— 完全漏

**⇒ 第 1、2 块是同一个前置**：组目前必然绑定订阅（`syncFromProfile` 认领）。
所以下一步的自然落点 = **批次 3（组不再绑定订阅）**，它同时解锁"手动建组"与"手动新建节点"。
详见 `docs/design/nekobox-priority.md` §8。

**需要"补齐或明确降级"的 5 项硬充**：磁贴、Dashboard、Proxy Chain 术语、开机自启、Custom Config。

**可以低成本补齐的小功能**：Clear test results / TCPing（应用侧可做）/ 快捷方式补 2 个动作（Android）/
备份加"按类别勾选"；**内核卡住不能做的**：Clear traffic statistics / Remove duplicate（部分）、`trafficSniffing` 等（见 parity §8.2）。

---

## 6. 反向清单：hiddify 特有（NekoBox 完全没有）

> 审计只列"缺什么"会失真 —— 这张表列**NekoBox 没有、而这里有**的东西，
> 用来回答"照 NekoBox 补齐"到底要不要动它们（结论：**A/B 档一律保留**，它们是跨平台与内核能力，不是偏差）。

### A. 能力型（NekoBox 结构上不可能有）

| # | 能力 | 证据 | 为什么 NekoBox 不可能有 |
|---|---|---|---|
| A1 | **6 个平台**：android / ios / linux / macos / web / windows | 工程根目录 6 个平台目录 | NekoBox 只有 Android |
| A2 | **内核常驻 + 运行期接管切换**（system-proxy / tun / proxy 三档语义分离） | `config_option_repository.dart`（`setSystemProxy` 运行时开关） | NekoBox 靠 Android VpnService，没有"系统代理"概念 |
| A3 | **静默启动 + 托盘 + 窗口状态记忆 + 关闭动作** | `silent_start`、`features/system_tray/`（50 处）、`features/window/`（`action_at_close`） | 桌面端概念 |
| A4 | **应用自更新**（appcast 拉取+提示） | `features/app_update/notifier/app_update_notifier.dart`（93 行） | Android 走商店/自行下载 apk |
| A5 | **11 种语言**（ar/en/es/fa/fr/id/pt-BR/ru/tr/zh-CN/zh-TW） | `assets/translations/` 11 份 i18n | NekoBox 语言数少得多 |
| A6 | **深链导入 `hiddify://import/<url>`**（带"来自哪个域名"的确认弹窗，防被网页静默发起） | `add_profile_modal.dart:259-273` | NekoBox 无深链导入 |
| A7 | **局域网共享代理**（可设密码） | `features/settings/widget/lan_sharing_tile.dart`（106 行） | NekoBox 无此功能 |
| A8 | **按地区自动勾选分流应用** | `per_app_proxy/overview/auto_apps_selection_modal.dart`（171 行） | NekoBox 只有手工勾选 / 反选 |
| A9 | **流量拆分统计**（代理/直连分开计） | `features/stats/model/traffic_split.dart`（164 行） | NekoBox 只有总量的 yacd 面板 |
| A10 | **多订阅并排**（一份订阅 = 一个 Tab，横向切） | `proxies_overview_notifier.dart` + Phase 1 定案 | NekoBox 一次只看选中的那份配置 |

### B. 协议与内核能力型

| # | 能力 | 证据 | 说明 |
|---|---|---|---|
| B1 | **协议面更宽**：33 项枚举 | `singbox_proxy_type.dart`：AWG、xVLESS/xVMess/xTrojan/xFragment/xShadowsocks/xSocks、Warp、Tor、SSR… | NekoBox 无 AWG、无 xray 核心系、无内置 Warp 出站 |
| B2 | **TLS 调优（内核级）**：分片 / 填充 / mixed SNI（7 项）+ mux 4 项 | `tls_tricks_page.dart`、`config_option_repository.dart` | NekoBox 有 "TLS Camouflage" 但实现不同（另一套机制），不是同一物 |
| B3 | **DNS 增强**：FakeDNS、独立 DNS 缓存、remote/direct DNS 分流 + domain strategy | `dns_options_page.dart`、`independent-dns-cache` | NekoBox 的 DNS 走规则集管线 |
| B4 | **四类入站端口**：mixed / tproxy / redirect / direct | `inbound_options_page.dart`、`config_option_repository.dart` | NekoBox 只有 socks/http + VPN |
| B5 | **内核开关族**：`use-xray-core-when-possible` / `balancer-strategy` / `strict-route` / `url-test-interval` | parity §4.6 | NekoBox 无对应项 |
| B6 | **增强出站链**：WARP / Psiphon（extraSecurity + unblocker 两套，共 15 项） | `chain_options_page.dart`（17 处） | ⚠️ 这就是"硬充"那一项的另一面：**能力是 hiddify 自己的**，只是与 NekoBox 的 front/landing 同名 |
| B7 | **更细的规则模型**：独立 orderId + 预设规则集 | `rule_page.dart`、`predefined_rules_modal.dart:75/84` | NekoBox 是 RuleEntity + rule assets（Assets 那半我们缺） |
| B8 | **每应用代理的 模式级导入导出**（文件 + 剪贴板 × 各模式） | `per_app_proxy_page.dart:163-212` | NekoBox 的菜单项更少 |

### C. 结论：这些怎么处理

| 档 | 处理 |
|---|---|
| A1–A10、B1–B5、B7–B8 | **保留**，它们是跨平台/内核能力，不是"与 NekoBox 不一致的偏差"。对齐 NekoBox 时**不要**把它们删掉迎合"1:1" |
| B6（chain） | **保留但正名**：在 UI/文档里叫"WARP / Psiphon 前置"，不要与 NekoBox 的 "Proxy Chain（前置/落地代理）"混称 |
| A3 / Auto Connect | 语义差异要注明（见 §3 硬充第 6 项） |
| A9 / Dashboard | 与 NekoBox 的 yacd 面板是**两种东西**，建议在页面上明确叫"流量统计"，不要宣称为面板 |

**一句话**：缺的 50 项集中在"节点 / 分组 / 协议表单"这条 NekoBox 的强项线上；
而 hiddify 强在"跨平台 + 内核选项 + 订阅体验"。这与 `docs/design/core-architecture-comparison.md` §7 的结论一致 ——
**两边不是"强弱"，是"强的方向不同"，且都长在各自的配置真源模型上。**

其中 **14 项属于"功能重叠、可融合"**（见 §7）：它们不该按 NekoBox 再建一套，
而是在已有页面里扩一段 —— 这是本轮唯一能直接省工作量的结论。

---

## 7. 第五类：**功能重叠、可以融合的**（不要按 NekoBox 再建一套）

> 判定的意义：把"完全漏 / 硬充"里的若干项**从"新建一块"降级为"在已有一处扩一段"**。
> 这是本轮审计里唯一能直接省工作量的结论。

### 7.0 什么才算"可融合"（三条必要条件，缺一不可）

1. **同一入口或同一数据对象**：两边指的是同一件东西的两个位置，而不是两个概念。
2. **NekoBox 那一项的操作对象在我们这儿已经存在**（数据已取到 / 实体已有 / 组件已有）。
3. **融合后不产生第二真源**（若融合会引入新的状态主人 ⇒ 不融合，只能立新项）。

**否决条件**：语义不同（同名不同物）时不许"看起来像就合" —— 那会造出比"完全漏"更差的"假 1:1"。

### 7.1 融合清单

| # | 重叠双方 | 重叠在哪 | 融合方式 | 数据/组件是否已具备 | 融合后省掉 |
|---|---|---|---|---|---|
| M1 | NekoBox `traffic_item_menu`（连接项 4 项：复制/打开应用/设置/建规则）／ hiddify `stats_overview_page` | **同一个"连接"对象** | 在统计页把"连接"从统计卡做成**可展开列表**，行内放 NekoBox 那 4 个动作 | ✅ `singbox_stats` 里本来就有 `connections`（`singbox_stats.freezed.dart` 48 处）；`connection_stats_card.dart` 已在用 | 不需要引入 yacd webview 就补上"按连接操作" |
| M2 | NekoBox `BackupFragment` 的三类勾选 ／ hiddify `tools_page._BackupTab` | **同一个备份 tab、同一个 JSON 导出** | 在现有备份 tab 的导出前加"配置 / 规则 / 设置"三个勾选（默认全选） | ✅ `config.exportJsonFile/Clipboard` 已存在（`tools_page.dart:136-168`） | 不新建页面，只在已有 tab 加三个开关 |
| M3 | NekoBox `AssetsActivity`（规则资源）／ hiddify 预设规则（`predefined_rules_modal.dart:75/84` 写死 `ruleSets: ["geosite-…"]`） | **同一批规则资源**：预设规则依赖的资源文件就是 Assets | 把 Assets 管理做成 Route 页里"规则资源"入口（NekoBox 也是从 route 菜单进），并让预设规则**显示它依赖哪个资源** | 🟡 规则模型已有引用；资源文件管理需新增（内核侧规则集下载） | 不新建独立 Activity，且顺手解决"预设规则像黑盒" |
| M4 | NekoBox 三个快捷方式（QuickToggle/Enable/Disable）／ hiddify `ShortcutActivity.kt`（单动作 toggle） | **同一个 Activity + 同一个 `toggleConnection()`** | 同一个 Activity 用 intent 参数区分 toggle / enable / disable；`shortcuts.xml` 加两个条目 | ✅ `ShortcutActivity` 已在处理 `ACTION_CREATE_SHORTCUT` + BoxService | 不写第二套快捷方式逻辑 |
| M5 | NekoBox 磁贴 ／ hiddify `ShortcutActivity` 的切换逻辑 | **同一个"快速开关"语义** | 实现磁贴时**复用** `connectionStatus.toggleConnection()`，不再写一套 | ✅ 逻辑已有（`android_quick_settings_tile.dart` 注释里就是它） | 磁贴从"硬充"变可用，成本≈取消注释 + 接状态回调 |
| M6 | NekoBox `profile_share_menu`（QR/剪贴板/SN Link/文件 × 组/标准）／ hiddify 已有的 `qr_code_dialog.dart` + `qr_code_scanner_screen.dart` + 节点级"复制出站 JSON" | **导出/分享同一批数据**（订阅配置 / 出站定义） | 统一成一个**分享面板**：粒度（订阅 / 节点）× 形式（QR / 剪贴板 / 文件），QR 复用现有对话框 | ✅ 两个 QR 组件已在（扫+显），导出走 FilePicker | 9 项分享不必各写一遍；顺带把扫/显两个 QR 组件合成一个（两模式） |
| M7 | NekoBox 测速三项（URL Test / TCPing / Clear results）／ hiddify 现有"测试全部" | **同一个测速入口** | 一个测速菜单放三项（NekoBox 也是同一菜单）；URL Test 已有，TCPing 与清空结果新增 | 🟡 清空结果需应用侧自己记（内核无 clear RPC）；TCPing 可纯应用侧实现 | 一个入口三件事，不新增页面 |
| M8 | NekoBox `bypassLan`（应用侧）+ `bypassLanInCore`（内核侧，两个项）／ hiddify 预设规则里的 Bypass LAN + 单项 `bypass-lan` | **同一目的（绕过局域网）的两条实现路径** | 保持"内核开关"一项 + 预设规则一项，**但在 UI 上互为说明**；不要照抄成两个含义相近的开关 | ✅ 两边实现都在 | 避免用户面对两个"Bypass LAN" |
| M9 | NekoBox `ProfileSelectActivity` / `SwitchActivity` ／ hiddify 代理页 | 都是"选节点" | 已在代理页覆盖（**不新建**）；只在从外部唤起选择时的场景按需复用 | ✅ | 两个 activity 不必实现 |
| M10 | NekoBox `AppListActivity` / `AppManagerActivity` ／ hiddify `per_app_proxy_page` + `android_apps_page` | 同一个应用清单 | 已 1:1；NekoBox 的"反选"可作现有工具栏的一个按钮 | ✅ | 不新建页面 |
| M11 | NekoBox `config_preferences`（自定义配置）／ hiddify `json_editor.dart`（订阅级） | **同一个 JSON 输入框** | 共用同一编辑器外壳：节点级走协议表单（批次 1），订阅级/自定义配置走 JSON —— 一个页面两种模式 | ✅ `json_editor` 已在 | 不写第二个 JSON 编辑器 |
| M12 | NekoBox `profile_config_menu` 的 `Custom outbound JSON` ／ hiddify 节点级"复制出站 JSON"（`extractOutboundJson`） | **同一份出站 JSON** | 同一个对话框：可看可编辑可复制（现在只有复制） | ✅ 取数链路已有 | 节点级 JSON 编辑几乎零成本 |
| M13 | NekoBox 内嵌 yacd 面板 ／ hiddify 统计页 | 都在"看流量/连接" | **两种选择**：(a) 融合 = 统计页补连接列表（见 M1）；(b) 不融合 = 引入 webview 面板 | 🟡 (b) 需打包 yacd 资源 | 明确选 (a) 可省一整个 webview 模块 |
| M14 | NekoBox `TempDatabase` ／ hiddify 导入走内存 | 同为"导入中转" | 不必移植（我们不需要中转表） | — | 省一张表 |

**可融合合计：14 项**，其中 **11 项能把"完全漏/硬充"降级为"在已有页面扩一段"**
（M1 Dashboard 连接项、M2 备份勾选、M3 Assets 入口、M4/M5 快捷方式与磁贴、M6 分享 9 项、M7 测速三项、M11/M12 两个 JSON 编辑、M13 面板选择、M14 中转表）。

### 7.2 明确**不能融合**的（防止为省事而造"假 1:1"）

| 不能融合 | 原因 |
|---|---|
| 协议表单（12 份）↔ 订阅级 JSON 编辑器 | 粒度不同（逐字段校验 vs 整段文本）。可以**共用页面外壳**（M11），但语义不能合并 |
| `front/landing` 代理（NekoBox chain）↔ WARP/Psiphon（hiddify chain） | 语义不同：前者"一个链"是出站列表，后者是固定的前置工具。只能**同名分档**（`nekobox-parity.md`），不能合并实现 |
| Assets 资源文件 ↔ 预设规则模板 | 资源是"文件"，规则是"模板条目"。可互链（M3），不同物 |
| RuleEntity 模型 ↔ `rulesProvider` 设置项 | 一个是我们自己的规则存储，一个是"用谁家的规则集源"。可以并存，不该互相替代 |
| 磁贴 ↔ 快捷方式（语义层） | **实现层可融合**（M5），但它们是两个系统入口，都得存在 |


