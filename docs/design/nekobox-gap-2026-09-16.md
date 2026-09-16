# NekoBox 对照差距清单（2026-09-16 重新对照，不依赖旧审计文档）

> 对照方法：全部从 `S:\test\NekoBoxForAndroid` 源码重读规格，hiddify 侧读当前工作区实现，
> 每条注明两侧依据（file:line）。旧 parity/audit 文档的结论**未引用**。

## 一、抽屉 / 导航结构

NekoBox `res/menu/main_drawer_menu.xml` 三组九项：
configuration / group / route / settings ‖ logcat / traffic / tools ‖ tuiguang / faq / about。

hiddify `lib/app/shell/nav_items.dart:52-138`：home(profiles 隐藏) / **groups** / subscriptions / route / settings ‖ logs / traffic / tools ‖ about。

| NekoBox | hiddify | 结论 |
|---|---|---|
| configuration | home | 已有 |
| group | groups | 已有（本轮批次 3 新增） |
| route | route | 已有 |
| settings | settings | 已有 |
| logcat | logs | 已有 |
| traffic | traffic | 已有 |
| tools | tools | 已项 |
| tuiguang(推广) | — | 无，且**不应复刻**（推广位） |
| faq | — | **缺**：帮助/FAQ 入口 |
| about | about | 已有 |

hiddify 额外多了 subscriptions 独立页（NekoBox 里订阅是 group 卡片动作，无独立页）。
结构上 hiddify 多一栏、少 FAQ。

## 二、代理页（ConfigurationFragment 对照）

NekoBox `ui/ConfigurationFragment.kt`（1743 行）toolbar ＋菜单 8 项
（`res/menu/add_profile_menu.xml:80-...`）：更新订阅 / 清流量统计 / 去重 / tcp ping / url test / 清结果 / 删不可用 / 排序(origin/name/delay)。

hiddify `proxies_overview_page.dart` ⋮ 菜单仅 **3 项**（urltest / sort / route）。

| ⋮ 菜单项 | 状态 |
|---|---|
| url test | ✅ 已有 |
| 排序（origin/name/delay） | ✅ 已有 sort |
| 路由设置入口 | hiddify 特有（NekoBox 放抽屉） |
| 更新订阅 | ❌ 缺（NekoBox `menu_update_subscriptions`） |
| 清流量统计 | ❌ 缺 |
| 嬪去重（`Protocols.Deduplication`） | ❌ 缺 |
| tcp ping | ❌ 缺（NekoBox `bg.proto.TcpPing`） |
| 清测试结果 | ❌ urltest 结果可被 sort 覆盖，但没有独立"清结果"动作 |
| 删不可用节点 | ❌ 缺 |
| 17 种手动新建 | ⚠️ 部分：hiddify `kManualCreatableProtocols`（protocol_form.dart:323）仅 4 种（ss/vless/hysteria2/anytls），NekoBox 有 17 种（+http/trojan/trojan-go/mieru/naive/hysteria/tuic/shadowtls/ssh/wireguard/custom config/chain） |
| 搜索 | ✅ 已有 |
| 扫码/剪贴板/文件导入 | hiddify 走订阅页，无节点级导入 |
| 使用中节点禁编辑/删除 | ✅ 已有（`editEnabled: !(isSelected && nodeInUse)`） |
| 删除撤销 Snackbar | ✅ 已有（removeNode + restoreNode） |
| 分组 Tab `size < 2` 隐藏 | ✅ 已有（proxyGroupTabsProvider） |
| 连接测试并发/进度/可取消 | ⚠️ 有 urltest 但无进度对话框（NekoBox TestDialog nowTesting + N/M 进度 + 最小化为通知 + 取消落库） |
| 列表/网格切换 | hiddify 已有 |

## 三、分组页（GroupFragment 对照）

NekoBox `ui/GroupFragment.kt` 全套：
- toolbar：新建分组 / 更新所有订阅
- 卡片：✎ 编辑（进 GroupSettingsActivity **11 项表单**） / ⟳ 更新（仅订阅组） / ⋮ 动作菜单（分享订阅 universal link / 导出节点 std links 到剪贴板或文件 / 清空分组）
- 拖拽排序（ItemTouchHelper + userOrder，ungrouped 与更新中禁拖）
- 滑动删除 + undo（UndoSnackbarManager）
- 订阅流量三态展示（SIP008 / raw userinfo / 无）
- 状态文案：BASIC「N 个配置」；订阅「N 个配置 · M-D 前更新」
- 更新中进度条

hiddify `lib/features/proxy/overview/groups_page.dart`（197 行）现状：
＋ 创建 / ✎ 重命名 / 🗑 删除 / 点卡片跳组 Tab。

| 功能 | 状态 |
|---|---|
| 新建分组 | ✅ 已有 |
| 编辑/重命名 | ⚠️ 只能改名。NekoBox 是 11 项表单（groupName/groupType/groupOrder/groupIsSelector/groupFrontProxy/groupLandingProxy/subscriptionLink/forceResolve/deduplication/updateWhenConnectedOnly/userAgent/autoUpdate/autoUpdateDelay——实际 13 键） |
| 删除分组 | ✅ 已有（NekoBox 是滑动删+undo，hiddify 是确认框，交互不同但功能在） |
| 更新所有订阅（toolbar） | ❌ 缺（工具页 Backup Tab 里有"更新订阅"行，但分组页没有） |
| ⟳ 更新单组（仅订阅组） | ❌ 缺 |
| ⋮ 分享订阅链接 | ❌ 缺 |
| ⋮ 导出节点（剪贴板/文件） | ❌ 缺 |
| ⋮ 清空分组 | ❌ 缺 |
| 拖拽排序 | ❌ 缺（userOrder 交换算法 + clearView 批量落库） |
| 订阅流量展示 | ❌ 缺（SIP008 bytesUsed/bytesRemaining 或 userinfo 正则） |
| 状态文案「N 个配置 · M-D」 | ⚠️ 有节点数，缺最后更新时间 |
| 更新中进度条 | ❌ 缺 |

## 四、设置页（global_preferences.xml 五类对照）

hiddify `settings_page.dart` 已复刻五类内联结构（基础/路由/DNS/入站/其他）。

| global_preferences.xml 键 | hiddify 现状 |
|---|---|
| isAutoConnect | ✅ autoStart（桌面） |
| appTheme/nightTheme | ✅ palette + themeMode |
| serviceMode | ✅ |
| tunImplementation | ✅ |
| mtu | ✅（本轮新增） |
| speedInterval | ❌ 缺 |
| profileTrafficStatistics | ❌ 缺 |
| showDirectSpeed | ❌ 缺 |
| showGroupInNotification | ❌ 缺 |
| alwaysShowAddress | ❌ 缢缺 |
| metered / acquireWakeLock | ❌ 缺 |
| logLevel | ✅ |
| globalCustomConfig | ⚠️ 有 globalCustomConfig 对应能力？（待核） |
| proxyApps | ✅ perAppProxy |
| bypassLan / bypassLanInCore | ⚠️ hiddify 只有内核侧 bypassLan 一个（代码注释已记档两者差异） |
| trafficSniffing | ✅ resolveDestination 近似（NekoBox 是 sniffing 独立键） |
| resolveDestination | ✅ |
| ipv6Mode | ✅ |
| rulesProvider | ❌ 缺 |
| remoteDns + domain_strategy_for_remote | ✅ |
| directDns + domain_strategy_for_direct | ✅ |
| domain_strategy_for_server | ❌ 缺 |
| enableDnsRouting | ❌ 缺 |
| enableFakeDns | ✅ |
| mixedPort | ✅ |
| appendHttpProxy | ❌ 缺（hiddify 是 lanSharing 近似项） |
| allowAccess | ✅ lanSharing |
| connectionTestURL | ✅ |
| enableClashAPI | ✅ |
| networkChangeResetConnections / wakeResetConnections | ❌ 缺 |
| globalAllowInsecure | ⚠️ 在 TLS 技巧子页 |
| allowInsecureOnRequest / appTLSVersion | ❌ 缺 |
| showBottomBar | ✅（hiddify 列表/网格切换近似） |

设置页缺口集中在**通知/速度显示类**（speedInterval/profileTrafficStatistics/showDirectSpeed/showGroupInNotification/alwaysShowAddress）与 **DNS server 策略/DNS 路由**、**重置连接类**。

## 五、工具页

NekoBox ToolsFragment = Network（Stun 测试）+ Backup 两 Tab。
hiddify `tools_page.dart` 已是同构两 Tab：STUN/NAT 测试 ✅ + 备份（导出/导入/重置/更新订阅）✅。
**基本对齐**；NekoBox 备份内容含节点库备份（备份整个 app 数据），hiddify 只备配置 JSON——备份**内容**差异。

## 六、分享/导出链路

NekoBox `profile_share_menu.xml`：节点级 QR(standard/SN) + 剪贴板(standard/SN) + 配置导出(clipboard/file)；
分组级 `group_action_menu.xml`：分享订阅 universal link + 导出 std links + 清空。
hiddify：节点级分享/QR **缺**；分组级分享/导出/清空**缺**（批次 5 规划）。

## 七、总结：按影响排序的缺口 Top

1. **⋮ 菜单 5 缺**（更新订阅/清流量统计/去重/tcp ping/删不可用/清结果）——代理页主交互面
2. **分组页全套动作**（单组更新/分享/导出/清空/拖拽排序/流量展示/进度条）
3. **新建协议 17→4**（缺 13 种表单；其中 custom config/chain 语义不同）
4. **节点级分享（QR/链接）**
5. **设置项 ~12 键缺**（通知/速度显示类 + DNS server 策略 + 重置连接类）
6. **连接测试进度对话框**（并发/取消/最小化为通知）
7. FAQ 入口
