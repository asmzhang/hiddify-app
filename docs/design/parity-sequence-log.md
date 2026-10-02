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
见 `docs/design/ui-real-device-observations-2026-09-22.md`。部件本就 1:1，无修正项。

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

**测试坑四条**：
1. ConfirmationDialog 按钮用 `context.pop` —— 纯 MaterialApp 报 "No GoRouter found in context"，
   须 `MaterialApp.router` + `navigatorKey: rootNavKey`
2. `goNamed` 目标 GoRoute 必须带 `name:'rule'`
3. ReorderableListView 懒加载在默认 800×600 视口只 build 2 卡，3 卡断言须放大视口
4. `_ExpandableFab` mini 项标签 Opacity(0) 常驻树内无 IgnorePointer ⇒ 收起后仍可命中
   = **疑似产品 bug，记录不修**

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
