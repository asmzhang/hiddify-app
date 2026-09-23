# UI 实机观察（2026-09-22，1:1 对照阶段输入）

> 来源 = 三级 UI 测试的**实机层**（Windows debug 构建，真实订阅数据；
> 证据截图：`build/real_app_maximized.png` / `real_menu_open.png` / `real_drawer_open.png` /
> `real_drawer_after_fix.png`，不入库）。
> 性质：观察记录 + 对照候选（C 层），逐条进功能盘点时以 NekoBox 规格源核实后才算数。

## 配置页（宽屏 2560×1408）——待定案候选

1. **节点卡宽屏留白**：内容贴左、操作图标贴右，中部大片空白。NekoBox 是手机窄列表无此形态；桌面是否做内容最大宽度约束 → 待对照 Throne（§3.0#3 决策链适用场景）。
2. **卡片三行布局**（名/地址/协议）比 NekoBox 双行紧凑行松散 → proxies 列表页 1:1 时的核心对照项（功能⑤范围）。
3. **「快速设置选项」悬浮 chip** 为 hiddify 遗留，NekoBox 主界面无此物 → 不移植/降权清单候选（需所有者定案）。

## 抽屉（功能②，2026-09-22 已落地）

**规格实证（grep）**：
- `main_drawer_menu.xml` 三段 = [配置 分组 路由 设置] | [日志 仪表板 工具] | [推广(不移植) 文档 关于]，zh-rCN 词表逐词核对。
- **抽屉无头**：layout_main.xml 的 NavigationView 只有 `app:menu`、无 headerLayout，Kotlin 无 addHeaderView——此前实现的「dhead」规格引用**不存在**（A 层实证推翻旧结论）。
- 无「订阅」项：NekoBox 订阅管理在 GroupSettingsActivity 与 ⋮ 菜单。

**落地修正**（`drawer_entries_test.dart` 2 用例钉死 + 实机复验 `real_drawer_after_fix.png`）：
1. 移除抽屉头（`NkDrawerHeaderLegacy` 退役保留，不删码）。
2. 「订阅」导航降权 `navVisible:false`（页面/路由保留；**分组页订阅入口 TODO**，对位 GroupSettingsActivity）。
3. faq 动作项移到「关于」**之前**（spec 组 3 顺序），图标 menu_book → data_usage。
4. 图标对齐 spec drawable：配置=description、分组=view_list、路由=directions、日志=bug_report、仪表板=transform、工具=construction。
5. 词表：「仪表盘」→「sing-box 仪表板」（zh-CN）；en `proxies.title` Profiles→Configuration、`traffic.title`→sing-box Dashboard。zh-rTW 缺 menu_dashboard 键（spec 本身回退 en），不碰（§3.0#12）。
6. 抽屉条目收敛为唯一数据源 `nkDrawerEntries`（nav_items.dart），widget 层直接渲染；faq 索引/选中态映射有纯函数可测。

## 设置页 17 项"完全漏"重验（2026-09-22，按采信规则重验 09-15 矩阵）

| 分类 | 项 | 处置 |
|---|---|---|
| 已落地（前批） | globalCustomConfig / GroupSettingsActivity / route_preferences 表单序 | 批次 8 / 功能④ / 功能⑨ |
| 本轮落地 | alwaysShowAddress | 设置主表开关（spec 默认 false，邻位对齐 global_preferences.xml）+ 节点卡地址行门控（`ConfigurationFragment.kt:1557-1563` 同构） |
| 本轮落地 | profileTrafficStatistics | 设置主表开关（默认 true，spec 邻位 = alwaysShowAddress 前邻）+ NkProfileTile 流量列闸门（TrafficLooper 对应物，落点同为显示层） |
| 平台不适用 | meteredNetwork / acquireWakeLock / showGroupInNotification / speedInterval | Android 专属（通知/锁电/计量网络），桌面无对应物，记档跳过 |
| 内核未开放（C 组） | trafficSniffing※ / appendHttpProxy※ / domain_strategy_for_server※ / networkChangeResetConnections※ / wakeResetConnections※ | sing-box 1.13 内核未开放，等内核 |
| 无消费者（死键） | appTLSVersion（NekoBox 自身零引用）/ globalAllowInsecure（消费在内核侧链接解析，我方对应物 = 表单手动勾选） | 跳过并记档 |
| 待办（桌面可做） | showDirectSpeed（需直连/代理分流速率数据源） | 数据源就绪后再做 |
| 不移植（定案） | rulesProvider | geo 资产管线不做，等价物 = 预设规则 |
| 语义差异（记档） | isAutoConnect（硬充） / bypassLan（预设规则覆盖） | 已有记录 |

## 功能①菜单实机验证（2026-09-22 闭环）

- ⋮ 菜单真实主题下八项权威顺序 + zh-rCN 文案 + 排序子菜单箭头全部正确（`real_menu_open.png`）。

## 测试资产

- 视觉层 golden：`test/features/proxy/proxies_menu_golden_test.dart` + `goldens/`（字体定案见文件头注释）。
- 结构层抽屉：`test/app/shell/drawer_entries_test.dart`（L1 红灯 → 修正 → 全绿）。
- 实机层链路：构建 → 启动 → 最大化/缩窗 → 模拟点击 → 按窗口矩形截屏 → 目检。可重复，脚本内联于会话（暂不入库）。
- 全量 115/115 绿（2026-09-22 功能②收口时点）。
