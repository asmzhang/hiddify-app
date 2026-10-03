# 「1:1 逐功能对比」序列 — 逐功能详细记录

> **本文是什么**：HANDOVER.md §3 剩余 #10 的**明细**部分。HANDOVER 只保留状态清单与提交锚点，
> 每个功能的规格抽取、测试用例、对比收口裁定、测试坑全部记录在这里。
>
> **为什么分开**：这段内容原先以单行 9298 字符的形式塞在 HANDOVER 里（占全文 21%），
> 导致交接文档本身需要工具取样才能读。搬家后 HANDOVER 恢复「一小时读完」，细节仍可检索。
>
> 序列口径见 HANDOVER §3.0#13（按用户真实动线排）。规格源 = `S:\test\NekoBoxForAndroid`。
> 测试基建与六条 widget 测试纪律见本文末「横切纪律」。

---

## 已完成功能（按序列序）

### 节点页 ⋮ 菜单（功能①）`82a39b20`
8 项权威顺序 + radio 排序子菜单 + 文案对齐 + 删「路由」项，L1 结构测试 5 用例。
规格源 `res/menu/add_profile_menu.xml`。详见 HANDOVER §2 与 `docs/design/nekobox-parity.md`。

### 抽屉核验收口（功能②）`3931652e`
规格 `res/menu/nav_drawer.xml`。测试写法样板见 `test/features/proxy/proxies_menu_test.dart`。

### 分组页（功能③）`32783b20` / 分组设置（功能④）`82f19327`
已完成，无遗留修正项。

### 配置页主体 `567a45f4`（2026-09-30）
NkProfileTile L1 spec 测试 4 用例全绿——卡规格 margin4/elevation2/圆角4+左缘 4dp 选中条、
三行结构、状态着色分支、本地配置收起、流量闸门。

**两个观察点收口**：宽屏留白按 NekoBox 原样不做约束；三行 vs 双行按形态分化收口。
部件本就 1:1，无修正项（原观察记录 `docs/design/ui-real-device-observations-2026-09-22.md`
2026-10-03 精简删除，`git log --diff-filter=D -- docs/design/` 可找回）。

### 连接链路 `c7d8bcbc`（2026-09-30）
FAB 四态已在 `897269a8`。状态条收口 = NkCaptureStatusBar 提公共部件（纯参数注入，ConnectionFab 同型）
+ `captureStatsBarVisible` 纯映射进 `connection_status.dart` + 页面删双写 `nkState` 归一，
L1 spec 测试 3 用例（可见性矩阵 / 单行内容 / 点击触发测速）。

**收口裁定**：
- 通知面定性 = **平台差异非缺口**（桌面壳对应物 `system_tray_notifier` 已按四态复刻；托盘缺「重置连接」动作 = 观察点不立测）
- 交互分化收口 = 点击测速走进度弹窗（Throne 形态），不对照内联文案

### 添加配置流 `5fc3cb35`（2026-09-30）
AddProfileModal L1 spec 测试 6 用例全绿——默认选项页 / startInManual 直达 / 手动表单结构
（名称·URL·禁用自动更新·自动更新间隔 Slider）/ 校验闸门 emptyName·invalidUrl 不触 repo /
桌面四键 + qr 仅移动端 / AsyncLoading→ProfileLoading。

部件本就 1:1 复刻 `add_profile_menu.xml` 五入口，无修正项。
**测试坑**：AddProfileNotifier 的 `ref.disposeDelay(1min)`（`riverpod_utils.dart:6`）在
container.dispose 留 60s Timer，测试必须 override fake。

### ②订阅页 `ec4dd8ec`（2026-09-30）
SubscriptionsPage L1 spec 测试 6 用例全绿——desktop/mobile 骨架（ShellDrawerButton 按 <600dp 断点）、
空态 rss_feed + 添加配置文件、`groupOrderProvider` 持久化排序与未上榜回退、
Dismissible 删 → SnackBar + 撤销记账。

可达性部分早闭环有测试（`groups_page` → `group_settings_sheet` `onOpenSubscriptions` 4 用例）。
**测试坑**：`List<String>` 偏好持久化为 `;` 连接字符串（`preferences_utils.dart:27-29`），
mock 预置须 `'p2;p1'` 非 StringList。

### ③路由页 `4136b3c0`（2026-09-30）
RoutingOptionsPage + RuleTile L1 spec 测试 9 用例全绿——空态 rule_rounded + 空菜单只显导入 2 项
（`getRange(0,2)` 项目特有语义）/ 列表 + 出站词 直连·拦截·代理 / 菜单 5 项词值 /
FAB 展开 hitTestable + 收起 Opacity(0) / GeneralOptions 展开收起
（SizeTransition 折叠在树内不可命中，断言用 hitTestable）/ 长按删除流
（ConfirmationDialog 真实确认框 → deleteRule 落账）/ updateEnabled Switch 翻转 + 记账 /
点行 `goNamed('rule')` 进编辑页。

**对比收口**：NekoBox 滑删 + undo 无对位（本项目长按/右键删，形态分化）；
路由规则页 = 项目增强面，**非 1:1 缺口**。
（2026-10-06 补：当时判「非缺口」只在**页面骨架**层面成立 —— 后来按 m08253「全nekobox」
定案 fork A 复查，发现**预置规则**是真缺口，见下方 ③-b。）

**测试坑四条**：
1. ConfirmationDialog 按钮用 `context.pop` —— 纯 MaterialApp 报 "No GoRouter found in context"，
   须 `MaterialApp.router` + `navigatorKey: rootNavKey`
2. `goNamed` 目标 GoRoute 必须带 `name:'rule'`
3. ReorderableListView 懒加载在默认 800×600 视口只 build 2 卡，3 卡断言须放大视口
4. `_ExpandableFab` mini 项标签 Opacity(0) 常驻树内无 IgnorePointer ⇒ 收起后仍可命中
   = **疑似产品 bug，记录不修**

### ③-b 路由页预置规则 1:1（fork A）`bf78eb19`（2026-10-06）

**触发定案**：User said (m08253): 「全nekobox」⇒ 取 fork A = 忠实 NekoBox（进入路由页自动种下
预置规则 + 删除 hiddify 自有的「预设规则」弹窗），而非保留弹窗的 B 方案。

**规格源**：`ProfileManager.kt:184-237 getRules()` + `ui/RouteFragment.kt:131-144 RuleAdapter.reload()`
（详见 `docs/design/nekobox-parity.md` §3.5.1，本轮已全量重写）。

**对照结论**：原实现 2 条（广告 + bypassLan，且广告 `outbound` 误写 `direct` ⇒「拦截广告」实为
「广告直连」）；新实现 5 条（cn）/ 9 条（非 cn），顺序与字段逐条对齐上游，全部默认关。
国家维度用 `ConfigOptions.region`（上游用 `Locale.getDefault().country`，判据不同但结果集等价）。
bypassLan 预置删除（上游无此项），内核侧 `bypass-lan` 通道不受影响。

**测试用例**：`predefined_rules_test.dart` 13 例（纯函数逐字段 + 条数 + has-bit 往返 + zh-CN 文案）；
`routing_options_page_spec_test.dart` 新增 ⑨a-⑨d（自动种下 9 条全关 / `region=cn` 只 5 条 /
有历史存储不覆盖 / 重置后重种），全量 **291/291 passed**。

**测试坑两条**：
1. `Rule` 工厂必须**显式**传 `enabled: false` —— proto3 只在显式赋值时置 has-bit，
   而「编辑已有规则 → 保存」走 `writeToJsonMap()` → `Rule.fromJson` 往返，has-bit 缺失会踩
   `rule_notifier.dart:115 assert(state.hasListOrder() && state.hasEnabled())`。落盘语义不受影响
   （`route_rule_json.dart:31` 只在 true 时输出该键）。
2. 测试里 `reason:` 字符串含 `$country` 会被当 Dart 插值 ⇒ 需加 `r` 前缀（`Undefined name 'country'`）。

### ③-c 按应用代理 ⋮ 菜单 · 反选（`per_app_proxy_menu.xml` 四项收口）（2026-10-06）

**触发定案**：User said (m00190): 「你似乎没有必要问我，和NekoBox 一样不行吗」⇒ 不再逐事请示，
NekoBox 有的直接照做（`action_invert_selections` 原样移植，不另设计）。

**规格源**：`res/menu/app_list_menu.xml` + `per_app_proxy_menu.xml`（4 项，扁平无子菜单：
invert → clear → export_clipboard → import）+ `AppListActivity.kt:239-303 onOptionsItemSelected`。

**照抄的三条语义（决定实现范围）**：
1. 反选遍历 **`apps` 全集**（`AppListActivity.kt:49 cachedApps` = 全部已安装包，仅去掉 NekoBox 自身），
   `showSystemApps` / 搜索框只作用于 adapter 的 `filteredApps`，**从不缩小 `apps`** ⇒ 我方必须收全量
   `phonePkgs`，不能拿当前可见/搜索过滤后的子集。
2. `proxiedUids[key] = true` 对**没有条目的 uid 也置选中** ⇒ 无 DB 行的包反选后必须**新建行**且为
   userSelection（纯变换已有行会漏掉绝大多数包）。
3. 反选后 `apps.sortedWith(compareBy({!isProxiedApp(it)}, {name}))` 重排 ⇒ 我方列表也要重排。

**★修正的判据缺陷（本功能真正的 bug）**：`invertSelectionFlag` 原先按 **userSelection 位**判定
（`PkgFlag.userSelection.check(value)`），但界面勾选态是 `PkgFlag.checkboxValue(value)` 而它
**forceDeselection 优先** ⇒ flag=3（userSelection|forceDeselection）被判「已勾选」→ 翻成 2，
可见态仍是未勾选 = **点反选毫无反应**。改为
`int invertSelectionFlag(int value) => PkgFlag.checkboxValue(value) == true ? PkgFlag.forceDeselection.add(value) : PkgFlag.userSelection.add(value);`
（`lib/features/per_app_proxy/model/pkg_flag.dart:76-79`）。修正后映射
0→1 / 1→2 / 2→1 / 3→1 / 4→5 / 5→6 / 6→5 / 7→5（旧 3→2、7→4 是错的），三条不变量仍成立：
**结果永不置零（不会凭空删行）**、两个选择位互斥、autoSelection 位保留。

**实现落点**：
- `app_proxy_data_source.dart:71-108` `AppProxyDao.invertSelections({required Set<String> phonePkgs, required AppProxyMode mode})`：
  `transaction` 内先 select 出该模式现况建 `{pkgName: flags}` 快照，再逐包算新值，
  **已存在的行走 `b.replaceAll`（UPDATE-by-pk）、无行的包走 `b.insertAll`** —— 两条路必须分开：
  `replaceAll` 的文档语义就是「同主键的行被替换」，**不会为不存在的包建行**（drift 2.28.2
  `batch.dart:101-122`；实测只写它 → 2 例红：`Expected: <1> Actual: <null> 列表里还没有的包也要被翻成已勾选`）。
  `phonePkgs` 之外的行走都不动（NekoBox 重写 `DataStore.routePackages` 会丢弃已卸载包的行，
  我方按既有既定差异**保留历史行**）。
  **★踩坑（勿再试）**：`insertAll(..., onConflict: DoUpdate((AppProxyEntries old) => ...))` 里
  `old` 是 **DSL 表对象**、`old.flags` 是 `Column<int>` 不是 Dart `int` ⇒ 无法表达位运算，
  编译报 `Error: The argument type 'Column<int>' can't be assigned to the parameter type 'int'.`
  （drift 2.28.2 `insert.dart:483-564` `Insertable<D> Function(T old)`）。
- `per_app_proxy_notifier.dart:62-70` `invertSelections()`：`loggy.info` → `_mode == null` 早退 →
  `await future` 等首次发射 → 用字段 `_installedPkgs`（`build` 里 `InstalledApps.getInstalledApps(false)`
  算出的全量手机包，原为闭包局部变量，本轮升为字段）→ 调 datasource。空集合 = 空转（对齐 NekoBox
  `apps` 为空时循环即空转）。
- `per_app_proxy_page.dart`：⋮ 菜单按 NekoBox 序重排为 **反选 → 清空 → 导出 → 导入 →（分隔线）→ 分享给所有人**
  （`:163-228`；导出/导入仍是「剪贴板/文件」两子项的 submenu，`shareToAll` 是 region 门控的本项目特有项）；
  `sortListener`（bool 翻转）改成 **`sortTicker`（递增 int）** —— 反选一次改动成千上万行而**行数不变**，
  `ref.listen` 的「长度差 > 1」判据抓不到；bool 双翻转还会互相抵消（流发射与显式自增到达顺序不定），
  改递增计数后 memo 依赖必变 ⇒ 必然重排。

**i18n**：11 份 `assets/translations/*.i18n.json` 的 `perAppProxy.options` 段新增 `invertSelections`
（插在 `shareToAll` 与 `clearAllSelections` 之间）：zh-CN「反选」/ en "Invert selections"（= NekoBox
`values-zh-rCN` / `values` 词值）/ zh-TW「反向選取」/ ru「Инвертировать выбранное」/ ar「عكس التحديدات」/
es "Invertir selecciones" / fa「برعکسکردن گزینههای انتخابشده」/ fr "Inverser la sélection" /
id "Balikkan pilihan" / tr "Seçimleri ters çevir"（**pt-BR 无 NekoBox 对应，自撰 "Inverter seleções"**）。
同时把 `clearAllSelections` 的 **zh-CN「清除所有选择」→「清空」、en "Clear all selections" → "Clear selections"**
对齐 NekoBox `clear_selections`（其余 9 语言未动；全仓无任何测试断言旧串）。之后**全量**跑
`dart run build_runner build --delete-conflicting-outputs`（`--build-filter` 会漏 slang 的
`lib/gen/translations_*.g.dart`）。

**测试（先红后绿）**：
- `test/features/per_app_proxy/pkg_flag_test.dart` 13 例（纯函数，含 8 项映射表 + 4 条不变量 + 可见态翻转循环）。
- `test/features/per_app_proxy/invert_selections_dao_test.dart` **8 例**打真 `AppProxyDao`（`Db(NativeDatabase.memory())`）：
  全量遍历 / 无行包建行 / flag=3 按可见态翻 / autoSelection 位保留 / 已卸载包历史行不被删 / 另一模式不受影响 / 空集合空转 / 两次自反。
- `test/features/per_app_proxy/per_app_proxy_menu_spec_test.dart` **6 例**泵**真 `PerAppProxyPage`**（family notifier
  用 `PerAppProxyProvider(AppProxyMode.include).overrideWith(() => fake)` 替身记账；`installed_apps`
  MethodChannel 用 `setMockMethodCallHandler` 拦成空列表）：四项文案齐备 / 权威顺序 / 旧顺序回归 / 点反选调用记账 /
  点清空调用记账 / 导入子菜单两级仍在。**非空洞性验证**：把「反选」`MenuItemButton` 整块删掉重跑 ⇒ 3 红，随后还原。
- 全量 `flutter test` **321/321 passed**，`flutter analyze lib test` **No issues found!**

### ④设置页 `e0339608`（2026-10-01）
SettingsPage L1 spec 测试 7 用例全绿——desktop 骨架（五段头 + 五卡关键行 + 默认值 + 平台/视口分支行）/
autoStart 开关翻转记账 / 导入确认流（两级菜单→确认框，取消不执行·确定 importFromClipboard）/
Clash API 联动（端口行 enabled 随开关，关闭后 tap 无效）/ 链行门控 hasAnyProfile /
customConfig JSON 徽标有无 / mobile 400×1600 视口（抽屉键 + desktop OS 行仍渲染）。

**对比收口**：无 1:1 修正项（部件本就位，纯补测）；补 2 条 android 行不出现断言
（「在通知中显示速度」「触觉反馈」）。

**测试坑**：
- `PlatformUtils.isDesktop` 按 `defaultTargetPlatform` 判（可测试版设计）⇒ `_pump` 钉
  `debugDefaultTargetPlatformOverride=windows`，**重置必须 body 末尾显式调 `_resetPlatformOverride`**
  （addTearDown 晚于 `flutter_test/binding.dart:1078` `_verifyInvariants`，必炸 foundation invariant）
- `autoStartNotifierProvider` 需 body 内预热（复刻 `bootstrap.dart:80` 启动时序，
  否则首帧 `settings_page.dart:150` `asData!` 落 AsyncLoading）
- direct-dns-address 实际默认 `1.1.1.1`（`config_option_repository.dart:98`
  defaultValueFunction 按 region 覆盖静态默认 `udp://1.1.1.1`）
- 同词碰撞断言：「入站」「其他」→ `findsNWidgets(2)`；
  「Clash API 端口」行标题 + 对话框 title + 输入框 hint 三处 → `findsNWidgets(3)`

spec 落盘 `.workbuddy/spec-settings-page-tests.md`。

### ⑥日志页 `006b50b3`（2026-10-01）
LogsPage L1 spec 测试 8 用例全绿——初始渲染（加载占位→标题/筛选/全部/等级徽标/extractMessage 去前缀/
时间戳/暂停·清空键/分享菜单）/ extractMessage 纯函数（多词去前缀·两词取尾·单词原样）/
关键词筛选防抖 200ms 命中剔除清空恢复 / 等级筛选 warn 及以上回「全部」恢复 /
暂停恢复（新日志不上屏·恢复补上·图标切换）/ 清空 `repo.clearLogs` 记账 /
错误流 → SliverErrorBodyPlaceholder +「意外错误」/ mobile 400×1600 视口。

**对比收口**：日志页是原生组合移植（无 NekoBox 对位页），无 1:1 修正项，纯补测。

**测试坑**：
- `environmentProvider` 必须 `overrideWithValue(Environment.prod)` ——
  `DebugModeNotifier._pref` 里 `ref.read(environmentProvider)`，而 `app_info_provider.dart:13`
  桩直接 throw（**全仓库测试首创 override**）
- `ref.disposeDelay(20s)`（`logs_overview_notifier.dart:19` → `riverpod_utils.dart:12` onCancel 挂 Timer）
  用例末尾必须 `pumpWidget(SizedBox.shrink())` 卸树触发 onCancel 再 `pump(21s)` 推假时钟烧掉，
  否则 `binding.dart:1617` 报 pending timer
- 真 import `fluentui_system_icons` 用 `FluentIcons.pause_20_regular` 等常量
  （自造 IconData 包装类 == 不匹配 byIcon，**教训：`find.byIcon` 只认真 IconData**）
- 其余同 ④（钉 windows + 显式重置 / 禁 pumpAndSettle 加载态 / pump(300ms) 推节流假时钟）

spec 落盘 `.workbuddy/spec-logs-page-tests.md`。

### ⑥余下仪表板/工具/关于 — 定性不立测（2026-10-01）
记档 `.workbuddy/qual-remaining-pages-2026-10-01.md`：
- Dashboard = traffic 页常驻差异（NekoBox `enableClashAPI` gate）
- tools/about 原生组合无对位

### ⑦首启引导 — 定性不移植
已定性：NekoBox 无 onboarding，不移植，仅记档。

### ①手动新建节点链 `9231100c` + `429bf873`（2026-10-01）
- `manual_node_flow_spec_test` 6 用例：选协议对话框 17 项列全 / 取消回退 / initialProtocol 直进 /
  chain→ChainSettings 空成员 / config→ConfigSettings / 普通协议→ProtocolFormModal 新建
- `protocol_form_modal_spec_test` 6 用例：新建 anytls 全字段渲染·分节·布尔 Switch·choice 未设置·
  ⋮ 菜单仅编辑模式 / 空名拒存 `errors.unexpected` + name 标星不落库 / 填名保存断 createNode 参数·
  payload `server_port` 443 int·种子 `tls.enabled` 保留 / `trojan_go` unsupported 占位 /
  坏 JSON jsonInvalid 占位 / 编辑回显 int toString·List 逗号 join·保存只动改过的键未编辑键原样含嵌套 tls

**测试坑**：fake ProxiesOverviewNotifier 覆写 `build()` 为现成 Stream 不挂 `disposeDelay(15s)`
⇒ 无 Timer 残留；不注入 proxyEntityRepository ⇒ 无 drift 真异步 ⇒ pumpAndSettle 全程可用；
TextFormField 无 decoration getter，断 errorText 用内层 TextField；
chain 弹层 drift 真异步 `_tapGoAndSettle bounded=false` 12×pump(50ms)。

### ⑤协议表单字段级 1:1（15 类协议）
依附「手动添加」分支。规格已抽取 `.workbuddy/spec-protocol-forms-tests.md`
（17 项菜单对齐 + 143 行字段矩阵 + P0/P1/P2 三批计划 + 真缺口表）。

**P0 已收口** `ba21921d`（2026-10-01）：`protocol_form_fields_p0_spec_test.dart` 603 行 12 用例全绿
——anytls/vless/hysteria2/shadowsocks × 新建渲染/编辑回显/新建保存。
矩阵 7 差异以代码为准固化：anytls password 非必填、vless flow 是 text 非 choice、
certificates 三协议 text 非 stringList、hysteria2 hopInterval text + 's' 后缀、
shadowsocks pluginName text 拆 `plugin`/`plugin_opts`、method 无默认值、hysteria2 无 TLS 分节标题。
**新坑两条**：同文案分节 + 字段 `findsNWidgets(2)`；choice 选项 `find.text().last`。

**P1 已收口** `4c0c1da0`（2026-10-01）：`protocol_form_fields_p1_spec_test.dart` 778 行 15 用例全绿
——vmess/trojan/hysteria/tuic/ssh × 同三用例。差异固化（**前三条已于 2026-10-01 由 `15b41d37` 修复**）：
vmess 无 alterId/encryption 字段（spec 复制 `_vlessSpec` 换 type）、trojan 种子无 tls 默认不落键（待裁定）、
tuic 四字段（UDP 中继/拥塞控制/禁 SNI/降 RTT）无 zh 词条界面显示英文 id、
hysteria 双窗口 `recv_window_conn`/`recv_window` 双向断言防 NekoBox 抄写 bug 回归、
ssh 无 privateKeyPath（`private_key` text 单串 + `host_key` stringList + 密码/私钥双写）。
**坑** = enterText 向 `maxLines=1` 注入多行 PEM 被剥换行 ⇒ private_key 改断单串。

**P2 已收口** `1a750b50`（2026-10-01）：`protocol_form_fields_p2_spec_test.dart` 783 行 20 用例全绿
——socks/http/shadowtls/mieru/wireguard/naive × 新建渲染/编辑回显/新建保存 + 收尾 2
（菜单 17 项顺序 + display 名映射 hysteria 分列 1/2；chain/config/trojan_go 无 spec + 15 协议 spec 非空）。
差异固化：socks version 无 writeValues 落原串 '5'、http host/path 死字段表单与 payload 均无、
shadowtls version 落 **int**（writeValues `{'2':2,'3':3}`）、mieru serverPort/protocol 落
`portBindings[0]` + 种子 `[{}]` 占位、wireguard reserved integerList 0-255 数字数组 +
种子 `mtu:1420`/`peers:[{}]` + `'256'` 越界拒存 errorText '!'、
naive serverProtocol writeValues `{'https':null,'quic':true}`——https 档删键/quic 档落 bool/
**缺键反查默认 'https' 不显示「未设置」**（`protocol_form.dart:866-877` 反查 null 匹配 `writeValues['https']`）。

**新坑两条**：
1. 容器 dropWhen 只认显式 `'false'` —— 新建未碰开关时不写键（`SwitchListTile onChanged` 才写
   `'true'`/`'false'`，`protocol_form_modal.dart:388`），测摘除须先开再关
2. **同一 fake notifier 实例挂进第二个 ProviderContainer 炸 LateError**
   （`Field '_element' has already been initialized`）—— 一次 `_pump` 一个新 `_Fixture`，
   勿跨 container 复用

### ⑧9 语言翻译补全 `17f32a0b`（2026-10-01）
zh-TW/ar/fa/es/fr/id/pt-BR/ru/tr 全量补齐 1367 键 + slang 再生 + analyze lib 0 + 全量测试绿，
i18n 缺口清零。

### ⑨小屏形态 `4f77caee`（2026-09-30）
- `test/features/proxy/small_screen_sheets_spec_test.dart`（7 用例）：协议新建 vless/shadowsocks
  360/320dp——**ListView 懒构建，屏外分节 find 落空，滚动可达断言**；chain/config 新建 + 编辑；
  弹窗 build 挂 drift useFuture ⇒ 有界泵
- `test/app/shell/drawer_small_screen_spec_test.dart`（3 用例）：真 MyAdaptiveLayout mobile 断点
  8 可见 + 1 隐藏分支壳——**分支表必须 = navMetas 全序，少搭隐藏分支 subscriptions 会令 goBranch 错位**，
  汉堡键开抽屉 + goBranch 导航 + 320dp 开合
- 全量 +273 绿（当时基线）

### ⑨-b 验收期缺陷 K-1：配置页数据层出错不再整页替换列表 `d1969a87`（2026-10-06）

**来源**：⑨ 终验收的窄屏 sweep（见 `.workbuddy/acceptance_checklist.md` 4.4）。两次 560×900
复现：`win_23_document.png`、`narrow2_01_config.png`（26071 B）——配置页 body 只剩一行
`Unexpected error`，页面骨架（AppBar / 订阅 tab 条 / FAB）正常；同一构建 1.5 分钟后的
`win_20c_config_recheck.png` 渲染正常 ⇒ **偶发**，与视口宽度无因果（正常窄屏页 36k–57k，
错误页 ≈26k）。

**NekoBox 判据（决定"不换页"这条结论）**：列表由 DB 流驱动（`ConfigBuilder.kt:131 proxyDao.getByGroup`），
**本身没有失败态**；`ConfigurationFragment.kt` 全类错误一律 snackbar / alert
（`:317` / `:324` / `:337` / `:451` / `:1588` / `:1678` / `:1704` / `:1729`），
**没有任何"用整页错误替换列表"的分支**。

**根因（riverpod 2.6.1 源码实证；不是猜的）**：
1. `ProxiesOverviewNotifier.build()` 是 `async*` 生成器，流一报错生成器即终止
   （`proxies_overview_notifier.dart:132-135` 的 `yield* Stream.error(const ServiceNotRunning())`；
   实时流出错时 `:165` 附近把 `watchProxies()` 的 `Either` left 重抛）。
2. riverpod 把状态留在 `AsyncError` 但**带着上一份数据**（`hasValue: true`）——
   `riverpod-2.6.1/lib/src/common.dart:528-539` 的 `AsyncError.copyWithPrevious` 保留
   `previous.valueOrNull` / `previous.hasValue`。
3. `.when` 的 `skipError` 默认 `false`（同文件 `:738` `if (hasError && (!hasValue || !skipError))`）
   —— **有旧数据也走 error 分支** ⇒ 已被顶掉的列表不会自己回来，错误页永久停留。

**改动（呈现层，最小）**：`lib/features/proxy/overview/proxies_overview_page.dart`
`skipError: true` + `error:` 分支回落空态 `t.pages.proxies.empty` + build 内
`ref.listen(proxiesOverviewNotifierProvider, ...)` 经 `showErrorToast` 报错。
**不做**：不动 loading 旗标；不在 notifier 层加重试/重订阅（`watchProxies` 是 gRPC 流，
自造退避会引入 NekoBox 没有的语义）。

**测试**：`test/features/proxy/proxies_overview_error_spec_test.dart`（3 例，泵**真**页 + 脚本化假
notifier：①已有列表时出错；②首次加载即出错回落空态；③出错后流继续发数据恢复更新）。
**先红 3/3**（`addError` 后 `Found 0 widgets with type "ProxyTile"`、屏上出现「服务未运行」整页文案）
**后绿 3/3**。

**残差（本次未做，另案）**：同形状的整页错误分支还有 5 处 ——
`groups_page.dart:170`、`subscriptions_page.dart:129`、`profiles_page.dart:61`、
`profile_details_page.dart:329`、`logs_page.dart:183`。它们的上游 provider 同样是
`async*`/`Stream` 打底（`GroupsNotifier` / `ProfilesNotifier.build()` `:38` 的
`.map((event) => event.getOrElse((l) => throw l))` 等），机制相同。
未一并改的理由：K-1 的判据来自 `ConfigurationFragment`，其余页要各自取 NekoBox 对位页的
错误处理证据（`GroupFragment` / 订阅页 / 详情页）才能定案，**不靠类比外推**。
（`logs_page.dart:183` 的 `SliverErrorBodyPlaceholder` 尤需单独看：日志页是原生组合、
无 NekoBox 对位页，属"形态分化"候选而非缺口。）

### 六缺口修复 `15b41d37`（2026-10-01）
见 HANDOVER §2 该条目；socks 置灰（第 8 项 / 真缺口 #5）见 `6309e141`。

---

## 方法纪律（序列执行口径）

每功能先抽规格（menu XML / preferences XML / Activity 源码 + strings 词表）→ L1 结构测试红灯 →
按「NekoBox 规格 → 复用已有机制 → 参考 Throne → 自己实现」修正 → 全绿提交 → 记档。

「对比收口」的三种结论必须显式写明其一：
1. **1:1 无修正项**（部件本就位，纯补测）
2. **形态分化**（本项目与 NekoBox 形态不同但等价，写明为何）
3. **真缺口**（规格有、实现无 ⇒ 修）

缺口的定性顺序（**不可颠倒**）：先读**内核源码**证支持性 → 再找「NekoBox 为何这么做」的机制理由 →
最后定我方处理方式（隐藏 / 置灰 / 不做）。跳过第二步会把语义问题当外观问题。
详见 `.workbuddy/spec-protocol-forms-tests.md` §5「真缺口汇总」及 HANDOVER §3 该条。

---

## 横切纪律（widget 测试六坑，全部批次共用）

1. `environmentProvider` 桩直接 throw（`app_info_provider.dart:13`）—— 必须 override
2. `ref.disposeDelay` Timers（`riverpod_utils.dart:12`）在 FakeAsync 里永不烧 ——
   卸树（`pumpWidget(SizedBox.shrink())`）后 `pump(21s)`
3. drift 真异步（useFuture / DB）永不定 —— 有界泵（如 12×`pump(50ms)`）
4. 自造 `implements IconData` 类不匹配 `find.byIcon` —— 引真 `FluentIcons.*`
5. `debugDefaultTargetPlatformOverride` 必须在 body 末尾重置，不能 addTearDown
6. key 名对照 zh-CN i18n json 核实

## 附录 · 批次 1–14 落地记录（原 `HANDOVER.md` §2，2026-10-03 移入）

## 2. 提交清单（2026-09-14 会话 16 个 + 9-16~9-20 批次 1-9；~~均未推送~~ **2026-09-30 已全量推送**）

**环境/修复（换机恢复，09-14）**
- `8c931843` Makefile PATH 截断修复 / `62da695b` doctor Go 版本检查 / `a961021a` 钉死代码生成器版本
- 规范：`5bb8e28a` 行尾 LF 唯一化 / `b3373c53` CI 门禁 / `64ed0e5e` 镜像版 pubspec.lock（勿回退）
- NekoBox UI 一期（`117f5397`→`560b65b5`）：主题色板/主壳/卡片分组/设置/拖拽排序/导航命名

**实体线 + 复刻批次（09-16 → 09-20，`d9fc1aa8` → `c0cc2171`）**
- 批次 1 `d9fc1aa8` 实体层移植（分组/节点实体 + drift v7，211 files）
- 批次 2 `69c33934` 协议表单 4→10；2.5 `d387adfe` 路由 per-rule package routing
- 批次 3 `e5d05926` 节点分享标准链接（8 协议，hiddify-core 侧 ray2sing 往返校验）
- 批次 4 `1ea4c8d6` 连接测试进度对话框 + FAQ；审计修复 `f9916a77`（pop 竞态）
- 批次 5 `56b8699b` 清流量统计（⋮ 菜单 8/8 收官）
- `15e27935` **Windows 构建通关**（hiddify-core.dll + 插件 junction + CMakeLists 注释 install）
- `3c2708e7` Windows 集成测试冒烟（integration_test/main_test.dart 全绿）
- 批次 6 `db8ee6f0` trojan + hysteria v1 表单（手动菜单 12 项；valueSuffix 机制）
- 批次 7 `39f6075a` 设置页 NekoBox 对照审计（38 项：21 覆盖 + 9 等价 + 8 挂起）
- 批次 8 `b86d57f7` custom_config 全局自定义配置（两阶段 raw 通道，见 docs/design/implementation-notes.md 批次 8）
- 批次 9 `c0cc2171` wireguard endpoint 表单 + endpoints 通路（见 docs/design/implementation-notes.md 批次 9；手动菜单 13 项）
- 切片 8.5 `1fc06b58` 节点级自定义配置覆写（customOutbound/customConfig 两列；drift v8）
- `7b10a467` 迁移测试补 v7→v8 覆盖
- **批次 10 `b13d7a16` chain 任意节点串联**（见 docs/design/implementation-notes.md 批次 10；type='chain' 实体 + buildChainOutbounds 组装 + ChainSettings 弹窗；手动菜单 +chain；复刻口径 ≈95%）
- **`142cfa29` chain detour 方向修正**（内核级验证抓出：v1 方向反了会被静默旁路；按 ConfigBuilder.kt:311 + sing-box DialerOptions 语义重写为落地穿中间跳→入口直连 + 同名成员 #N 防撞；HiddifyCli run7/run9 三断言全过——①配置启动 ②curl 出口=落地节点出口≠入口出口 ③§hide§ 不进 select 组。验证通道与坑见 docs/design/implementation-notes.md 批次 10）
- **`98060f8d` custom_config raw 通道实机验证闭环 + createService 假失败修复**（integration_test/custom_config_test.dart 全绿：真 Windows 内核全链路 prefs→addLocal(Parse FFI)→节点覆写 DB 直写→reconnect raw 通道→clash API @16990 探针 HTTP 200 = raw 启动 + 节点覆写生效的运行态硬证据；顺带修 core_status.dart 的 ALREADY_STOPPED→createService 误映射——内核 stop.go:32 良性回执被当成假失败日志的根因）
- **批次 12 `b07830af` http 表单**（协议表单收官，NekoBox HttpBean 移植）：字段照 `StandardV2RaySettingsActivity.kt:103-109` 对 HttpBean 的可见性裁剪 = server/port/username/password + TLS 段（security→tls.enabled，关 ⇒ tls 连根删，同 vless/trojan 构型）。**host/path 不移植**：`V2RayFmt.kt:628-637` HttpBean 分支只搬 server/port/username/password/tls——UI 显示但构建期不读，是死字段；内核 `HTTPOutboundOptions`（simple.go:32-40）也无 Host（host 属 headers map[string][]string，文本表单写不出正确形状）。菜单位 = `action_new_http` 紧跟 socks（add_profile_menu.xml 第 2 项），显示名 HTTP（strings.xml:213）。手动菜单 14 项（NekoBox 17 项里 trojan_go 内核缺出站不移植、其余全齐）
- **批次 11 `db8e1f1a` config 类型节点**（NekoBox ConfigBean 双形态移植）：type='config' 实体，payload=用户手写 JSON。**outbound 形态**（顶层有 `type` 键）照普通节点进 outbounds 段 + tag 组装期注入（ConfigBuilder.kt:402 `_hack_config_map` 语义）；**full 形态**（无 `type` 键）= payload 即启动配置本体，旁路整个 outbounds 拼装（ConfigBuilder.kt:66-78 type=0 分支对应物，`assembleConfigEntityConfig`；≥2 个 full 实体=语义无定义→回落常规路径）。UI：ConfigSettings 弹窗（名称+JSON 编辑器+**按内容自动识别形态**提示——NekoBox 的 isOutboundOnly 开关可能与其 JSON 自相矛盾，自动识别让 UI 提示与组装判据永远同一路径）；手动菜单 +config（NekoBox 菜单序 config 紧挨 chain 前）；分享隐藏（haveLink=false）；full 形态不可做 chain 成员（outbound 形态可以）
- **批次 13 `8483aeeb`(core) + `99f9c6f8` Go 侧、`<本提交>` Dart 侧 路由规则活通**（geo 资源管理页**不移植**的等价物；Task #40 重定义）：
  - **Go 侧**（hiddify-core `03f70ba`，4 files +507/−135）：新建 `v2/config/route_rules.go`（proto Rule → sing-box 1.13 option.DefaultRule/DefaultDNSRule 全字段映射；rule-set URL 展开/去重/5 天更新周期）+ `route_rules_test.go`（7 测试钉 Dart JSON 契约：复数键 + 数字枚举）+ builder.go 注释块换 `makeUserRouteRules()` + 删遗留 rules.go。
  - **Dart 侧**：根因 = `config_option_repository.dart:572` 发 `RouteRule.toProto3Json()`——proto3 JSON 单数键（rule_set/package_name）+ 枚举名（"direct"），而 Go pb.go json tag 是复数 + 数字枚举，unmarshal **静默丢弃**（上游注释掉消费点的原始动机）；叠加 freezed kebab rename 后顶层键 `route-rule` ≠ Go tag `rules` 且类型是对象不是数组，双重死亡。修复：模型字段 `routeRule: Map` → `rules: List<Map<String,dynamic>>`（kebab 后顶层键即 `rules`）；新建 `lib/features/route_rules/data/route_rule_json.dart`（routeRuleToCoreJson：只发显式赋值字段、复数 tag、枚举发 .value 数字、network=all 不发键；coreJsonToRules 反向读回供导入流）。
  - **校验**：`tool/check_route_rule_json.dart` 25 断言（契约形状/枚举锚定/空字段不发键/往返幂等/Go fixture 互验）+ `tool/check_route_rules_option_roundtrip.dart`（SingboxConfigOption 层 toJson→fromJson 无损 + 最终 HiddifySettingsJson 片段形状）全绿；flutter test 76/76；dart analyze 0 error 0 warning。
  - **坑**：dart run 直接跑引用 Flutter SDK 的 tool 脚本会撞 Flutter SDK 自身 Dart 版本编译错（text_painter.dart），要用 `flutter test tool/xxx.dart` 跑；flutter test 前必须 unset 代理变量（WebSocketException 老坑）。
- **批次 14 路由规则 NekoBox 全语义（`2b4d08c`(core)+`78981c8a` 前半、`eb37a6d`(core)+`d5268ad1` 后半，均已推送）**：
  - **前半：前缀语义**（NekoBox `SingBoxOptionsUtil.makeSingBoxRule` + `ConfigBuilder.kt:499-603`）。Go `expandUserRuleDomains/expandUserRuleIps`：domains 列吃 `geosite:/full:/domain:/regexp:/keyword:`（裸值→suffix，全 lowercase），ip 列吃 `geoip:`（`geoip:private`→IPIsPrivate 内建条件，其余→rule-set）。geo 引用走 **MetaCubeX meta-rules-dat 远程 .srs**（`geosite:cn`→URL `.../geo/geosite/cn.srs`，tag `geosite-cn`），复用批次 13 注册+去重池（无 geo 资产管线定案的等价通路）。DNS 规则只吃域名桶（NekoBox 只喂 rule.domains）。**关键语义：Domains/IpCidrs 是前缀承载字段，展开结果替代原值**（合并会泄漏原串进规则——测试抓过）；suffix/keyword/regex 显式 pb 值才与展开 mergeUnique。Dart：validators `isDomainInput/isIpInput` 前缀化；**预定义规则裸 tag 启动失败 bug 顺带修复**（原 `geosite-category-ads-all` 等无人注册→选中即启动失败）。
  - **后半：规则指向节点/分组 + 每规则覆写**（NekoBox `RuleEntity.outbound`→`tagMap[id]`（ConfigBuilder.kt:577）与 `RuleEntity.config`→`_hack_custom_config`（:584)）。proto Rule 加 `outbound_tag=19`/`config=20`，钉死工具链按文件定向重生成（protoc `--go_out=.` **不是** `--go_out=./v2/config`——后者 paths=source_relative 会错位产 v2/config/v2/）。Go：outbound_tag 非空⇒路由到该 tag 且**不产 DNS 规则**（NekoBox when 只处理 bypass/proxy/block）；config 走 marshal→mergeMap→unmarshal（可接受键=sing-box 解析器本身，无第二事实源；list REPLACE/map 递归/标量覆盖；坏 JSON fail-open 记日志）。Dart：转换器直通两字段（契约 31 断言）；UI = 「路由到节点」**选择器**（selectableChainMembers 数据源 + None 清空——手输 tag 未知会让 sing-box 启动校验失败，故不做自由文本）+「自定义配置」JSON 编辑（对象校验）；translations en/zh-CN/zh-TW。
  - **校验**：go test 18 全绿（含 outbound_tag 覆盖枚举/不发 DNS、config 覆盖/坏 JSON/未知键）+ dart analyze 0 error 0 warning + 契约 31 断言/option 往返 + DLL 重构建 + Windows 冒烟全绿。
- **wireguard endpoint 结构验证通关 + 内核契约 bug 修复（core `eb52b62`，主仓库 `c58b70af`，均已推送）**：
  - **HiddifyCli 验证通道摸清**：`bin/HiddifyCli.exe run -c config.json -d settings.json --log info`；`-c` = sing-box 原生配置（顶层 `endpoints` 段直接进 `option.Options.Endpoints`，settings **没有** endpoints 字段——builder.go:220 的 `input.Endpoints` 宿主是 `-c` 配置不是 `-d` settings）；`-d` = HiddifyOptions（log-level/balancer-strategy/remote-dns/direct-dns/region 必给全）；解析链 = `ParseBuildConfig`（非全量只提取 outbounds+endpoints）→ patchWarp → CheckConfigOptions → BuildConfig（endpoint tag 非 `§hide§` 进 selector 组）→ StartService。**构建入口必须 `./cmd/main`**（`./cmd` 产 6MB 无 tag 残废二进制）。
  - **抓到并修复批次 9 遗留 bug**：sing-box 内核对 wireguard endpoint 的每个 peer **硬校验 allowed_ips**（`transport/wireguard/endpoint.go:82` "missing allowed ips for peer N"），而批次 9 表单 8 字段没有 allowed_ips（NekoBox Bean 也没有——它的 legacy 扁平 outbound 形态无此约束）。修复 = 内核 `patchWarp` 给缺失 allowed_ips 的 peer 补默认 `0.0.0.0/0 + ::/0`（full-tunnel，与 WARP builder warp.go:57 同语义），在 parse 与 final 两阶段都生效（parse 阶段的 CheckConfigOptions 也会初始化 endpoint 校验）。
  - **验证闭环**：不带 allowed_ips 的 wg endpoint 配置 → HiddifyCli 真启动成功（`sing-box started 5.05s`）→ endpoint 进 selector 组 → final 配置里 allowed_ips 已自动补上。go test 全绿无回归。
  - **实连清单（剩）**：需用户提供真实 wireguard 凭据（private_key/peer public_key/endpoint host:port/local address CIDR），在 app 表单填入真节点后 FAB 连接验证握手；测试残留已清理（bin/wg-test 删除）。
- **`e86dfaa6` URL 测速无反应修复（已推送）**：⋮ 菜单「URL Test」点了只闪一下对话框、零进度零报错——**双重重入 guard**：页面外层包了一次 `runUrlTest`，`proxiesOverviewNotifier.urlTest()` 内部又包一次；外层置 running=true 后内层 guard 误判「已在跑」直接 return，核心 RPC 从未发出（外层还报成功）。tcpPingNodes 只有一层 guard 所以 TCPing 一直正常——同组对照定位的关键。修复：`urlTest()` 变纯测试体，guard+对话框归调用方（页面），规则钉进注释「**一次用户动作 = 恰好一层 guard**」；「already running」分支现在显式打出嵌套提示；新增 `test/features/proxy/connection_test_notifier_test.dart`（4 用例钉死嵌套拒绝/单层执行/guard 必复位/抛异常也复位）。flutter test 106/106。
- **功能① 节点页 ⋮ 菜单 1:1（`82a39b20`，已推送；1:1 逐功能对比阶段第一项）**：
  - **规格源**：`S:\test\NekoBoxForAndroid\app\src\main\res\menu\add_profile_menu.xml`（`action_misc` 内层 8 项，顺序权威）+ 三语词表 `values/strings.xml` / `values-zh-rCN` / `values-zh-rTW`（TCPing/URL Test 是 `translatable="false"` 固定词，全语言不译）。行为参照 `ConfigurationFragment.kt`（更新订阅 460-475 / 清流量 495-532 / 去重 534-580 / TCPing 694-832 / URL Test 834-901 / 清理 1110-1155）。
  - **产出**：菜单从页面内联 `PopupMenuButton<String>`（9 项乱序 + 'sort' 弹窗 + 'route' 项）抽成 `lib/features/proxy/widget/proxies_menu_button.dart`（MenuAnchor + MenuItemButton + SubmenuButton radio 子菜单，✓ 标当前排序项）；页面只留 `const ProxiesMenuButton()`。
  - **八项权威顺序**：更新当前组订阅 → 清空流量统计数据 → 删除重复的服务器 → TCPing → URL Test → 清理测试结果 → 清理不可用配置 → 排序（子菜单 原始/以名称/以延时，`checkableBehavior="single"` 语义；hiddify 遗留 usage 排序枚举保留但不进菜单）。**删「路由」项**（NekoBox 路由在抽屉，`nav_items.dart` 确认可达性不破坏）。
  - **测试**：`test/features/proxy/proxies_menu_test.dart` 5 用例（L1 结构对等：项数/顺序/逐词文案 vs zh-rCN 词表/无「路由」回归/子菜单无 usage/勾选态跟随/组件可独立构建）；全量 111/111 绿；analyze 干净。
  - **slang 键变更**：删 `sort`/`testDelay`/`testAll`/`updateSubscriptions` 及 orderOptions 旧值；增 `urlTest`("URL Test")/`order`/`orderOptions.origin|name|delay`/`tcpPing`("TCPing")/`updateSubscription`("Update current Group's subscription")。en/zh-CN/zh-TW 三语已对齐；**其余 8 语言键脱节未动**（见 §7）。
- **`05c4e7a4` 日志页第二层修复 + 测速对话框闪帧修复（2026-09-30，已推送）**：
  - **根因（日志页无限转圈）**：`lib/hiddifycore/hiddify_core_service.dart` 的 `watchLogs` 两条路都是零事件流——logController（BehaviorSubject）无种子、core 未初始化直接 return；`LogsOverviewNotifier` 的 asyncMap 收不到首个事件，state 永停 AsyncLoading。修法 = 方法开头 `yield logBuffer;`（立即首事件，空列表也行）再走未初始化分支；订阅顺序改 fg 恒开 + bg 仅 `!isSingleChannel()`（照 setup() 模式）——此前桌面单通道无条件 bg+fg 双订阅同一 client，logBuffer 重复入账。
  - **根因（测速对话框闪帧）**：`lib/features/proxy/notifier/connection_test_notifier.dart` runTcpPing/runUrlTest 收尾 state 丢 currentNode/currentResult/total/finished → 对话框按 `state.currentNode ?? t.pages.proxies.connectionTest.testing` 闪一帧「测试中…」。修法 = hoist lastNode/lastResult/finishedCount 局部变量，收尾与 catch 双分支保留最后进度；防重入 guard 断言全部原样保留。
  - **测试**：connection_test_notifier_test.dart 新增 4 断言钉死新语义（收尾保留 n3/timeout 与 10/7）；flutter analyze 5 info（= 基线，全在 route_rule_json.dart）、flutter test 155/155。
  - **执行方式备忘**：本提交为 Qwen3.8 子代理按主线写死的逐行补丁 spec 执行、主线逐行审查 diff + 独立复验 analyze/test 后提交——「简单机械工作交 Qwen3.8（用户 2026-09-30 指示），spec 越细越可靠」。
- **`ee6ca57f` raw 通道 selector 归一化——custom-config「切节点永不生效」根治（2026-09-30，已推送）**：
  - **根因**：用户 custom-config 用裸键 `outbounds`（List）整体替换出站列表 → 内核契约组 tag=`select`（builder.go 内核常量，内核每次启动丢弃输入组重建）消失、route.final 指向用户自己的 selector（tag 常为订阅原名）→ 应用切节点发 `SelectOutbound("select")` 报 "selector not found" → 点选永不生效。即 2026-09-23 假连接事故（MEMORY.md:42）的 raw 通道遗留形态。
  - **修法（定案 = 合并后归一化，不动用户输入）**：新增 `lib/features/proxy/data/raw_config_normalize.dart` 的 `normalizeRawConfigSelector(Map<String, dynamic>)`——就地改、返回被改名旧 tag / 无需改返回 null。7 步：outbounds 非空 List → 已有 tag=='select' 即返回 null（契约已满足，绝不动用户配置）→ 候选 = type=='selector' 且 tag 非空非 §hide§ → 目标 = route.final 匹配候选否则首个 → 改名 kRuntimeSelectorTag('select') → 精确相等重写全部引用（route.final / route.rules[].outbound / outbounds[].outbounds[] / .default / .detour）。接入点 = `connection_repository.dart` `_startWithCustomConfig` 节点覆写块后 + `loggy.info("raw config selector normalized: …")`。
  - **测试**：`test/features/proxy/data/raw_config_normalize_test.dart` 6 用例（zh-CN）：事故形态改名+四类引用重写 / 已有 select 整体不动（含 route.final 指向用户 selector 的意图保护）/ 无 selector 不动 / route.final 指向 urltest 时改首个 selector / §hide§ 不作候选 / 非法形态三种返回 null。全量 165/165、analyze 5 info 基线。
  - **执行方式**：Qwen3.8 子代理（medium）按主线 spec 实现 3 文件，产出与 spec 零偏差；主线逐行审查 + 独立复验后提交。
- **`15b41d37` 协议表单六缺口修复（2026-10-01，已推送）**：字段级 spec（⑤ P0/P1/P2）把「规格矩阵有、实现无」的六处全数暴露 → 一次性补齐实现 + 同步测试。明细见 `docs/design/parity-sequence-log.md`。关键项：vmess 独立 `_vmessSpec`（此前**只有引用没有定义，编译即断**）、ECH 两字段进 vless/trojan/http、trojan 种子 TLS 默认开、tuic 四字段中文词条 + `disabledBy` 置灰机制、`protocolFormLayout` 分节重复标题缺陷（同一 section 渲染 3 次）。19 files/+411/−128；全量 273/273，analyze lib+test 双清零。

