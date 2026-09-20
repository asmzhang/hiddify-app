# 节点级自定义配置 — 设计定案（2026-09-20，批次 8 切片 8.5）

> 规格 = NekoBoxForAndroid；承接 `custom-config-2026-09-18.md`（全局 custom_config，切片 8.1-8.4）。

## 1. NekoBox 规格（源码核实）

**Bean 有两个独立字段**（`fmt/AbstractBean.java:24-25`）：

| 字段 | 合并目标 | 合并时机 |
|---|---|---|
| `customOutboundJson` | **该节点的出站 JSON** | 出站序列化时（`SingBoxOptions.java:91-93`；赋值点 `ConfigBuilder.kt:404`） |
| `customConfigJson` | **根配置**（仅选中该节点时） | 全部拼装完成后（`ConfigBuilder.kt:744`，最后改卷权） |

- 合并语义 = 全局同一个 `Util.mergeMap`（深合并 / `key+` / `+key` / 替换）
- **订阅更新保留**（`group/RawUpdater.kt:165-166`）：两个字段从旧 bean 抄回新 bean
- **UI**：`ProfileSettingsActivity` ⋮ 菜单两项（`profile_config_menu.xml:25-30`），各开 ConfigEditActivity
- 合并顺序（根级）：global 先（`:741` 经序列化器）→ 选中节点后（`:744`）——节点覆写对全局有最后改卷权

## 2. 本项目挂载点推导

关键差异（同批次 8）：最终配置由 Go 内核拼装，Dart 只做「实体 → 基准出站表」的组装。
两个覆写各自落在既有链路上，**不新增通路**：

| NekoBox 字段 | 本项目挂载点 | 理由 |
|---|---|---|
| `customOutboundJson` | `applyEntitiesToOutbounds` 组装时，深合并进该节点的出站/endpoint JSON | 实体是出站权威（批次 1 起的既定边界），组装是"节点定义完成的最后一步" |
| `customConfigJson` | `_startWithCustomConfig` 内，global 合并之后再合并选中节点那份 | 只对**选中**节点生效（NekoBox `proxy.requireBean()` 语义）；复用批次 8 两阶段 raw 通道 |

## 3. 定案要点

1. **存储 = drift v8 两列**（`proxy_entities.custom_outbound` / `.custom_config`，默认空串）：
   - 不烘进 `payload` —— `syncFromProfile` 是整组替换，烘进去订阅更新即丢；
     独立列才能照 `RawUpdater.kt:165-166` 保留（`syncFromProfile` 替换前快照、按 tag 回填）
   - payload 保持**净定义**：dedup 键 / 显示地址 / 分享链接读原始值（NekoBox 的
     Bean 字段同样不进 `Deduplication.hash()`、`displayAddress()`）——覆写是构建期概念
2. **合并失败降级**：坏覆写 JSON 按无覆写处理（组装跳过该实体覆写；启动侧记日志跳过），
   覆写不该让节点整个失效；UI 写入时校验拦截（`_showJsonEditDialog`）
3. **raw 通道门槛不变**：仍以 global customConfig 非空为门槛（批次 8 行为边界，
   无 global ⇒ 现状路径零变化）；选中节点覆写在 raw 通道内追加合并
4. **UI**：编辑表单头部 ⋮ 菜单两项（对应 profile_config_menu.xml），JSON 编辑对话框；
   新建模式也能配（保存后随 createNode 一起落库）
5. **不做**：节点级覆写不进 `applyProtocolForm`（协议字段与覆写是两个编辑面）；
   每条路由规则的 `rule.config`（NekoBox `ConfigBuilder.kt:584`）不在本切片

## 4. 验证口径

- `check_config_assembly`：覆写合并进覆盖/追加两路 + endpoints 段 + 坏覆写跳过 + 无覆写零变化
- `dart analyze lib test tool` 0 issue；flutter test 存量全绿
- 实机（挂起）：选中带覆写节点连接，内核日志确认合并结果生效
