# 批次 9 设计定案：WireGuard 表单 + endpoints 通路

日期：2026-09-18　|　前置：批次 8（custom_config，`cac9fb4e`）　|　规格源：NekoBoxForAndroid（唯一）

## 0. 一句话

给 ⋮ 手动菜单补上第 13 项 WireGuard：表单字段 1:1 照 NekoBox `wireguard_preferences.xml`（8 字段），
产物形态按**内核现实**（endpoint，非 NekoBox 的 legacy outbound），并把 Dart 应用侧「endpoints 通路」
从零打通（组装 / 派生 / 解析 / 判据四处）。

## 1. 内核事实（全部已读源码核实，hiddify-core）

| # | 事实 | 出处 |
|---|---|---|
| K1 | legacy wireguard **outbound 是纯 stub**：注册为 `StubOptions`，启动即报错 "deprecated in 1.11.0 and removed in 1.13.0, use WireGuard endpoint instead"。`protocol/wireguard/outbound.go` 里那份完整 legacy 实现是死代码（`include/wireguard.go` 只调 `RegisterEndpoint`，无人调它的 `RegisterOutbound`） | `include/registry.go:200-201`、`include/wireguard.go` |
| K2 | 正确形态 = **endpoint**：`WireGuardEndpointOptions`。内核 `Parse` 透传 JSON `endpoints` 字段；`setOutbounds` 处理 `input.Endpoints`（过滤预定义 tag / WARP 去重 / `patchEndpoint` / 收 tag） | `option/wireguard.go:11-37`、`v2/config/parser.go:75-77`、`builder.go:220-257` |
| K3 | **组可以引用 endpoint tag**（内核原生）：`adapter.Endpoint` 内嵌 `Outbound` 接口；outbound manager `Outbound(tag)` 未命中回落 `endpoint.Get(tag)`；builder 对 endpoint 也收非 `§hide§` tag 进 selector/balancer 成员 | `adapter/endpoint.go:10-15`、`adapter/outbound/manager.go:201-209`、`builder.go:252-254` |
| K4 | `patchWarp(final=true)` 对 `type==wireguard` 的 endpoint 有 WARP 特化，但**只命中特殊值**（`peers[0].address ∈ {auto,default,random,auto4,auto6,被墙域名}` 或 `port==0`）；真实地址/端口的普通 wg endpoint 原样通过 | `v2/config/warp.go:253-300` |
| K5 | `address` 字段是 `badoption.Listable[netip.Prefix]`，反序列化走 `netip.ParsePrefix` —— **裸 IP（无 `/掩码`）被拒**（`Prefixable` 才容裸 IP，本结构不是） | sing `badoption/netip.go`（v0.8.11） |
| K6 | `reserved` 是 `[]uint8`（= []byte）：JSON 收**数字数组**或 **base64 字符串** 两形态 | `option/wireguard.go:36` |
| K7 | 订阅链接 `wg://|wireguard://|warp://|awg://` 经内核 Parse（ray2sing `AWGSingbox`）**已自动产 endpoint 进 endpoints 段** —— 订阅侧无需 Dart 做任何事；缺口只在应用侧实体管理 | `ray2sing/convert.go:50-54`、`awg.go:207-376` |

### 内核 endpoint JSON 形态（表单产物目标）

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

## 2. NekoBox 规格 → 内核形态的字段映射

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

### reserved 的归一决策

NekoBox `genReserved`：3 个数字 → b64 单行字符串，否则原样 —— 那是为适配它手写镜像类里
`reserved: String` 的约束。我们内核是 `[]uint8`（K6），数字数组是 ray2sing/内核生态原生形态
（`awg.go:341-349` 同款）。定案：表单收「逗号/换行分隔的 0-255 数字」，写入产**数字数组**；
读回数组 join 成逗号串。不是 3 数字也接受（1~n 个），非数字报错拒存。b64 串输入不支持
（用户如拿到 b64，粘贴到内核或其他工具都能转数字；表单不做双向 b64 猜测）。

### localAddress 的掩码决策

K5：裸 IP 被内核拒。NekoBox 对 localAddress 也是**原样透传**（`listByLineOrComma` 不补掩码），
默认 Bean 值自带 `/32`。定案：stringList 原样透传 + 翻译 hint 说明 CIDR 形态，不做自动补掩码。

## 3. Dart 侧 endpoints 通路（四处 + 判据）

### 3.1 判据（runtime_outbound_tags.dart）

- `isNodeOutbound` **排除 `wireguard`**（它不再可能是合法 outbounds 节点：K1 必报错；
  排除后派生/解析/组装三消费者一致，legacy wg 不再被当节点派生成读不出字段的实体）
- 新增 `kEndpointOutboundTypes = {'wireguard'}` + `isNodeEndpoint(type)`

### 3.2 组装（config_assembly.dart，`applyEntitiesToOutbounds`）

实体按 `isNodeEndpoint` 拆两桶：

1. **outbounds 段**（照旧逻辑，只喂非 endpoint 实体）：覆盖/追加/按 staleTags 删除；
   另外**剔除基准 outbounds 里的 `type==wireguard`**（K1：留着 = 这份配置启动必炸；剔除反而救活订阅；
   记 removed 计数）。不做 legacy→endpoint 自动迁移（罕见场景，YAGNI，记档）。
2. **endpoints 段**（新）：基准 `config['endpoints']`（可缺省）按 tag 做 endpoint 实体的
   覆盖/删除（判据同 stale 思路：基准 endpoints 里是 wireguard endpoint 而实体集合没有 → 删；
   基准没有的 endpoint 实体 → 追加在末尾）；基准无 endpoints 段且有 endpoint 实体时新建数组。

组不用动：输入里的组照旧透传，内核重建组时自己收 endpoint tag（K3）。

### 3.3 派生（proxy_entity_import.dart，`deriveProxyGroupFromConfig`）

outbounds 遍历（isNodeOutbound 已排除 wg）+ **endpoints 遍历**（`isNodeEndpoint` → 实体，
payload 整条留存）。

### 3.4 判重（`dedupKeyOf`）

endpoint payload 无顶层 `server`/`server_port` → 现判据返回 null（天然放行，安全）。
补一个分支对齐 NekoBox 口径：payload 有 `peers[0]` 时用 `peers[0].address|port|type`。

### 3.5 解析列表（offline_proxy_parser.dart）

- `parseSubscriptionGroup`：endpoints 遍历产 `OutboundInfo`（host/port 取 `peers[0]`）
- `serverAddressOfPayload`：endpoint payload → `peers[0].address/port`（节点卡地址行、
  列表构建共用；tcpPing 本就被 `canTcpPing('wireguard')==false` 排除）

### 3.6 存储与通道（无需改 schema / repo）

endpoint 实体复用 `proxy_entities` 表：`type='wireguard'`、payload = 整条 endpoint JSON。
`assembleOutboundsForProfile` 不改 —— 它把实体行原样转 `ImportedProxyEntity`，拆桶在组装函数内部。
手动新建 → `createNode` → 组装 endpoints 段 → `_reloadCoreIfAffected` 重载内核，链路全部现成。

## 4. 表单数据层（protocol_form.dart）

- `_wireguardSpec`：§2 的 8 字段 + 路径（`peers` 数组用 int 下标 0，`_set` 已支持 —— mieru 先例）
- 新 `ProtocolFieldKind.integerList`：apply 时逗号/换行 split → `int.tryParse`（失败 return null）
  → `List<int>`；read 走 `_stringify`（List 递归 join，现成）；validate 对每元素 tryParse
- `kManualCreatableProtocols` 加 `wireguard`（NekoBox add_profile_menu 第 15 项 wg）→ 13 项
- `protocolDisplayName` 加 `'wireguard' => 'WireGuard'`
- 种子 `protocolSeedPayload('wireguard')` = `{'mtu': 1420, 'peers': [{}]}`（NekoBox defaultValue +
  peers[0] 路径占位，同 mieru portBindings 占位逻辑）
- modal：integerList 渲染走 text 形态分支（与 integer/text/stringList 并列）；label switch 加 5 个新 id

## 5. 翻译（新增 5 key ×2 语言）

`pages.proxies.form.localAddress`（本地地址 / Local Address）、`privateKey`（私钥 / Private Key）、
`peerPublicKey`（对端公钥 / Peer Public Key）、`peerPreSharedKey`（预共享密钥 / Pre-Shared Key）、
`reserved`（Reserved / Reserved）。slang 全量 build_runner 生成（批次 8 教训：`--build-filter` 会漏 `lib/gen/`）。

## 6. 不做 / 记档

- legacy wg outbound → endpoint 自动迁移（罕见；基准里 legacy wg 由组装剔除兜底）
- `listen_port` / `workers` / `system` / `noise` / `awg`（AmneziaWG 参数）/ `udp_timeout`：
  NekoBox 表单没有（AWG 是 SagerNet 生态的独立格式，`awg://` 由订阅解析走 ray2sing，不经表单）
- WARP 表单（`warp://`）：内核 `Warp.EnableWarp` 已有专用通道，订阅里的 warp:// 经 ray2sing 自动解析；
  手动编辑 WARP 凭据是另一个批次的事

## 7. 验证口径

1. `dart run tool/check_protocol_form.dart`：wireguard 读值/写回/往返幂等/integerList 校验/种子
2. `dart run tool/check_config_assembly.dart`：endpoints 覆盖/追加/stale/legacy wg 剔除/两段并存
3. `dart analyze lib test tool` 0 issue
4. 全量 build_runner（翻译）后 `unset 代理变量 && flutter test` 存量全绿
