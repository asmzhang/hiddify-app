# UI 实机观察（2026-09-22，1:1 对照阶段输入）

> 来源 = 三级 UI 测试的**实机层**（Windows debug 构建 @ HEAD `cce8f2c9`，真实订阅数据；
> 证据截图：`build/real_app_maximized.png` / `real_menu_open.png` / `real_drawer_open.png`，不入库）。
> 性质：观察记录 + 对照候选（C 层），非定案；逐条进功能盘点时以 NekoBox 规格源核实后才算数。

## 配置页（宽屏 2560×1408）

1. **节点卡宽屏留白**：内容贴左、操作图标贴右，中部大片空白。NekoBox 是手机窄列表无此形态；桌面是否做内容最大宽度约束 → 待对照 Throne（§3.0#3 决策链适用场景）。
2. **卡片三行布局**（名/地址/协议）比 NekoBox 双行紧凑行松散 → proxies 列表页 1:1 时的核心对照项（功能⑤范围）。
3. **「快速设置选项」悬浮 chip** 为 hiddify 遗留，NekoBox 主界面无此物 → 不移植/降权清单候选（需所有者定案）。

## 抽屉（520×1000 手机断点，功能②输入）

4. **结构对齐**：深色头（应用名 + 连接状态行）+ 三组分段（配置组/工具组/关于组，组间分隔线）+ 尾部「文档」动作项 —— 与 `main_drawer_menu.xml` 的 dhead + 三段 + nav_faq 对应；推广位未移植（已定案）。
5. **头部内容待核**：本实现第二行 = 连接状态（未连接）；NekoBox dhead 确切内容（是否含版本号等）待抽 `dhead` 规格核实。
6. **「文档」项文案待核**：当前 = `t.pages.about.faq`（渲染「文档」）；NekoBox `nav_faq` 的 zh-rCN 词表值待核对。
7. **选中态样式**：M3 NavigationDrawer 默认 pill 高亮 vs NekoBox NavigationView 高亮 —— 视觉近似，1:1 核对时确认即可。

## 功能①菜单实机验证（顺带闭环）

- ⋮ 菜单真实主题下八项权威顺序 + zh-rCN 文案 + 排序子菜单箭头全部正确（`real_menu_open.png`）——功能①的实机层验收完成。

## 同日测试资产

- 视觉层 golden：`test/features/proxy/proxies_menu_golden_test.dart` + `goldens/`（`cce8f2c9`；字体定案见文件头注释）。
- 实机层链路：构建 → 启动 → 最大化/缩窗 → 模拟点击 → 按窗口矩形截屏 → 目检。可重复，脚本内联于会话（暂不入库）。
