# 实体线移植记录（2026-09-16）

> 起因：用户要求「当前项目改造 —— 以 NekoBoxForAndroid 规格、复用副本机制、参考 Throne、自己实现」。
> 本文记录**评估判定 + 移植执行 + 校验 + 后续缺口**。执行结果与证据均在本文内。

---

## 1. 核心判定：不是"新老版本"，是"两条线在同一分叉点各走一个方向"

| 资产 | 路径 | HEAD | 走的方向 |
|---|---|---|---|
| 改造主体 | `S:\test\1\hiddify-app` | `99cef297`（= origin/my） | **UI 线**：NekoBox 壳复刻 + 分层重构 + drawer header |
| 快照 | `S:\test\1\hiddify-app - 副本` | `99cef297`，**与主体逐字节一致** | 纯回滚快照，非独立资产 |
| 实体线 | `S:\test\hiddify-app` | `620125ef`（"restore after .git object loss"） | **实体线**：drift v7 实体层 + 协议表单 + 分组页 + 配置组装 + 校验脚本 |
| 规格源 | `S:\test\NekoBoxForAndroid` | — | Kotlin，`res/menu/*.xml` 17 份 + `res/xml/*_preferences.xml` |
| 架构参照 | `S:\test\Throne`（Formerly Nekoray，Qt/C++） | — | `src/configs/generate.cpp`、`OutboundFactory.cpp`、`src/database/entities/` |

### 血缘事实（在当前仓库内验证）
- 共同祖先 `ade99eaa`，**已被主体 HEAD `99cef297` 完整包含**（`git log HEAD..ade99eaa` 为空，反向 29 个提交）
- 实体线 `620125ef` 的父提交即 `ade99eaa`
- **关键**：`620125ef` 的树 ⊃ `99cef297` 的树。证据：`nav_items.dart` 的差异是 `620125ef` **新增** `groups` 导航项
  → **实体线是在 UI 线之上继续做的，"老项目"其实内容更新**
- 实体线对象在主体仓库可达（`git cat-file -e 620125ef:<path>` 成功）→ **`.git` 损坏不影响提取**

### 差量组成（`git diff 99cef297 620125ef`）
```
152 files changed, 13000 insertions(+), 1401 deletions(-)
  47 A（新增） / 96 M（修改） / 6 R（重命名） / 3 D（删除）
```
质量分布：`lib/features/proxy` +4560/−521、`lib/core/db` +307 纯增、`lib/features/connection` +143/−34。
UI 侧 97 个 M 文件全是小增量（settings +49/−28、route_rules +14/−11、log +9/−5），**无回退迹象**。

6 个重命名全部是同向架构收敛（dialog/sheet 从 `core/router/` 搬进各自 feature），
对应 `docs/design/layering.md` 记录的 `core→features` 逆依赖 47 → 0。

---

## 2. 移植执行

### 2.1 安全前置
```
git branch bak-pre-entity-merge 99cef297     # 一键回退点
```
> 注：本机 Git for Windows 2.55 **无法创建带斜杠的分支名**（静默失败，exit 0 但 ref 未落盘），故用扁平命名。

### 2.2 应用差量
```
git read-tree -u -m HEAD 620125ef
git checkout-index -a -f -u
```
**第二行是必需的，原因是本机一个真实缺陷**：`read-tree -u` 在该环境会把两树间**内容完全相同**的
257 个文件也从工作树删掉（索引始终正确 —— `git diff-files` 报 `D`，但 `cat-file` 两树都有）。
用 `checkout-index` 把索引重新物化即可修复。**下次做同类树级操作时务必带这一行，并做下面的校验。**

### 2.3 校验结果（全部通过）
| 校验项 | 结果 |
|---|---|
| 工作树 vs `620125ef` 树 | `git diff 620125ef` **为空** → 逐字节一致 |
| 工作树 vs HEAD 差量 | **152 files, +13000 / −1401**（与两树 diff 完全吻合） |
| 索引树哈希 | `bb500aaf9b71ee7336d019dae32ab93b5eb0c6d5` == `620125ef^{tree}` |

### 2.4 环境绕行（本机特有）
- bash 需显式 `export PATH="/usr/bin:/bin:/c/Windows/System32:/c/Windows:$PATH"`，否则 coreutils 全缺
- **`flutter` 工具链被沙箱拦截**：Flutter doctor 校验器要调 `reg.exe`（程序黑名单）→ `flutter pub get` 崩溃。
  **绕法：改用 `dart pub get` / `dart run build_runner` / `dart analyze`**，不经过 flutter 工具。
- pub 走镜像：`PUB_HOSTED_URL=https://pub.flutter-io.cn`

---

## 3. 移植后本项目新增的能力（实体线产出）

### 3.1 数据层 —— 让"应用侧持有配置真源"
- **drift v7**：新增 `ProxyGroups` / `ProxyEntities` 两表（payload 含完整凭据），`db.steps.dart` +307 行迁移
- `config_assembly.dart`（187 行）—— **核心机制**。关键结论写在文件头：
  内核 `v2/config/builder.go:130-371` 每次启动都**重建所有组**（selector `select` + balancer `balance`/`lowest`），
  应用写进去的组会被丢掉。**所以应用只需裁量"节点出站那一段"**，组不碰。
  `staleNodeTags()` 解决"删了节点内核里还在"（界面 47 / 内核 48）的根因 —— 基准里那段必须由实体说了算。
- `proxy_entity_repository.dart`（746 行）：组/节点 CRUD，默认值逐项照 NekoBox `ProxyGroup.kt:14-25`
- `proxy_entity_import.dart`、`runtime_outbound_tags.dart`（"什么算节点/组/隐藏出站"的判据收敛到一处）、
  `live_proxy_join.dart`、`selected_proxy_store.dart`、`selection_reconcile.dart`、`tcp_ping.dart`

### 3.2 接口层
- `protocol_form.dart`（627 行）：协议表单数据层，4 份规格（anytls / vless[含 vmess 复用] / hysteria2 / shadowsocks），
  字段与下拉取值逐项照 `res/xml/*_preferences.xml` + `res/values/arrays.xml`
- `protocol_form_modal.dart`（451 行）、`manual_node_flow.dart`：表单 UI + 手动新建流程
- `groups_page.dart`（460 行）：对应 NekoBox `GroupFragment` + `add_group_menu`

### 3.3 校验资产（12 个纯 Dart 断言脚本，`dart run` 可跑）
`check_protocol_form`（69 项断言）/ `check_config_assembly` / `check_dedup` / `check_tcp_ping` /
`check_unavailable` / `check_group_reorder`（17 项）/ `check_entity_import` / `check_selection_reconcile` /
`check_live_proxy_join` / `check_async_lock` / `check_insecure_request` / `check_offline_proxy_parser`

### 3.4 规格与审计文档（当前工作区此前只有一份 `layering.md`）
`docs/design/`：`nekobox-parity.md`（980 行，字段级规格，唯一准绳）/ `nekobox-priority.md`（246 行，执行顺序表）/
`nekobox-gap-2026-09-16.md`（对照差距清单）/ `connection-model.md` / `core-architecture-comparison.md` /
`proxy-model-root-fix.md` / `layering.md`
`docs/audit/`：`nekobox-function-matrix.md`（四分类矩阵）/ `full-logic-audit` / `logic-layer-audit` / `code-audit`

---

## 4. Throne（→ 前身 Nekoray）的参照点

实体线的 `backup/nekobox-parity.md §4.7` 已用 **`S:/test/nekoray` 4.0.1** 回答过"Android 特有能力在桌面的正统形态"。
`S:\test\Throne` 是同源后继（README: "Throne (Formerly Nekoray)"），结构一一对应：

| Throne（C++） | 本项目（Dart） | 说明 |
|---|---|---|
| `src/configs/generate.cpp` | `features/proxy/data/config_assembly.dart` | 配置生成/组装 |
| `src/configs/common/OutboundFactory.cpp`、`src/configs/outbounds/` | `features/proxy/data/protocol_form.dart` | 按协议构造出站 |
| `src/database/entities/{Group,Profile,RouteProfile,RouteRule}.cpp` | `ProxyGroups` / `ProxyEntities` / `RuleEntity` | 实体模型 |
| `src/configs/sub/` | `features/profile/data/` | 订阅处理 |
| `src/stats/{traffic,connectionLister,autoselector}/` | `features/stats/` | 流量/连接列表/自动选择 |

**参照价值**：Throne 是"应用侧持有实体 + 自建配置组装"的完整桌面实现，正是本项目第 3 档架构的 C++ 对照物。
已核过的事实写进了 `core-architecture-comparison.md`（NekoBox vs hiddify 六维对照，含"配置真源方向相反"这一根因）。

---

## 5. 后续缺口

> **重要**：`nekobox-gap-2026-09-16.md`（写于 09-16 10:52）**已过时** —— 它成文时实体线还有两项没做完，
> 之后被补齐了。下面每一项都经**代码复核**（非引用文档），复核命令写在每项里。

### 5.1 已确认做完（不必再做）

| 项 | 复核证据 |
|---|---|
| **代理页 ⋮ 菜单 6 项全接线** | `proxies_overview_page.dart:123-257`：`clearResults` / `dedup` / `tcpPing` / `updateSubscriptions` / 删不可用 / 排序 + urlTest，均有 `PopupMenuItem` 与处理分支；`tcpPingNodes` 落在 `proxies_overview_notifier.dart:571` |
| **分组页 ⋮ 动作菜单** | `groups_page.dart:230-266`：分享订阅链接（订阅组限定，子菜单 URL 到剪贴板 / 二维码）/ 导出节点（剪贴板 / 文件）/ 清空分组 |
| **分组拖拽排序** | `groups_page.dart:78` `ReorderableListView.builder` + `:171` `moveGroups`；repo `:378` |

### 5.2 仍缺（按影响排序）

1. **协议表单 4 → 12**（最明确的一块）
   现仅 `kManualCreatableProtocols = ['shadowsocks','vless','hysteria2','anytls']`（`protocol_form.dart:323`）。
   缺 8 份：`socks` / `ssh` / `tuic` / `shadowtls` / `mieru` / `naive` / `trojan_go` / `wireguard`。
   框架已就位（`ProtocolFormSpec` + `containers` 分节），**按 `nekobox-priority.md` 批次 2 补规格数据即可**，
   每份都能独立交付并配 `check_protocol_form.dart` 断言。
2. **设置项缺**：`speedInterval` / `showDirectSpeed` / `showGroupInNotification` / `alwaysShowAddress`
   （通知与速度显示类）、`domain_strategy_for_server` / `enableDnsRouting`（DNS 策略）、
   `networkChangeResetConnections` / `wakeResetConnections`（重置连接类）。
   > 注：其中通知类多数在 `nekobox-parity.md §4.7` 已用 nekoray 对照判为"桌面用托盘 tooltip 已够用，不做独立开关"，
   > 落地前先看该节的结论文档，别重复劳动。
3. **连接测试进度对话框**：NekoBox `TestDialog`（nowTesting + N/M 进度 + 最小化为通知 + 可取消）。
   本项目有 urltest/tcpPing 但无进度与取消。
4. **节点级分享**：QR（standard / SN）+ 链接导出。分组级已有，节点级缺。
5. **FAQ 入口**（`nekobox-parity.md` 记录 `nav_faq` 缺；`nav_tuiguang` 已定为🅝不移植）。

### 待拍板项 → 已按参考优先级定案（2026-09-17，见 §5.3）

---

## 6. 下一步

- [ ] `dart analyze` 确认移植后 0 error
- [ ] 跑 12 个 `check_*.dart` 回归
- [ ] 语义化提交
- [ ] 按 §5 顺序分批次推进（每批一提交，改前先核对 `nekobox-parity.md` 原版行为）

---

## 5.3 两个"待拍板项"按参考优先级定案（2026-09-17）

> 用户指出：参考优先级（NekoBox 规格 → 复用已有机制 → 参考 Throne → 自己实现）本身就是决策规则。
> 以下每步给源码依据。

### ① SN Link：第 1 优先级（NekoBox 规格）直接否掉 —— 它是 Kryo 专有格式，不该复刻

规格源 `fmt/UniversalFmt.kt:21-34`：
```kotlin
fun AbstractBean.toUniversalLink(): String {
    var link = "sn://"
    link += TypeMap.reversed[ProxyEntity().putBean(this).type]
    link += "?"
    link += Util.b64EncodeUrlSafe(Util.zlibCompress(KryoConverters.serialize(this), 9))
    return link
}
```
机制：`sn://<type>?<b64url(zlib(Kryo 序列化 bean))>`。载荷不是 URI 字段，是
**Kryo 5.2.1 二进制 Java 对象序列化**（`KryoConverters.java:29-39`，`bean.serializeToBuffer`），
字段顺序 = 各 `*Bean.serializeToBuffer` 的写入序。

**判定**：
- 该格式**只有 NekoBox 全家（SagerNet/NekoBox/edndo 等）能解析**——解析端必须有同一套 Bean 类定义 + 同版本 Kryo。
- Dart 侧没有 Kryo；用 Flutter 重写一个 Kryo 编码器属于"自己实现"里的下下策，产出还是一个**生态内无人消费**的格式（hiddify 系订阅/分享根本不认 `sn://`）。
- 这正属于 NekoBox 里"实现栈绑死"的部分——与"推广位"同类，**1:1 复刻没有收益**。

**结论：SN Link 🅝 不移植。** 分享菜单的 SN 子项用**标准分享链接**顶上（这才是跨客户端通用格式）：
- NekoBox 自己也给标准链接：`ShadowsocksFmt.kt:77-91`（`ss://` + SIP002）、`V2RayFmt.kt:520`（vless/trojan）、`TuicFmt.kt:68`、`HysteriaFmt.kt:164`（hy2）、`SOCKSFmt.kt:46` 等。
- 已有机制（第 2 优先级）：ray2sing（内核子模块 `hiddify-core/ray2sing/ray2sing/`）是**链接→sing-box 出站**的正向解析，24 个协议文件，反向（出站→链接）确认不存在（全库 grep `Export|Sing2|sing2` 仅 `ParseUrl` 正向）。
- **实现方案**：出站 → 分享链接的**反向转换器在 Dart 侧自己写**（`lib/features/proxy/data/outbound_to_link.dart`，纯 Dart 可校验）。不做 Kryo，只做标准链接：ss(SIP002) / vless / vmess(base64 JSON) / trojan / hysteria2(hy2) / tuic / socks / http 八种起步，字段映射直接对照 NekoBox 各 `*Fmt.toUri()` + ray2sing 各 `*.go` 的解析逻辑（解析逻辑反过来写就是生成逻辑，两份源码互为规格）。每个转换配 `check_outbound_to_link.dart` 断言：**自己生成 → ray2sing 解析 → 出站等价**（往返幂等，同 protocol_form 的验收模式）。

### ② 路由：保留 hiddify 规则模型 + 补 NekoBox 的编辑 UI（不做规则集管线）

按优先级逐级推导：
- **第 1 优先级（NekoBox 规格）**：`route_preferences.xml` 是 9 字段的**单条规则**表单（routeName/domain/ip/port/source/sourcePort/network/protocol/outbound）。注意：NekoBox 的"规则集/Assets 管线"是**另一块**（`AssetsActivity` + `rulesProvider`），不在 route 表单里。
- **第 2 优先级（已有机制）**：hiddify 的 `RuleEntity` 模型**已具备全部 9 个字段**（`nekobox-function-matrix.md` §2.1 判定 Route 页 1:1，含预设规则）。缺的只是"新建/编辑规则的表单 UI"——是**暴露层缺口**，不是模型缺口。
- **第 3 优先级（Throne 参考）**：`src/database/entities/RouteRule.cpp` + `RouteProfile.cpp` 与 hiddify 的规则模型同构（实体即规则），印证 hiddify 方向没错——Throne 同样没有把 NekoBox Android 的 Assets 管线搬进桌面。

**结论：**
1. **本轮做**：按 `route_preferences.xml` 9 字段补"新建/编辑规则表单"（`ProtocolFormSpec` 框架直接复用，一个 spec + 一个 modal），1:1 对照，工作量小、收益直接。
2. **不做**：NekoBox 的 geo Assets 下载/更新管线（`AssetsActivity`）。hiddify 已有独立的 geo/路由资源机制（`docs/BUILD.md`、内核侧 assets），重复建设违反归一原则。若后续真需要"多套 geosite 源切换"，作为独立需求重新立项。
3. **后置**：`global_preferences.xml` 的 `rulesProvider` 键（它是 Assets 管线的设置项）——管线都不做，设置键自然悬置。

### 执行顺序更新（§5.2 之前加一条）
- **批次 2.5（新增，插在协议表单之后）**：路由规则新建/编辑表单（9 字段，复用 ProtocolFormSpec）。
- **SN Link 从缺口清单移除**；节点级分享 = QR(标准链接) + 复制标准链接 + 导出 JSON，全部依赖 `outbound_to_link.dart`。

## 6. 批次 2 执行记录：协议表单 4 → 10（2026-09-17）

### 6.1 内核支持矩阵（决定"哪些做、哪些不做"的依据）

逐协议查证 `hiddify-core/hiddify-sing-box/include/registry.go`（出站注册）+
`option/*.go`（JSON 选项结构）+ `ray2sing/ray2sing/`（链接解析）后的结论：

| 协议 | 内核支持 | 决定 |
|---|---|---|
| socks | 原生出站 `SOCKSOutboundOptions` | ✅ |
| ssh | 原生出站 `SSHOutboundOptions` | ✅ |
| tuic | 原生出站 `TUICOutboundOptions` | ✅ |
| shadowtls | 原生出站 `ShadowTLSOutboundOptions` | ✅ |
| mieru | **fork 专有** `MieruOutboundOptions`（上游没有） | ✅ |
| naive | 原生出站（`with_naive_outbound` 恒开，`Makefile:14`） | ✅ |
| trojan_go | **无出站注册**（NekoBox 靠外部二进制） | ❌ 不移植 |
| wireguard | outbound 已是 stub（1.13 移除，须走 endpoints）；手动节点 payload 只进 `outbounds` 通道 | ❌ 暂缓 |

**trojan_go 不移植的原理**：sing-box 从未实现过 trojan-go 协议（ trojan-go 的 ws/
shadowsocks 层与 trojan 是不同栈）；NekoBox 用独立二进制进程跑它，hiddify 没有
"外部二进制出站"机制。表单做了 payload 也无消费方，做=死代码。

**wireguard 暂缓的原理**：内核 1.13 起 WireGuard outbound 报错指向 endpoint
（`registry.go:200-202`）；`AWGSingbox` 产出的 endpoint 只在**链接解析**通路生效，
而手动节点实体 payload 走 `config_assembly` 的 `outbounds` 数组——两条通路尚未接通。
等 endpoint 通路打通后按 `WireGuardEndpointOptions` 补表单。

### 6.2 框架扩展（protocol_form.dart）

1. **路径元素从 `String` 扩成 `Object`**（`List<Object>`，int = 数组下标）：
   mieru 的端口/协议落 `portBindings[0]`（内核 `validateMieruOptions`：bindings
   非空即合法，`server_port` 留 0）。`_get/_set/_remove/_pruneEmptyMaps` 相应支持。
2. **新增 `ProtocolField.writeValues`**（表单取值 → JSON 值映射，null=删键）：
   - shadowtls `version`：内核是 **int**，"2"/"3" 必须写成 2/3（严格解析拒字符串）；
   - naive `serverProtocol`：内核 `quic` 是 **bool**，https→删键（内核默认非 QUIC）、
     quic→true；读回时缺键反查为 "https"（不显示"未设置"）。

### 6.3 六份新 spec 的字段来源（全部交叉核对 XML + Fmt + 内核选项）

- **socks**：版本直接列 `"4"/"4a"/"5"`（内核 `socks.ParseVersion` 只认这三个串，
  跳过 NekoBox 的整数中间层，同 `kPacketEncodings` 的处理）。
- **ssh**：`private_key` 用 **text** 不用 stringList——PEM 含换行，按行/逗号拆会
  毁掉密钥；`serverCertificates`(标题 ssh_public_key) → 内核 `host_key`；
  `serverAuthType` 下拉不移植（sing-box 先试公钥再试密码，无需 UI 分支）。
- **tuic**：恒用 TLS（`TuicFmt.kt:84-97` 写死 enabled），种子带 `tls.enabled`；
  v4 被 `TuicFmt.kt:72` 显式拒绝 → `protocolVersion` 不进表单。
- **shadowtls**：`version` int 化（writeValues）；恒用 TLS（Bean security="tls" 写死）。
- **mieru**：fork 专有选项结构；**`serverMTU` 不纳入**——内核 `MieruOutboundOptions`
  没有 mtu 键（sing-box 严格解析，未知键直接拒）。
- **naive**：`serverHeaders`/`sUoT` 不纳入——内核 `extra_headers` 是
  `map[string][]string`、`udp_over_tcp` 是对象，文本/布尔写不出正确形状；
  恒用 TLS（ray2sing security 缺省置 "tls"）。

### 6.4 校验

- `check_protocol_form.dart` 从 81 → **134 项断言**（+53）：六个协议各配往返幂等 +
  读值 + 改写 + 容器/种子断言；ssh 数组私钥归一成单串有专门断言（内核
  `Listable[string]` 等价，形状归一是有意的）。
- `dart analyze`（4 个改动文件）0 issue；12 个 check 脚本全 PASS 无回归。

### 6.5 菜单与文案

- `kManualCreatableProtocols`：4 → 10（socks / shadowsocks / vless / mieru / naive /
  hysteria2 / tuic / shadowtls / anytls / ssh），顺序照 `add_profile_menu.xml`。
- 显示名照 NekoBox `strings.xml` 的 `action_*`（SOCKS / SSH / TUIC / ShadowTLS /
  Mieru / Naïve）。
- 新增 7 个字段文案键（en / zh-CN / zh-TW 三份 `.i18n.json` + slang 重新生成）。

## 7. 批次 2.5 执行记录：路由规则表单核查 + 恢复应用分流（2026-09-17）

### 7.1 核查结论：§5.3 的"缺表单"判定已过时

§5.3（及 `nekobox-function-matrix.md` §2.1）判定"缺新建/编辑规则的表单 UI"，实际
核查后 **RulePage 编辑页在上游就是完整实现**（证据链）：

- `lib/features/route_rules/overview/rule_page.dart`：18 字段中 16 个已有控件
  （name/outbound/ruleSet/process×2/network/port×2/protocol/ipCidr×2/domain×4），
  多选/列表/单选/文本四类控件齐备；
- 路由已接线：FAB 新建 → `rule/new`，`RuleTile` 点击 → 编辑，`onExit` 自动保存
  （`routing_config_notifier.dart:196,204`）；
- 模型是 **protobuf `Rule`**（`route_rule.pb.dart`，18 tag）+ `RuleNotifier`
  （riverpod，字段级 update + validator），不是 drift `RuleEntity`——
  **比 NekoBox 的 9 字段更丰富**（domain 拆 exact/suffix/keyword/regex，process 拆
  name/path，多 ruleSet、protocol 枚举集）；
- `dart analyze lib/features/route_rules` 0 issue。

对 NekoBox 9 字段逐项对照后，**唯一真实缺口 = routePackages（规则级应用分流）**：

| NekoBox | hiddify 现状 | 处置 |
|---|---|---|
| routeName/domain/ip/port/source/sourcePort/network/protocol/outbound | 全有且更细 | 无需改动 |
| routePackages | **整链路被注释**（commit `205316b6`"replaced by per-app proxy"） | 本轮恢复 |
| serverConfig（规则级自定义配置） | 无对应模型 | 后置（见 §7.3） |

### 7.2 恢复 routePackages 的依据与改动

**依据**：NekoBox 自身就是"全局 per-app proxy 与规则级 packages 并存"
（`RuleEntity.packages: Set<String>` 与 per-app 设置互不替代）；hiddify 上游简化成
只有全局 per-app proxy 属功能裁剪，按 1:1 对照原则恢复。`installed_apps` 依赖仍在
`pubspec.yaml`（git 依赖 VB10/installed_apps），恢复成本仅取消注释 + 补 i18n。

改动（commit `8bc2228b`）：
- `android_apps_notifier.dart` / `android_apps_page.dart` 取消整文件注释；
  `Ref` 从 `hooks_riverpod` 来（项目惯例，`flutter_riverpod` 非直接依赖）、删
  `dio` 死导入；搜索框文案键 `t.common.search` → `t.pages.proxies.search`（键位
  在上游 i18n 重构中迁移过）；
- `rule_page.dart` 恢复 packageName 的 `SettingGenericList` 控件
  （`isPackageName: true` + `showPlatformWarning`）；
- 三个 i18n 文件补回 `androidApps` 5 键（pageTitle/showSystemApps/hideSystemApps/
  clearSelection/uninstalled），en/zh 值从 git 历史 `58ec2dcd` 恢复；
- build_runner 重新生成 `android_apps_notifier.g.dart`。

### 7.3 serverConfig 后置的理由

NekoBox 的 `serverConfig`（`EditConfigPreference`，规则级绑定一份自定义配置）要求
"规则 → 具体配置实体"的引用模型；hiddify 的 `Rule` protobuf 无此字段，Throne 同样
没有（其 `RouteRule.cpp` 只有 9 个匹配字段）。三方对照后本轮不做，避免为对齐而
发明模型。

### 7.4 校验

- `dart analyze` 全项目 **0 issue**；
- `check_protocol_form.dart` 134 项断言全 PASS（无回归）。
