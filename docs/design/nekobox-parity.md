# NekoBox 功能对照清单（规格源：NekoBoxForAndroid 源码）

> 2026-09-15 建。**本文件是规格清单，不是设计方案** —— 每一行都以
> `S:\test\NekoBoxForAndroid` 的源码文件为准，标注 hiddify-app 的现状。
> 原则：**完全对照 NekoBox，功能也对照**（用户要求，勿按个人偏好裁剪）。
>
> **2026-10-05 全量复核**：用户指出"文档判 ❌/🟡 但代码其实已实现"的漂移后，§1–§8 逐条重跑
> `git grep` 复验并改写。**凡是标 ❌ 的行都带上了可复现的搜索命令或其 0 命中结论**；原判定与
> 新判定不一致的，在行内注明「2026-10-05 更正/翻案」。三处重要翻案：
> `enableDnsRouting`（有 proto 字段但**内核无消费者**，从"仅需接线"改为"⛔ 内核卡住"）、
> `meteredNetwork`（`VPNService.kt:99` 有 `setMetered(false)` 写死，从"❌ 0 命中"改为"🟡 差一个开关"）、
> `block-quic`（原写"暂不做"，实为**内核消费者活着、只差 Dart 侧接线** ⇒ A 组；同批发现 `block-ads` 同病）。
>
> ⚠️ **判 A 组 / C 组的唯一判据是「内核有没有消费者」，不是「proto 有没有字段」**：
> `enableDnsRouting` 与 `block-quic` 形状完全相同（都是 proto/pb 有字段），结论却相反 ——
> 前者 `builder.go:973` 的消费块被注释，后者 `builder.go:939` 是活的。详见 §8.1 的修正记录。
>
> ⚠️ **复验命令的坑**：`git grep` **没有 `--include` 选项** —— `git grep -n PATTERN -- lib --include=*.dart`
> 会把 `--include=*.dart` 当 pathspec，**结果全为 0 命中**。据此得出的"XX 缺失"结论全错（本轮第一版
> "实测缺 8 项"表即由此产生）。正确写法：`git grep -n -E "A|B" -- lib`。
>
> 状态图例：✅ 已对齐 ｜ 🟡 部分（注明差异）｜ ❌ 缺失 ｜ 🟠 硬充 ｜ ⚪ 非功能面（框架基类）｜ ⛔ 既有约定不移植
>
> **功能盘点看 `docs/design/parity-sequence-log.md`**（1:1 序列逐项结果 + 三处定性不移植），
> **要查规格看这份**。2026-09-15 的四类重判（1:1 完成 / 硬充 / 没有完成 / 完全漏，含 7 条口径
> 纠正：磁贴是硬充而非缺失、备份 tab 存在但缺分类勾选、6 个"页面"其实是框架基类等）原在
> `docs/audit/2026-09-15-nekobox-function-matrix.md`，2026-10-03 精简时删除，可用
> `git log --diff-filter=D -- docs/audit/` 找回。
>
> 规格源文件：`res/xml/*.xml`（设置与协议表单）、`res/menu/*.xml`（菜单动作）、
> `AndroidManifest.xml`（平台组件）、`database/`（实体）、`ui/*.kt`（页面）。

---

## 1. 导航抽屉（规格：`res/menu/main_drawer_menu.xml`）

| # | NekoBox 项 | id | hiddify 现状 |
|---|---|---|---|
| 1 | Configuration | `nav_configuration` | ✅ `proxies_overview_page.dart` |
| 2 | Group | `nav_group` | ✅ `groups_page.dart`＋`groups_page_spec.dart`（**分组实体已建**：工具栏 `createGroup`（`groups_page.dart:174-222`）、重命名/拖拽排序、卡片 ⋮「分享订阅 / 导出（剪贴板·文件）/ 清空」、右滑删除、`group_settings_sheet.dart`；订阅组由订阅派生） |
| 3 | Route | `nav_route` | ✅ `rule_page.dart`（含 domain/ip/port 细粒度字段） |
| 4 | Settings | `nav_settings` | ✅ `settings_page.dart`（五类内联） |
| 5 | Logs | `nav_logcat` | ✅ `logs_page.dart` |
| 6 | sing-box Dashboard | `nav_traffic` | 🟠 **硬充**：hiddify 自研统计页（3 张卡），NekoBox 是内嵌 yacd 面板（连接列表/按连接操作/建规则/面板 URL）—— 同名不同物，见 `docs/design/parity-sequence-log.md`（⑥ 仪表板定性）|
| 7 | Tools | `nav_tools` | ✅ `tools_page.dart` |
| 8 | Ads | `nav_tuiguang` | ⛔ 推广位，不移植 |
| 9 | Document | `nav_faq` | ✅ **抽屉项已插入**（`lib/app/shell/nav_items.dart:196-211` `NkFaqEntry`，落在 about 组首位的分隔线后；`my_adaptive_layout.dart:83-85` 点击即 `UriUtils.tryLaunch(Uri.parse(Constants.faqUrl))`）—— 目标 URL `lib/core/model/constants.dart:18` `https://matsuridayo.github.io/` 与 NekoBox `MainActivity.kt:343-346` `launchCustomTab("https://matsuridayo.github.io/")` **同一地址**。它是外开链接不是内容页，故**故意不占 GoRouter 分支**（`nkFaqDestinationIndex` 只做索引映射） |
| 10 | About | `nav_about` | ✅ `about_page.dart` |

---

## 2. 节点页工具栏（规格：`res/menu/add_profile_menu.xml`，32 项）

### 2.1 订阅/导入类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Update all subscriptions | `action_update_all` | ✅ `profiles_page` 批量更新 |
| Create group | `action_new_group` | ✅ 工具栏「新建分组」（`groups_page.dart:174-222` `NkGroupToolbarAction.createGroup` → `_createGroup` → `proxiesOverviewNotifierProvider.createGroup(name:)` → `proxy_entity_repository.dart:399` `Future<int?> createGroup({String? name, bool ungrouped = false, bool isSelector = false})`）；规格投影 `groups_page_spec.dart:22-30` |
| Add Profile | `action_add` | ✅ |
| Scan QR code | `action_scan_qr_code` | ✅ 已确认可用：`fix_btns.dart:60-67` → `showQrCodeScanner()` → `QrCodeScannerDialog`（`qr_code_scanner_screen.dart:403-464`）。该文件 403 行以前是**被注释的历史实现**，别再当成"不可用" |
| Import from Clipboard | `action_import_clipboard` | ✅ |
| Import from file | `action_import_file` | ✅ `proxies_overview_page.dart:514-529`（`FilePicker.pickFiles()` → `decodeNodeImportFile(name, bytes)` → `importNodeFiles`；解码失败 toast）；规格项 `add_profile_menu_spec.dart:8` `NkAddProfileAction.importFile` |
| **Manual Settings**（手动新建节点） | 17 个协议子项 | ✅ **已实施**：`kManualCreatableProtocols`（`protocol_form.dart:926-944`）17 项逐项对齐 NekoBox `add_profile_menu.xml:28-76`（socks/http/ss/vmess/vless/trojan/**trojan_go 不移植**/mieru/naive/hysteria/tuic/shadowtls/anytls/ssh/wg/config/chain）；流程 `manual_node_flow.dart`（选协议 → 定归属组 → 填表单，对应 `ProfileSettingsActivity.saveAndExit` 的 `editingId == 0` 分支）。trojan_go 不移植的理由：hiddify 内核无 trojan-go 出站注册（`include/registry.go` 无 `TypeTrojanGo`） |
| Custom Config | `action_new_config` | ✅ 手动菜单第二级 `config` 项（`manual_node_flow.dart:44-48` 特判 → `showConfigSettingsSheet(tag: '', isNew: true)`，`config_settings_page.dart:31`） |
| Proxy Chain | `action_new_chain` | ✅ 手动菜单第二级 `chain` 项（`manual_node_flow.dart:37-42` 特判 → `showChainSettingsSheet(tag: '', isNew: true)`，`chain_settings_page.dart:27`）；另有设置页「链式代理」15 项（hiddify 独有，保留） |

### 2.2 订阅维护类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Update current Group's subscription | `action_update_subscription` | ✅ |
| Clear traffic statistics | `action_clear_traffic_statistics` | ✅ `proxies_menu_button.dart:58` `_item(t.pages.proxies.clearTrafficStats, () => _clearTraffic(t))`，`:131-144` `_clearTraffic` → `ProxyEntityRepository.clearTrafficStats({profileId, groupId})`（`proxy_entity_repository.dart:563`）；照 `ConfigurationFragment.kt:460-475` 无确认框静默执行 |
| Remove duplicate servers | `action_remove_duplicate` | ✅ `proxies_menu_button.dart:59` `_item(t.pages.proxies.removeDuplicate, () => _removeDuplicate(t))`，`:146-183` `_removeDuplicate` → 照 `ConfigurationFragment.kt:545-559`：先列重名名单确认、上限 20 条、空名单只 toast。规格投影见 `proxies_menu_button.dart:13-36` 类注释 |

### 2.3 测速类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| TCPing | `action_connection_tcp_ping` | ✅ `proxies_menu_button.dart:185-210` `_tcpPing`（照 `ConfigurationFragment.kt:694-832` `pingTest(false)` 先弹进度框逐条回报）；结果模型 `lib/features/proxy/data/tcp_ping.dart:26-34` `TcpPingResult(status, ping, error)` |
| URL Test | `action_connection_url_test` | ✅ 菜单「测试全部」，按当前组下发 |
| Clear test results | `action_connection_test_clear_results` | ✅ `proxies_menu_button.dart:228-240` `_clearResults` → `proxiesOverviewNotifierProvider.clearTestResults({profileId, groupId})`（`proxies_overview_notifier.dart:652`）→ `ProxyEntityRepository.clearTestResults`（`proxy_entity_repository.dart:539`） |
| Clear unavailable | `action_connection_test_delete_unavailable` | ✅ `proxies_menu_button.dart:241-260` `_deleteUnavailable`（照 `ConfigurationFragment.kt:495-532` 一句确认、不带名单）；筛选 `ProxyEntityRepository.findUnavailableNodes(List<ProxyEntityEntry>)`（`proxy_entity_repository.dart:644`） |

> 以上五项（清空流量 / 删重复 / TCPing / 清测试结果 / 清不可用）与「更新订阅」共同构成 `action_misc` 8 项菜单，
> 顺序逐项对齐 `res/menu/add_profile_menu.xml:84-113`；`proxies_menu_button.dart:13-36` 的类注释即该规格的落地说明，
> 并显式登记两处**有意差异**：① 无「路由」项（NekoBox 路由在抽屉，归一原则「一个能力一个入口」）；
> ② 排序子菜单只有三项（`ProxiesSort.usage` 是 hiddify 遗留排序，枚举保留但无菜单入口）。

### 2.4 排序类

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Order → Origin | `action_order_origin` | ✅ `ProxiesSort.unsorted` |
| Order → By Name | `action_order_by_name` | ✅ `ProxiesSort.name` |
| Order → By Delay | `action_order_by_delay` | ✅ `ProxiesSort.delay` |
| （hiddify 额外） | — | ➕ `ProxiesSort.usage`（NekoBox 没有） |

---

## 3. 动作菜单（4 份规格）

### 3.1 `profile_config_menu.xml`（节点/配置项菜单）

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Remove | `action_delete` | ✅ 删除订阅（另：滑动删除可撤销，`profiles_notifier.dart:100` `restoreSubscription(String url)`） |
| Apply | `action_apply` | ✅ 设为激活订阅 |
| Create Shortcut | `action_create_shortcut` | 🟡 形态不同：NekoBox 是**逐节点** pin 一个快捷方式（`ProfileSettingsActivity.kt:164-168` 只在 `editingId != 0` 即编辑既有节点时可见；`:314-331` `ShortcutInfoCompat.Builder(activity, "shortcut-profile-${ent.id}")` + `.setIntent(QuickToggleShortcut, putExtra("profile", ent.id))` + `ShortcutManagerCompat.requestPinShortcut`）；hiddify 是**静态常量**快捷方式 `android/app/src/main/res/xml/shortcuts.xml` 的 `shortcutId="toggle"` → `com.hiddify.hiddify.ShortcutActivity`（`android/app/src/main/kotlin/com/hiddify/hiddify/ShortcutActivity.kt:24` `ShortcutManagerCompat.createShortcutResultIntent`、`:47` `reportShortcutUsed("toggle")`）。**缺**：逐节点 pin 快捷方式（`ShortcutActivity` 不接受 profile extra） |
| Move | `action_move` | ✅ 拖拽排序 |
| Custom outbound JSON | `action_custom_outbound_json` | ✅ 表单 ⋮ 菜单（仅编辑模式）：`protocol_form_modal.dart:266-281` `PopupMenuButton<String>` 的 `'outbound'` 项 → `saveOverride(isOutbound: true)`（`:149-160`）→ `_showJsonEditDialog(title: t.pages.proxies.form.customOutbound)` → 存 `ProxyEntities.customOutbound`（`db.dart:205-209`，v8 迁移 `:79-81`）→ 组装期 deepMerge 进该出站（`config_assembly.dart:474-481` 节点 / `:296` chain / `:326` chain 成员）。对应 NekoBox `ProfileSettingsActivity.kt:170` 的 `action_custom_outbound_json` |
| Custom config JSON | `action_custom_config_json` | ✅ 同一 ⋮ 菜单的 `'config'` 项 → `ProxyEntities.customConfig`；运行期覆盖整份配置（`connection_repository.dart:211` `_startWithCustomConfig`：`generateFullConfigByPath` → `deepMergeJson` → `startRawContent`）。`lib/features/profile/details/json_editor.dart`（`JsonEditor` :369）是 vendored 编辑器，`profile_details_page.dart:291` 在详情页也用了同一组件 |

### 3.2 `profile_share_menu.xml`（分享，9 项）

| NekoBox 项 | hiddify 现状 |
|---|---|
| QR code → Group / Standard / SN Link | ✅ Group（订阅分享链接）+ Standard（单节点分享链接）已实现；**SN Link 缺失**（NekoBox 的 `action_universal_qr`，`fmt/UniversalFmt.kt`）。落点：订阅卡 ⋮ → `lib/features/profile/widget/profile_actions.dart:23` `buildProfileShareItems` 的 `t.pages.profiles.share.showUrlQr`（`LinkParser.generateSubShareLink(url, name)` → `showQrCodeDialog`）；节点卡 ⋮ → `lib/features/proxy/widget/proxy_tile.dart:236-251` `_shareItems` 的 `t.pages.groups.shareQr`（`_readStandardLink` → `outboundToLink`） |
| Export to Clipboard → Group / Standard / SN Link | ✅ Group：`profile_actions.dart:23` `t.pages.profiles.share.urlToClipboard`（`LinkParser.generateSubShareLink`→Clipboard）；Standard：`proxy_tile.dart:240` `t.pages.groups.exportToClipboard`（`_copyStandardLink`）；**SN Link 缺失**。分组卡 ⋮ 另有 `shareUrlToClipboard`（`groups_page.dart:332-345` `_copySubscriptionUrl`） |
| Configuration → Export to Clipboard / Export to file | ✅ 两项都有：订阅卡 ⋮ → `profile_actions.dart:23` 第三项 `t.pages.profiles.share.jsonToClipboard` → `profiles_notifier.dart:82-97` `exportConfigToClipboard(ProfileEntity)`（`_profilesRepo.generateConfig` → Clipboard）；节点卡 ⋮ → `proxy_tile.dart:242-248` `t.common.configuration` 子菜单两项 `exportToClipboard`（`_copyConfigJson`）/`exportToFile`（`_exportConfigJson`，`:312`）。分组卡 ⋮ → `groups_page.dart:314/316` `_exportNodesToClipboard`（`:370-384`）/`_exportNodesToFile`（`:385-411`，UTF-8 字节写文件） |

> **唯一真缺口 = SN Link**（NekoBox `action_universal_qr` / `action_universal_clipboard`，实现是
> `fmt/UniversalFmt.kt` 的通用分享格式）。其余 8 项均已落地。
> 归一原则（`profile_actions.dart` 头注释「一个能力一个实现」）下，Group/Standard 两层
> 与 Configuration 两层分别由订阅卡与节点卡的同一份菜单代码承载。

### 3.3 `group_action_menu.xml`（分组右键）

规格 `res/menu/group_action_menu.xml` 3 组 5 项；我方实现 `groups_page_spec.dart:34-54` `nkGroupActionMenu({required bool isSubscription})`
（订阅组才有「分享订阅」子菜单，同 `GroupFragment.kt:406-408`），UI 由 `groups_page.dart:300-306` `_menuFromSpec` 渲染。

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Share Subscription → SN Link clipboard / SN Link QR | `action_share_subscription` / `action_universal_clipboard` / `action_universal_qr` | 🟡 订阅组有「分享订阅」子菜单，但项是**订阅 URL**（`groups_page.dart:332-345` `_copySubscriptionUrl` → `LinkParser.generateSubShareLink(profile.url, profile.name)`）与 QR（`_showSubscriptionQr`）；**SN Link 形式缺失** |
| Export → Export to Clipboard / Export to file | `action_export` / `action_export_clipboard` / `action_export_file` | ✅ `groups_page.dart:314` `_exportNodesToClipboard`（`:370-384`，`_nodesExportText` → Clipboard）／`:316` `_exportNodesToFile`（`:385-411`，UTF-8 字节落盘） |
| Clear | `action_clear` | ✅ `groups_page.dart:317` `_clearGroup`（`:412-425`：`showConfirmation(title: t.pages.groups.clearConfirm, message: 组名)` 确认后 `clearGroup(group.id)`，成功 toast `t.pages.groups.cleared`） |

> 分组卡另有工具栏 `createGroup` 与重命名/拖拽排序，见 §2.1 与 §1 第 2 行。

### 3.4 `traffic_item_menu.xml`（仪表盘按连接项）

规格 3 组 6 项（`action_copy` → `copy_label`/`copy_package_name`；`action_open` → `open_app`/`open_settings`/`open_market`；顶层 `create_rule`）。

| NekoBox 项 | id | hiddify 现状 |
|---|---|---|
| Copy → Copy Label / Copy Package Name | `copy_label` / `copy_package_name` | ❌ hiddify 仪表盘无**逐连接列表**（见 §1 第 6 行「硬充」定性：自研统计页只有速率/连接数/流量三张卡），故按连接项菜单无处挂载 |
| Open → Open App / Open Settings / Open Market | `open_app` / `open_settings` / `open_market` | ❌ 同上；根因是缺连接列表而非缺动作实现 |
| Create Rule | `create_rule` | ❌ 同上。路由规则页自身可建规则（`rule_page.dart`），但没有「从某条连接反推规则」的入口（对应 NekoBox `yacd` 面板内的建规则） |

### 3.5 其他菜单

| 规格文件 | 内容 | hiddify 现状 |
|---|---|---|
| `app_list_menu.xml` / `per_app_proxy_menu.xml` | 反选 / 清空 / 导出剪贴板 / 导入剪贴板 | ✅ **四项齐备且顺序对齐**（2026-10-06 收口反选）：`per_app_proxy_page.dart:163-228` 按 `per_app_proxy_menu.xml:3-20` 的 invert → clear → export → import 排列 —— 反选（`:167-170` `invertSelections()`）、清空选择（`:174-176` `clearAll()`）、导出剪贴板（`:181-183` `exportClipboard()`）、导入剪贴板（`:198-203` `importClipboard()`）；另有自动选择策略下拉（`:261-263` `clearAutoSelected()`）。**语义逐条对齐**：NekoBox `AppListActivity.kt:241-259` 反选遍历 `apps`（= `cachedApps` 全量已安装包，含系统应用；`showSystemApps` 只过滤 adapter 的 `filteredApps`）且对**无条目的 uid 也置选中** ⇒ 我方 `AppProxyDao.invertSelections({required Set<String> phonePkgs, required AppProxyMode mode})` 收全量手机包 + 无行包新建（`app_proxy_data_source.dart:71-108`）；判据用**可见勾选态** `PkgFlag.checkboxValue`（`pkg_flag.dart:76-79`）—— 按 userSelection 位判会把 flag=3 翻成 2 而显示不变。**形态差异（保留）**：NekoBox 是与 `app_list_menu.xml` 合一的扁平菜单，我方导出/导入各有「剪贴板/文件」两子项 + 末尾 region 门控「分享给所有人」（`shareToAll`，NekoBox 无）。测试：`test/features/per_app_proxy/invert_selections_dao_test.dart`（8 例）+ `per_app_proxy_menu_spec_test.dart`（6 例，泵真 `PerAppProxyPage`）+ `pkg_flag_test.dart`（13 例） |
| `logcat_menu.xml` | Update / Export debug info / Clear Logcat | 🟡 清空 ✅（`logs_page.dart:79-85` `notifier.clear`，`FluentIcons.delete_lines_20_regular`）；分享 ✅ 但**形态不同**：`logs_page.dart:31-51` 是「分享内核日志 / 分享应用日志」两项文件分享（`UriUtils.tryShareOrLaunchFile`），NekoBox 是单项「Export debug info」（打包诊断信息）。**缺**：Refresh 项（我方日志自动跟随），以及 NekoBox 式诊断包导出 |
| `route menu`（`add_route_menu.xml`） | Create Route / Reset / Manage Route Assets | 🟡 新建 ✅（FAB mini 项 → `rule_page.dart`）、重置 ✅（`rules_notifier.dart:189+ resetRules()`，菜单项在 `routing_options_page.dart:76-83`）；**无 Assets 管理**（`action_manage_assets`，对应 NekoBox `AssetsActivity`，负责 geo 资源）。形态差异：NekoBox 是 toolbar 菜单，我方是 FAB + 右上角菜单 |
| `yacd_menu.xml` | Set panel URL / close | ❌ 无内嵌面板（同 §1 第 6 行「硬充」定性） |

#### 3.5.1 预设规则对照（2026-10-05 新查，**本节结论重要**；2026-10-06 已按 fork A 完成 1:1 移植）

NekoBox 首次建规则在 `database/ProfileManager.kt:184-237 getRules()`（判据 `rules.isEmpty() && !DataStore.rulesFirstCreate`），
`outbound` 取值语义是 **`0`=proxy / `-1`=bypass / `-2`=block**（`database/RuleEntity.kt:26` `var outbound: Long = 0`、`:56-60 displayOutbound()`）。

**结论：已全量对齐**（`lib/features/route_rules/data/predefined_rules.dart`，纯函数 `buildNekoBoxPresetRules(Translations, Region)`）。

| NekoBox 预设（源码行） | 规则体 | outbound | hiddify 现状 |
|---|---|---|---|
| 屏蔽 QUIC（`:188-195`） | `port=443, network=udp` | `-2` block | ✅ 首条即 `Outbound.block` + `Network.udp` + `portRanges: ['443']`。注：与全局开关 `block-quic`（`RouteOptions.BlockQuic`，内核已实现仅差接线）是**两回事**，见 §8.1 |
| 屏蔽广告（`:196-202`） | `domains=geosite:category-ads-all` | `-2` block | ✅ `Outbound.block` + `geosite:category-ads-all`。**顺带修掉了原实现的语义 bug** —— 旧 `predefined_rules_modal.dart:69-81` 写的是 `Outbound.direct`（proto 值 `1`），把「拦截广告」做成了「广告直连」。同样与全局开关 `block-ads`（`HiddifyOptions.BlockAds`，内核已实现仅差接线）是两回事，见 §8.1 |
| 中国 Play 商店规则（`:213-218`） | `domains=googleapis.cn` | `0` proxy（上游不写该字段） | ✅ `Outbound.proxy` + `googleapis.cn`，仅 `cn` 一条。hiddify 侧必须显式写 outbound —— 否则 `addRule` 的 `assert(rule.hasOutbound())` 会炸 |
| 中国 域名规则（`:219-225`） | `domains=geosite:cn` | `-1` bypass → `Outbound.direct` | ✅ `Outbound.direct` + `geosite:${country.code}`，逐国一条 |
| 中国 IP 规则（`:226-232`） | `ip=geoip:cn` | `-1` bypass → `Outbound.direct` | ✅ `Outbound.direct` + `ipCidrs: ['geoip:${country.code}']`，逐国一条 |
| （hiddify 自有）绕过局域网 | `domains=geosite:private`, `ipCidrs=geoip:private` | `Outbound.direct` | ➖ **已删除该预设**：NekoBox 无此项，1:1 即不种。内核侧的 `bypass-lan` 通道保留不变（见 §4.2） |

- 国家清单：`:203-208` `fuckedCountry` 初始 `["cn:中国"]`，若 `Locale.getDefault().country != Locale.CHINA.country` 再加 `ir:Iran` / `ru:Russia`
  ⇒ **非中国地区会多出伊朗/俄罗斯两组**（`route_play_store` / `route_bypass_domain` / `route_bypass_ip` 三个字符串按国家格式化）。
  hiddify 侧改用 `ConfigOptions.region`（`Region.cn` ⇒ 仅 `cn` = 5 条；其它 region ⇒ `cn+ir+ru` = 9 条），**判据来源与上游不同但结果集等价**。
  国家名字面量（`中国` / `Iran` / `Russia`）**照抄上游硬编码**、不接 i18n ⇒ 保留「`Domain rule for 中国`」这种混合语言怪癖（en 模板 + 中文字面量）。
- **触发方式已对齐**：上游 `ui/RouteFragment.kt:131-144 RuleAdapter.reload()` 在进入路由页时自动种下、**无弹窗**；
  hiddify 现在同样由 `routing_options_page.dart:86-94` 的 post-frame 回调调 `ensureSeeded()`（复用既有的 deep link 钩子位）。
  原 `predefined_rules_modal.dart`（hiddify 自有发明，上游不存在）连同 FAB 入口一并删除。
- **「首次」判据的等价物**：上游是 `DataStore.rulesFirstCreate` 布尔位；hiddify 用**「`route_rule.proto` 文件是否存在」**
  （`rules_notifier.dart:189+ ensureSeeded()` → `if (state.isNotEmpty || file.existsSync()) return;`）。
  因 `_updateFile()` 每次改动都落盘（哪怕是空列表），语义等价：新装 ⇒ 无文件 ⇒ 种；用户删光规则 ⇒ 文件已写 ⇒ 不复活；重置 ⇒ 删文件 ⇒ 重新种。
- **重置后立刻重种**：对齐 `RouteFragment.kt:113-115`（`rulesDao.reset(); rulesFirstCreate = false; ruleAdapter.reload()`），
  `routing_options_page.dart:76-83` 的重置项现在是 `resetRules()` + `seedPresets()` 两连。
- **「预置但默认关闭」是 NekoBox 的设计，不是缺陷（2026-10-05 复核 + 真机截图确认）**：
  - `database/RuleEntity.kt:18` `var enabled: Boolean = false`（无 `@ColumnInfo`；同文件 `:15` 的 `@ColumnInfo(defaultValue = "")` 只作用于 `config` 字段）；`ProfileManager.kt:188-232` 建这 5 条时**从不传 `enabled`** ⇒ 落库即 `false`；`git log -p -S "enabled = true" -- .../ProfileManager.kt` **无任何命中**，即历史上从未被置真。
  - 只有「用户新建」才默认开：`ui/RouteSettingsActivity.kt:97-99` `if (DataStore.editingId == 0L) { enabled = true }`。
  - 运行时只吃启用的：`fmt/ConfigBuilder.kt:126` `val extraRules = if (forTest) listOf() else SagerDatabase.rulesDao.enabledRules()`；`RuleEntity.kt:74-75` `enabledRules(enabled: Boolean = true)` 即 `WHERE enabled = 1`。
  - 真机取证：`.workbuddy/device/nb_16_route.png`（sha256 `a022e0c6c23dd4d3c948c978f50d9b09e734734889db9b405d08709d26761de4`）5 条全部开关为**关**。
  - ⇒ **已对齐**：预置规则每条显式 `enabled: false`；`rules_notifier.dart:32-40 addRule` 不再硬写 `enabled = true`（改由调用方决定）；
    `rule_notifier.dart:90` 的新建分支补 `enabled: true`，对齐 `RouteSettingsActivity.kt:97-99`。
    显式传 `false`（而非省略）是必需的：proto3 只在显式赋值时置 has-bit，而编辑已有规则走 `writeToJsonMap()` → `Rule.fromJson` 往返
    （`rule_notifier.dart:103-109`），has-bit 一旦缺失就会踩 `rule_notifier.dart:115 assert(state.hasListOrder() && state.hasEnabled())`。
    落盘语义不受影响（`route_rule_json.dart:31` 只在 true 时输出该键）。
  - 顺带记一条上游隐患（不属移植范围）：`database/SagerDatabase.kt:33-43` 用了 `.fallbackToDestructiveMigration()`，且 `:36` 的 `.addMigrations(*SagerDatabase_Migrations.build())` 是**注释掉的** ⇒ 升级时 rules 表被清空后会被再次以「关闭」状态重建。
- 仍未对齐的一处（**待定夺**）：`rule_notifier.dart:90` 新建空规则用 `Outbound.direct`，NekoBox 默认是 `0`=proxy。
- 已知形态差异（不打算对齐）：NekoBox 路由列表有恒定的 position-0 `DocumentHolder` 说明卡（`:157-160` `getItemViewType`、`:170-172` `getItemCount() = ruleList.size + 1`、`:264-270` 点开 `https://matsuridayo.github.io/nb4a-route/`），hiddify 无此说明行。

---

## 4. 设置（规格：`res/xml/global_preferences.xml`，5 类 29 项）

### 4.1 App Settings（15 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `isAutoConnect` | Auto Connect | 🟡 hiddify 是 `silent_start`（`settings_page.dart:222-226`，桌面）+ 自动起内核，语义不同 |
| `appTheme` | Theme | ✅ 5 色板（`NkPalettePrefTile`，`settings_page.dart:156`） |
| `nightTheme` | Night Mode | ✅ 日/夜/AMOLED（`ThemeModePrefTile`，`settings_page.dart:157`） |
| `serviceMode` | Service Mode | ✅ `settings_page.dart:158-164` |
| `tunImplementation` | TUN Implementation | ✅ `settings_page.dart:200-207`（**值大小写差异**：NekoBox `gVisor`，hiddify `value.name` → `gvisor`；枚举来自 `TunImplementation.values`） |
| `mtu` | MTU | ✅ `settings_page.dart:167-173`（默认 9000） |
| `speedInterval` | 通知速率刷新间隔 | ❌ 无此开关：hiddify 通知速率由内核 `SystemInfo` 流每来一次即算差值（`android/app/src/main/kotlin/com/hiddify/hiddify/bg/ServiceNotification.kt:141-145`），无间隔可调 |
| `profileTrafficStatistics` | 订阅流量统计 | ✅ `settings_page.dart:175-181`（正式开关，默认 true；副标题对应 NekoBox 的「关闭后不统计流量」语义） |
| `showDirectSpeed` | 显示直连速率 | ❌ 通知只有总速率：`ServiceNotification.kt:145` `"${formatBytes(uplink)}/s ↑\t${formatBytes(downlink)}/s ↓ \n${status.current_outbound}"`，无 proxy/direct 分列（NekoBox `bg/proto/TrafficLooper.kt:155-156` 用 `showDirectSpeed` 决定 bypass 速率是否置 0） |
| `showGroupInNotification` | 通知显示分组名 | ❌ 通知标题恒为 `status.current_profile`、正文恒为 `status.current_outbound`（`ServiceNotification.kt:145-146`），无「节点@分组」形态（NekoBox `bg/ServiceNotification.kt:50` `if (DataStore.showGroupInNotification)`） |
| `alwaysShowAddress` | 始终显示地址 | ✅ `settings_page.dart:183-189`（`Preferences.alwaysShowAddress`，默认关闭） |
| `meteredNetwork` | 计费网络提示 | 🟡 **有实现但写死**：hiddify `android/app/src/main/kotlin/com/hiddify/hiddify/bg/VPNService.kt:99` `if (Build.VERSION.SDK_INT >= Q) builder.setMetered(false)` —— **恒为 false**，无开关；NekoBox 是 `bg/VpnService.kt:195` `metered = DataStore.meteredNetwork`（`DataStore.kt:149` 用户偏好）。⇒ 缺的只是那个开关。**注意别混淆**：`PlatformInterfaceWrapper.kt:136-137` 的 `boxInterface.metered = !networkCapabilities.hasCapability(NET_CAPABILITY_NOT_METERED)` 是**读**当前网络是否计费喂给内核，与此无关 |
| `acquireWakeLock` | 保持唤醒锁 | ❌ 全库 0 命中（`android` 侧 `WakeLock`/`PARTIAL_WAKE_LOCK` 均 0）；NekoBox `bg/BaseService.kt:295-305` `lateInit()` 里 `if (DataStore.acquireWakeLock) acquireWakeLock()`（`PowerManager.WakeLock`）。**已确认不做**：nekoray 亦无对应（§4.7） |
| `logLevel` | Log Level | ✅ `settings_page.dart:190-196` |
| `globalCustomConfig` | 全局自定义配置 | ✅ `settings_page.dart:423-429` `NkNavRow` → `/settings/custom-config` 子页（`sections/custom_config_page.dart`）；组装完成后深合并进整份配置（同 §3.1 的节点级 `customConfig`，但作用域是全局） |

### 4.2 Route Settings（7 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `proxyApps` | Apps VPN mode | ✅ `per_app_proxy`（Android），见 §3.5 |
| `bypassLan` | Bypass LAN（应用侧分流规则） | ⛔ **hiddify 无应用侧 bypassLan**：上游 `bypassLan` 是往路由表插一条应用级规则，hiddify 侧对应的入口已随 fork A 删除（原 `predefined_rules_modal.dart` 里的 Bypass LAN 预设，1:1 后不再种）。**内核侧那一半由下一行的 `bypassLanInCore` 承担**（这才是 hiddify 实际生效的通道） |
| `bypassLanInCore` | Bypass LAN in Core | ✅ 已实施（`d672db7e`；`settings_page.dart:280-281` 开关 → 内核 `bypass-lan` → `builder.go:677-695` 追加 `IPIsPrivate → direct`） |
| `trafficSniffing` | Enable Traffic Sniffing | ⛔ **内核有动作、无开关（2026-10-05 复核）**：`builder.go:517-518` `SniffEnabled`/`SniffOverrideDestination` 在 `InboundOptions` 注释块里被注释，**但** `:628` `Action: C.RuleActionTypeSniff,` 是活的（内核无条件追加一条 sniff 路由规则，紧接 `:634` `RuleActionTypeHijackDNS`）；`lib/` 全库无 `sniff` 命中 ⇒ 用户级开关做不了 |
| `resolveDestination` | Resolve Destination | ✅ `settings_page.dart:272-273` |
| `ipv6Mode` | IPv6 Route | ✅ `settings_page.dart:285-286` |
| `rulesProvider` | Rule Assets Provider | ❌ 无 Assets 源选择（`lib/` 无 `rule_set_provider`/`assetsProvider` 命中）；对应 NekoBox `route menu` 的 Manage Route Assets（§3.5） |

### 4.3 DNS Settings（7 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `remoteDns` | Remote DNS | ✅ `settings_page.dart:312-316` |
| `domain_strategy_for_remote` | Remote 域名策略 | ✅ `settings_page.dart:317-323` |
| `directDns` | Direct DNS | ✅ `settings_page.dart:324-328` |
| `domain_strategy_for_direct` | Direct 域名策略 | ✅ `settings_page.dart:329-335` |
| `domain_strategy_for_server` | 服务器地址域名策略 | ❌ `lib/` 全库 0 命中（`serverDomainStrategy`/`domain_strategy_for_server` 均无） |
| `enableDnsRouting` | Enable DNS Routing | ⛔ **内核卡住（2026-10-05 更正，先前误判）**：内核 proto/pb 侧确有字段（`hiddify_options.proto:65` `bool enable_dns_routing = 7;`、`hiddify_options.pb.go:339`、`hiddify_options.go:19` 默认 `false`），但**没有任何消费者**——`builder.go:973` 的 `// if opt.EnableDNSRouting {` 整块被注释掉，其下 `if hopt.EnableFakeDNS {` 是**独立条件**（fakedns 走自己的分支，与 dns-routing 无关）；`v2/config/hiddify_option.go:46` 的 JSON 字段也注释掉了。⇒ 即使应用侧接线，`singboxConfigOptions` 传进去也不会产生任何行为差异。**属 C 组（需重建内核）**，不是接线的活 |
| `enableFakeDns` | Enable FakeDNS | ✅ `settings_page.dart:336-340` |

### 4.4 Inbound Settings（3 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `mixedPort` | Proxy Port | ✅ `ConfigOptions.mixedPort`（入站子页 `sections/inbound_options_page.dart`，另有 hiddify 独有 tproxy/redirect/direct 三端口） |
| `appendHttpProxy` | Append HTTP Proxy to VPN | ❌ 全库 0 命中 |
| `allowAccess` | 允许局域网连接 | ✅ `allowConnectionFromLan` + `lan_sharing_password` |

### 4.5 Misc Settings（8 项）

| NekoBox key | 标题 | hiddify 现状 |
|---|---|---|
| `connectionTestURL` | Connection Test URL | ✅ `settings_page.dart:376-380` |
| `enableClashAPI` | Enable Clash API | ✅ `settings_page.dart:385-397`（开关 + `clash-api-port`，端口行随开关 `enabled`） |
| `networkChangeResetConnections` | 换网重置连接 | 🟡 **能力等价、开关不同（2026-10-05 复核）**：NekoBox 是显式开关（`DataStore.kt:92` 默认 `true`）→ `BaseService.kt:287` `if (DataStore.networkChangeResetConnections) Libcore.resetAllConnections(true)`。hiddify 无开关但**行为默认开启**：`hiddify-sing-box/route/network.go:481 notifyInterfaceUpdate` → `:519 r.ResetNetwork()`（且 `if !r.started { return }` 守卫），链路是 `PlatformInterfaceWrapper.kt:78-79 startDefaultInterfaceMonitor` → `DefaultNetworkMonitor`（`BoxService.kt:162` 启动 / `:289` 停止）→ `monitor.go:57 UpdateDefaultInterface` → 回调。**无「关掉」的开关**，但重置本身已实现 |
| `wakeResetConnections` | 唤醒重置连接 | ❌ 豁免项（判定不移植）：NekoBox `BaseService.kt:57-62` 监听 `PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED`，退出 doze 时 `Libcore.resetAllConnections(true)`。hiddify **也监听同一广播**（`BoxService.kt:127-131`，注册在 `:331`），但 `serviceUpdateIdleMode()`（`:253-261`）只调 `Mobile.wake()`，**不做重置**（对比 NekoBox `:60-62`）。`hiddify-sing-box/experimental/clashapi/connections.go:105` 的 `network.ResetNetwork()` 在 `DELETE /connections` 里，属另一条路径。⇒ 差异 = 缺 doze 退出后的重置 |
| `globalAllowInsecure` | 全局允许不安全 | ⛔ 内核卡住：NekoBox 在 4 个 Fmt.kt 组装层做 `bean.allowInsecure \|\| globalAllowInsecure`，hiddify 出站组装在内核 Parse（`HiddifyOptions` 无此字段），需重建内核库才能做 |
| `allowInsecureOnRequest` | 更新订阅时跳过证书检查 | ✅ `settings_page.dart:411-419` `NkSwitchRow`；`DioHttpClient` 增加订阅专用 insecure 实例（`badCertificateCallback` 放行），`ProfileParser` 订阅下载按开关路由；其余请求不受影响（`tool/check_insecure_request.dart` 10 项校验） |
| `appTLSVersion` | 订阅最低 TLS 版本 | ⛔ SDK 卡住：NekoBox 的 `restrictedTLS()` 是 Libcore(Go) 能力，dart:io 无最低 TLS 版本 API（仅 ALPN） |
| `showBottomBar` | SagerNet 式底部栏 | ✅ hiddify StatsBar（形态不同） |

### 4.6 hiddify 独有（NekoBox 没有，保留不删）

`use-xray-core-when-possible`、`balancer-strategy`、`region`、`strict-route`、`url-test-interval`、
`independent-dns-cache`、TLS 分片/填充/mixed-SNI 共 7 项、`mux-*` 4 项、
`chain`（extraSecurity / unblocker + WARP / Psiphon）共 15 项、tproxy/redirect/direct 端口 4 项、
`auto_apps_selection_*`、窗口位置/尺寸、`action_at_close` 等。

> **待接线（hiddify 自己有、当前被注释，不属 NekoBox 对照项）**：`block-ads`、`block-quic` ——
> 内核消费者都活着，只是 Dart 侧被注释/从未接线，详见 §8.1 的修正记录。接上之后应列入本节。

---

### 4.7 桌面形态映射（nekoray 参照，2026-09-16）

> 原则：**规格以 NekoBox（Android）为主，nekoray（桌面孪生，`S:/test/nekoray` 4.0.1）
> 只用来回答"Android 特有能力在桌面端的正统形态是什么"**。不做第二套界面。
> 此前被归入 B 档"Android 管线、桌面无意义"的项，经 nekoray 对照后重新分档：

| NekoBox Android 项 | nekoray 桌面形态（源码依据） | hiddify 桌面现状 | 结论 |
|---|---|---|---|
| `speedInterval`（通知速率刷新间隔） | `traffic_loop_interval`（500-5000ms，0=禁用），`TrafficLooper::Loop()` 线程 | 内核 `GetSystemInfoStream` 每秒推（`hcore commands.go`），托盘 tooltip 每秒更新 | ✅ 桌面固定 1s 已够用，不做独立开关 |
| `showDirectSpeed` | 主窗 `label_speed` "Proxy: x\nDirect: y" | 仪表盘/侧栏/代理页速率条已有；**托盘 tooltip 已加速率行**（↑↓，2026-09-16） | ✅ |
| `showGroupInNotification`（通知显示分组/节点） | tray tooltip：`[Tun]/[System Proxy]` + `节点@分组`（`mainwindow.cpp make_title`） | **托盘 tooltip 已加**：`[模式短名] 节点名` + 延迟 + 速率（2026-09-16） | ✅ |
| `acquireWakeLock`（保持唤醒） | nekoray 无对应（防睡眠未实现） | — | ⛔ 参考实现都没有，不做 |
| 快捷方式 / 磁贴 | nekoray：全局热键（`dialog_hotkey`）+ 托盘菜单 | 托盘菜单已有（连接切换/服务模式/退出）；热键缺 | 🟡 热键留待需要时做 |
| `alwaysShowAddress`（列表始终显示地址） | nekoray 列表设置 | **已实施**：`settings_page.dart:183-189` `Preferences.alwaysShowAddress` 开关（默认关闭），代理卡按开关决定是否显示服务器地址行（`proxy_tile.dart`） | ✅ Android/桌面同形，已对齐 |
| per-node 流量统计（Android TrafficLooper 逐 profile） | nekoray 走自家 core 的 v2rayapi `QueryStats(tag)`（`db/traffic/TrafficLooper.cpp`） | hiddify-core 未启用 V2Ray stats、hcore gRPC 无 per-outbound 统计 RPC（只有总速率 `GetSystemInfoStream`） | ⛔ 内核卡住不变 |

**技术事实**：hcore 的 `SystemInfo.uplink/downlink` 是**每秒速率**（UI 以 `.speed()` 直接格式化，
两次采样差值），`OutboundInfo.tagDisplay` 是节点显示名 —— 托盘 tooltip 的数据源全在 Dart 侧现成。

## 5. 协议编辑表单（规格：`res/xml/*_preferences.xml`，19 份）

**hiddify 现状：15 份协议表单已实施**（`lib/features/proxy/data/protocol_form.dart:874-890` `_specs`），
覆盖 NekoBox 全部 12 份协议 `*_preferences.xml`，**唯一未移植的是 `trojan_go`**（hiddify 内核
`include/registry.go` 无 `TypeTrojanGo`）。另有 3 份非协议表单以独立 sheet 实现（见 §5.3）。

> **依赖已就绪**（2026-09-15）：节点实体表（含凭据 payload）、组装成 `<id>.entities.json`、
> 列表以实体为准、删除+撤销 —— 全部已实施并**真机自测通过**。
> **2026-10-05 更新**：表单本身也已全部落地，"表单改完写回实体 → 重组装 → 重载内核"这条链路**已闭环**
> （写入端 `applyProtocolForm`，入口 `protocol_form_modal.dart:23 showProtocolFormSheet` / `:47 showProtocolCreateSheet`）。
> 分批执行顺序原在 `docs/design/nekobox-priority.md`（2026-10-03 精简删除，`git log --diff-filter=D -- docs/design/` 可找回）；批次 1–14 的落地结果见 `docs/design/parity-sequence-log.md`。

### 5.1 规格驱动的可执行表单

规格 = `lib/features/proxy/data/protocol_form.dart`；字段 → sing-box JSON 的映射在文件内逐条注明，
判据是 `fmt/*/*Fmt.kt` 的 `buildSingBoxOutbound*`，不是 Bean 属性名 —— 两处 key 名不一致，按**行为**对齐。

行号 = 该 `const _xSpec = ProtocolFormSpec(` 起、到下一个 spec 前一行为止的**整块**（字段数用 `Select-String -Pattern "ProtocolField\("` 在块内计数，实测 **15 份合计 166 字段**）。

| 表单（spec 行号） | 字段数 | 规格来源 | 备注 |
|---|---|---|---|
| `_anytlsSpec:203-231` | 8 | `anytls_preferences.xml` | 含 ECH（原判「真机 0 节点用到」已补齐） |
| `_vlessSpec:232-329` | 20 | `standard_v2ray_preferences.xml` | `encryption` 对 VLESS = `flow`；含 ECH / reality / uTLS |
| `_vmessSpec:330-421` | 21 | 同上（VMess 分支） | = vless − `flow` ＋ `alterId`（→`alter_id`）＋ `encryption`（→`security`，choices 含前导空串 = 未设置 ⇒ 不写键 ⇒ 内核默认 `auto`，`V2RayFmt.kt:662`） |
| `_hysteria2Spec:422-465` | 13 | `hysteria_preferences.xml` | v2 分支 |
| `_trojanSpec:466-561` | 18 | `trojan_go_preferences.xml` 的 TLS 部分 | trojan（非 trojan_go）；含 ECH；种子 `protocolSeedPayload:1105-1107` 默认 `tls.enabled = true` |
| `_hysteriaSpec:562-592` | 14 | `hysteria_preferences.xml` | v1 分支（`:546` 注释：本表单只收 v1 字段，v2 见 `_hysteria2Spec`） |
| `_shadowsocksSpec:593-623` | 6 | `shadowsocks_preferences.xml` | method 18 项取值照 `@array/ss_enc_method_value`；pluginName→`plugin` / pluginConfig→`plugin_opts` |
| `_socksSpec:624-655` | 5 | `socks_preferences.xml` | `serverPassword` `disabledBy: 'serverProtocol', disabledWhen: {'4','4a'}`（见下「置灰约定」） |
| `_httpSpec:656-699` | 12 | `standard_v2ray_preferences.xml`（`HttpBean` 同族） | 含 ECH；`security`→`tls.enabled`；两条 `ProtocolContainerRule`（`path: ['tls']` + `dropWhen: {'false'}`、`path: ['tls','utls']`） |
| `_sshSpec:700-719` | 7 | `ssh_preferences.xml` | |
| `_tuicSpec:720-757` | 12 | `tuic_preferences.xml` | `serverSNI` `disabledBy: 'serverDisableSNI'` |
| `_shadowtlsSpec:758-795` | 9 | `shadowtls_preferences.xml` | |
| `_mieruSpec:796-828` | 5 | `mieru_preferences.xml` | |
| `_wireguardSpec:829-853` | 8 | `wireguard_preferences.xml` | |
| `_naiveSpec:854-892` | 8 | `naive_preferences.xml` | |

汇总函数：`protocolFormSpecFor:893`、`kManualCreatableProtocols:926`、`protocolDisplayName:949`、
`resolveProtocolFieldPath:1170`、`protocolFieldEnabled:1181`。

**未纳入（如实）**：
- `trojan_go`（`trojan_go_preferences.xml:1-3608`）—— **内核无类型**，无法移植。
- `name_preferences.xml`（改名）—— `tag` 是节点身份（内核配置 / 选中偏好 / 删除基线三处都用它），
  要跨三处迁移，与「手动新建节点」是同一套机制，应一起做。**目前仍未做。**
- 跨协议零星项：mux 4 项（`enableMux`/`muxType`/`muxConcurrency`/`muxPadding`，hiddify 的 mux 在全局
  `ConfigOptions` 而非节点级）、`sUoT`（`socks`/`naive`/`shadowsocks` 都有；hiddify 侧
  shadowsocks 表单只有布尔而无 sing-box 的 `{enabled,version}` 对象形态）。

### 5.2 字段联动与置灰约定（跨表单）

`ProtocolField` 的 `disabledBy` / `disabledWhen`（`protocol_form.dart` 构造器）实现 NekoBox 的
`updateProtocol()` / `updateProtocolVersion()` 式联动；求值入口
`bool protocolFieldEnabled(ProtocolField field, {required Map<String, String> values})`（`:1181`），
UI 侧 `protocol_form_modal.dart:328` `enabled: protocolFieldEnabled(field, values: values.value)`。
`disabledWhen` 为空时 `when` 默认 `{'true'}`（布尔控制器）。

**置灰 vs 隐藏的有意差异**：NekoBox `SocksSettingsActivity.kt:53-55` 用 `password.isVisible =
version == SOCKSBean.PROTOCOL_SOCKS5`（**整行隐藏**），而 `SOCKSFmt.kt:66-75` 在 4/4a 下**照写**
password（sing-box `protocol/socks/client.go:128-135` 在 4/4a 下也不读它）。hiddify 统一改为
**置灰**（`disabledWhen`）并保留值写入 ⇒ payload 等价，差异仅在显示层。

### 5.3 非协议表单（同属 §5 规格范围）

| NekoBox 规格 | hiddify 落点 | 覆盖情况 |
|---|---|---|
| `config_preferences.xml`（自定义配置：profileName / isOutboundOnly / serverConfig） | `lib/features/proxy/widget/config_settings_page.dart:31` `showConfigSettingsSheet({tag, isNew})`；入口 `manual_node_flow.dart:44-48`（手动新建）+ 节点表单 ⋮ 菜单 | ✅ |
| `group_preferences.xml`（分组设置：groupName / groupType / groupOrder / isSelector / front / landing ＋订阅 6 项） | `lib/features/proxy/overview/group_settings_sheet.dart`（126 行）；入口 `groups_page.dart:156` `onEdit: () => _openGroupSettings(...)` | 🟡 分组名 / 删除有；**订阅链接·去重·自动更新**按归一原则交给订阅页（sheet 内提示行 + `onOpenSubscriptions` 可达，`:84-109`）；**前后置代理未做**（`:15` 注释：等 chain 语义定案） |
| `route_preferences.xml`（routeName / serverConfig ｜ routePackages / routeDomain / routeIP / routePort / routeSource / routeSourcePort / routeNetwork / routeProtocol / routeOutbound） | `lib/features/route_rules/`（`rule_page.dart` 251 行 + `setting_detail_chips.dart` 222 行 + `generic_list_page.dart`） | ✅ 规则模型见 §7 的 `RuleEntity` 行；**Create Rule 反查入口缺失**见 §3.4 |
| `balancer_preferences.xml`（profileName / balancerType / balancerStrategy / balancerGroup） | — | ❌ **无 balancer 实体**：hiddify 的 balancer 是内核自建常量表（`runtime_outbound_tags.dart:40-43` `OutboundURLTestTag`/`OutboundRoundRobinTag`），策略由全局 `ConfigOptions.balancerStrategy` 控制，没有「用户自建 balancer 组」这一层 |
| `name_preferences.xml` / `neko_preferences.xml` | — | ❌ 见 §5.1「未纳入」 |

---

## 6. 平台组件（规格：`AndroidManifest.xml`）

| 组件 | 类型 | hiddify 现状 |
|---|---|---|
| `MainActivity` | activity | ✅ |
| `BlankActivity` / `ThemedActivity` / `VpnRequestActivity` / `ToolbarFragment` / `SettingsPreferenceFragment` / `NamedFragment` | 框架基类 | ⚪ **不是功能面**（不计入缺口核对） |
| **16 个 `profile/*SettingsActivity`** | activity | 🟡 **15/16 已实现**，形态改为底部 sheet（`protocol_form_modal.dart:23` `showProtocolFormSheet` / `:47` `showProtocolCreateSheet`）；规格表见 §5.1。**唯一未实现的是 `TrojanGoSettingsActivity`**（内核无 `TypeTrojanGo`，无法移植） |
| `GroupSettingsActivity` | activity | 🟡 `group_settings_sheet.dart`（126 行）＝对话框等价物，入口 `groups_page.dart:156` `onEdit`。有：分组名 / 删除（危险动作，`TextButton` 用 error 色 + 页面侧确认框）。缺：订阅链接·去重·自动更新（归一原则 → 订阅页，sheet 内 `:84-109` 提示行 + `onOpenSubscriptions` 可达）、前后置代理（`:15` 注释：等 chain 语义定案） |
| `RouteSettingsActivity` | activity | ✅ `rule_page.dart`（251 行）+ `setting_detail_chips.dart`（222 行） |
| `AssetsActivity`（geo 资源管理） | activity | ❌ 未移植（同 §3.5 `route menu` 的 Manage Route Assets / §4.2 `rulesProvider`） |
| `AppListActivity` | activity | ✅ 每应用代理 |
| `AppManagerActivity` | activity | ✅ 每应用代理（`per_app_proxy_page` + `android_apps_page`） |
| `ScannerActivity`（扫码） | activity | ✅ 已确认可用且接线（`fix_btns.dart:60-67` → `QrCodeScannerDialog`） |
| `ProfileSelectActivity` | activity | ⚪ 复用配置页的选择模式，代理页本身即覆盖（非独立缺口） |
| `StunActivity` / `NetworkFragment` | activity / fragment | ✅ `tools_page._NetworkTab` STUN |
| `SwitchActivity` | activity | ⚪ 同 `ProfileSelectActivity`（选择器） |
| `QuickToggleShortcut` / `QuickEnableShortcut` / `QuickDisableShortcut` | activity（桌面快捷方式） | 🟡 `android/app/src/main/res/xml/shortcuts.xml` 只有 1 个（`shortcutId="toggle"` → `ShortcutActivity`）；NekoBox 有 4 个（toggle / enable / disable / scan）。且 NekoBox 的 `enable`/`disable` 是**语义分离**（我的 toggle 是单键切换），NekoBox 还支持**逐节点 pin 快捷方式**（§3.1 `action_create_shortcut`） |
| `ProxyService` / `VpnService` | service | ✅ 内核/接管机制（平台实现不同） |
| `TileService`（快捷磁贴） | service | ✅ **已实现（此前判「硬充」有误，2026-10-05 更正）**：磁贴走**原生 Kotlin** 路线，不依赖 Dart 侧的 `flutter_quick_settings`。`android/app/src/main/kotlin/com/hiddify/hiddify/bg/TileService.kt` 全实现：`onStartListening/onStopListening` 接 `ServiceConnection`、`onServiceStatusChanged(status)` 映射 `Status.Started/Stopped/其他` → `Tile.STATE_ACTIVE/INACTIVE/UNAVAILABLE`、`toggleService()` 走 `Settings.startCoreAfterStartingService = true; BoxService.start()/stop()`、`onClick()` 处理锁屏（`KeyguardManager.isKeyguardLocked` → `unlockAndRun`）。manifest 注册完整（`AndroidManifest.xml:109-121`，含 `BIND_QUICK_SETTINGS_TILE` 权限与 `TOGGLEABLE_TILE` meta-data）。被注释的只是废弃的 Dart 侧 `lib/features/platform_specific/android_quick_settings_tile.dart`（57 行全注释、`lib/` 内 0 处引用） |
| `BootReceiver`（开机自启） | receiver | 🟠 **硬充**：无 receiver，靠系统 always-on（`SUPPORTS_ALWAYS_ON`）+ `autoStart` 替代 |
| `FileProvider` | provider | 🟡 机制不同（FilePicker/导出文件），能力等价 |
| `BackupFragment`（备份/恢复） | fragment | 🟡 **形态等价、维度不同**：NekoBox `ui/BackupFragment.kt:80-97` 是 **三类勾选**（`binding.backupConfigurations` / `backupRules` / `backupSettings` → `doBackup(profile, rule, setting)`，`:137`）＋ 导出到文件 / 分享（走 `FileProvider` cache 文件）+ 导入文件 + `resetSettings`（`DataStore.configurationStore.reset()` + 全重启）。hiddify `tools_page.dart:117-182` `_BackupTab` 是 **两档**（匿名 / 全部，`excludePrivate`）× **两种载体**（文件 / 剪贴板）共 4 行 + 导入（文件/剪贴板，带确认）+ 重置选项 + 触发订阅更新。⇒ **缺「按配置/规则/设置分类导出」** |
| `WebviewFragment`（yacd 面板） | fragment | ❌ 无内嵌面板；hiddify 的 Dashboard 是自研统计（硬充） |

---

## 7. 数据库实体（规格：`database/`, `app/schemas/`）

> drift schema 版本：`lib/core/db/db.dart` `schemaVersion` = **8**（v8 迁移 `:79-81`
> `addColumn(schema.proxyEntities, schema.proxyEntities.customOutbound)`；新增 `customConfig` 同批）。
> 四张表：`ProfileEntries:95` / `AppProxyEntries:117` / `ProxyGroups:132` / `ProxyEntities:173`。

| NekoBox 实体/表 | 作用 | hiddify 现状 |
|---|---|---|
| `ProxyEntity` + `ProxyEntity.groupId` | 节点（含全部凭据） | ✅ `ProxyEntities`（drift v8；`payload` 存完整出站 JSON 含凭据，真机已落库 84 行；另有 `customOutbound`/`customConfig` 两列承载节点级覆写，见 §3.1） |
| `ProxyGroup` | 分组（type/ungrouped/isSelector/order/userOrder） | ✅ `ProxyGroups`（drift v8；另含 front/landing 两列）。**手动建组已做**：`proxy_entity_repository.dart:399` `Future<int?> createGroup({String? name, bool ungrouped = false, bool isSelector = false})`，入口 `groups_page.dart:174-222`（工具栏 `createGroup`）；另有 `renameGroup:454` / `moveGroups:436` / `removeGroup:469` / `clearGroupNodes:492` / `ensureUngroupedGroup:362` |
| `RuleEntity` | 路由规则 | ✅ hiddify 自己的规则模型（`lib/singbox/model/singbox_rule.dart` `@freezed class SingboxRule`，字段 `ruleSetUrl/domains/ip/port/protocol/network(默认 tcpAndUdp)/outbound(默认 proxy)`；`enum RuleOutbound { proxy, bypass, block }`；`enum RuleNetwork`） |
| `SubscriptionBean` | 订阅元数据 | ✅ `ProfileEntries` |
| `DataStore`（PublicDatabase） | 全局偏好 | ✅ shared_preferences |
| `TempDatabase` | 临时（导入流程） | ❌ 未移植（导入流程走应用内存，未用临时库） |

---

## 8. 缺口总表（已按**内核支持情况**核实，2026-09-15 建；**2026-10-05 逐条复验**）

核实方法：读 `hiddify-core/v2/config/hiddify_option.go`（内核实际接受的 JSON 字段）与
`v2/hiddifyoptions/hiddify_options.proto`，逐项确认"内核是否已支持"。

> **2026-10-05 复验说明**：8.1–8.5 逐条重跑 `git grep -n -E PATTERN -- lib`（**`git grep` 没有 `--include`**，见 §4 教训）
> 并回查内核源码。两条翻案：`enableDnsRouting` 内核无消费者（⛔，原判"仅需接线"）、`meteredNetwork` 代码写死 `setMetered(false)`（🟡）。
> 一条作废：清空测速/清空流量（清的是实体列，不需 RPC）。
> 一条改判（8.1 补记）：`block-quic` 原写「暂不做」，实为**消费者活着、仅 Dart 侧被注释** ⇒ A 组；同批复核发现 `block-ads` 同病（`868b85de` 注释掉后漏恢复）。

### 8.1 ✅ 内核已支持、app 侧整链被注释（**最省事，仅需接线**）

| 项 | 内核证据 | app 侧现状 |
|---|---|---|
| **Bypass LAN in Core**（NekoBox `bypassLanInCore`） | `RouteOptions.BypassLAN` `json:"bypass-lan"` **在册可用**；内核确有实现 —— `v2/config/builder.go:677-695`：`BypassLAN` 为真时追加路由规则 `IPIsPrivate: true → outbound: direct` | ✅ **已接线（提交 8 项改动）**：`config_option_repository` 的选项定义 / `preferences` 映射 / 装配三处取消注释；`singbox_config_option.dart` 字段恢复；设置页「路由」卡新增 `NkSwitchRow`（复用 NekoBox 文案 `bypass_lan_in_core` = "Bypass LAN in Core" / "在核心中绕过 LAN"） |
| **TUN service 模式（`vpn-service`）** | `InboundOptions.EnableTunService` `json:"enable-tun-service"` 在册 | ⚠️ **不是 NekoBox 项** —— 核实后 NekoBox 的 `serviceMode` 取值是 `[vpn, proxy, transproxy]`（`res/values/arrays.xml`），**没有 tunService**。hiddify 的 `tunService` 是它自己的东西（且被注释）。→ 改按 NekoBox 的口径处理：**hiddify 缺的是 `transproxy`**（见 8.5） |
| **Block QUIC** | `RouteOptions.BlockQuic` `json:"block-quic"` 在册（`v2/config/hiddify_option.go:74`），**消费者活着**：`v2/config/builder.go:939` `if hopt.RouteOptions.BlockQuic {` → `:940-953` 追加 `Protocol: []string{C.ProtocolQUIC}` + `RuleActionTypeReject` 规则 | ⚠️ **不是 NekoBox 项**（NekoBox 全 `res/xml` 无此开关；`route_opt_block_quic` 只是预设规则的**名字**字符串），属 hiddify 侧自己注释掉的遗漏。`lib` 内 `blockQuic\|block_quic\|block-quic` **0 命中**。→ 定性由「暂不做」改为**A 组仅需接线**（2026-10-05 复核，见下） |
| **Block Ads** | `HiddifyOptions.BlockAds` `json:"block-ads,omitempty" overridable:"true"`（`v2/config/hiddify_option.go:21`），**消费者活着**：`v2/config/builder.go:756` `if hopt.BlockAds {` → `:757-816` 注册 6 个远端 ruleset（`geosite-ads`/`geosite-malware`/`geosite-phishing`/`geosite-cryptominers`/`geoip-malware`/`geoip-phishing`，`UpdateInterval 5*24h`）→ `:818-838` 一条 `RuleActionTypeReject` 规则引用全部 tag → `:839-850` 4 个 tag 的 DNS reject 规则；另一消费者 `v2/hcore/independent_instance.go:52` `hiddifySettings.BlockAds = false` | ⚠️ 同样**不是 NekoBox 项**。Dart 侧 3 处被注释：`config_option_repository.dart:43`（选项定义 `PreferencesNotifier.create<bool, bool>("block-ads", false)`）、`:376`（`preferences` 映射）、`:494`（`SingboxConfigOption(...)` 实参）；另 `lib/singbox/model/singbox_config_option.dart:20` `// required bool blockAds,`。注释来源 = `868b85de update sing box repo and model for adding route rule and removing blockAds and bypassLan`（同期 `bypassLan` 也被注释，**后来已恢复**）⇒ 属**漏恢复**，A 组 |
| **`block-quic` 为何不需要重建内核**（判 A/C 组的依据） | Dart 侧**不构造 proto `HiddifyOptions`**：`lib/singbox/model/singbox_config_option.dart:16-64` 是 `@JsonSerializable(fieldRename: FieldRename.kebab)` 的纯 Dart 模型，`format()` 用 `JsonEncoder.withIndent('  ').convert(toJson())` → `lib/hiddifycore/hiddify_core_service.dart:160` `changeOptions(SingboxConfigOption)` → `:165-171` `ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson()))` → 内核 `v2/hcore/buildconfighelper.go:88` `ChangeHiddifySettings` → `:121` `json.Unmarshal([]byte(in.HiddifySettingsJson), static.HiddifyOptions)`，而 `static.HiddifyOptions` 的类型是 `v2/hcore/static_data.go:17` `HiddifyOptions *config.HiddifyOptions`（**Go 结构体**，非 proto 生成物） | ⇒ **只要 Go 结构体上有 `json:` 标签就通**。`block-quic` 虽**不在** proto（`v2/hiddifyoptions/hiddify_options.proto:95-100` `message RouteOptions` 只有 `resolve_destination/ipv6_mode/bypass_lan/allow_connection_from_lan`），`block-ads` 在 proto（`:22` `bool block_ads = 8;`）—— 但两条路径 App 都没用，`lib` 非生成物里 `HiddifyOptions` 的 4 处命中**全是注释**，`overrideHiddifyOptions`/`OverrideHiddifyOptions` **0 命中** |

> **8.1 三项修正记录（2026-10-05 第二回复核）**
> 1. `Block QUIC` 原写「暂不做」，**改判为 A 组（仅需接线）** —— 与 §8.2 的 `enableDnsRouting` 是**同类形状、相反结论**：
>    两者都是「proto/pb 字段在册」，但 `enableDnsRouting` 的内核消费者被注释（`builder.go:973`），
>    `BlockQuic` 的消费者**活着**（`builder.go:939`）。判组别时**必须看消费者，不能看字段**。
> 2. 同批发现 **`Block Ads`** 同病：内核消费者活着（`builder.go:756`），Dart 侧 `868b85de` 注释掉后**漏恢复**
>    （同提交里 `bypassLan` 也被注释，但它后来恢复了 —— 这就是漏恢复的证据）。
> 3. 接线动作（两项相同，**无需重建内核**）：`config_option_repository.dart` 的 `:43` 选项定义 / `:376` `preferences` 映射 /
>    `:494` 装配实参三处取消注释（`block-ads`）或新增（`block-quic`），`singbox_config_option.dart` 补字段，
>    设置页「路由」卡加开关。`block-quic` 的 JSON key 取 `hiddify_option.go:74` 的 `json:"block-quic,omitempty"`。
>    **注意区分**：这与 §3.5.1 的预设规则「屏蔽 QUIC / 屏蔽广告」是**两回事** ——
>    预设规则是 per-rule 的 `port=443,network=udp` / `geosite:category-ads-all`，
>    全局开关是内核里硬编码的 6 个远端 ruleset（`hiddify-geo/rule-set/block/*.srs`）+ 一条 Reject 规则。

### 8.5 ✅ serviceMode 已实质对齐（先前误判，已撤销）

核实过程（先资源、后代码）：

| 证据 | 结果 |
|---|---|
| `res/values/arrays.xml` `service_mode_values` | `[vpn, proxy, transproxy]` |
| `Constants.kt:15-17` | 只声明 `SERVICE_MODE` / `MODE_VPN` / `MODE_PROXY` —— **没有 transproxy 常量** |
| `bg/SagerConnection.kt:25-29` | `when (serviceMode) { MODE_PROXY -> ProxyService; MODE_VPN -> VpnService; else -> throw UnknownError() }` |
| 全仓库搜 `transproxy` | 16 个命中**全是资源文件**（arrays + 各语言 strings），**Java/Kotlin 里 0 处** |

→ NekoBox 实际只有 **2 种模式**，`transproxy` 是资源里的死项（选到会 `throw UnknownError()`）。

对照结果：

| NekoBox | hiddify | 判定 |
|---|---|---|
| `vpn`（VPN） | `tun`（"VPN"） | ✅ 对齐 |
| `proxy`（"Proxy only"） | `proxy`（"仅代理服务"） | ✅ 对齐 |
| `transproxy` | — | ⛔ **NekoBox 自己也没实现，无需补** |
| — | `systemProxy`（"设置系统代理"） | ➕ 桌面端增强，保留 |

**结论：8.5 结案，serviceMode 不用改。** （我先前据 arrays 里的死项判定"hiddify 缺 transproxy"是错的 —— 记在此以免重犯。）

---

## 8.6 8.4 移植规格：NekoBox 的实体层（**已实施，2026-10-05 更新**）

> 规格取自 NekoBox 源码实测，**照抄结构，不做设计发挥**。

### 8.6.1 NekoBox 的表结构（`database/`，SagerDatabase version 6，3 张表）

**`proxy_groups`**（`database/ProxyGroup.kt`）
```
id, userOrder, ungrouped:Boolean, name, type:Int(GroupType.BASIC|SUBSCRIPTION),
subscription:SubscriptionBean?,      // 订阅详情（Kryo 序列化）
order:Int(GroupOrder.ORIGIN|BY_NAME|BY_DELAY),
isSelector:Boolean,
frontProxy:Long, landingProxy:Long   // 前置/落地代理（链式）
```

**`proxy_entities`**（`database/ProxyEntity.kt`，索引 `groupId`）
```
id, groupId, type:Int, userOrder, tx, rx, status, ping, uuid, error,
+ 每个协议一个列：socksBean / httpBean / shadowsocksBean / vmessBean / trojanBean /
  trojanGoBean / mieruBean / naiveBean / hysteriaBean / tuicBean / sshBean /
  wireGuardBean / shadowTLSBean / anyTLSBean / configBean / chainBean …
  （各 Bean 用 Kryo 序列化成二进制列）
```

**`rules`**（`database/RuleEntity.kt`）
```
id, name, config, userOrder, enabled, domains, ip, port, sourcePort,
network, source, protocol, outbound:Long(0=proxy/-1=bypass/-2=block/其他=指定的配置 id),
packages:Set<String>
```

关键机制（`fmt/ConfigBuilder.kt`，756 行）：**从 DB 读 entities/groups → 拼 sing-box 配置**；
`GroupManager.createGroup` 只在「导入订阅」与「手动新建」时调用。

### 8.6.2 映射到 hiddify（drift + 现有内核接口）

| NekoBox | hiddify 侧对应 | 说明 |
|---|---|---|
| `proxy_groups` 表 | **新增 drift 表** `ProxyGroups` | 字段照抄；`subscription` 存 JSON（hiddify 是 JSON 栈，不引入 Kryo）；`frontProxy`/`landingProxy` 改为引用 node 主键 |
| `proxy_entities` 表 | **新增 drift 表** `ProxyEntities` | 协议字段不用 15 个列，改为**一个 `payload` JSON 列**（等价于 NekoBox 的 Bean，序列化方式不同，语义相同） |
| `rules` 表 | hiddify 已有自己的规则模型（`rule_page.dart` + route rules） | 不移植，只补字段（§5 的 route 表单） |
| 订阅导入建组 | `ProfileEntries` 保留为"订阅源"，导入后**派生** group + entities | 与 NekoBox 一致：订阅 = group |
| `ConfigBuilder.kt`（DB→配置） | **应用只接管「节点出站那一段」**，不生成整份配置 | ⚠️ 本行初稿曾写「配置生成权从内核收回到应用」并引用 `Start(config_content, enable_raw_config=true)` —— **该结论已被 §8.6.8 推翻**：`enable_raw_config` 会让 `setInbound`/`setDns`/`setRoutingOptions` 一次都不执行，且 `GenerateConfig` 那条 RPC 在 proto 里是注释掉的。最终机制是**把出站表喂给内核、按路径启动**（`configs/<id>.entities.json`），inbounds/dns/route/log 仍由内核按 HiddifyOptions 构建 |
| 节点凭据来源 | `Parse` 返回的**完整配置文本**里含每个出站的完整定义（应用已用它实现「复制出站 JSON」） | 导入时解析落库即可拿到凭据 |

### 8.6.3 补充核实（本轮新增，两条都很关键）

**① NekoBox 的订阅导入 = 逐行解析分享链接，忽略订阅内的分组。**

| 证据 | 结果 |
|---|---|
| `ktx/Formats.kt:106 parseProxies(text)` | 按行/空格切分，逐条 `parseSOCKS` / `parseHttp` / `parseUniversal`(`sn://`) … → `AbstractBean` |
| 全代码搜 `proxy-groups` / `proxyGroups` | **0 处命中** ⇒ 订阅里的 clash proxy-group **不产生实体、不占 Tab** |
| `GroupManager.createGroup` | 只在「导入订阅」与「手动新建」时调用 ⇒ **一份订阅 = 一个 group** |

**② 由此确认"Tab 粒度"应按 NekoBox 口径：一份订阅 = 一个分组 = 一个 Tab。**
当前实现的「订阅 × 配置内分组」是 hiddify 内核能力带来的额外维度，**与 NekoBox 不一致**（见本文档 §5 `group_preferences` 与 `docs/design/connection-model.md` 第六节的"未对齐项"）。

### 8.6.4 实施进度

- ✅ **第 1 步（已完成）：凭据可落库验证**
  - 产出 `lib/features/proxy/data/proxy_entity_import.dart`：`deriveProxyGroupFromConfig()` —— 从内核 `Parse`/`generateConfig` 的**配置文本**派生「订阅分组 + 节点实体」，实体含**完整出站 JSON（凭据在内）**
  - 产出 `tool/check_entity_import.dart`：24 项断言 **ALL PASS**（实体集合排除规则、密码/UUID/TLS/uTLS/端口保留、payload 可原地拼回、四种边界 → null）
  - 排除规则照 NekoBox 口径：配置内的 selector/urltest/balancer **不成为实体**（它们由 `isSelector` 生成），`direct`/`block`/`dns` 与 `§hide§` 内部出站不算节点
- ✅ 第 2 步（**已完成**）：drift schema v6 → v7
  - 新增 `lib/core/model/proxy_group.dart`：`ProxyGroupType{basic,subscription}`、`ProxyGroupOrder{origin,byName,byDelay}`（照 NekoBox `GroupType`/`GroupOrder`；NekoBox 用 Int 存，此处用 `textEnum`，与既有表一致）
  - `lib/core/db/db.dart`：新增 `ProxyGroups`（10 列，字段逐一对照 `database/ProxyGroup.kt`）与 `ProxyEntities`（12 列，对照 `ProxyEntity.kt`，含 `groupId` 索引 `proxy_entities_group_id`）；`schemaVersion 6 → 7` + `from6To7` 迁移（**纯新增，不动既有表**）
  - 工具链：`build.yaml` 的 drift `schema_dir` 已就位 ⇒ ① `dart run build_runner build --delete-conflicting-outputs`（生成 `db.g.dart`）② **`dart run drift_dev make-migrations`**（生成 `db.steps.dart` 的 `Schema7` + 导出 `drift_schema_v7.json` + 重生成测试 schema `schema_v7.dart`）
  - 迁移测试无需改：`migration_test.dart` 遍历 `GeneratedHelper.versions`，版本列表已自动扩为 `[1..7]`，v1→v7…v6→v7 全覆盖
  - 踩坑：drift 不允许 `autoIncrement()` 与 `@override primaryKey` 同时使用（会出警告并可能不生成 steps）—— 两处 override 已删
  - ⚠️ 本项目既有约定是「排序/设置类小状态优先 shared_preferences，别轻易动 drift schema」（HANDOVER §5）。本次动 schema 是因为**实体层无法用偏好模拟**（需要关联关系、索引、迁移能力），属 8.4 的必要前提
  - ⚠️ 【已过时，2026-10-05 更正】此条原写「本环境跑不了 `flutter test`（缺 flutter_tester）」—— 实测 `%LOCALAPPDATA%\mise\installs\flutter\3.38.5\bin\cache\artifacts\engine\windows-x64\flutter_tester.exe` **存在**（38517760 B），当前全量 `flutter test` **291/291 通过**（含 `migration_test.dart` 的 v1→v7 遍历）。此条据以得出的「未在本机执行」结论作废
- ✅ 第 3 步（**已完成**）：导入管线（订阅写入 → 派生实体落库）
  - 新增 `lib/features/proxy/data/proxy_entity_repository.dart`：`ProxyEntityRepository.syncFromProfile()` —— 内核 `generateFullConfigByPath` 取配置文本 → `deriveProxyGroupFromConfig` 派生 → **事务内**按 `profileId` 认领分组（无则建、有则更新并整组替换节点）+ 批量插入实体
  - 挂钩点：`ProfileRepositoryImpl` 的**订阅写入咽喉**（`upsertRemote` 的 insert/edit、`addLocal` 的 insert、`offlineUpdate` 的 edit 共 4 处，统一调 `_syncEntities(id)`）—— 于是新增订阅、手动添加、批量更新、撤销删除重拉、编辑内容保存**全部覆盖**，无需改动 notifier
  - 反查键：`profileId` 记在 `proxy_groups.subscription` 这段 JSON 里（**不额外动 schema**），读写函数 `encodeSubscriptionPayload`/`profileIdOfSubscription` 放在**纯 Dart** 的 `proxy_entity_import.dart`，以便脚本校验
  - **失败策略**：`syncFromProfile` 内部吞掉所有异常只记日志 ⇒ 实体派生失败**不会**让订阅导入/更新失败
  - 依赖方向：`profileRepository → proxyEntityRepository →(db / 路径解析 / 内核)`，单向不成环
  - 校验：`tool/check_entity_import.dart` 扩到 **34 项断言 ALL PASS**（含反查键的 10 项边界）；`flutter analyze` 0 issue、release 构建通过
  - ⚠️ 【已过时，2026-10-05 更正】未验证项原文为「本环境无 flutter_tester」—— 见第 2 步同款更正；`migration_test.dart` 实际已在本机跑通
- ✅ 第 4 步（**已完成**）：出站表归应用 —— 见 §8.6.8（**含对 4a 前提的推翻与重做**）
  - 4a 重写：`lib/features/proxy/data/config_assembly.dart` 的 `applyEntitiesToOutbounds()`
    - 基准 = **应用写下的 `configs/<id>.json`**（`{"outbounds":[…]}`，也就是内核读的那份输入）
    - 规则只有三条：实体覆盖同名节点出站（含凭据）、基准里没有的实体追加、`staleTags` 里的移除
    - **不再重建组、不再设 default、不再识别"主 selector"** —— 内核每次都会丢弃输入里的组并自建（见 §8.6.8）
    - 校验 `tool/check_config_assembly.dart`：**24 项断言 ALL PASS**，核心是"只动节点、组一律原样透传"
  - 4b：`ProxyEntityRepository.assembleOutboundsForProfile(profileId)` → 写 `configs/<id>.entities.json` → `ConnectionRepository._start()` 优先用它启动
    - **失败回落**：组装失败 / 文件缺失 / 启动失败 → 一律回落到订阅基准文件（就是改动前的行为，不会更差）
    - **未用 `enable_raw_config`** —— 理由见 §8.6.8；那条路会丢掉内核从 HiddifyOptions 生成的 inbounds/dns/route/log
  - 4c（映射，本轮）：新增 `runtime_outbound_tags.dart`（内核 tag 常量的 Dart 镜像）+ `live_proxy_join.dart`（按**节点 tag** 贴实时值），修掉三处"拿订阅组名去对内核说话"的实质错误（切节点 / 测整组 / 仪表盘活跃出站）。见 §8.6.8.1
  - 4d（选中持久化，本轮）：新增 `selected_proxy_store.dart` + `selection_reconcile.dart`（纯函数决策，15 项断言），校准挂在 `ActiveProxyNotifier`（对应 NekoBox 的 `BaseService.reload()`）。见 §8.6.8.2
  - 4e（节点行写路径，本轮）：实体层写接口 + **列表以实体为准**（配置文本回落）+ 节点行 🗑（带撤销）/ ⤴ 改为实体优先。~~✎ 编辑仍缺~~ → **2026-10-05 已落地**：节点行 ✎（`proxy_tile.dart:145-162`，顺序照 `layout_profile.xml` 的 `edit → share → remove`）→ `proxies_overview_page.dart:443 showProtocolFormSheet` → `protocol_form_modal.dart:23`。见 §8.6.13
- ✅ 第 5 步（**已完成**，2026-10-05 更新）：协议表单 —— `const _specs`（`protocol_form.dart:874-890`）已实施 **15 份**、字段总数 166，覆盖 NekoBox 全部 12 份协议 xml（唯一未移植 `trojan_go`，内核无该类型）。逐份行号与字段数见 §5。✎ 编辑按钮随之落地（`protocol_form_modal.dart:23` `showProtocolFormSheet`）。**本步已不再是"下一步的主体工作"**

### 8.6.5 与 NekoBox 的差异清单（实体层）

| 维度 | NekoBox | 本项目（8.4 目标） |
|---|---|---|
| 节点来源 | 逐行解析分享链接 → Bean | 从内核 `Parse` 的配置文本派生（复用既有链路，免造链接解析器） |
| Bean 序列化 | Kryo 二进制列（每协议一列） | 单个 `payload` JSON 列（语义等价，栈一致） |
| 分组来源 | 订阅（1 个 group）+ 手动新建 | 同左（**不再**把配置内 proxy-group 当 Tab） |
| 配置生成 | `ConfigBuilder.kt` 从 DB 拼**整份**配置 | 只接管**出站表那一段**（`{"outbounds":[…]}`），其余（inbounds/dns/route/log/experimental）由内核从 HiddifyOptions 生成 —— 见 §8.6.8 |
| 规则 | `rules` 表 | 沿用 hiddify 既有规则模型（只补字段） |

### 8.6.7 NekoBox `ConfigBuilder.kt` 实测对照（"再次对照"的结果）

> 【编号说明，2026-10-05】本节编号从 8.6.5 直接跳到 8.6.7，`8.6.6` 空缺。**不回填**：8.6.8 起的编号已被 `HANDOVER.md:205`（§8.6.15）、`docs/design/connection-model.md:148`（§8.6.12）、`docs/design/proxy-model-root-fix.md:149`（§8.6.12）以及本文档内部十余处交叉引用；回填会连带作废这些引用与 `HANDOVER.md` 里的行号锚（如 `nekobox-parity.md:890-895`）。属历史编号遗留，非内容缺失。

按用户要求重读源码逐项核对（行号为 `fmt/ConfigBuilder.kt`）：

| 维度 | NekoBox（源码位置） | 我的 4a | 判定 |
|---|---|---|---|
| 构建粒度 | `buildConfig(proxy, forTest, forExport)`（:62）—— **以单个选中节点为入口** | 全量实体 + 覆盖 | 差异（下同） |
| **selector 组是否含全部节点** | **含**：`buildSelector = !forTest && group?.isSelector == true && !forExport`（:131）；为真时 `proxyDao.getByGroup(group.id)` 取**该组全部节点**逐个 `buildChain`，再 `outbounds.add(0, Selector{tag: TAG_PROXY, default: 选中节点, outbounds: 全部成员})`（:463-473） | 含全部实体 | ✅ **思路一致** |
| 非 selector 组 | 只编选中节点：`buildChain(0, proxy)`（:475） | 不分情况一律全量 | 差异 —— hiddify 内核一次只加载一份 profile，必须全量才能在运行期切换 |
| selector tag | 固定常量 `TAG_PROXY = "proxy"`（:44） | 沿用基准（订阅组名「节点选择」或 profile 名「冲上云霄」） | 差异 —— 我**不重命名**是为了保住 `route.final`、`dns.servers[].detour` 的引用（NekoBox 的配置**没有** `route.final`） |
| 成员 tag | 节点显示名（`tagOut = selectorName(bean.displayName())`，:297） | 配置里的 tag | 差异（hiddify 的 tag 通常等于显示名） |
| urltest / balancer | **没有**（自己测速：`TestInstance` → `buildConfig(profile, true)`，`bg/proto/TestInstance.kt:43-44`） | 保留内核 urltest | hiddify 特有 |
| direct / bypass 出站 | `arrayOf(TAG_DIRECT, TAG_BYPASS)` 追加（:611） | 沿用基准（`direct §hide§` 等） | ✅ 一致 |
| `route.final` | **不设置**（靠 rules 的 outbound 指定） | 保留基准的 final → 主 selector | hiddify 特有 |
| 原始配置透传 | `ConfigBean.type == 0` 直接返回 `bean.config`（:64-75） | — | 对应内核的 `enable_raw_config` |

**两条纠正（我先前说错/做错的地方）**：

1. **4a 提交信息里"NekoBox 从 DB 白手起家拼整份配置"不完整**：它对**selector 组**是把该组**全部节点**都编进配置、并加一个 selector（tag 固定为 `proxy`）—— 与 hiddify 的 selector 思路一致；只有非 selector 组才只编选中节点。已更正。
2. **删除规则改了**：原先实现按"看起来像节点"（非组/非内部/不带 `§hide§`）推断删除 —— 这属自我发挥，且有真风险：内核会加 `🔒 WARP` 这类出站（实测确认既不是组也不是内部类型、也不带 `§hide§`），会被误删。现在**删什么只由调用方给 `staleTags`**：事实归属上，"哪些 tag 属于实体层"由实体层说了算（`ProxyEntityRepository` 在整组替换前知道旧实体集合）。校验脚本已加"`🔒 WARP` 必须保留"与"不传 staleTags 就不删"两条用例。

**结论**：4a **不是** NekoBox 的做法，而是 **hiddify 语义下的"内核基准 + 出站层覆盖"**（内核一次只加载一份 profile、且配置含 `route.final` / dns detour 等 NekoBox 没有的结构）。取舍理由与差异已逐条记档，不再以"NekoBox 就这么做"表述。

### 8.6.8 实测推翻 4a 前提：**组由内核重建，应用只该管节点那一段**

本轮把"内核真正在跑的那份配置"读出来对照（`%APPDATA%\Hiddify\hiddify\data\current-config.json`），结果推翻了 4a 的前提。

**两份文件必须分清**（这是先前搞错的地方）：

| 文件 | 谁写 | 内容 |
|---|---|---|
| `configs/<id>.json` | 应用写、内核**读作输入** | **只有 `{"outbounds":[…]}`** —— 订阅自带的组（selector「冲上云霄」+ urltest「自动选择」）+ 节点 |
| `data/current-config.json` | 内核启动时写 | **真正在跑的**：`outbounds` 的组是 `select` / `balance` / `lowest`（固定常量），`route.final = "select"`，另有 `inbounds`（`mixed-in` / `dns-in`）、`dns`、`log`、`experimental` |

**内核 `v2/config/builder.go` 的 `setOutbounds`（:130-371）自己重建组**：

1. 丢弃输入里的**所有组**（selector/urltest/balancer，:154-164）、丢弃 `direct`/`bypass`/`block` 与预定义 tag（:142、:169），**只留下节点**（:178-183 顺带收集非 `§hide§` 的 tag）
2. 自建 `balance`（strategy = `opt.BalancerStrategy`，:295-310）与 `lowest`（`lowest-delay`，:278-293）
3. 自建 selector，tag = **常量** `OutboundSelectTag = "select"`，members = `[balance, lowest, …节点]`，default = `balance`（:311-341）
4. `setRoutingOptions` 再把 `route.final` 设成同一个常量

源码里甚至留着一段注释（:157-164）写明这件事：*"the app generates a config and then starts the core from that generated file, so the builder runs twice"*。

**因此 4a 那三条"硬规则"全部作废**（它们是从 `configs/<id>.tmp.json`＝**订阅原文**反推的，而那不是被启动的文件）：

| 4a 的说法 | 实测 |
|---|---|
| "主 selector 的 tag 可变（订阅组名 / profile 名），按第一个 selector 识别" | 运行期 selector tag 恒为 `select` |
| "`route.final` 与 dns detour 指向主 selector 的 tag，所以不能重命名" | 运行期 `route.final = "select"`，由内核设置 |
| "重建成员：selector = [其它组, 非节点, 节点]" | 内核自己重建为 `[balance, lowest, …节点]` |

⇒ **已删除** `config_assembly.dart` 里识别主 selector / 重建成员 / 设 default 的全部逻辑。应用负责的只有**节点出站那一段**，这恰好也是"节点可编辑"所需的最小权限。

**为什么不用 `enable_raw_config`**（先前 4b 的计划）：

- `StartRequest{config_content, enable_raw_config: true}` → `BuildConfig`（`buildconfighelper.go:28-44`）走 `ReadSingOptions`，**原样读取、跳过 builder**
- 于是 `setInbound` / `setDns` / `setRoutingOptions` / `setExperimental` / `setLog` **一次都不会执行** ⇒ 配置里没有 inbounds / dns / route / log，内核即使起得来也毫无意义（没有入站端口、没有 DNS、没有路由策略）
- 而应用也**拿不到"构建后的完整配置"来当基准**：`GenerateConfig` 那条 RPC 在 proto 里是**注释掉的**（`hcore_service.proto`：`//rpc GenerateConfig (GenerateConfigRequest) returns (GenerateConfigResponse);`）—— Go 侧有实现（`buildconfighelper.go:145`），但没挂在服务上，Dart 存根里也没有
- ⇒ 正确机制是**把出站表喂给内核、按路径启动**，其余部分仍由内核按 HiddifyOptions 构建。这也正是内核注释里描述的那条既有链路（"app generates a config and then starts the core from that generated file"）

**落地**：

- `ProfilePathResolver.entityFile(id)` → `configs/<id>.entities.json`
- `ProxyEntityRepository.assembleOutboundsForProfile(profileId)`：读盘取订阅基准 → 实体覆盖节点段；**只记日志、绝不抛出**
- `ConnectionRepository._start()`：优先用实体文件启动，组装修建失败 / 文件缺失 / 启动失败 → 回落订阅基准文件（即改动前行为）
- 回落之所以安全：内核组装或启动失败都会走 `errorWrapper → StopAndAlert → SetCoreStatus(STOPPED)`（`hcore/custom.go`），状态被复位，第二次 `start` 不会被判成 `ALREADY_STARTED`
- 订阅基准 `<id>.json` **保持不变**，随时可对照、可回退

#### 8.6.8.1 「映射」怎么解决（本轮，已实施）

上一节结尾的遗留是"组这一层 tag 对不上"。**NekoBox 的答案是：映射不靠 tag 相等，靠构建期建立的绑定。**

它的实现（源码位置）：

| NekoBox | 作用 |
|---|---|
| `ConfigBuilder.kt:44` `TAG_PROXY = "proxy"` | 运行期 selector 的 tag 是**常量** |
| `ConfigBuildResult.profileTagMap`（`Map<实体id, 配置tag>`） | **构建期**产出，随配置一起携带 |
| `BaseService.kt:185-190` `data.proxy!!.config.profileTagMap[ent?.id]` → `box.selectOutbound(tag)` | 运行期把选中实体翻译成 tag 再下发 |
| `DataStore.kt:36` `var selectedProxy by configurationStore.long(Key.PROFILE_ID)` | 选中项是**一条偏好**（实体 id） |
| `bg/proto/TrafficLooper.kt` `idMap`/`tagMap` 双索引，广播 `TrafficData(id = ent.id, …)` | 每节点实时值按实体 id 送 UI |
| `ConfigurationFragment` 的列表来自 `proxyDao.getByGroup` | 列表内容/顺序/显示名来自 DB |

**照此落到本项目**（`lib/features/proxy/data/runtime_outbound_tags.dart`）：

- 内核 tag 常量的 Dart 镜像：`select` / `lowest` / `balance` / `direct §hide§` / `direct-fragment §hide§` / `dns-out §hide§` / `🔒 WARP`（依据 `builder.go:37-43`）。**沿用内核自己的常量，不另造名字。**
- 由此修掉三处"拿订阅组名去对内核说话"的实质错误：

| 位置 | 原来 | 为什么错（源码依据） | 现在 |
|---|---|---|---|
| `proxies_overview_notifier.changeProxy` | 下发 `SelectOutbound(groupTag: 订阅组名)` | `commands.go` 的 `SelectOutbound` 是 `box.Outbound().Outbound(in.GroupTag)`，找不到就返回 `selector not found: <订阅组名>` —— 这就是"点了没反应" | 下发常量 `select` |
| `proxies_overview_notifier.urlTest` | `UrlTest(tag: 订阅组名)` | `commands.go` 的 `UrlTest` 在 `in.Tag == ""` 时才走 `UrlTestActive()`（内部用常量 `select`）；否则 `monitor.TestNow(组名)` —— 测一个不存在的出站 | `UrlTest(tag: "")` |
| `active_proxy_notifier.build` | `groups.first.items.first` | 内核第一组是 `select`，其第一个成员是 `balance`（balancer，不是节点）—— 仪表盘显示的是一行组名 | 取 `select` 组的 **`selected` 那个条目** |

- 取数分工照 NekoBox：`lib/features/proxy/data/live_proxy_join.dart` 的 `joinLiveIntoGroup()`
  - **列表内容 / 顺序 / tag** ← 骨架（订阅 / 实体清单）
  - **每节点延迟 / 测速时间 / 上下行 / 端口 / 主机 / IP / TLS** ← 内核，**按节点 tag** 逐个贴
  - **选中** ← 内核 `select` 组的 `selected`
  - **组 tag 不参与匹配**（这正是 Phase 1 "按组 tag 取那一组"的病根：组 tag 永远对不上，于是每次都落到 `liveGroups.first` = `select`，把内核那张并把 `balance`/`lowest` 都算进来的并集表当成了用户的组）
  - 校验：`tool/check_live_proxy_join.dart` **21 项断言 ALL PASS**（列表以骨架为准、组 tag 不参与、内核没给的节点保留骨架值、`isGroup` 的 live 条目不被当节点、退化路径等）

**与 Phase 1 的关系（如实说明）**：Phase 1 删掉了 `_mergeLive`，理由是"内核已经给全量组，不需要缝"。这个判断只在那两份数据**是同一个东西**时成立；而内核的组是重建出来的并集表，与订阅分组不是一回事。所以按 NekoBox 的分工把"按节点 tag 贴实时值"补了回来 —— 这不是回到旧的"双源缝合"，因为**匹配键换成了节点 tag（两侧天然一致），组 tag 完全不参与**。

#### 8.6.8.2 选中的持久化与校准（本轮，已实施）

上一节的"遗留"里还剩一条：**选中是"应用一次就清空"的临时值**。NekoBox 不是这样：

| NekoBox | 位置 | 作用 |
|---|---|---|
| `var selectedProxy by configurationStore.long(Key.PROFILE_ID)` | `DataStore.kt:36` | 选中是**持久偏好**（实体 id） |
| `DataStore.selectedProxy = proxyEntity.id` → `SagerNet.reloadService()` | `ConfigurationFragment.kt:1504-1517` | 用户点节点：**先落盘、再通知服务**，从不清空 |
| `box.selectOutbound(tag)`（同组时）/ start·stop（换组时） | `BaseService.kt:180-212` `reload()` + `canReloadSelector()` | 由**服务侧**应用，不在 UI 层 |
| `default_ = tagMap[proxy.id]` | `ConfigBuilder.kt:471` | 选中项在**构建期**写成 selector 的 `default` ⇒ 重启后自然还在 |
| `selector_OnProxySelected` → `cbSelectorUpdate(id)` → 回写 `DataStore.selectedProxy` | `NativeInterface.kt:84-105`、`MainActivity.kt:416-423` | 外部（yacd/webui）改选时**采纳并回写** |

**hiddify 的差异**：内核把 selector 的 `default` **写死成 `balance`**（`builder.go:311-341`），应用拿不到构建期那个口子（否则就要走 `enable_raw_config`，而那会丢掉内核生成的 inbounds/dns/route，见 §8.6.8）。⇒ 选中的"恢复"只能在**每次内核 ready 之后**补一次 `selectOutbound`。

**落地**：

- `lib/features/proxy/data/selected_proxy_store.dart`：持久存储「期望选中的节点」+「它属于哪份订阅」（对应上述两条 NekoBox 偏好；键名沿用历史，语义改为持久值）
- `lib/features/proxy/data/selection_reconcile.dart`：纯函数 `decideSelectionReconcile()`，判断顺序即优先级
  1. 没有期望值 → 不动（内核默认即当前事实）
  2. 期望值属于别的订阅 → 等待（内核一次只加载一份配置）
  3. 与内核当前选中一致 → 不动（**幂等**，所以每次事件都跑也不会重复下发）
  4. 内核节点集合里没有这个 tag → 等待（不硬下发，避免对不存在的 tag 反复重试）
  5. 内核停在它自己的默认值（`balance` / `lowest` = 没人选过）→ **下发期望值**
  6. 否则（内核选中是个具体节点）→ **采纳并回写**（对应上面的 `selector_OnProxySelected`）
- `ActiveProxyNotifier`：校准挂在这里 —— 它是 `keepAlive` 且被 `bootstrap.dart:104` eager listen，内核一起来就被驱动，**等价于 NekoBox 把这件事放在服务里做**
- `ProxiesOverviewNotifier.changeProxy`：改为"点节点 = 落盘持久期望值 + 立刻下发"；删掉了 `pending_proxy_group`（组恒为常量 `select`）与"应用后清空"的逻辑

**顺带修掉**：旧的"写 pending → 等内核事件 → 应用并清空"在跨订阅时会吃到旧内核的事件（旧内核还在推事件时组名碰巧存在就静默生效）。现在期望值不再被清空，归属校验一律以期望值为准，那个窗口期竞态自然消失。

**校验**：`tool/check_selection_reconcile.dart` **15 项断言 ALL PASS**（覆盖六个分叉与优先级顺序，含"期望值不在内核配置里时即使内核停在默认值也不许下发"）。

### 8.6.9 应用启动即崩溃：内核注册表不可重入（已修）

**现象**：新构建的 App 启动后进程直接消失。`%APPDATA%\Hiddify\hiddify\crash_reports\2026-09-15T05-37-06` 与 `...T05-37-20` 两份 dump（只有这两份，都在本次构建之后 ⇒ 是新引入的）。

**根因（在核心里，不在 Dart）**：

```
internal/runtime/maps.fatal                        ← Go 运行时「并发写 map」，进程直接 abort，不可恢复
 → sing-box/protocol/hiddify/dnstt.loadResolvers()      tools.go:22-28
 → dnstt.RegisterOutbound → include.OutboundRegistry()  registry.go:116
 → libbox.baseContextWithParent / baseContext
 → libbox.CheckConfigOptions
```

`hiddify-core/hiddify-sing-box/protocol/hiddify/dnstt/tools.go`：

```go
var (
	countryResolvers map[string][]string   // 包级
	resolverCountry  map[string]string     // 包级
)

func loadResolvers() {                     // ← 无任何同步
	json.Unmarshal(resolvers_bytes, &countryResolvers)
	resolverCountry = make(map[string]string)
	for country, resolvers := range countryResolvers {
		for _, resolver := range resolvers {
			resolverCountry[resolver] = country   // tools.go:26
		}
	}
}
```

而 `dnstt/outbound.go:26-29` 的 `RegisterOutbound` **每次注册都调它一遍**（不是 `sync.Once`）：

```go
func RegisterOutbound(registry *outbound.Registry) {
	outbound.Register[option.DnsttOptions](registry, C.TypeDNSTT, NewOutbound)
	loadResolvers()   // ← 每次重建 registry 都重写这两个包级 map
}
```

⇒ **任何两个并发地"重建注册表"的调用都会让进程 abort。** 这份数据是 `//go:embed` 的只读资源，重写纯属多余。

**证据（不是推断）**：两份 dump 里各有**恰好 2 个** goroutine 停在 `loadResolvers`，一个来自 `Parse`（`v2/config/parser.go:153` 的 `validateResult` → `CheckConfigOptions`），一个来自 `Start`（`v2/hcore/service.go:31` 的 `NewService`，以及 `start.go:131` 的 `libbox.FromContext`）。Dart 侧 `app.log` 的时间线也对上：`13:37:34.945 ConnectionNotifier: starting core in the background` 与 `13:37:35.039 offline proxies: ...` 重叠。

**会走到这条路的 RPC（全库枚举）**：`Parse` / `Start` / `StartService` / `Restart`（`v2/hcore/restart.go:40` 的 Restart 内部就是 StartService）。`Stop` / `SelectOutbound` / `UrlTest` / `ChangeHiddifySettings` / `OutboundsInfo` 不进这条路。

#### 已实施：应用侧串行化（本层能做的根因修复）

- `lib/core/utils/serial_async_lock.dart`：`SerialAsyncLock` —— 性质是**不重叠 / 保序（FIFO）/ 一次失败不破坏锁**
  （第三条最易漏：把失败的 Future 当链尾会让后续任务永久排队，表现为功能无声卡死，比崩溃更难查）
- `lib/hiddifycore/hiddify_core_service.dart`：`validateConfigByPath`（Parse）、`generateFullConfigByPath`（Parse）、
  `start`（Start）、`restart`（Restart）四处的 RPC 全部经 `_serializeRegistryAccess()` 串行化
- 为什么落在应用侧是正当的：内核这几条路径**不可重入**，而应用是唯一客户端；这与既有代码已经
  手工排序 `stop → 等 1.5s → start` 是同一个道理的延伸
- 校验：`tool/check_async_lock.dart` **8 项断言 ALL PASS**（含"连败三次后仍可用"与"同步抛出后仍继续"）

#### 上游修法（一行，未实施）

```go
var loadResolversOnce sync.Once

func loadResolvers() {
	loadResolversOnce.Do(func() { /* 原来的函数体 */ })
}
```

数据是 embed 的只读资源，`sync.Once` 既消除竞态也省掉每次注册的重复解析。
实施需要重建 `hiddify-core.dll`（本项目已有通路：`LOCAL_CORE=1 make windows-libs-local`，
见 `Makefile:805-841`，会用 Go + mingw 从源码构建）。**这是改 vendored 第三方源码 + 重产出 64MB 二进制，
属需要拍板的动作，故本轮只落应用侧修复并记录在此。**

> 注意 `EnableDNSRouting` 在**内核侧也被注释**（`hiddify_option.go` 的 `DNSOptions` 里是 `// EnableDNSRouting ...`），
> 所以「Enable DNS Routing」不是接线问题，**属 C 组**。我先前把它归入 A 组是错的。

### 8.6.10 「连接了但没流量」：系统代理链路上有两个断点（已修）

**现象**：点「连接」→ 界面显示已连接，但流量恒为 0、外网没走代理。

**Windows 侧实测**（python 读注册表）：`ProxyEnable = 0`（系统代理**未启用**），而 `ProxyServer = http://127.0.0.1:12334` 已经写好 —— 说明**这条链路曾经成功过**（值就是 sing-box 写的），只是要点亮的开关没人点亮。

#### 断点 1（内核侧，上游缺口）：命令服务器从不启动

- `v2/hcore/system_proxy.go:41-42` 的 `SetSystemProxyEnabled` 走 `libbox.NewStandaloneCommandClient()`，
  它去连 `<workingDir>/command.sock`（`command_client.go:125-126`）
- 那个 socket 由 `libbox.CommandServer.Start()` 创建（`command_server.go:119`），
  而**唯一那句调用在内核里被注释掉了**：`v2/hcore/service.go:48-50`
  ```go
  // if err := startCommandServer(instance); err != nil {
  // 	return errorWrapper(MessageType_START_COMMAND_SERVER, err)
  // }
  ```
  且 `startCommandServer` 这个函数在全库**已不存在**（只剩这行注释）
- ⇒ 该 RPC 必然失败：`dial unix …\hiddify\command.sock: connect: No connection could be made…`（实测 13:49:07 / 13:50:36）
- 注：`EnableOldCommandServer: true` 只在 FFI 导出 `start`/`restart`（`platform/desktop/custom.go:115`、`:137`）里传，
  Dart 侧走 gRPC、**不用这两个导出** ⇒ 这条口子对应用是无效的

#### 断点 2（应用侧，**这是"没流量"的直接原因**）：`rethrow` 让兜底永不执行

`ConnectionNotifier.setCapture`（`connection_notifier.dart:206-223`）本来有**正确**的兜底：

```
运行时 RPC 成功 → 结束
运行时 RPC 失败 → 重启内核，让 sing-box 自己设系统代理
                （common/listener/listener.go:109-117 → common/settings/proxy_windows.go:28 的 wininet.SetSystemProxy）
```

但 `HiddifyCoreService.setSystemProxyEnabled` 的 catch 里写的是 `rethrow`。
**`TaskEither` 体内抛出会变成"被拒绝的 Future"而不是 `Left`** ⇒ 调用方的 `applied.isRight()`
那一行**根本执行不到** ⇒ 兜底不触发，异常还逃到平台层（日志里的 `app: PlatformDispatcherError`）。

同类隐患共 4 处（都在 `hiddify_core_service.dart`）：`changeOptions` / `setSystemProxyEnabled` /
`selectOutbound` / `urlTest`。**要么返回 `Left`，要么整个 Either 契约对调用方失效。**

#### 修复

1. 这 4 处一律改为 `return left(...)` —— 恢复 Either 契约。**2026-10-05 复验已全部落地**：
   `hiddify_core_service.dart:378-383`（`setSystemProxyEnabled`，带整段说明注释）、`:495-498`（`selectOutbound`）、
   `:514-518`（`urlTest`）、`:172-179`（`changeHiddifySettings`，注释在 `:176`）。
   同文件里剩下的 4 处 `rethrow`（`:446` / `:467` / `:480` / `:546`）都在 **Stream 方法**里
   （`watchGroups` / `watchMainOutbounds` / `watchStats` / `watchLogs`），不走 `TaskEither` ⇒ 不受此契约影响
2. `setSystemProxyEnabled` 超时 10s → **3s**：既然在这份内核上注定失败，
   不该让用户每次点「连接」都干等 10 秒。将来内核若恢复命令服务器，这条路会自动重新可用
3. 修复后的链路：点「连接」→ 写 `captureEnabled = true` → 运行时 RPC 失败（3s）→
   **兜底重启内核** → 配置里 `set-system-proxy: true`（`config_option_repository.dart:506`，
   `mode == systemProxy && captureEnabled`）→ sing-box 的 mixed 入站安装系统代理 ⇒ 流量走起来

**校验**：`flutter analyze` 0 issue；五个校验脚本全 PASS；windows release 构建通过。

**未验证**：真机确认「连接后 `ProxyEnable = 1` 且流量开始计数」需要你跑一次（沙箱不能常驻 GUI）。

### 8.6.11 实体回填：让第 3/4 步真正跑起来（已实施）

**为什么需要**：真机 DB 实测（`%APPDATA%\Hiddify\hiddify\db.sqlite`）——
`proxy_groups` **0 行**、`proxy_entities` **0 行**。原因是实体落库挂在「订阅写入」这条咽喉上，
而两份订阅都是在实体表出现**之前**导入的。于是第 3/4 步的代码从未被走过：
`configs/` 下没有 `.entities.json`，组装每次都回落到订阅基准（回落本身是对的，但等于实体层是死的）。

**回填判据**：库里已有该订阅的分组就跳过 —— 纯函数 `missingEntityProfileIds()`
（`proxy_entity_import.dart`，含 8 项断言）。幂等 ⇒ 第二次运行只是一次 DB 读。
对应 NekoBox 的 `GroupManager`「有组就不重建」。

**触发点**：新增 `lib/features/proxy/entity/entity_backfill_notifier.dart`（`@Riverpod(keepAlive)`），
订阅清单一变就检查一遍；在 `bootstrap.dart` 与 `activeProxyNotifierProvider` 并排 eager listen，
位于内核 init **之后**；fire-and-forget，不挡启动。

**顺带把配置文本的来源改对了**（`ProxyEntityRepository._sourceConfigTextFor`）：
优先**直接读** `configs/<id>.json`，而不是调内核 `Parse`。三条理由：

1. 那个文件本身就是 `Parse` 的产物（导入/更新时 `validateConfig()` 让内核把解析结果写在这里），内容等价；
2. **不需要内核在跑** ⇒ 回填才能安全地放在启动路径上（`Parse` 走内核里那段不可重入的注册表，见 §8.6.9）；
3. 真机实测**幂等**（见下表）——没有编辑时，从 `.entities.json` 启动与从订阅基准启动完全等价。

**真机数据验证**（本轮：把第 1~4 步的纯函数跑在**真实配置**上，而非仿写 fixture）：

| 订阅 | 实体数 | 类型分布 | 组装幂等（实体覆盖回基准） |
|---|---|---|---|
| 一分机场 `0a34c1c6` | 36 | hysteria2×15, vless×21 | ✅ **逐字节相同** |
| 云霄 `e2d4f850` | 48 | anytls×41, hysteria2×5, shadowsocks×2 | ✅ **逐字节相同** |

与离线解析日志 `[一分机场] 2 groups (节点选择:37, 自动选择:36)` 吻合：
selector 成员 = `[自动选择] + 36 个节点` ⇒ 实体 36 个。

**验收（已自测通过，2026-09-15，见 §8.6.15）**：

- `db.sqlite`：`proxy_groups` **2 行**、`proxy_entities` **84 行**（云霄 48 + 一分机场 36）✅
- 启动激活订阅后 `configs/<activeId>.entities.json` **已生成** ✅
- `app.log`：`entity assembly: [e2d4f850…] ConfigAssemblyResult(replaced=48, added=0, removed=0)` ✅
- 第二次启动**不再回填**（幂等，日志无 `entity backfill`）✅

**与 NekoBox 的对应**：NekoBox 的 `GroupUpdater`/`GroupManager` 在订阅更新时维护分组+节点；
本项目除了那条路径，还需要对"表出现之前就已存在的数据"补一次 ——
这是新表对既有数据的**一次性迁移**，此后完全由导入/更新驱动。

### 8.6.12 分组模型对齐：**一份订阅 = 一个分组**（已实施，Tab 粒度定案）

**用户指出的问题**：代理页凭空有一栏「自动选择」。对照 NekoBox 核实 —— **它没有这个东西**。

**NekoBox 的三条证据**：

| 证据 | 内容 |
|---|---|
| `Constants.kt` | `object GroupType { BASIC = 0; SUBSCRIPTION = 1 }` —— 组类型**只有这两种**，没有"自动选择/urltest" |
| `group/RawUpdater.kt:768-787` | 订阅是 sing-box 配置（`json.has("outbounds")`）时，把 `dns` / `block` / `direct` / `selector` / `urltest` **逐个过滤掉**，只留真节点 ⇒ 一份订阅产出**一个** group |
| `database/ProxyGroup.kt` `displayName()` | 组名就是**订阅名**（`name` 为空才用默认名） |

全仓搜 `urltest` 只有两种用途：`RawUpdater` 的**过滤名单**，以及 `SingBoxOptions` / `UrlTestPreference`
（用户手动建 url-test **出站**时用）。**没有任何地方把 urltest 当成"分组"。**

**改动**：

- `offline_proxy_parser.dart`：`parseOfflineProxyGroups()`（把配置里的 selector/urltest/balancer 当分组）
  → **`parseSubscriptionGroup(configJson, groupName:)`**：返回**唯一**一个组，`tag` = 订阅名，
  `items` = 过滤后的全部节点（顺序照配置）。**选中不由配置决定** —— 配置里的 `default` 不是选中，
  选中是 `SelectedProxyStore` 的持久偏好。
- `offline_proxies.dart`：`ProfileProxies{profile, groups, fallback}` → `{profile, group}`（`fallback` 概念消失）。
- 代理页：Tab = 订阅，标签就是订阅名（不再拼组名），`_tabLabel` 删除。
- `proxies_overview_notifier`：认订阅 id 即可（不再按组 tag 找组）；`urlTest(groupTag)` → **`urlTest()`**
  （NekoBox 没有"按组测速"，测速是工具栏的 URL Test）；新增 `_withExpectedSelection()`。
- 清理：`tool/offline_parse_check.dart` 与 `tool/check_offline_proxy_parser.dart` 是同一件事的两份脚本，
  合并成后者；`hiddenTag` 改为委托 `isHiddenTag`（同一条 `§hide§` 规则原来写了两遍）。

**真机数据验证**（新解析器跑在真实 `configs/<id>.json` 上）：

| 订阅 | 节点数 | 类型分布 |
|---|---|---|
| 一分机场 `0a34c1c6` | 36 | hysteria2×15, vless×21 |
| 云霄 `e2d4f850` | 48 | anytls×41, hysteria2×5, shadowsocks×2 |

与实体派生（§8.6.11）**完全一致**，且两个配置内分组（`节点选择` / `自动选择`）都已被正确过滤掉。

**一个必须说明的取舍**：`_withExpectedSelection()` 会把**持久化的期望选中**贴到列表上。
理由：内核那个 selector 的 `default` 被写死成 `balance`（`builder.go:311-341`），在它校准过来之前，
内核报的选中项（`balance`）**不是列表里的任何节点** —— 直接照抄就会整列没有高亮，看起来像"选中的节点丢了"。
规则是**只在"内核没给出可用选中"时兜底**：期望值属于别的订阅 ⇒ 不贴；不在本清单里 ⇒ 不贴。

**验收（已自测通过，2026-09-15，见 §8.6.15）**：

- 代理页 Tab 只有**订阅名**（「云霄」「一分机场」），**不再出现「自动选择」** ✅（截图为证）
- 每个订阅列出的节点数 = 它的全部节点：云霄 48 / 一分机场 36 ✅
- 每个订阅的列表都标注来源：`(from entities)` ✅

### 8.6.13 节点行三件套 + 「列表以实体为准」（已实施）

**规格（NekoBox，本轮读源码取）**：

| 证据 | 内容 |
|---|---|
| `res/layout/layout_profile.xml` | 行 1 右侧依次 `@id/edit`（✎）→ `@id/share`（⤴）→ `@id/remove`（🗑） |
| `ui/ConfigurationFragment.kt:1594-1600` | ✎ → `proxyEntity.settingIntent(ctx, isSubscription)` → 该协议的 `*SettingsActivity` |
| `:1602-1608` | 🗑 → `adapter.remove(index)` + `undoManager.remove(index to proxyEntity)` |
| `:1612-1613` | `editButton.isGone = select` / `removeButton.isGone = select` —— **只在"选择器模式"下隐藏**（Chain 端点选择等）；正常浏览时两个按钮都显示 |
| `:1624-1625` | `isEnabled = !started`，`started = selected && serviceState.started && currentProfile == entity.id` ⇒ **正在使用的那个节点不允许编辑/删除** |
| `widget/UndoSnackbarManager.kt` | 删除后弹 Snackbar「已删除 %d 个配置」+ **Undo**；点 Undo → 恢复；Snackbar 关闭（非 ACTION）→ `commit` 落库；新操作到来 → `flush()` |

**⚠️ 口径纠正**：`proxy_tile.dart` 原先写着"🗑 与 NekoBox 一致默认隐藏（订阅节点的增删走订阅更新）"——
**这条是错的**。XML 里 `@id/remove` 确实默认 `visibility=gone`，但 `bind()` 每次都会按 `select` 覆写
（正常模式 `select == false` ⇒ 显示）。所以 NekoBox 的节点行**默认就有删除按钮**，订阅节点也能删。

**本轮落地**：

- 实体层写接口（`ProxyEntityRepository`）：`groupForProfile()`（= `proxyDao.getByGroup`）、
  `removeNode()`（= `removeButton`）、`restoreNode()`（= undo）、`payloadOfNode()`（分享数据源）。
- **列表以实体为准**：`offlineAllProfilesProxyGroupsProvider` 改为先读实体表
  （`buildGroupFromEntityNodes`，组名 = 订阅名、顺序照 `userOrder`）；没有实体分组时回落到
  "解析配置文本"这条老路 ⇒ 行为与引入实体层前一致，最坏情况只是看不见新能力，不会让页面空掉。
  **节点级删除/编辑因此立刻可见**，不必等下一轮订阅解析。
- 节点行：按 NekoBox 顺序补上 🗑 与 ✎（**2026-10-05：✎ 已落地** —— `proxy_tile.dart:145-162`
  行内动作顺序 `edit → share → remove`，`:160` `FluentIcons.edit_24_regular`/`t.common.edit`，
  回调 `onEdit`（`:68-70`）由 `proxies_overview_page.dart:443 showProtocolFormSheet` 承接）；
  `NkCardAction.onTap` 支持 `null` = 禁用（置灰不响应），照 `isEnabled = !started`。
- 删除 + 撤销：Material `SnackBar` + `SnackBarAction(撤销)`。
  差异说明：NekoBox 是"延迟落库 + 撤销"，这里是"立即落库 + 撤销时重新插入" ——
  用户可见行为一致，且少了"离开页面时漏提交"的风险。
- 分享改为**实体优先**、配置回落（列表以实体为准后，从配置里找 tag 会漏掉新节点或给出旧内容）。

**校验**：`tool/check_offline_proxy_parser.dart` 扩到 **36 项断言 ALL PASS**，新增 11 项覆盖
"实体来源 → 分组"（组名 = 订阅名、顺序照 `userOrder`、显示名用库里那一列、不预置选中、空清单→空组）
以及**两个来源必须产出同一形状**（否则"回落"会换掉列表长相）。六个校验脚本全 PASS；
`flutter analyze` 0 issue；release 构建通过。

**验收（已自测通过，2026-09-15，见 §8.6.14）**：

- 节点行右侧出现 🗑（悬停显示 tooltip「删除」）；正是"正在使用"的那个节点上是灰的
- 点 🗑 → 列表**立刻**少一项，底部弹出「已删除节点」+「撤销」
- 点「撤销」→ 节点回来；连做两轮，数据库计数 **47 → 46 → 47 → 46** 逐步吻合
- 无新崩溃报告；`app.log` 里 `offline proxies: [云霄] 48 nodes (from entities)`

### 8.6.14 节点卡地址行：取自**实体**而不是运行期（已实施 + 已自测）

**自测发现的缺陷**：节点卡第 2 行显示成 `:0`（主机/端口都是空）。
查证后确认**不是**本次改动引入的，而是从来如此 —— 因为那两个字段的来源选错了：

| 来源 | 有没有 host/port |
|---|---|
| 内核 `OutboundInfo` | ❌ 不给（实测：Clash API `/proxies` 的节点项只有 `type` / `name` / `udp` / `history`） |
| 订阅配置 / 实体 payload | ✅ `server` + `server_port`（真机 132 个节点**全部**都有） |

**NekoBox 的规格**：节点卡那一行是 `proxyEntity.displayAddress()`
→ `AbstractBean.displayAddress()` = `wrapIPV6Host(serverAddress) + ":" + serverPort`
（`fmt/AbstractBean.java`）——**取自 Bean 字段**，运行期只负责延迟/流量/选中；IPv6 用
`ktx/Nets.kt` 的 `wrapIPV6Host()` 加方括号。

**改法**：两个来源都补上地址（口径一致，回落不会换掉列表长相）——
新增纯函数 `serverAddressOfPayload()`（从 payload 读 `server`/`server_port`）与
`displayAddress()`（IPv6 加方括号）；`parseSubscriptionGroup` 也从配置里同样读取。

**自测结果**：地址行显示为 `b.ka.ws.3333399.xyz:443`、`en.hk.ha.444407.xyz:443` …

**已知不含**：`server_ports`（端口**区间**写法，hysteria2 range 形态）——
本项目的真实订阅里没有这种节点，暂不处理。

### 8.6.15 自测手段：截图 → 像素定位 → 点击 → 数据库校验

**为什么重要**：此前每轮都以"沙箱不能常驻 GUI"为由把真机验证推给用户 ——
但这是个 Windows 桌面程序，**完全可以自己跑**。本轮起改用下面这条链路，
它当场抓出了上面那个 `:0` 缺陷（以及一处我自己写错的 UI 规格判断）：

1. **启动**：`build\windows\x64\runner\Release\Hiddify.exe`（前台/后台都行）。
   注意用 `DETACHED_PROCESS` 启动会静默失败，直接 `Popen` / bash 后台跑即可。
2. **读日志**：`%APPDATA%\Hiddify\hiddify\app.log` —— 启动、回填、组装、列表来源
   （`(from entities)` / `(from config)`）都在里面。崩溃另有 `crash_reports\`。
3. **读数据库**：`db.sqlite` 的 `profile_entries` / `proxy_groups` / `proxy_entities`
   行数变化是**最硬的证据**（删除/撤销各一步都能对上）。
4. **看界面**：`.workbuddy/shot.py` 用 GDI `PrintWindow(hwnd, hdc, 2)`
   （**必须传 2**，否则 Flutter 的 GPU 合成面是全黑）截窗口存 PNG，再直接看图。
5. **点界面**：`.workbuddy/click.py` 先把窗口置前并核对 `GetForegroundWindow()`，
   再按截图像素坐标点击 —— 若目标窗口不是前台，**绝不能点**（会点到别的程序上）。
6. **量坐标**：`.workbuddy/px.py` 解自己写的 PNG（filter=0/RGB）找图标的深色像素区间。
   踩过的坑：聊天里显示的图被缩放成 1092 宽（实际 1230），按显示坐标去点会偏 ~11%。

**收尾纪律**：自测会改真实数据（本轮删了节点），结束后必须**按订阅原文把数据补回**
并在日志/DB 上复核（本轮：48 → 46 → … → 补齐回 48）。

### 8.6.16 批次 1 第一刀：4 份协议表单 + 节点行 ✎（已实施 + 已自测）

**做了什么**（字段映射见本文件 §5）：
1. `lib/features/proxy/data/protocol_form.dart`（纯 Dart）—— 4 份规格 + 双向变换
   （`readProtocolFormValues` / `applyProtocolForm`），**未知键一律原样保留**；
   NekoBox 的两条语义照抄：空值删键（`blankAsNull()`）、布尔 false 不写键。
2. `lib/features/proxy/widget/protocol_form_modal.dart` —— 规格驱动表单（分节照 `PreferenceCategory`）。
3. `proxy_tile.dart` 补齐 `edit → share → remove`；`proxies_overview_page.dart` 接线；
   `ProxyEntityRepository.updateNodePayload` + `ProxiesOverviewNotifier.updateNodePayload`。

**为什么容器要单独建模**（本轮的设计要点，不是细节）：
NekoBox 的构建函数有**三段"整体消失"**的语义 —— `transport` 在 `type=tcp` 时为 null、
`tls` 在 `security != tls` 时为 null、`utls`/`reality`/`obfs` 在各自密码为空时不写对象。
用"逐字段置空"表达会留下 `{enabled:true}` 之类的空壳（内核可能拒绝），所以引入
`ProtocolContainerRule`：**有控制器**（如 `transport` 由 `type` 决定）与**无控制器**
（如 `tls.utls`：其下受管字段全空则摘除）两种。这是把 NekoBox 的控制流搬成了数据。

**最重要的不变量（`tool/check_protocol_form.dart` 第 1 条）**：**往返幂等** ——
读出来原样写回，payload 逐字节等价。它等价于"表单没管理的键全部原样保留"，
真机 4 种协议的实测 payload 全部逐条断言（含 `tls.reality` / `tls.utls.enabled` /
`stream_receive_window`）。**69 项断言 ALL PASS。**

**真机自测（`.workbuddy/` 三件套 + `win.py`/`kbd.py`）**：
改一个 anytls 节点的 `server_port` 443→8443 →「保存」⇒
- `app.log`: `node payload updated: [🇭🇰 Hong Kong AWS B|4x]` →
  `ConnectionNotifier: reloading core with the new config (not capturing - capture state untouched)` →
  `entity assembly: replaced=48, added=0, removed=0`
- DB payload 的 `server_port` = 8443，**其余键逐字未变**（`tls.utls.enabled`、`tls.insecure`、password）
- `configs/<id>.entities.json` 里该出站也是 8443，总条数仍 51（没有多删少删）
- 列表地址行即时变为 `b.ka.ws.3333399.xyz:8443`，弹出「节点已更新」
- **无新崩溃报告**；测完已把 payload 与组装文件复原到 443 并复核
- 见过的既有噪声（非本次引入）：`SystemTrayNotifier: error getting active proxy`，启动阶段就有

**自测工具补充（写进 `windows-gui-self-test` skill）**：
- `Ctrl+A` 在 Flutter `TextField` 上**不可靠**（实测变成"追加"）⇒ 用**退格清空**再输入；
- 应用可能只留一个可见窗口（本次直接可见），但枚举仍应**按 pid 而不是 `IsWindowVisible`**。

### 8.2 ❌ 内核未开放（需上游或降级，属 C 组）

> **2026-10-05 逐条复验**：本表原先只有「全库 0 命中」式结论，复核后按「内核有没有、app 有没有」拆开重写。
> 复验命令一律 `git grep -n -E PATTERN -- lib`（**注意 `git grep` 没有 `--include`**，见 §4 的教训）。

| 项 | 核实结果（2026-10-05） |
|---|---|
| `trafficSniffing`（流量嗅探） | ⛔ **内核有动作、无开关**：`v2/config/builder.go:517-518` 的 `SniffEnabled` / `SniffOverrideDestination` **在 `InboundOptions` 注释块内被注释**（mixed inbound 段 `:505-521`）；**但** `:628` `Action: C.RuleActionTypeSniff,` **是活的**（内核无条件追加一条 sniff 路由规则，紧接 `:634` `Action: C.RuleActionTypeHijackDNS`）。`HiddifyOptions` 无该字段、`lib/` 全库无 `sniff` 命中 ⇒ 用户级开关做不了 |
| `appendHttpProxy` | ❌ 全库 0 命中（`lib` 与 `hiddify-core` 皆无） |
| `domain_strategy_for_server` | ❌ `DNSOptions` 无该字段；`lib` 无 `serverDomainStrategy`/`domain_strategy_for_server` 命中 |
| `enableDnsRouting`（DNS 路由） | ⛔ **内核卡住（2026-10-05 翻案，先前误判为"仅需接线"）**：proto/pb 字段确实在册（`hiddify_options.proto:65` `bool enable_dns_routing = 7;`、`hiddify_options.pb.go:339` + `:416-418` `GetEnableDnsRouting()`、`hiddify_options.go:19` 默认 `false`），**但没有任何消费者** —— `v2/config/builder.go:973` `// if opt.EnableDNSRouting {` 整块被注释（该函数是 `setRoutingOptions(options, hopt)` `:574`，局部变量名是 `hopt`；紧跟其后的 `:974 if hopt.EnableFakeDNS {` 是**独立条件**，别误读为 dns-routing 的分支），`v2/config/hiddify_option.go:46` `// EnableDNSRouting bool \`json:"enable-dns-routing,omitempty"\`` 同样被注释。Dart 侧 `config_option_repository.dart:205` / `:404` / `:529` 三处也全注释（`singbox_config_option.dart:52`）⇒ **属 C 组，不是接线的活** |
| `networkChangeResetConnections` | 🟡 **能力等价、只是没有开关**：hiddify **行为默认开启** —— `hiddify-sing-box/route/network.go:481 notifyInterfaceUpdate` → `:519 r.ResetNetwork()`（`if !r.started { return }` 守卫）。链路：`PlatformInterfaceWrapper.kt:78-79 startDefaultInterfaceMonitor` → `bg/DefaultNetworkMonitor.kt:15`（`:20-24` 注册、`:54-72` `checkDefaultInterfaceUpdate` 调 `listener.updateDefaultInterface(...)`，重试 10 次 × `sleep(100)`）→ `experimental/libbox/monitor.go:57 UpdateDefaultInterface` → `:69 updateDefaultInterface`（`:95-97` 接口 Name+Index 都没变则**直接 return**，变了才回调）→ `route/network.go:125/:130` `RegisterCallback(nm.notifyInterfaceUpdate)`；启停 `bg/BoxService.kt:162` / `:289`。NekoBox 侧是显式开关（`DataStore.kt:92` 默认 `true`）→ `BaseService.kt:287` `Libcore.resetAllConnections(true)`。⇒ 缺的是**关掉的开关**，不是重置本身 |
| `wakeResetConnections`（唤醒重置） | ❌ **豁免项（判定不移植）**：NekoBox `bg/BaseService.kt:57-62` 在 `PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED` 分支里退出 doze 时 `Libcore.resetAllConnections(true)`。hiddify **也监听同一广播**（`bg/BoxService.kt:127-131`，注册在 `:328-333`），但 `serviceUpdateIdleMode()`（`:253-261`）只调 `Mobile.wake()`、**不做重置**（对照 NekoBox `:60-62`；我方 `// boxService?.pause()` / `//Mobile.pause()` 是注释）⇒ 差异 = 缺 doze 退出后的重置。`hiddify-sing-box/experimental/clashapi/connections.go:105` 的 `network.ResetNetwork()` 在 `DELETE /connections` 里，属另一条路径 |
| ~~清空测速结果 / 清空流量统计~~ | ⚠️ **此判定 2026-10-05 已作废**：内核确实无 clear 类 RPC（`hcore_service.proto` 只有 Start/Stop/Restart/SelectOutbound/UrlTest/UrlTestActive/Parse/…），但 hiddify 的这两个清空动作**清的是实体列**而非内核状态，因此不需要 RPC —— 已实现：`proxy_entity_repository.dart:539` `Future<int> clearTestResults({String? profileId, int? groupId})`（清 ping/status 列）、`:563` `Future<int> clearTrafficStats({String? profileId, int? groupId})`（清 tx/rx 列，照 NekoBox 只碰非零行、零值行不进 update）；notifier 层 `proxies_overview_notifier.dart:652` / `:671`；菜单入口 `proxies_menu_button.dart:58`（清空流量统计）/`:62`（清空测速结果）。**不是缺口** |

**附带查清的硬边界（判「能不能做」时直接引用）**：内核 gRPC 面（`v2/hcore/hcore_service.proto`）全部 rpc 为
`Start` / `CoreInfoListener` / `OutboundsInfo` / `MainOutboundsInfo` / `GetSystemInfo` / `GetSystemInfoStream` /
`Setup` / `Parse` / `ChangeHiddifySettings` / `StartService` / `Stop` / `Restart` / `SelectOutbound` /
`UrlTest` / `UrlTestActive` / `GenerateWarpConfig` / `GetSystemProxyStatus` / `SetSystemProxyEnabled` /
`LogListener` / `Close`。其中 **`Close` 不是「关闭连接」** —— `v2/hcore/pause.go:11` 只做 `CloseGrpcServer(mode)`，
`CloseRequest` 唯一字段是 `Mode SetupMode`。真正能重置全部连接的是 **Clash API**（`hiddify-sing-box/experimental/clashapi/connections.go:23-27`
挂 `DELETE /connections` → `closeAllConnections`：`snapshot := trafficManager.Snapshot(); for _, c := range snapshot.Connections { c.Close() }; network.ResetNetwork()`，
`:105`；挂载点 `clashapi/server.go:129`）。**Dart 侧完全没有消费 clash API 的客户端** —— `lib` 内 `clash` 只有
`app_info_entity.dart:21-25`（User-Agent 说明）、`connection_repository.dart:59-78`（端口选择，仅 Windows 且 `enableClashApi` 时）、
`config_option_repository.dart:180-181`/`:400`（`clash-api-port` 偏好）；`ConnectionStatsCard` 走的是内核 gRPC，与 clash API 无关。

### 8.3 🟡 纯 app 侧（不需内核，但需 Android 平台管线）

`speedInterval`（通知速率间隔）、`showDirectSpeed`、`showGroupInNotification`、
`meteredNetwork`、`acquireWakeLock`、`appTLSVersion`（订阅下载的 TLS 下限，在 `DioHttpClient`）、
快捷方式三动作（QuickToggle/Enable/Disable，逐节点 pin 亦缺）。

> **2026-10-05 复核后从此组移出（已实现，不再是缺口）**：
> `alwaysShowAddress`（`settings_page.dart:183-189`）、`allowInsecureOnRequest`（`:411-419`，`tool/check_insecure_request.dart` 10 项校验）、
> 磁贴 `TileService`（原生 Kotlin 全实现，`android/app/src/main/kotlin/com/hiddify/hiddify/bg/TileService.kt` + manifest `:109-121`）、
> 导出用 FileProvider（`UriUtils.tryShareOrLaunchFile`）、日志清空/分享（`logs_page.dart:31-51` / `:79-85`）。
> `BootReceiver` 开机自启：**判为不移植**（hiddify 走 always-on + 启动时 `_safeInit("auto start service")`，形态不同且桌面端更完整）。

### 8.4 ⛔ 需模型层（B 组，体量最大）

节点实体、分组实体、路由实体编辑、Assets 管理 —— 见 §5 / §6 / §7。

**完成度（2026-10-05 复核）**：四块里已完成三块半 ——
① 实体层（节点实体 + 订阅分组 + 导入管线 + 回填 + 组装 + 列表 + 删除 + 编辑）✅；
② **手动分组 ✅ 已做**（`proxy_entity_repository.dart:399` `createGroup`，入口 `groups_page.dart:174-222`；另有 `renameGroup:454` / `moveGroups:436` / `removeGroup:469` / `clearGroupNodes:492` / `ensureUngroupedGroup:362`）；
③ **协议表单 ✅ 15 份已实施**（§5，唯一未移植 `trojan_go`，内核无该类型）；
④ Assets（geo 资源管理）❌ **仍未做**，路由编辑本身 ✅（`rule_page.dart`）。
**结论：B 组只剩 Assets 管理一项**（原「150 个协议字段表单」已随 §5 完成而消失）。

---

## 9. 既有约定（不移植）

- `nav_tuiguang`（推广位）
- Material You 主题（已由 NekoBox 五色板取代）

> **2026-10-05 更正**：`nav_faq`（Document）**已从本清单移出** —— 它实际已实现（抽屉项 + 外开链接，
> 见 §1 第 9 行）。此处原先把它与推广位并列写"不移植"，与代码不符。

---

## 10. 使用方式

1. 动手前先看 **`docs/design/parity-sequence-log.md`**（1:1 序列与批次落地结果），
   本文件只提供"规格与现状"，不提供顺序
2. 每条实现完，把状态改为 ✅ 并在本文件记录实现位置（commit 号）
3. 涉及 UI 的，规格以 NekoBox 的 layout/menu/xml 文件为准（不自行发明）
4. **动手前必须核实内核支持**（本轮已发现 `enable-dns-routing` 这类"看起来能接线、实际内核也注释了"的坑）

