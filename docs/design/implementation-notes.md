# 落地特性实现笔记（批次 8 – 批次 10）

> 2026-10-03 文档精简：由四份带日期的实现笔记合并而成，正文原样保留（各级标题降一级）。
> 原文可用 `git log --diff-filter=D -- docs/design/` 找回。

---

## 批次 8 · 全局 custom_config（两阶段 raw 通道）

> 来源：`docs/design/custom-config-2026-09-18.md`（已并入本文件）

## custom_config 全局自定义配置 — 设计定案（2026-09-18）

> 批次 8 设计调研。规格源 = NekoBoxForAndroid；本项目约束 = hiddify 分层架构 + hiddify-core Go 内核。

### 1. NekoBox 规格（准绳）

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

### 2. 本项目现状与挂载点推导

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

### 3. 实现切片

#### 8.1 合并器（纯 Dart，可单测）
`lib/core/utils/json_merge.dart`（新文件）：
- `deepMergeJson(Map dst, Map src)` 逐条实现 §1 表格语义
- 与 `ProfileParser._mergeJson` 对齐：升级后者调用方或直接复用新实现（避免两份合并器——归一）

#### 8.2 存储
- `ConfigOptions.customConfig`（`PreferencesNotifier.create<String,String>("custom-config","")`）
- 加入导出白名单（非 private），重置=清空

#### 8.3 启动管线接入（connection_repository）
`_start` 内：
1. 读 `ConfigOptions.customConfig`；为空 ⇒ 现状路径原样（entities 组装 → start）
2. 非空：
   a. 先照常组装 entities 文件（失败回落订阅，与现状一致）
   b. `singbox.generateFullConfigByPath(路径)` 拿内核拼好的完整 JSON
   c. `deepMergeJson(完整JSON, parseCustomConfig(customConfig))`
   d. `singbox.startRawContent(合并JSON, profile.name, disableMemoryLimit)`
      （新方法：StartRequest 带 `configContent` + `enableRawConfig: true`）
3. raw 启动失败 ⇒ 记日志回落到现状路径（保证「不会比原来更差」）

#### 8.4 UI
- 设置页「其他」卡加导航行「自定义配置」→ 编辑页（大 TextField + 校验 + 恢复默认）
- 无效 JSON 拦截在写入时（不拦在启动时）

#### 8.5 节点层（后续切片）
protocol_form 侧 `customConfigJson` 键直通出站 JSON——等 8.1-8.4 落地后单独评估
（订阅节点场景少，手动新建场景才需要）。

### 4. 风险与对策

| 风险 | 对策 |
|---|---|
| raw 启动跳过内核拼装，某些 option 未被 patch | 两阶段：先正常构建产完整 JSON（patch 全部完成）再合并，合并只做增量 |
| 用户写坏 JSON 导致无法连接 | 写入时校验 + raw 启动失败自动回落现状路径 + 「清空自定义配置」入口 |
| `inbounds` 被覆盖后端口失配 | 合并基准 JSON 的 inbounds 由内核生成（与 ChangeHiddifySettings 一致）；用户覆盖则自担，内核 raw 路径 unmarshal 校验兜底 |
| 与 chain 模式组合 | chain 在内核 BuildConfig 内完成（HiddifyOptions 驱动），custom_config 在其产物之后合并，天然兼容 |
| entities 组装失败 | 与现状一致回落订阅基准；customConfig 合并在两者之后，不受影响 |

### 5. chain（链式代理）切片另立
本项目已有 warp/psiphon 双链骨架。NekoBox 式「任意节点串联」涉及 profile 数据模型
（出站间 detour 引用 + 环检测 + 分组 UI），待 8.1-8.4 验证 raw 通道后另立设计文档。

---

## 批次 8.5 · 节点级 custom config 覆写

> 来源：`docs/design/node-custom-config-2026-09-20.md`（已并入本文件）

## 节点级自定义配置 — 设计定案（2026-09-20，批次 8 切片 8.5）

> 规格 = NekoBoxForAndroid；承接 `custom-config-2026-09-18.md`（全局 custom_config，切片 8.1-8.4）。

### 1. NekoBox 规格（源码核实）

**Bean 有两个独立字段**（`fmt/AbstractBean.java:24-25`）：

| 字段 | 合并目标 | 合并时机 |
|---|---|---|
| `customOutboundJson` | **该节点的出站 JSON** | 出站序列化时（`SingBoxOptions.java:91-93`；赋值点 `ConfigBuilder.kt:404`） |
| `customConfigJson` | **根配置**（仅选中该节点时） | 全部拼装完成后（`ConfigBuilder.kt:744`，最后改卷权） |

- 合并语义 = 全局同一个 `Util.mergeMap`（深合并 / `key+` / `+key` / 替换）
- **订阅更新保留**（`group/RawUpdater.kt:165-166`）：两个字段从旧 bean 抄回新 bean
- **UI**：`ProfileSettingsActivity` ⋮ 菜单两项（`profile_config_menu.xml:25-30`），各开 ConfigEditActivity
- 合并顺序（根级）：global 先（`:741` 经序列化器）→ 选中节点后（`:744`）——节点覆写对全局有最后改卷权

### 2. 本项目挂载点推导

关键差异（同批次 8）：最终配置由 Go 内核拼装，Dart 只做「实体 → 基准出站表」的组装。
两个覆写各自落在既有链路上，**不新增通路**：

| NekoBox 字段 | 本项目挂载点 | 理由 |
|---|---|---|
| `customOutboundJson` | `applyEntitiesToOutbounds` 组装时，深合并进该节点的出站/endpoint JSON | 实体是出站权威（批次 1 起的既定边界），组装是"节点定义完成的最后一步" |
| `customConfigJson` | `_startWithCustomConfig` 内，global 合并之后再合并选中节点那份 | 只对**选中**节点生效（NekoBox `proxy.requireBean()` 语义）；复用批次 8 两阶段 raw 通道 |

### 3. 定案要点

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

### 4. 验证口径

- `check_config_assembly`：覆写合并进覆盖/追加两路 + endpoints 段 + 坏覆写跳过 + 无覆写零变化
- `dart analyze lib test tool` 0 issue；flutter test 存量全绿
- 实机（挂起）：选中带覆写节点连接，内核日志确认合并结果生效

---

## 批次 9 · WireGuard endpoint 表单 + endpoints 通路

> 来源：`docs/design/wireguard-endpoint-2026-09-18.md`（已并入本文件）

## 批次 9 设计定案：WireGuard 表单 + endpoints 通路

日期：2026-09-18　|　前置：批次 8（custom_config，`cac9fb4e`）　|　规格源：NekoBoxForAndroid（唯一）

### 0. 一句话

给 ⋮ 手动菜单补上第 13 项 WireGuard：表单字段 1:1 照 NekoBox `wireguard_preferences.xml`（8 字段），
产物形态按**内核现实**（endpoint，非 NekoBox 的 legacy outbound），并把 Dart 应用侧「endpoints 通路」
从零打通（组装 / 派生 / 解析 / 判据四处）。

### 1. 内核事实（全部已读源码核实，hiddify-core）

| # | 事实 | 出处 |
|---|---|---|
| K1 | legacy wireguard **outbound 是纯 stub**：注册为 `StubOptions`，启动即报错 "deprecated in 1.11.0 and removed in 1.13.0, use WireGuard endpoint instead"。`protocol/wireguard/outbound.go` 里那份完整 legacy 实现是死代码（`include/wireguard.go` 只调 `RegisterEndpoint`，无人调它的 `RegisterOutbound`） | `include/registry.go:200-201`、`include/wireguard.go` |
| K2 | 正确形态 = **endpoint**：`WireGuardEndpointOptions`。内核 `Parse` 透传 JSON `endpoints` 字段；`setOutbounds` 处理 `input.Endpoints`（过滤预定义 tag / WARP 去重 / `patchEndpoint` / 收 tag） | `option/wireguard.go:11-37`、`v2/config/parser.go:75-77`、`builder.go:220-257` |
| K3 | **组可以引用 endpoint tag**（内核原生）：`adapter.Endpoint` 内嵌 `Outbound` 接口；outbound manager `Outbound(tag)` 未命中回落 `endpoint.Get(tag)`；builder 对 endpoint 也收非 `§hide§` tag 进 selector/balancer 成员 | `adapter/endpoint.go:10-15`、`adapter/outbound/manager.go:201-209`、`builder.go:252-254` |
| K4 | `patchWarp(final=true)` 对 `type==wireguard` 的 endpoint 有 WARP 特化，但**只命中特殊值**（`peers[0].address ∈ {auto,default,random,auto4,auto6,被墙域名}` 或 `port==0`）；真实地址/端口的普通 wg endpoint 原样通过 | `v2/config/warp.go:253-300` |
| K5 | `address` 字段是 `badoption.Listable[netip.Prefix]`，反序列化走 `netip.ParsePrefix` —— **裸 IP（无 `/掩码`）被拒**（`Prefixable` 才容裸 IP，本结构不是） | sing `badoption/netip.go`（v0.8.11） |
| K6 | `reserved` 是 `[]uint8`（= []byte）：JSON 收**数字数组**或 **base64 字符串** 两形态 | `option/wireguard.go:36` |
| K7 | 订阅链接 `wg://|wireguard://|warp://|awg://` 经内核 Parse（ray2sing `AWGSingbox`）**已自动产 endpoint 进 endpoints 段** —— 订阅侧无需 Dart 做任何事；缺口只在应用侧实体管理 | `ray2sing/convert.go:50-54`、`awg.go:207-376` |

#### 内核 endpoint JSON 形态（表单产物目标）

```json
{
  "type": "wireguard",
  "tag": "…",
  "address": ["172.16.0.2/32"],
  "private_key": "…",
  "mtu": 1420,
  "peers": [{"address": "srv", "port": 51820, "public_key": "…", "pre_shared_key": "…", "reserved": [1,2,3]}]
}
```

### 2. NekoBox 规格 → 内核形态的字段映射

规格：`res/xml/wireguard_preferences.xml`（proxy_cat 8 字段）+ `fmt/wireguard/WireGuardFmt.kt`。
NekoBox 的 `buildSingBoxOutboundWireguardBean` 产 **legacy Outbound_WireGuardOptions** —— 它 pin 的
旧内核（≤1.10）形态，在我们的 1.13 内核上是 K1 的必报错形态。**字段清单照 NekoBox，产物按内核**
（同 mieru `portBindings[0]` 的处理先例）：

| NekoBox 字段（key） | 内核 endpoint JSON | 表单 kind / id |
|---|---|---|
| serverAddress | `peers[0].address` | text / serverAddress |
| serverPort | `peers[0].port` | integer / serverPort |
| localAddress（listByLineOrComma） | `address`（数组，需 CIDR） | stringList / localAddress |
| privateKey | `private_key` | text / privateKey |
| peerPublicKey | `peers[0].public_key` | text / peerPublicKey |
| peerPreSharedKey | `peers[0].pre_shared_key` | text / peerPreSharedKey |
| mtu（defaultValue=1420） | `mtu` | integer / serverMTU（复用既有 key） |
| reserved（genReserved） | `peers[0].reserved` | **integerList（新）** / reserved |

`name`（配置名称）照旧由表单顶部名称框承担，不进字段表。

#### reserved 的归一决策

NekoBox `genReserved`：3 个数字 → b64 单行字符串，否则原样 —— 那是为适配它手写镜像类里
`reserved: String` 的约束。我们内核是 `[]uint8`（K6），数字数组是 ray2sing/内核生态原生形态
（`awg.go:341-349` 同款）。定案：表单收「逗号/换行分隔的 0-255 数字」，写入产**数字数组**；
读回数组 join 成逗号串。不是 3 数字也接受（1~n 个），非数字报错拒存。b64 串输入不支持
（用户如拿到 b64，粘贴到内核或其他工具都能转数字；表单不做双向 b64 猜测）。

#### localAddress 的掩码决策

K5：裸 IP 被内核拒。NekoBox 对 localAddress 也是**原样透传**（`listByLineOrComma` 不补掩码），
默认 Bean 值自带 `/32`。定案：stringList 原样透传 + 翻译 hint 说明 CIDR 形态，不做自动补掩码。

### 3. Dart 侧 endpoints 通路（四处 + 判据）

#### 3.1 判据（runtime_outbound_tags.dart）

- `isNodeOutbound` **排除 `wireguard`**（它不再可能是合法 outbounds 节点：K1 必报错；
  排除后派生/解析/组装三消费者一致，legacy wg 不再被当节点派生成读不出字段的实体）
- 新增 `kEndpointOutboundTypes = {'wireguard'}` + `isNodeEndpoint(type)`

#### 3.2 组装（config_assembly.dart，`applyEntitiesToOutbounds`）

实体按 `isNodeEndpoint` 拆两桶：

1. **outbounds 段**（照旧逻辑，只喂非 endpoint 实体）：覆盖/追加/按 staleTags 删除；
   另外**剔除基准 outbounds 里的 `type==wireguard`**（K1：留着 = 这份配置启动必炸；剔除反而救活订阅；
   记 removed 计数）。不做 legacy→endpoint 自动迁移（罕见场景，YAGNI，记档）。
2. **endpoints 段**（新）：基准 `config['endpoints']`（可缺省）按 tag 做 endpoint 实体的
   覆盖/删除（判据同 stale 思路：基准 endpoints 里是 wireguard endpoint 而实体集合没有 → 删；
   基准没有的 endpoint 实体 → 追加在末尾）；基准无 endpoints 段且有 endpoint 实体时新建数组。

组不用动：输入里的组照旧透传，内核重建组时自己收 endpoint tag（K3）。

#### 3.3 派生（proxy_entity_import.dart，`deriveProxyGroupFromConfig`）

outbounds 遍历（isNodeOutbound 已排除 wg）+ **endpoints 遍历**（`isNodeEndpoint` → 实体，
payload 整条留存）。

#### 3.4 判重（`dedupKeyOf`）

endpoint payload 无顶层 `server`/`server_port` → 现判据返回 null（天然放行，安全）。
补一个分支对齐 NekoBox 口径：payload 有 `peers[0]` 时用 `peers[0].address|port|type`。

#### 3.5 解析列表（offline_proxy_parser.dart）

- `parseSubscriptionGroup`：endpoints 遍历产 `OutboundInfo`（host/port 取 `peers[0]`）
- `serverAddressOfPayload`：endpoint payload → `peers[0].address/port`（节点卡地址行、
  列表构建共用；tcpPing 本就被 `canTcpPing('wireguard')==false` 排除）

#### 3.6 存储与通道（无需改 schema / repo）

endpoint 实体复用 `proxy_entities` 表：`type='wireguard'`、payload = 整条 endpoint JSON。
`assembleOutboundsForProfile` 不改 —— 它把实体行原样转 `ImportedProxyEntity`，拆桶在组装函数内部。
手动新建 → `createNode` → 组装 endpoints 段 → `_reloadCoreIfAffected` 重载内核，链路全部现成。

### 4. 表单数据层（protocol_form.dart）

- `_wireguardSpec`：§2 的 8 字段 + 路径（`peers` 数组用 int 下标 0，`_set` 已支持 —— mieru 先例）
- 新 `ProtocolFieldKind.integerList`：apply 时逗号/换行 split → `int.tryParse`（失败 return null）
  → `List<int>`；read 走 `_stringify`（List 递归 join，现成）；validate 对每元素 tryParse
- `kManualCreatableProtocols` 加 `wireguard`（NekoBox add_profile_menu 第 15 项 wg）→ 13 项
- `protocolDisplayName` 加 `'wireguard' => 'WireGuard'`
- 种子 `protocolSeedPayload('wireguard')` = `{'mtu': 1420, 'peers': [{}]}`（NekoBox defaultValue +
  peers[0] 路径占位，同 mieru portBindings 占位逻辑）
- modal：integerList 渲染走 text 形态分支（与 integer/text/stringList 并列）；label switch 加 5 个新 id

### 5. 翻译（新增 5 key ×2 语言）

`pages.proxies.form.localAddress`（本地地址 / Local Address）、`privateKey`（私钥 / Private Key）、
`peerPublicKey`（对端公钥 / Peer Public Key）、`peerPreSharedKey`（预共享密钥 / Pre-Shared Key）、
`reserved`（Reserved / Reserved）。slang 全量 build_runner 生成（批次 8 教训：`--build-filter` 会漏 `lib/gen/`）。

### 6. 不做 / 记档

- legacy wg outbound → endpoint 自动迁移（罕见；基准里 legacy wg 由组装剔除兜底）
- `listen_port` / `workers` / `system` / `noise` / `awg`（AmneziaWG 参数）/ `udp_timeout`：
  NekoBox 表单没有（AWG 是 SagerNet 生态的独立格式，`awg://` 由订阅解析走 ray2sing，不经表单）
- WARP 表单（`warp://`）：内核 `Warp.EnableWarp` 已有专用通道，订阅里的 warp:// 经 ray2sing 自动解析；
  手动编辑 WARP 凭据是另一个批次的事

### 7. 验证口径

1. `dart run tool/check_protocol_form.dart`：wireguard 读值/写回/往返幂等/integerList 校验/种子
2. `dart run tool/check_config_assembly.dart`：endpoints 覆盖/追加/stale/legacy wg 剔除/两段并存
3. `dart analyze lib test tool` 0 issue
4. 全量 build_runner（翻译）后 `unset 代理变量 && flutter test` 存量全绿

---

## 批次 10 · chain 任意节点串联

> 来源：`docs/design/chain-2026-09-20.md`（已并入本文件）

## chain 任意节点串联 — 设计定案（2026-09-20）

规格源：NekoBoxForAndroid（唯一）。桌面形态差异处参考 Throne 已在批次定案中确认过——chain 是
数据/组装层能力，不涉及桌面布局适配，Throne 本期不进决策链。

---

### 0. NekoBox 规格（实测源码，勿凭记忆）

#### 0.1 数据模型
- `fmt/internal/ChainBean.java`：唯一业务字段 `public List<Long> proxies`（**有序** proxy id 列表），
  Kryo version=1，displayName 缺省 `"Chain " + abs(hashCode())`。
- `ProxyEntity.TYPE_CHAIN = 8`（ProxyEntity.kt:97）。
- `haveLink() = false`（:232）→ 无分享/QR/剪贴板（ConfigurationFragment.kt:1610-1644）。

#### 0.2 展平与方向（ConfigBuilder.kt:86-124）
```
resolveChainInternal(): 递归展开嵌套 chain → 按 bean.proxies 顺序收集 → asReversed()
resolveChain(): resolveChainInternal + group.frontProxy（list.add，尾部）+ group.landingProxy（list.add(0,…)，头部）
```
**方向约定**：`bean.proxies` 的 UI 语义 = **流量经过顺序**（第一行 = 入口/前置代理，最后一行 = 落地）。
build 序经过 asReversed 后 index 0 = UI 序最后一行 = **落地**。证据：
- `index == profileList.lastIndex`（build 序最后一个 = UI 序第一行 = 入口）→ `needGlobal = true`、
  tag `g-<id>`（这条出站**直连出去**，它是要拨号到真实服务器的第一跳）；
- `chainId == 0 && index == 0`（build 序第一个 = UI 序最后一行 = 落地）→ tag `TAG_PROXY = "proxy"`，
  即**路由最终指向的出站**。

#### 0.3 连接方式（buildChain, ConfigBuilder.kt:248-459）
- tag 规则：`c-<chainId>-<proxyId>`；出口落地：`proxy`；入口（build 序 last）：`g-<id>`。
- **detour 链**（internal 出站）：build 序 `index > 0` 时
  `pastOutbound._hack_config_map["detour"] = tagOut` —— 即每条出站通过 `detour` 字段把流量交给
  **build 序中的下一条**（UI 序的上一条），最终由落地出站发出。sing-box 语义：
  `dialer.detour = "tag"` = 本出站的底层拨号走 tag 那条出站。
- external（插件）代理：不进 detour 链，改 route rule `{inbound: mapping-inbound, outbound: 下一条}` +
  direct mapping inbound（override_address/port）。本项目无插件 external 机制（hiddify 芯没有
  needExternal 概念），**此分支不移植**。
- 每条链上出站设 `domain_strategy`；合并 `bean.customOutboundJson`（:404，对应本项目切片 8.5 的
  节点覆写）；mux 每条链只应用一次。
- **selector 全量建链**（:462-480）：组内每个 proxy 各 `buildChain(it.id, it)`，所以无论选中谁，
  所有 chain 的中间跳出站都在配置里；选中即把 selector 指向对应 chain 的 tag。

### 1. 本项目挂载点（已通读确认的事实）

| 事实 | 出处 |
|---|---|
| 内核读到「tag 含 `§hide§`」的出站：**保留进配置但不收进 select/balance/lowest 组** | `builder.go:178-179`（`!strings.Contains(out.Tag,"§hide§")` 才 `tags=append`），出站本体 `:183` 照样 `outbounds=append` |
| detour 是 sing-box DialerOptions 标准字段，fork 保留 | sing-box `option.DialerOptions.Detour`（内核全量 patch 后不剥） |
| 内核丢弃输入里的所有组并重建 select/balance/lowest | `builder.go:151-164` + `:311-341` |
| `§default§` tag 出站会被选为 selector default | `builder.go:313-317` |
| 选中模型 = 持久期望 tag + 内核 ready 后 `SelectOutboundRequest(select, tag)` 下发 | `selected_proxy_store.dart` + `selection_reconcile.dart` |
| 实体表 `proxy_entities`(payload/customOutbound/customConfig, type str) schemaVersion=8 | `lib/core/db/db.dart` |
| 组装 = 覆盖/追加/点名删除/组透传，一实体一出站假设 | `config_assembly.dart applyEntitiesToOutbounds` |
| 手动组（type=basic）节点被追加进**任何**订阅组装 | `proxy_entity_repository.dart:808-823` |
| 节点级覆写链路：组装期 deepMerge 进该节点出站 | 切片 8.5（`config_assembly.dart:186-202`） |
| 新建流程：选协议 → 定手动组 → 表单；`kManualCreatableProtocols` | `manual_node_flow.dart` + `protocol_form.dart:712` |

### 2. 定案

#### D1 数据模型 — chain 实体照存 `proxy_entities`，payload = chain 定义 JSON

- `type = 'chain'`；`payload` 存 `{"proxies": ["tag1","tag2",…]}`（**tag 引用**，不是 NekoBox 的 id）。
  记档差异：NekoBox 用 Long id，本项目实体身份本来就是 tag（内核配置、选中、stale 全按 tag），
  改用 tag 引用可让组装层零 join 展平；id 引用没有额外好处（跨组引用手动节点用 tag 更直接）。
- `customOutbound`/`customConfig` 列照常可用（与其他节点同语义）。
- **不迁移 schema**（不排 v9）：零新列。
- chain 实体落在手动组（type=basic），所以天然走 `manualNodes()` 追加进任何订阅组装 ——
  这与「NekoBox 的配置由整个 DB 现场构建、所有 chain 常在」**语义对齐**。
- 展平/方向照 NekoBox：`proxies` UI 序 = 流量经过顺序（第一行入口，最后一行落地）；
  嵌套 chain 递归展开；`asReversed()` 后 build。frontProxy/landingProxy（组级前后置）**本期不启用**
  （组列已预留但从未有 UI，属独立功能）。

#### D2 组装算法 — `buildChainOutbounds`（新纯函数，进 config_assembly.dart）

为每个 chain 实体生成一串出站，全部 tag 带 `§hide§` **除了落地那一条**：

```
输入：chain 实体 c（tag=C，proxies=[p0..pn-1] UI 序）、全实体 tag→payload 索引、
      每成员的「独立出站 tag」（成员若已是普通实体，其自己的出站 tag = 成员 tag）
展平：递归展开嵌套 chain（成员引用另一个 chain 实体 ⇒ 用它的 proxies 展开；环检测见 D3）
build 序 = [pn-1, …, p0]（asReversed，落地在 build index 0）
成员出站 tag 命名：`c-<chainTag>-<成员tag>`；落地（build index 0 / UI 序最后一行）：
  `chain:<chainTag>`（不带 §hide§ —— 它是路由/选中真正指向的 tag）
连接：build 序 index>0 的成员出站 `detour = 上一条 build 出站的 tag`
      （sing-box DialerOptions 语义：**本出站拨号要穿过 detour 指向的出站**。
      NekoBox ConfigBuilder.kt:311 `pastOutbound.detour = tagOut`：靠落地侧的出站
      穿过靠入口侧的出站 ⇒ build 序每条穿过下一条（更靠入口），末条（= UI 第一行 =
      入口）无 detour 直连。流量：客户端 → 入口 → … → 落地 → 目标）

> **⚠ 2026-09-21 内核级验证抓出的方向 bug（已修）**：第一版实现把 detour 写反了
> （入口 detour→落地、落地无 detour），check 单元断言还把错误方向固化——选中
> `chain:x` 后流量直连落地服务器，整条链被静默旁路。内核级对账 NekoBox 源码
> （ConfigBuilder.kt:311 + sing-box detour 语义）抓出，v2 修正为：
> **build index 0（落地）detour→index 1，…，最后一条（入口）无 detour**。
> 同名重复成员第二次起加 `#N` 后缀防 tag 撞车（§hide§ 恒在末尾）。
> 实证：HiddifyCli run7 curl 经 select→`chain:us-hk-us` 出口 = 落地节点出口
> 64.204.26.182（≠US 入口独立出口 23.134.76.66 ⇒ 未旁路），三段链逐跳日志可见。
```

关键映射（NekoBox → 本项目）：
- NekoBox 的 `TAG_PROXY="proxy"` → 本项目**没有固定 TAG_PROXY**（路由 final 固定指 `select`，
  切节点 = `SelectOutboundRequest(select, tag)`）。所以落地出站必须**不带 §hide§**、
  成为 select 组的一个可见成员 —— 选中 chain 即把 selector 指到 `chain:<tag>`。这是本模型下
  「选中 = 生效」的唯一通路（比 NekoBox 更收敛：连 selector 全量建链都简化了——每条 chain 只需
  一个可见 tag）。
- NekoBox 的 `g-<id>`（入口 needGlobal）→ 本项目**不需要**：那是 NekoBox 为了「同节点被多条链
  复用时共享出站实例」的内存优化 + bypassDNS 收集，本项目内核按 tag 全量重建，复用无意义，
  每跳独立出站即可（tag 里带 chainTag 天然隔离）。
- 中间跳/入口出站 tag 全部带 `§hide§` ⇒ 进配置、不进 select/balance 组、UI 看不到 ——
  与 NekoBox「中间跳不该出现在可切换列表」行为一致。
- 成员出站定义 = 成员实体 payload 深拷贝 + `tag` 换成 chain 成员 tag + `detour` + 该实体的
  `customOutbound` deepMerge（NekoBox :404 同构）。成员是 endpoint 型（wireguard）时**排除**：
  endpoint 不能做 chain 中间跳（NekoBox 的 WireGuardBean 虽是 outbound 形态，本项目内核是
  stub，乱拼必炸）——UI 选择器与组装层双重拦截。
- chain 自身的 `customOutbound`：deepMerge 进**落地出站**（NekoBox 对 chain bean 本身没有
  customOutbound 概念——`_hack_custom_config` 用的是每个成员 bean 的；但本项目实体模型统一，
  chain 实体也有这两列，合并点选落地 = 「对最终出站做覆写」的直觉语义。记档差异）。

#### D3 循环引用防护（NekoBox ChainSettingsActivity.kt:181-204 同构）

- 编辑/保存时递归检查：候选成员（展开后）不得包含正在编辑的 chain 自身 tag（直接或嵌套）。
  NekoBox 只在双方 type==8 时比较；本项目 chain 成员引用是 tag，直接比较 tag 字符串即可覆盖。
- 组装期兜底：展平时做 `visiting` 集合（DFS 灰集），发现环 ⇒ **整条 chain 跳过** + 记日志，
  不让它拖死启动（宁可这条链不生效，不能整份配置失败）。

#### D4 选中/启动管线 — 零新代码通路

- chain 落地出站是普通可见成员 ⇒ 现有 `SelectedProxyStore`（存 `chain:<tag>`）+ 内核重建后
  `SelectOutboundRequest(select, tag)` 原样可用。选中持久化、重连保持、UI 勾选全复用。
- raw 通道（customConfig 全局覆写）不感知 chain —— 它在内核拼装后做根合并，chain 出站早已
  在实体文件里。
- chain 实体的 `customConfig`（根配置覆写）：切片 8.5 的 `selectedNodeConfig` 通路按 tag 查实体
  （`nodeByTagAnyGroup`），chain tag 一样能查到 ⇒ 自动生效，零改动。

#### D5 UI 入口与编辑页

- **新建**：`kManualCreatableProtocols` 加 `'chain'`（菜单位置照 NekoBox add_profile_menu 的
  `action_new_chain`：手动设置子菜单内）；显示名 `Proxy Chain`（strings.xml:226 `proxy_chain`）。
  chain 不是协议表单 ⇒ `manual_node_flow` 对它特判：跳过 `showProtocolCreateSheet`，直接开
  **ChainSettings 页**（新建模式：空列表）。
- **ChainSettings 页**（新文件 `chain_settings_page.dart`，对齐 NekoBox ChainSettingsActivity）：
  - 名字输入（= 实体 tag；新建时缺省 `Chain <随机短码>`，对齐 NekoBox displayName 缺省语义）
  - 成员列表（ReorderableListView 长按拖排序 = ItemTouchHelper；左滑删除 = Dismissable）
  - 「添加节点」行（NekoBox AddHolder）：点按弹节点选择对话框 —— 列出**全部可选实体**
    （手动组 + 当前订阅组，排除 endpoint 型、排除其他 chain 的落地 tag？——不，NekoBox 允许
    chain 嵌 chain，**保留嵌套**），循环引用候选置灰 + 提示（circular_reference 同构）
  - 点已有成员 = 替换模式（NekoBox `replacing`：选新节点替换该行）—— 照做
  - 保存 = 落库（新建 createNode / 编辑 updateNodePayload）+ 提示内核换配置
- **无分享**：chain 实体不提供分享/QR（`haveLink()=false` 对齐）——分享菜单对 type=chain 隐藏。
- **列表展示**：proxies 页 chain 行显示成员链摘要（NekoBox displayType→chainName：
  `p1 ➔ p2 ➔ p3` 形态），点 ✎ 进 ChainSettings 编辑而非协议表单。

#### D6 明确不做（记档，防伪欠账）

- external 插件成员（needExternal/mapping inbound）：hiddify 芯无插件机制，NekoBox 分支不移植。
- frontProxy/landingProxy：组级前后置代理，列已预留但 UI/语义属独立功能，本期不启用。
- mux 单次限制：本项目成员出站各自带自己的 mux 设置（payload 里），无 NekoBox 的「链上复用
  一个 mux」问题，不额外处理。
- `§default§` 技巧：内核支持但本项目选中通路已是 SelectOutboundRequest，不引入。

### 3. 实现清单（Task #31 按此执行）

1. `config_assembly.dart`：新增 `buildChainOutbounds()` 纯函数（展平 + detour + §hide§ tag +
   覆写合并 + 环兜底）；`applyEntitiesToOutbounds` 接 chain 实体（先拆桶：chain / node / endpoint）。
2. `proxy_entity_repository.dart`：`chainNodes()`（type=='chain' 的手动实体）、
   `saveChain()`（create/update）、成员 payload 编解码 helper（`{"proxies":[…]}`）。
3. UI：`chain_settings_page.dart`（名字 + 拖排序/滑删/添加/替换成员 + 循环引用置灰）；
   `manual_node_flow` 特判 chain；proxies 列表行 chain 摘要 + ✎ 路由；分享菜单 chain 隐藏。
4. 翻译键：chain 相关（`pages.proxies.chain*` / 循环引用提示）。
5. 校验：`tool/check_config_assembly.dart` 扩展 chain 用例（展平顺序/方向/tag/detour/§hide§/
   环兜底/endpoint 拒绝）；`dart analyze lib test tool`；`flutter test`（先 unset 代理变量）。

### 4. 风险与回退

- 组装失败（含环兜底触发）⇒ `applyEntitiesToOutbounds` 返回 null 或跳过该 chain，回落现状路径
  （与批次 8「不因组装失败而无法连接」同原则）。
- chain 落地出站若与现有节点 tag 撞名（用户把节点命名为 `chain:xxx`）：`chain:` 前缀保留字，
  createNode 层拒绝用户以 `chain:` 开头的普通节点 tag（与 `§hide§` 同待遇）。
- 单元级：buildChainOutbounds 是纯函数，check 脚本可直接断言全部语义，不依赖实机。
  实机验证（选中 chain 真连）挂常规验收清单。

---

