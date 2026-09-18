# custom_config 全局自定义配置 — 设计定案（2026-09-18）

> 批次 8 设计调研。规格源 = NekoBoxForAndroid；本项目约束 = hiddify 分层架构 + hiddify-core Go 内核。

## 1. NekoBox 规格（准绳）

**UI**：`global_preferences.xml:92-96` → `EditConfigPreference`（key=`globalCustomConfig`），
设置页里一个大文本编辑入口，整段 JSON。节点层同款（`config_preferences.xml:14-18`，key=`serverConfig`）。

**合并语义**（`moe/matsuri/nb4a/utils/Util.kt:129-159`，`mergeMap`）：

| 输入键 | 行为 |
|---|---|
| 标量 / 类型不同 | 直接覆盖 `dst[k] = v` |
| 双方都是 Map | 递归深合并 |
| `key+`（List） | 追加到 dst 现有 List 末尾 |
| `+key`（List） | 前插到 dst 现有 List 头部 |
| 裸键（List） | 整体替换 |

**挂载点**（`fmt/ConfigBuilder.kt:741-744`）：内核配置**全部拼装完成后**，先节点级
`proxy.requireBean().customConfigJson` 合并，输出最终 JSON。即「最后改卷权」。

## 2. 本项目现状与挂载点推导

**关键差异**：NekoBox 在 app 层拼完整 sing-box JSON；本项目最终配置由 **Go 内核拼装**
（`v2/config/builder.go: BuildConfig`：setOutbounds/setDns/setRoutingOptions...），
Dart 侧只通过 protobuf `HiddifyOptions` 传结构化选项。

推导出的可行挂载点（三选一）：

- **A. Dart 侧对 SingboxConfigOption JSON 做合并** → ❌ 不可行。
  `SingboxConfigOption` 是强类型 freezed 模型（kebab-case JSON），custom_config 的键是
  sing-box 原生结构（`route.rules[]`、`dns.servers[]`...），两者 schema 不同构，合并进去的键会被
  `toJson()/fromJson()` 丢失。且 protobuf 契约按字段传输，未知字段不过桥。
- **B. 内核侧加 override 通道** → 存在半成品：`v2/config/hiddify_option.go` 的
  `GetOverridableHiddifyOptions`（reflect + `overridable` tag）。但只覆盖**结构化 HiddifyOptions
  字段**（bool/int/string），不支持 List 合并策略（`key+`/`+key`），且当前无调用方
  （dead code），还需改 protobuf 接口。工程量大且能力面仍受限于 HiddifyOptions schema。
- **C. 走 `EnableRawConfig` 原始配置通道**（`v2/hcore/buildconfighelper.go:28-44`）→
  内核本来就支持 `StartRequest.EnableRawConfig=true` 时直接读完整 sing-box JSON
  （`ReadSingOptions`）。Dart 侧在启动前：内核 BuildConfigJson 产出完整 JSON
  （或本地模板）→ 应用 custom_config 深合并 → 原始 JSON 启动。

**定案 = C**。理由：
1. 不改 protobuf 契约、不改内核（内核 raw 通道现成，`enable_full_config` 语义上游已验证）
2. 合并语义与 NekoBox 完全同构（Dart 侧 `Util.mergeJSON` 等价物，纯 Map/List 操作）
3. 节点层（每个节点的 customConfigJson）在 profile/出站解析时同样适用同一合并器
4. `applyProfileOverride`（profile_parser.dart:459）已证明 Dart 侧深合并是既有先例——
   但它缺 List `key+`/`+key` 策略，需升级为 NekoBox 完整语义

**两阶段启动语义**（内核路径核实结论，hcore/buildconfighelper.go:28-44）：
- `EnableRawConfig=false`（现状）：内核 `BuildConfig(ctx, static.HiddifyOptions, readOpt)` 拼装
- `EnableRawConfig=true`：内核 `ReadSingOptions` 直接用原始 JSON，**跳过全部拼装**

因此 custom_config 模式下的启动序列是**两次调用内核**：
1. 正常（raw=false）跑 `generateFullConfigByPath` —— 内核用 HiddifyOptions + 订阅/实体出站
   拼出**完整最终 JSON**（含 patchWarp、静态 IP、DNS、路由全部处理完）
2. Dart 侧 `deepMergeJson(完整JSON, customConfig)` —— NekoBox 语义最后改卷
3. 以 `EnableRawConfig=true` + `configContent=合并结果` 启动 —— 内核只校验（`CheckConfigOptions`
   由 BuildConfigJson 内完成；raw 路径 unmarshal 即解析）直接用
- customConfig 为空 ⇒ 完全走现状单阶段路径，零行为变化

## 3. 实现切片

### 8.1 合并器（纯 Dart，可单测）
`lib/core/utils/json_merge.dart`（新文件）：
- `deepMergeJson(Map dst, Map src)` 逐条实现 §1 表格语义
- 与 `ProfileParser._mergeJson` 对齐：升级后者调用方或直接复用新实现（避免两份合并器——归一）

### 8.2 存储
- `ConfigOptions.customConfig`（`PreferencesNotifier.create<String,String>("custom-config","")`）
- 加入导出白名单（非 private），重置=清空

### 8.3 启动管线接入（connection_repository）
`_start` 内：
1. 读 `ConfigOptions.customConfig`；为空 ⇒ 现状路径原样（entities 组装 → start）
2. 非空：
   a. 先照常组装 entities 文件（失败回落订阅，与现状一致）
   b. `singbox.generateFullConfigByPath(路径)` 拿内核拼好的完整 JSON
   c. `deepMergeJson(完整JSON, parseCustomConfig(customConfig))`
   d. `singbox.startRawContent(合并JSON, profile.name, disableMemoryLimit)`
      （新方法：StartRequest 带 `configContent` + `enableRawConfig: true`）
3. raw 启动失败 ⇒ 记日志回落到现状路径（保证「不会比原来更差」）

### 8.4 UI
- 设置页「其他」卡加导航行「自定义配置」→ 编辑页（大 TextField + 校验 + 恢复默认）
- 无效 JSON 拦截在写入时（不拦在启动时）

### 8.5 节点层（后续切片）
protocol_form 侧 `customConfigJson` 键直通出站 JSON——等 8.1-8.4 落地后单独评估
（订阅节点场景少，手动新建场景才需要）。

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| raw 启动跳过内核拼装，某些 option 未被 patch | 两阶段：先正常构建产完整 JSON（patch 全部完成）再合并，合并只做增量 |
| 用户写坏 JSON 导致无法连接 | 写入时校验 + raw 启动失败自动回落现状路径 + 「清空自定义配置」入口 |
| `inbounds` 被覆盖后端口失配 | 合并基准 JSON 的 inbounds 由内核生成（与 ChangeHiddifySettings 一致）；用户覆盖则自担，内核 raw 路径 unmarshal 校验兜底 |
| 与 chain 模式组合 | chain 在内核 BuildConfig 内完成（HiddifyOptions 驱动），custom_config 在其产物之后合并，天然兼容 |
| entities 组装失败 | 与现状一致回落订阅基准；customConfig 合并在两者之后，不受影响 |

## 5. chain（链式代理）切片另立
本项目已有 warp/psiphon 双链骨架。NekoBox 式「任意节点串联」涉及 profile 数据模型
（出站间 detour 引用 + 环检测 + 分组 UI），待 8.1-8.4 验证 raw 通道后另立设计文档。
