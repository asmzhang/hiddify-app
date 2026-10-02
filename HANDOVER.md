# 交接文档 — hiddify-app（新机器迁移 + NekoBox UI 复刻）

> 写于 2026-09-14 晚，2026-09-22 刷新（新增阅读规则 + 定案清单 + 未验证清单；**同日二刷**：功能①⋮ 菜单 1:1 完成 + zh-CN 翻译基准定案 + slang 测试大坑 + 未推送提交盘点）。上一份 anytls 修复交接（D:\ 时代）已被本文取代,
> 旧版可在 git 历史找回：`git show 117f5397~40:HANDOVER.md` 附近。
> 目的：任何人（或没有上下文的 AI）读完就能接着干。

---

## 接手须知（先读：如何采信本文与记忆文件）

本文与 `.workbuddy/memory/MEMORY.md`（新会话自动注入）里的内容**不等于同等可信**。按三层采信：

| 层 | 内容特征 | 采信方式 |
|---|---|---|
| **A 实证事实** | 带 commit SHA / 测试名 / 命令复现路径 / 日志输出（本文 §1 环境事实、§2 提交清单、§4 大坑实录的复现步骤） | 可直接引用，因为可复现 |
| **B 所有者定案** | 见下方「定案清单」——是**项目所有者的决策**，不是技术真理 | 照办；实现细节可以优化；**方向性推翻必须先问用户** |
| **C 推断/评估** | 根因分析的因果解释、复刻口径百分比、性能印象、"应该没问题"类表述 | **视为待验证假设**，动手改代码前先用测试/日志/命令复现证据 |

原始证据链：`.workbuddy/memory/YYYY-MM-DD.md` 每日日志比 MEMORY.md 更细（含验证输出、命令、失败尝试），存疑时回溯它。

**如果你是新会话的 AI 且用户只说「继续」**：先读完本文与 MEMORY.md，按上表分层采信，然后从 §3「剩余」清单顶部选活，**先给方案再动手**；方案分歧按「NekoBox 规格 → 复用已有机制 → 参考 Throne → 自己实现」自行推导定案，不要把可推导的问题退回给用户。

快速验证工具（A 层结论的复现入口）：`make doctor`（环境）/ `flutter test test/`（Dart，**先 unset 代理变量**）/ `dart analyze lib test tool`（分目录）/ `go test ./...`（在 hiddify-core/）/ `HiddifyCli.exe run -c <cfg> -d <settings> --log info`（内核配置验证）。

---

## 0. 一句话现状

**工程完整可构建可测（Windows debug 版），NekoBox 复刻的可做项已全部落地（批次 1-14 + 审计 B/C/D + Go 1.27 升级）；主仓库与 core 子模块均全量推送**（远端 `origin/my` = `03420bad`，2026-10-01 ls-remote 实证 = 本地 HEAD；⑤协议表单字段级 P0 = `ba21921d`、P1 = `4c0c1da0`、P2 = `1a750b50`、**六缺口修复 = `15b41d37`**（vmess alterId/encryption + ECH 三协议 + tuic 中文标签/禁 SNI 置灰 + trojan 种子 TLS）+ 记档 `03420bad`；①手动新建节点链 L1 测试收口 = `9231100c`/`429bf873`；⑨小屏形态（协议/chain/config 弹层+主壳抽屉，360/320dp）= `4f77caee`+记档 `1ee7ad7b`；⑧9 语言翻译补全 = `17f32a0b`；⑥日志页 = `006b50b3`；④设置页 = `e0339608`），core 远端 my = `1075e82`。注：2026-09-30 洗订阅 token 历史（git filter-repo 重写全史）后 force push 重锚，全仓库旧 SHA 引用已按 commit-map 批量更新）；
2026-09-22 起 UI 复刻进入**「1:1 逐功能对比」新阶段（用户定案，见 §3.0#11）：功能①节点页 ⋮ 菜单已完成（`82a39b20`）——8 项权威顺序 + radio 排序子菜单 + 文案对齐 + 删「路由」项，L1 结构测试 5 用例 + 全量 111/111 绿；
**翻译策略定案（§3.0#12）：测试与验收一律以 zh-CN 为基准，en 仅作 slang base_locale 保键同步，其余 8 语言键已脱节（runtime 回退 en 不炸），翻译批次放最后。**
剩：8 语言翻译批次、~~日志页第二层（watchLogs gRPC 流建立）~~ **已完成（2026-09-30，`05c4e7a4`，见 §2）**、~~集成测试 smoke 重跑~~（已完成，见 §7）、wireguard 真实握手（用户定案暂缓，无凭据）、上游 PR（前置=洗 token 历史，已完成）、后续功能②③…。

> 接手前必读上方「接手须知」：本文内容分 A（实证事实）/ B（所有者定案，见 §3.0）/ C（推断待验证，见 §7）三层，采信方式各不同。

---

## 1. 环境事实（这台机器，照抄即用）

| 项 | 值 |
|---|---|
| 开发目录 | **`S:\test\1\hiddify-app`**（分支 `my`；老 `S:\test\hiddify-app` 是 git 损坏的历史项目，物理 HEAD 仍 `620125ef`——老仓未被 2026-09-30 洗历史重写、不含 `579b6fe8`；取实现：老仓 `git show 620125ef:<path>`，或主仓 `git show 579b6fe8:<path>`（重写后 restore 根线 npr-restore-root）无损取出） |
| UI 线快照 | `S:\test\1\hiddify-app - 副本`（与主体逐字节一致，回滚用） |
| 规格源 | `S:\test\NekoBoxForAndroid`（Kotlin 源码；menu/preferences XML 是唯一规格准绳） |
| 架构参照 | `S:\test\Throne`（C++；看 configs / database / stats 的组织方式） |
| 仓库 | 顶层 `asmzhang/hiddify-app` + 8 层子模块（hiddify-core / hiddify-sing-box / ray2sing / replace 下 4 个），**全部本地 `my` 分支跟踪 `origin/my`** |
| Flutter | **3.38.5，mise 管理**（`mise use -g flutter@3.38.5`）；pub 走 `pub.flutter-io.cn` 镜像 |
| Go | **1.27.x**（`mise use -g go@1.27.1`；仓库 `.mise.toml` 同源）。2026-09-22 重测结论：1.26 的 psiphon-tls 布局断言 panic 在 1.27 已消失（1.27.1 实测编 core + DLL 加载 + 内核启动零 panic），原 1.25 硬约束解除；**勿回退到 1.26**。`make doctor` 已改为查 1.27.x |
| cgo 编译器 | `C:\platform\llvm-mingw-20260908-ucrt-x86_64`（`make doctor` 能自动发现） |
| GOMODCACHE | 已固化 `go env -w GOMODCACHE=$env:USERPROFILE/go/pkg/mod2` |
| 网络代理 | `socks5h://127.0.0.1:7890` 可用 —— 核心库下载失败时给 curl 加 `--proxy` |
| proto 工具链 | **protoc 28.0 + protoc-gen-go v1.34.2 + protoc_plugin 23.0.0**（版本必须钉死，见 §4.3） |
| 测试订阅 | 见 `.workbuddy/tokens.md`（token 不入库：cpdd 39 anytls；yfjc 21 vless + 15 hysteria2，无 anytls 属正常） |
| 订阅 UA 机制 | App UA（`HiddifyNext/... sing-box v2ray`）→ 面板返回 sing-box JSON（anytls 保留）；浏览器 UA 会返回 Clash YAML（丢 anytls） |
| 深链导入 | `hiddify://import/<订阅URL>` → 弹确认框 + 预填 sheet。**有防零点击 SSRF 的确认设计，需人工点两次，不要绕过** |

---

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
- 批次 8 `b86d57f7` custom_config 全局自定义配置（两阶段 raw 通道，docs/design/custom-config-2026-09-18.md）
- 批次 9 `c0cc2171` wireguard endpoint 表单 + endpoints 通路（docs/design/wireguard-endpoint-2026-09-18.md；手动菜单 13 项）
- 切片 8.5 `1fc06b58` 节点级自定义配置覆写（customOutbound/customConfig 两列；drift v8）
- `7b10a467` 迁移测试补 v7→v8 覆盖
- **批次 10 `b13d7a16` chain 任意节点串联**（docs/design/chain-2026-09-20.md；type='chain' 实体 + buildChainOutbounds 组装 + ChainSettings 弹窗；手动菜单 +chain；复刻口径 ≈95%）
- **`142cfa29` chain detour 方向修正**（内核级验证抓出：v1 方向反了会被静默旁路；按 ConfigBuilder.kt:311 + sing-box DialerOptions 语义重写为落地穿中间跳→入口直连 + 同名成员 #N 防撞；HiddifyCli run7/run9 三断言全过——①配置启动 ②curl 出口=落地节点出口≠入口出口 ③§hide§ 不进 select 组。验证通道与坑见 .workbuddy/memory/2026-09-21.md）
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
- **`15b41d37` 协议表单六缺口修复（2026-10-01，已推送）**：字段级 spec（⑤ P0/P1/P2）把「规格矩阵有、实现无」的六处全数暴露 → 一次性补齐实现 + 同步测试。详见 §3「剩余」10 条目内「六缺口修复已收口」。关键项：vmess 独立 `_vmessSpec`（此前**只有引用没有定义，编译即断**）、ECH 两字段进 vless/trojan/http、trojan 种子 TLS 默认开、tuic 四字段中文词条 + `disabledBy` 置灰机制、`protocolFormLayout` 分节重复标题缺陷（同一 section 渲染 3 次）。19 files/+411/−128；全量 273/273，analyze lib+test 双清零。

---

## 3. 进度与剩余（按优先级）

### 3.0 定案清单（B 层：所有者决策，照办不推翻；实现细节可优化，方向性推翻先问用户）

1. **NekoBox 壳 + hiddify 芯**：UI/信息架构 1:1 对照 NekoBoxForAndroid，底层沿用 hiddify 的 sing-box 内核与 Dart 分层。
2. **规格源唯一 = NekoBoxForAndroid**：menu/preferences XML 是唯一规格准绳；nekoray 不进决策链。**当 NekoBox 规格与 sing-box 1.13 内核契约冲突时，以内核契约为准并记录**（已发生 3 起：legacy geo 移除、wg legacy outbound stub、wg allowed_ips 硬校验——2026-09-22 显性化，免于每次重新纠结）。
3. **桌面第二规格源 = Throne**（C++）：NekoBox 是安卓-only，凡规格明显不适配桌面形态（交互/布局类）之处参考 Throne；协议/数据结构仍以 NekoBox 为准。
4. **方案分歧决策链**：NekoBox 规格 → 复用已有机制 → 参考 Throne → 自己实现。能推导的自行定案，不退回用户。
5. **FAB = 唯一连接开关**（四态：stopped▶/connecting 转圈禁点/connected⏹/disconnecting 转圈）；系统代理模式放设置。
6. **多平台形态**：手机 = NavigationDrawer；PC ≥600dp = NavigationRail 常驻；统一 Flutter 代码库。**「先 PC」= 先在 Windows 平台构建、跑起来、测试**。
7. **归一原则**：每个能力只允许一个数据源/入口；退役 UI 不删码只降权；每步一提交。
8. **不移植清单（已定案，勿重新讨论）**：SN Link `sn://`（Kryo 专有二进制，分享用标准链接顶上）；geo 资产管理页（等价物 = 远程 .srs + 路由规则全语义）；http 表单 host/path（NekoBox 构建期死字段）；推广位。
9. **路由**：保留 hiddify RuleEntity 模型 + 补字段编辑表单（复用 ProtocolFormSpec）；不做 geo Assets 管线。
10. **工具纪律**：生成代码不入库（build_runner 全量跑）；小状态优先 shared_preferences 不轻易动 drift schema；不用裸下载/自造脚本（用 mise/pub/仓库已有命令）。
11. **UI 复刻新阶段 = 「1:1 逐功能对比」**（2026-09-22 拍板）：逐功能抽 NekoBox 规格 → L1 结构测试红灯 → 修正 → 全绿提交。节奏 = 一个功能一个功能推进（功能①⋮ 菜单已完成）。
12. **翻译基准 = zh-CN**（2026-09-22 拍板）：**先只考虑 zh-CN，翻译放最后**。测试断言直接用 zh-CN 文案（对齐 NekoBox values-zh-rCN 词表）；en 仅作 slang base_locale 保持键同步；其余 8 语言（ar/es/fa/fr/id/pt-BR/ru/tr）本轮不碰，runtime 靠 `fallback_strategy: base_locale` 回退 en 不炸。
13. **「1:1 序列按用户使用顺序推进」**（2026-09-22 拍板）：功能对照顺序 = 用户真实动线（首启 → 添加配置 → 配置页 → 连接 → 抽屉/分组/订阅 → 路由 → 设置 → 日志/仪表板/工具/关于），不按界面架构排。已完成的 ⋮ 菜单/抽屉/分组页/分组设置视为按此序"提前完成"的条目，后续从序列最前端未完成项续作。

**设计原则（同 B 层，浓缩版）**：NekoBox 壳 + hiddify 芯 / FAB 四态唯一开关 / 手机 Drawer + PC(≥600dp) NavigationRail / 归一原则 / 每步一提交。规格源唯一 = NekoBoxForAndroid（nekoray 不进决策链）。

**已完成**：主题色板/主壳/主页卡片/分组页（滑删+拖拽）/导航命名 ‖ 实体层（分组+节点+编辑+分享+删除+去重+组装）‖ ⋮ 菜单 8/8（功能①1:1 收口 `82a39b20`）、抽屉 10/11 ‖ 协议表单 14/15（socks/http/ss/vless/vmess/trojan/hy1/hy2/tuic/shadowtls/anytls/mieru/naive/ssh/wireguard）‖ 设置页审计归一 ‖ custom_config 全局（两阶段 raw）‖ 节点级覆写（切片 8.5）‖ wireguard endpoint 通路 ‖ **chain 任意串联**（批次 10）‖ **config 类型节点**（批次 11）‖ **http 表单**（批次 12，`b07830af`）‖ Windows 构建 + 冒烟测试 ‖ 审计 B/C/D + Go 1.27.1 升级。

**剩余（按优先级）**：
1. ~~实机验证 custom_config raw 通道 + 节点级覆写~~ **已完成**（`98060f8d`）。~~wireguard 表单结构验证~~ **已完成**（core `eb52b62`：allowed_ips 缺省契约 bug 修复 + HiddifyCli 真启动验证）。**剩余 wireguard 真实握手**（需用户提供真实凭据/端点，其余链路已全通）
2. ~~切片 8.5~~ **已完成**（`1fc06b58`）
3. ~~chain 任意节点串联~~ **已完成 + 内核级验证闭环**（`b13d7a16` + `142cfa29`，设计 docs/design/chain-2026-09-20.md §D2 含方向修正记录）
4. ~~config 类型节点~~ **已完成**（`db8e1f1a`，批次 11）。~~协议表单剩 http 可选~~ **已完成**（`b07830af`，批次 12：host/path 是 NekoBox 构建期死字段 V2RayFmt.kt:628-637 不消费、内核 HTTPOutboundOptions 也无 Host，不移植）。~~geo 资源管理~~ **不移植（批次 13 定案）**：sing-box 1.13 内核 legacy geo 已移除（本地 .db 无读取通道）、Throne 同架构也无资产页（2197 条名称→.srs URL 目录编译进 srslist.h）——等价物 = **路由规则活通 + NekoBox 全语义（前缀/指向节点/每规则覆写），已完成**（批次 13 + 14；远程 .srs 缓存进内核 cache.db 无用户可见文件）。路由规则 UI 对照差异：~~domain 列收敛为单一输入框~~ **已完成**（Task #49，`31be8173`：domainSuffix/domainKeyword/domainRegex 三 tile 退役 → 单一 domain 输入框 + 前缀语义，`rule_page.dart:189` §Batch 14/NekoBox routeDomain；旧 pb 字段数据仍流向内核，只是无编辑 UI）。至此**可做项**对照差异清零（协议表单 14/15—trojan_go 内核缺出站不移植；不移植清单见 §3.0#8。复刻口径百分比仍是盘点印象，见 §7）
5. ~~审计 B 供应链包~~ **已完成**（`fc3c38f2`）：CORE_FETCH 加 GitHub release asset digest sha256 校验（mismatch 删文件失败退出、取不到 WARN 降级、curl rc 显式检查防截断文件进后续步骤；make recipe 里 `\${VAR##*/}` 会被 make 吞掉，tag 用 `\$(notdir ...)` 派生）；circle_flags/installed_apps git 依赖锁 ref（与 pubspec.lock resolved-ref 对齐）；build.yml 删 FLUTTER_VERSION env、两 job 改 `flutter-version-file: pubspec.yaml`（单事实源=pubspec environment.flutter，Makefile REQUIRED_VER/Dockerfile 同源）；CI 缓存 `.cache/core-libs`（key=channel+hash(dependencies.properties+Makefile)，test job 先写 build job 读）。配套：rule_page_test 断言跟上批次 14 UI（SettingText 2 个/SettingGenericList 9 个，`54284b22`）。**sha256-OK 全绿路径留 CI 首跑验证**（本机网络下载 26MB 不动，失败路径 curl-56 已实证）
6. ~~审计 C 安全包~~ **必修项已完成**（2026-09-22，见下）。原「威胁模型待定案」提法撤销——本地构建 sentry_dsn 为空编译期常量 → Sentry 全禁用，不存在「分发二选一」的现状问题。**必修三项落地**：①`Random.secure()`——gRPC secret（core_interface_desktop.dart）+ STUN txId（stun_client.dart），全库仅此两处 `Random()`；②9 处空/吞异常 catch 补日志（原审计说 3 处已过时）：closeFront×2（debug 级）、ip_utils（注释说明兜底语义）、directories_provider（stderr）、config_settings_page×2（debug/stderr）、config_assembly×5（`_assemblyLog` stderr helper——纯 Dart 模块不引 loggy）；③Sentry token 泄漏堵住：`scrubSensitiveUrls`（sentry_utils.dart，regex 剥 http(s) URL 的 query 尾巴，log 包裹符 `)]` 不误伤）接进 `SentryLoggyIntegration` 的 breadcrumb+event 出口——实测 3 处日志消息嵌订阅 URL（profiles_notifier×2/profile_notifier），6 个单测钉住（test/utils/sentry_utils_test.dart）。flutter test 82/82 + analyze 干净。**分发时才修（未做）**：gRPC mTLS/随机端口（上游 mTLS 代码在 core_interface 被注释）、分发版 Sentry 配置审查。**不修**：loopback 明文 gRPC（127.0.0.1:17078 + secret 鉴权，自用维持现状）
7. ~~审计 D 架构包~~ **复核完成**（2026-09-23，全部按「先复核现状再动手」原则逐项验证）：
   - **core→features 逆依赖**：原审计「14 处」**已过时**——实测 0（layering.md 记录的 47→0 收敛早已完成），无需行动。
   - **json_editor.dart 拆分**：**不做**。1690 行是 vendored 第三方（json_editor_flutter），analysis_options 已排除 + 文件头已注明来源版本（原 2026-09-14 roadmap 建议：exclude + 注明，该 roadmap 已删除）；拆分反而制造升级障碍。
   - **riverpod 风格**：**无真混用**。4 个「混用」文件实际是同文件内两种注解各司其职——`@Riverpod(keepAlive: true)` 给保活 class notifier、`@riverpod` 给 autoDispose provider，这是 riverpod_generator 的生命周期语义不是风格漂移。仅 1 处裸 `@Riverpod()` 空括号（per_app_proxy_loading_notifier）归一为 `@riverpod`（语义等同）。准则：按生命周期选注解，不按口味。
   - **业务测试**：补齐 config_assembly 两大零覆盖区（+18 测试，31/31 绿）——`buildChainOutbounds`（两跳/三跳 detour 方向锚点、嵌套展平、环/自引用 null、endpoint/内置/组/full 形态拒绝、重复成员 #N 后缀、覆写合并、空链 null）+ `applyEntitiesToOutbounds` endpoints 段（legacy wg outbound 剔除 K1、覆盖/追加/stale 删除/坏 payload 跳过/不新建空段）。detour 方向期望按实现+ NekoBox 定案修正（落地穿过入口侧、UI 首行直连——写测试时理解反了被红测当场纠正，锚点价值即此）。drift 迁移已有 migration_test，未动。
   - **老审计（2026-09-15）遗留抽查**：#9 `startedByUser` 仍只写不读（唯一读取点 connection_wrapper.dart:52 在注释块里）；#11 IpInfoNotifier guard 语义未变。两者是上游 hiddify 自带行为且无功能损害，**降级为观察项不行动**（动它们 = 超出 NekoBox 对照范围的自由发挥）。
8. 上游 PR（anytls 修复 + Makefile PATH 修复提给 hiddify 官方）。~~推送 origin/my~~ 已推送；~~前置：洗 token 历史~~ 已完成（2026-09-30 git filter-repo 替换双 token + force push，全史 0 命中实证）。
9. ~~**Go 1.27 重测**~~ **已完成并升级**（2026-09-22）。**结论：panic 消失，已升 1.27.1**。
   - 背景：Go 1.25 已 EOL（2026-08-19 起无安全补丁），原钉死理由仅「1.26 编核心 psiphon-tls 布局断言 panic」的 1.26 实测。
   - 实测（1.27.1 + llvm-mingw + `make windows-libs-local`）：`go mod tidy` 过 → `hiddify-core.dll` 64.9MB / `HiddifyCli.exe` 编译通过 → **DLL 加载零 panic**（CLI 打印命令树 rc=0）→ 内核真启动 `sing-box started (7.73s)`，mixed 12334 / clash API 16756 / grpc 17078 全监听。
   - **psiphon 确在构建内**（`go list -deps ./platform/desktop` 实测 1154 包含 `psiphon-tls` + `sing-box/protocol/psiphon` + 整棵 psiphon-tunnel-core）→ 探针有效，非"没编进去所以不炸"。
   - **chain 三断言**：①内核起+三端口监听零 panic **PASS**；③clash API `/proxies/select` 的 `all` 只有 `chain:us-hk-us`、**零 §hide§** **PASS**；②出口 IP 本次 **INCONCLUSIVE**（09-21 那批节点/凭据已失效：3 个节点 TCP 全通但 anytls 会话 3.0s 后 `use of closed network connection`）——**A/B 对照证明非回归**：用 Go 1.25.6 编的旧 DLL（60.9MB，`build/windows/x64/runner/Debug/hiddify-core.dll`）跑同一配置，日志序列与失败点**逐字一致**。运行态链路由亦正确（日志可见 `chain:us-hk-us` → HK 成员 → 落地服务器 的拨号链）。
   - 落地：`.mise.toml` go → 1.27.1；`Makefile` doctor 改查 go1.27*；§1 Go 行、§4 大坑 #2、§6 命令、docs/BUILD.md 同步。
   - 待办（低优先）：换新订阅后补跑断言②（出口 IP 对照），以恢复 traffic-path 证据链。
10. **「1:1 逐功能对比」序列（§3.0#13：按用户使用顺序排）**：已做 = 节点页 ⋮ 菜单（`82a39b20`）‖ 抽屉核验收口（功能②，`3931652e`）‖ 分组页（功能③，`32783b20`）‖ 分组设置（功能④，`82f19327`）‖ **配置页主体**（2026-09-30，`567a45f4`：NkProfileTile L1 spec 测试 4 用例全绿——卡规格 margin4/elevation2/圆角4+左缘 4dp 选中条、三行结构、状态着色分支、本地配置收起、流量闸门；两个观察点收口=宽屏留白按 NekoBox 原样不做约束、三行 vs 双行按形态分化收口，见 ui-real-device-observations-2026-09-22.md；部件本就 1:1，无修正项）‖ **连接链路**（2026-09-30，`c7d8bcbc`：FAB 四态已在 `897269a8`；状态条收口=NkCaptureStatusBar 提公共部件（纯参数注入，ConnectionFab 同型）+ captureStatsBarVisible 纯映射进 connection_status.dart + 页面删双写 nkState 归一，L1 spec 测试 3 用例（可见性矩阵/单行内容/点击触发测速）；通知面定性=平台差异非缺口（桌面壳对应物 system_tray_notifier 已按四态复刻，托盘缺「重置连接」动作=观察点不立测）；交互分化收口=点击测速走进度弹窗（Throne 形态）不对照内联文案）‖ **添加配置流**（2026-09-30，`5fc3cb35`：AddProfileModal L1 spec 测试 6 用例全绿——默认选项页/startInManual 直达/手动表单结构（名称·URL·禁用自动更新·自动更新间隔 Slider）/校验闸门 emptyName·invalidUrl 不触 repo/桌面四键+qr 仅移动端/AsyncLoading→ProfileLoading；部件本就 1:1 复刻 add_profile_menu.xml 五入口，无修正项。测试坑：AddProfileNotifier 的 ref.disposeDelay(1min)（riverpod_utils.dart:6）在 container.dispose 留 60s Timer，测试必须 override fake）。**下一步按用户动线序**：~~②订阅页~~（2026-09-30，`ec4dd8ec`：SubscriptionsPage L1 spec 测试 6 用例全绿——desktop/mobile 骨架（ShellDrawerButton 按 <600dp 断点）、空态 rss_feed+添加配置文件、groupOrderProvider 持久化排序与未上榜回退、Dismissible 删→SnackBar+撤销记账；可达性部分早闭环有测试（groups_page→group_settings_sheet onOpenSubscriptions 4 用例）；测试坑：`List<String>` 偏好持久化为 `;` 连接字符串（preferences_utils.dart:27-29），mock 预置须 'p2;p1' 非 StringList）‖ **③路由页**（2026-09-30，`4136b3c0`：RoutingOptionsPage+RuleTile L1 spec 测试 9 用例全绿——空态 rule_rounded+空菜单只显导入 2 项（getRange(0,2) 项目特有语义）/列表+出站词 直连·拦截·代理/菜单 5 项词值/FAB 展开 hitTestable+收起 Opacity(0)/GeneralOptions 展开收起（SizeTransition 折叠在树内不可命中，断言用 hitTestable）/长按删除流（ConfirmationDialog 真实确认框→deleteRule 落账）/updateEnabled Switch 翻转+记账/点行 goNamed('rule') 进编辑页；**对比收口**：NekoBox 滑删+undo 无对位（本项目长按/右键删，形态分化）、路由规则页=项目增强面非 1:1 缺口；测试坑：ConfirmationDialog 按钮用 context.pop——纯 MaterialApp 报 "No GoRouter found in context"，须 MaterialApp.router+navigatorKey:rootNavKey；goNamed 目标 GoRoute 必须带 name:'rule'；ReorderableListView 懒加载在默认 800×600 视口只 build 2 卡，3 卡断言须放大视口；_ExpandableFab mini 项标签 Opacity(0) 常驻树内无 IgnorePointer（收起后仍可命中=疑似产品 bug 记录不修））；~~④设置页~~（2026-10-01，`e0339608`：SettingsPage L1 spec 测试 7 用例全绿——desktop 骨架（五段头+五卡关键行+默认值+平台/视口分支行）/autoStart 开关翻转记账/导入确认流（两级菜单→确认框，取消不执行·确定 importFromClipboard）/Clash API 联动（端口行 enabled 随开关，关闭后 tap 无效）/链行门控 hasAnyProfile/customConfig JSON 徽标有无/mobile 400×1600 视口（抽屉键+desktop OS 行仍渲染）；**对比收口**：无 1:1 修正项（部件本就位，纯补测；补 2 条 android 行不出现断言「在通知中显示速度/触觉反馈」）；**测试坑**：PlatformUtils.isDesktop 按 defaultTargetPlatform 判（可测试版设计）→ _pump 钉 debugDefaultTargetPlatformOverride=windows，**重置必须 body 末尾显式调 _resetPlatformOverride**（addTearDown 晚于 flutter_test binding.dart:1078 _verifyInvariants，必炸 foundation invariant）/autoStartNotifierProvider 需 body 内预热（复刻 bootstrap.dart:80 启动时序，否则首帧 settings_page.dart:150 asData! 落 AsyncLoading）/direct-dns-address 实际默认 1.1.1.1（config_option_repository.dart:98 defaultValueFunction 按 region 覆盖静态默认 udp://1.1.1.1）/「入站」「其他」同词碰撞→findsNWidgets(2)/「Clash API 端口」行标题+对话框 title+输入框 hint 三处→findsNWidgets(3)；spec 落盘 .workbuddy/spec-settings-page-tests.md）；~~⑥日志页~~（2026-10-01，`006b50b3`：LogsPage L1 spec 测试 8 用例全绿——初始渲染（加载占位→标题/筛选/全部/等级徽标/extractMessage 去前缀/时间戳/暂停·清空键/分享菜单）/extractMessage 纯函数（多词去前缀·两词取尾·单词原样）/关键词筛选防抖 200ms 命中剔除清空恢复/等级筛选 warn 及以上回"全部"恢复/暂停恢复（新日志不上屏·恢复补上·图标切换）/清空 repo.clearLogs 记账/错误流→SliverErrorBodyPlaceholder+「意外错误」/mobile 400×1600 视口（抽屉键+desktop OS 行仍渲染）；**对比收口**：日志页原生组合移植（无 NekoBox 对位页），无 1:1 修正项，纯补测；**测试坑**：environmentProvider 必须 overrideWithValue(Environment.prod)——DebugModeNotifier._pref 里 ref.read(environmentProvider)，app_info_provider.dart:13 桩直接 throw（全仓库测试首创 override）/ref.disposeDelay(20s)（logs_overview_notifier.dart:19→riverpod_utils.dart:12 onCancel 挂 Timer）用例末尾必须 pumpWidget(SizedBox.shrink()) 卸树触发 onCancel 再 pump(21s) 推假时钟烧掉，否则 binding.dart:1617 报 pending timer/真 import fluentui_system_icons 用 FluentIcons.pause_20_regular 等常量（自造 IconData 包装类 == 不匹配 byIcon，教训：find.byIcon 只认真 IconData）/其余同④（钉 windows+显式重置/禁 pumpAndSettle 加载态/pump(300ms) 推节流假时钟）；spec 落盘 .workbuddy/spec-logs-page-tests.md）；~~⑥余下仪表板/工具/关于定性~~（2026-10-01 记档 `.workbuddy/qual-remaining-pages-2026-10-01.md`：Dashboard=traffic 页常驻差异（NekoBox enableClashAPI gate）、tools/about 原生组合无对位——均非缺口不立测）；~~⑦首启引导~~（已定性 NekoBox 无 onboarding 不移植，仅记档）；~~①手动新建节点链~~（2026-10-01，`9231100c`+`429bf873`：manual_node_flow_spec_test 6 用例（选协议对话框 17 项列全/取消回退/initialProtocol 直进/chain→ChainSettings 空成员/config→ConfigSettings/普通协议→ProtocolFormModal 新建）+ protocol_form_modal_spec_test 6 用例（新建 anytls 全字段渲染·分节·布尔 Switch·choice 未设置·⋮ 菜单仅编辑模式/空名拒存 errors.unexpected+name 标星不落库/填名保存断 createNode 参数·payload server_port 443 int·种子 tls.enabled 保留/trojan_go unsupported 占位/坏 JSON jsonInvalid 占位/编辑回显 int toString·List 逗号 join·保存只动改过的键未编辑键原样含嵌套 tls）全绿；**测试坑**：fake ProxiesOverviewNotifier 覆写 build() 为现成 Stream 不挂 disposeDelay(15s)⇒无 Timer 残留；不注入 proxyEntityRepository⇒无 drift 真异步⇒pumpAndSettle 全程可用；TextFormField 无 decoration getter，断 errorText 用内层 TextField；chain 弹层 drift 真异步 _tapGoAndSettle bounded=false 12×pump(50ms)）；⑤协议表单字段级 1:1（15 类，依附"手动添加"分支，规格已抽取 `.workbuddy/spec-protocol-forms-tests.md`（17 项菜单对齐+143 行字段矩阵+P0/P1/P2 三批计划+真缺口 6 项待裁定））。**P0 已收口**（2026-10-01，`ba21921d`：protocol_form_fields_p0_spec_test.dart 603 行 12 用例全绿——anytls/vless/hysteria2/shadowsocks × 新建渲染/编辑回显/新建保存；矩阵 7 差异以代码为准固化：anytls password 非必填、vless flow 是 text 非 choice、certificates 三协议 text 非 stringList、hysteria2 hopInterval text+'s' 后缀、shadowsocks pluginName text 拆 plugin/plugin_opts、method 无默认值、hysteria2 无 TLS 分节标题；新坑两条=同文案分节+字段 findsNWidgets(2)、choice 选项 find.text().last）。**P1 已收口**（2026-10-01，`4c0c1da0`：protocol_form_fields_p1_spec_test.dart 778 行 15 用例全绿——vmess/trojan/hysteria/tuic/ssh × 同三用例；差异固化（**其中前三条已于 2026-10-01 修复，见本行末「六缺口修复」**）：vmess 无 alterId/encryption 字段（spec 复制 _vlessSpec 换 type）、trojan 种子无 tls 默认不落键（待裁定）、tuic 四字段（UDP 中继/拥塞控制/禁 SNI/降 RTT）无 zh 词条界面显示英文 id、hysteria 双窗口 recv_window_conn/recv_window 双向断言防 NekoBox 抄写 bug 回归、ssh 无 privateKeyPath（private_key text 单串+host_key stringList+密码/私钥双写）；坑=enterText 向 maxLines=1 注入多行 PEM 被剥换行→private_key 改断单串）。**P2 已收口**（2026-10-01，`1a750b50`：protocol_form_fields_p2_spec_test.dart 783 行 20 用例全绿——socks/http/shadowtls/mieru/wireguard/naive × 新建渲染/编辑回显/新建保存 + 收尾 2（菜单 17 项顺序+display 名映射 hysteria 分列 1/2；chain/config/trojan_go 无 spec+15 协议 spec 非空）；差异固化：socks version 无 writeValues 落原串 '5'、http host/path 死字段表单与 payload 均无、shadowtls version 落 **int**（writeValues {'2':2,'3':3}）、mieru serverPort/protocol 落 portBindings[0]+种子 [{}] 占位、wireguard reserved integerList 0-255 数字数组+种子 mtu:1420/peers:[{}]+'256' 越界拒存 errorText '!'、naive serverProtocol writeValues {'https':null,'quic':true}——https 档删键/quic 档落 bool/**缺键反查默认 'https' 不显示「未设置」**（protocol_form.dart:866-877 反查 null 匹配 writeValues['https']）；**新坑两条**：①容器 dropWhen 只认显式 'false'——新建未碰开关时 values='' 不触发摘除（SwitchListTile onChanged 才写 'true'/'false'，protocol_form_modal.dart:388），测摘除须先开再关；②**同一 fake notifier 实例挂进第二个 ProviderContainer 炸 LateError（Field '_element' has already been initialized）**——一次 _pump 一个新 _Fixture，勿跨 container 复用）。**方法纪律**：每功能先抽规格（menu XML/preferences XML/Activity 源码 + strings 词表）→ L1 结构测试红灯 → 修正 → 全绿提交；测试断言一律 zh-CN（§3.0#12）。**六缺口修复已收口**（2026-10-01，`15b41d37`，19 files/+411/−128）：P0/P1/P2 三个字段级 spec 文件实测出「规格矩阵有、实现无」六处 → 全部按 NekoBox 规格补齐实现并同步测试：①**vmess 独立 `_vmessSpec`**（此前 `_specs:853` 引用 `_vmessSpec` 但**定义缺失=编译炸**）：vless 减 flow，加 alterId（integer→`alter_id`）与 encryption（choice→`security`，choices `['','chacha20-poly1305','aes-128-gcm','auto','none','zero']`，首位空档=未设置⇒不写键⇒内核回落 auto，V2RayFmt.kt:662）；②**ECH 两字段** `enableECH`/`echConfig`（boolean→`tls.ech.enabled`、stringList→`tls.ech.config`）覆盖 vless/trojan/http 三协议（standard_v2ray_preferences.xml:173-185、V2RayFmt.kt:615-622）；③**trojan 种子** `protocolSeedPayload` 加 `'trojan' => {'tls': {'enabled': true}}`（StandardV2RayBean.java:83-89，NekoBox 新建 trojan 默认开 TLS——此前测试断「不落键」属规格误读，已反转）；④**tuic 四字段 zh 词条**（此前界面裸奔英文 id）+ 新增 `disabledBy` 机制：`_tuicSpec` serverSNI 带 `disabledBy: 'serverDisableSNI'`，modal 侧 `enabled: field.disabledBy == null || values.value[field.disabledBy!] != 'true'`（TuicSettingsActivity.kt:55-61）；⑤新词条 8 个（alterId/encryption/enableECH/echConfig/serverDisableSNI/serverReduceRTT/serverCongestionController/serverUDPRelayMode）——en/zh-CN 出译文，其余 **9 语言按 ⑧ 批次惯例补 en 占位**（parity missing=0）；⑥**顺带修 `protocolFormLayout` 分节重复标题缺陷**：原判据 `if (out.isEmpty || field.section != null)` 对每个带 `section` 的字段都开新节，ECH 两字段自带 `section:'security'` ⇒「TLS 安全设置」渲染 3 次（vless/trojan/http 全中，trojan 新建用例先撞上：Found 3 widgets）；改为 `if (out.isEmpty || (field.section != null && field.section != out.last.section))`——连续同名字段只开一节、`section` 可标在节内任意字段上（**教训：新增字段顺手复制 `section:` 会静默重复分节标题；分节标题断言保持 findsOneWidget 勿放宽**）。**测试同步**：P0 vless 20 字段/`SwitchListTile` ×3/「未设置」×3；P1 vmess 21 字段（`流控` findsNothing、未设置 ×4）、trojan 18 字段（种子 TLS 默认 true）、tuic 中文标签 + 旧英文 id findsNothing 防回退 + **交互顺序陷阱**（置灰后的 TextFormField 打不进字：保存用例须**先 `_fill('服务器名称指示')` 再 `_toggle('禁用 SNI')`**，并断 `enabled isFalse` 且置灰不清值）；P2 http 7 字段 + ECH；小屏注释 18→20 字段。**顺带清零 test 目录 4 条 analyze info**（logs_page_spec_test :26 导入顺序 / :100 多余 await、nk_profile_tile_spec_test :86 cast、:116 `DateTime(2020)`）；`flutter analyze lib` 与 `test` 均 **No issues found!**（tool/ 17 info 为已知基线），全量 `flutter test` **273/273 passed**（基线 243，+30 字段级新用例）。

---

## 4. 大坑实录（换机/新环境必读）

1. **make 的 sh 里 PATH 被截断**：agent/IDE 注入 `\\?\` 设备路径条目 + Makefile 的 POSIX 前缀（`/usr/bin:/bin:`）→ MSYS 按冒号解析、在盘符冒号处整串切碎 → recipe 里 curl/git 全失踪，但 make 直启的命令正常（极具迷惑性）。已修（Makefile 15-38 行：Windows 格式前缀 + subst 剥离 `\\?\`）。
2. **Go 版本**：**用 1.27.x**（1.26 编核心 → 运行时 panic，psiphon-tls 布局断言；1.27 已修，2026-09-22 实测）。doctor 会查。CI 依赖解析失败时以 CI 报错为准重锁 lock，不手工猜版本。
3. **pubspec.lock 与镜像**：`PUB_HOSTED_URL=pub.flutter-io.cn` 与 lock 里 `pub.dev` 来源不匹配 → pub 每次 pub get 重解析（版本在约束内漂移）。已提交镜像版 lock 为基线；pub.dev 机器（CI）自行解析不回写。**不要试图"恢复干净 lock"——那是死循环**。
4. **单实例**：旧实例还在跑时启动新构建 → 新进程握手后 exit 0（像闪退）。烟测前先杀干净 Hiddify 进程。
5. **生成代码不入库**：新机器必须 `dart run build_runner build --delete-conflicting-outputs`（freezed/slang/drift/riverpod 全靠它），否则 analyze 报一堆 undefined。**必须全量跑**：`--build-filter` 会漏掉 slang 真正输出（lib/gen/translations_*.g.dart）。
6. **git submodule update 不带 `--remote` 会锁死在父仓库记录的 SHA**（游离 HEAD）——本项目约定全层跟 `my` 分支，见 docs/BUILD.md「取源码」节。
7. **后台任务里跑 git checkout 会留下半路状态**（index.lock / 半删文件）——git 操作放前台。
8. **flutter test 前必须 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`**——代理变量存在（哪怕指向已关闭的本地端口）就劫持 flutter_tester 本地 WebSocket，全部测试 "Invalid WebSocket upgrade request" 挂载失败。
9. **`for (final x in list ?? const [])` 类型陷阱**：裸 `const []` 让 `??` 的类型 LUB 劣化，循环变量掉成 `Object?` → 4 个 error + dead_code。必须 `const <Map<String, dynamic>>[]` 或 `if (list != null)` 包裹。
10. **全量 flutter analyze 被沙箱 reg.EXE 黑名单拦截** → 用 `dart analyze lib test tool` 分目录替代。
11. **Windows 构建三关**（详见 .workbuddy/memory/MEMORY.md「Windows 构建链」）：hiddify-core.dll 不带 with_ech / 插件 junction 预建（tool/ensure_plugin_junctions.ps1）/ CMakeLists 两条 install 已注释。
12. **沙箱里 git 的 ref **创建**类操作静默失败**（2026-09-21 实证）：`git update-ref`（创建）、`git fetch` 的 ref-store 事务 rc=0 但不写盘——删除/修改能落盘，于是 fetch 后 tracking ref 可能停在旧值甚至被删（status 幻象 `ahead N` / `[gone]`）。**判据**：push 成功与否用 `git ls-remote origin <branch>` 核对真实远端，别信 status；**修复**：`mkdir -p .git/refs/remotes/origin && printf '<sha>\n' > .git/refs/remotes/origin/<branch>` 手工写松散文件（目录可能已被删，要先建）。另注意本机 PATH 里 git 实际解析到 `/c/platform/Git/cmd/git`（2.55），导出的 PortableGit usr/bin 只提供 sh 工具链、不含 git.exe。
    - 补充（2026-09-22）：**子模块的 tracking ref 不在 `hiddify-core/.git/`（那是 gitfile，指向主仓 `.git/modules/hiddify-core`）**，要写到 `<父仓>/.git/modules/hiddify-core/refs/remotes/origin/my`；且 `origin/my` 可能只存在于 **packed-refs**（旧值），需同时建 loose ref 才盖得住。
13. **`flutter build windows` 报 `cpp_client_wrapper\*.cc` 无法打开（C1083）**（2026-09-22 实证，两次构建间复现一次）：`windows\flutter\ephemeral\cpp_client_wrapper\` 丢了 6 个 `.cc` 源文件（只剩 `include/`），而 **flutter 工具不会自动补**——引擎版本未变时它认为 ephemeral 已是最新，直接跳过重拷（`.plugin_symlinks` 的 junction 和 `generated_config.cmake` 都还在，极易误判成插件问题）。修法 = 从 SDK 引擎产物拷回：
    ```powershell
    $sdk = (Get-Command flutter).Source | Split-Path | Split-Path   # <flutter>/bin
    Copy-Item "$sdk\cache\artifacts\engine\windows-x64\cpp_client_wrapper\*" `
              "windows\flutter\ephemeral\cpp_client_wrapper\" -Recurse -Force
    ```
    （本机 SDK 缓存 = `C:\Users\Administrator\AppData\Local\mise\installs\flutter\3.38.5\bin\cache\artifacts\engine\windows-x64\cpp_client_wrapper`；含 core_implementations.cc / standard_codec.cc / plugin_registrar.cc / flutter_engine.cc / flutter_view_controller.cc / engine_method_result.cc + 若干 .h + include/）
13. **slang 非 base 语言是 deferred 库，widget 测试直接 `buildSync()` 必炸**（2026-09-22，功能①测试的最大坑）：
    - 机制：base_locale=en，其他语言是延迟加载库——`AppLocale.zhCn.buildSync()` 抛 `_DeferredNotLoadedError`（`l_zh_CN was not loaded`）；`AppLocale.zhCn.build()` 内的 `loadLibrary()` 是真异步，在 testWidgets 的 **FakeAsync zone 里永不完成** → 用例 30s 静默超时（输出只有用例名就断流）。`AppLocale.zhCN` 也不存在——生成枚举值是 camelCase `zhCn`。
    - **正确泵法**（proxies_menu_test.dart 可抄）：
      ```dart
      final t = await tester.runAsync(() => AppLocale.zhCn.build());  // runAsync = 真实事件循环
      translationsProvider.overrideWith((ref) => Future.value(t)),
      // override 后必须 pre-warm，否则首帧 requireValue 炸 AsyncLoading：
      await container.read(translationsProvider.future);
      ```
    - 连带坑：`MenuItemButton` 的勾选参数名是 `leadingIcon` 不是 `leading`；`find.ancestor(of: 文本, matching: Row)` 会双命中（MenuItemButton 内部 Row 外还有行级 Row），表达「图标与文本同行」用**祖先 Row 集合交集非空**。
14. **flutter test 输出被截断/被掐时判真跑完的方法**：用户发消息会掐断前台命令，PowerShell stdout 又不被捕获（`*> file.txt 2>&1` 落盘再 Read）——但文件也可能是中途快照，**唯一可信判据 = 文件尾部 grep 到 `All tests passed`**；断流（只有用例名）多半是 FakeAsync 卡异步（见坑 13）而非环境故障。

### 4.3 proto 生成工具链（改 .proto 才需要；版本必须钉死）

**版本钉子**（改 proto 前先确认，用错版本会产出成百上千行噪声 diff，甚至直接编译失败）：

| 工具 | 版本 | 与仓库关系 |
|---|---|---|
| `protoc` | **28.0** | 仓库多数 `*.pb.go` 头部的 `protoc v5.28.0` 就是它（protoc 28.0 的内部版本号打印为 5.28.0） |
| `protoc-gen-go` | **v1.34.2** | 仓库多数 `*.pb.go` 头部一致（另有 2 个 v1.36.11、1 个 v1.33.0 是历史遗留，**不要重生成那两个**） |
| `protoc_plugin`（protoc-gen-dart） | **23.0.0** | 仓库多数 `*.pb.dart` 一致。**24.0.0 删了 `createRepeated()`**；21.x 产 `@dart = 2.12` 旧风格；22.0.0 自带生成代码要 protobuf 5.x 而其 pubspec 写 `^3.1.0` → `pub global activate` 直接编译失败 |

**换机器准备**（全部走包管理器/源码，无需手动下 zip）：
```bash
mise install                                                      # 按仓库内 .mise.toml：protoc=28.0、protoc-gen-go=1.34.2、go=1.27.1、flutter=3.38.5
go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.34.2   # 或 mise 的 aqua 版；两者版本一致
dart pub global activate protoc_plugin 23.0.0
# PATH 必须含 pub 全局 bin（protoc-gen-dart 在这里，pub 默认不加）：
#   Windows: %LOCALAPPDATA%\Pub\Cache\bin    Linux/macOS: ~/.pub-cache/bin
```
> **`.mise.toml` 已入库**（项目钉版；上游那份 `.gitignore` 里的 ignore 行已移除，本机临时覆盖改用 `*.local.toml`，见 HANDOVER 同节说明）。

**重生成（按文件定向，不要全量 `make protos`）**：
```bash
# Go（在 hiddify-core/ 内跑；-I . 是相对路径，protoc 是原生程序，绝对 POSIX 路径会报 directory does not exist）
cd hiddify-core && protoc --go_opt=paths=source_relative --go_out=./ -I . v2/config/<你的>.proto
# Dart（回仓库根跑）
protoc --dart_out=grpc:lib/hiddifycore/generated --proto_path=hiddify-core/ v2/config/<你的>.proto
```
**校验技巧**：先输出到临时目录再比对，确认「工具链版本对 + 生成文件与 proto 同步」后再写回：
```bash
mkdir -p /tmp/g && (cd hiddify-core && protoc --go_opt=paths=source_relative --go_out=/tmp/g -I . v2/config/x.proto)
diff --strip-trailing-cr /tmp/g/v2/config/x.pb.go hiddify-core/v2/config/x.pb.go   # Go 要忽略行尾：仓库 CRLF（autocrlf）vs 新生成 LF
```
**踩过的坑**：①`protoc-gen-dart` 是 `.bat`，bash 里不能按裸名调用，但 protoc 自己能找到它——只要它在 PATH 上；②bash 下把 `/s/test/...`、`/c/...` 当路径参数传给 protoc（原生 exe）必失败，命令一律用相对路径；③别用脚本自己下 zip：Git-Bash 的 curl 走 schannel 遇代理会握手失败甚至挂死（拿到截断包），下载要么交给 mise（aqua，带 checksum），要么手动放好。


---

## 5. 排错方法论（本次验证过的）

1. **先 `make doctor`**：能报出 Flutter/Dart/Go/gcc 四类版本与缺失，别直接跑构建。
2. **抓 App 启动日志**：`Start-Process -RedirectStandardError`，panic/初始化失败全在 stderr；GUI 双击看不到。
3. **验证导入成功**：看 `%APPDATA%\Hiddify\hiddify\` 下 `db.sqlite`（字符串 grep 订阅域名）、`configs/<id>.tmp.json`（数 `"type":"anytls"` 应=39）、`shared_preferences.json`（`selected_proxy_group`）。
4. **验证核心可加载**：`hiddify-core\bin\HiddifyCli.exe --help` 退出码 0 = DLL 初始化无 panic。
5. **排序/设置类小状态**：优先 shared_preferences（PreferencesNotifier），别轻易动 drift schema。

---

## 6. 快速上手（新机器/新 clone）

```powershell
# 0) 工具：Git for Windows + mise
mise use -g flutter@3.38.5
mise use -g go@1.27.1
go env -w "GOMODCACHE=$env:USERPROFILE/go/pkg/mod2"
# 1) 源码（全层 my）
git clone -b my https://github.com/asmzhang/hiddify-app.git && cd hiddify-app
git submodule update --init --recursive --remote
# 2) 自检（「Required」段无 FAIL 即可；Core-from-source 段的 go module cache FAIL 是保守启发式，
#    2026-09-22 实测该 FAIL 与 make windows-libs-local 全绿并存 —— 不阻塞，介意再 go clean -modcache）
make doctor
# 3) 准备（pub get + 代码生成 + 核心库；本地编核心加 LOCAL_CORE=1）
make windows-prepare LOCAL_CORE=1 CORE_GOPROXY=https://goproxy.cn,direct
# 4) 构建与验收
flutter build windows --release
.\build\windows\x64\runner\Release\Hiddify.exe
# 导入订阅：＋ 粘贴 URL，或（App 运行时）Start-Process "hiddify://import/<订阅URL>"
```

---

## 7. 未验证清单（C 层：待验证假设 + 未跑过的通道；新会话优先用"新眼睛"审这里）

**未跑过的通道（证据真空，勿默认可用）**：
- ~~本地 2 个提交未推送~~ **已全量推送（2026-09-30 ls-remote 实证 0 未推送；同日洗订阅 token 历史：git filter-repo 重写全史 2984 commits + force push，主仓远端 my = `151a3655`，npr = `579b6fe8`，core 子模块未动 = `1075e82`；tag 136 个全指向未重写的 pre-token 史，未强推）**。推送备忘（2026-09-30 更新）：三种通道成败随会话网络变化——按 **直连（`-c http.proxy= -c https.proxy=` 显式禁代理）→ `http://127.0.0.1:35496` → 全局 7890** 顺序轮试；推后用 `git ls-remote origin my` 核对（本地 tracking ref 显示 `[gone]` 是 §4.12 沙箱幻象，别信）。
- ~~集成测试 smoke_test.dart 本体未重跑~~ **已完成（2026-09-24）**：集成测试两层根因已修（bootstrap.dart:40 `FlutterError.onError` 被 `Logger.logFlutterError` 顶掉不转发 → binding.dart:1018 崩；physicalSize 2560×1400 假视口 vs 真窗口 868×668），integration_test 重写为单 testWidgets + dumpUi，用户终端验证全绿（`+1 All tests passed`）。
- ~~8 语言翻译批次~~ **已完成**（2026-10-01，`17f32a0b`：9 语言 zh-TW/ar/fa/es/fr/id/pt-BR/ru/tr 全量补齐 1367 键 + slang 再生 + analyze lib 0 + 全量测试绿，i18n 缺口清零）。
- **CI 全绿未背书**：审计 B 的 sha256-OK 校验路径、flutter-version-file、core-libs 缓存都只在本地静态验证过（pyyaml 解析/失败路径实证），**push 后首次 CI 才是最终背书**。
- **Android/iOS/Linux/macOS 构建链**：新机器全未实测（流程在 BUILD.md/CI 里）。批次 9-14 的新 UI（表单/chain/config）从未在真机/安卓上跑过。
- **wireguard 真实握手**：结构验证通关（假凭据真启动），但真隧道未通过——需真实凭据（private_key/peer pubkey/endpoint/local address CIDR）或本地起 wg server 端点。**用户定案暂缓（2026-09-30：当前无 wg 节点，等有凭据再做）**。
- **小屏（<600dp）形态**：**部分已补**（2026-09-22）。路由规则页现带小屏回归测试（`rule_page_test.dart` 的「小屏手机形态」组：360×640dp + 320×568dp，溢出会以 FlutterError 让用例失败），并借此抓出并修掉两个**真实溢出 bug**——`SettingDivider` 的本地化长标题行（360dp 溢 25px / 320dp 溢 65px）、`SettingGenericList` 的平台警告行（`Flexible` 缺失：360dp 溢 75px / 320dp 溢 115px，安卓正是走这条路）。**仍未见小屏**：~~协议表单 / chain 设置弹窗 / config 弹窗 / 主壳 NavigationDrawer~~ **已补齐（2026-09-30，`4f77caee`）**：`test/features/proxy/small_screen_sheets_spec_test.dart`（7 用例：协议新建 vless/shadowsocks 360/320dp——**ListView 懒构建，屏外分节 find 落空，滚动可达断言**；chain/config 新建+编辑；弹窗 build 挂 drift useFuture ⇒ 有界泵）+ `test/app/shell/drawer_small_screen_spec_test.dart`（3 用例：真 MyAdaptiveLayout mobile 断点 8 可见+1 隐藏分支壳——**分支表必须 = navMetas 全序，少搭隐藏分支 subscriptions 会令 goBranch 错位**，汉堡键开抽屉+goBranch 导航+320dp 开合）。全量 +273 绿。

**推断性结论（本文与记忆里的因果解释，采信前建议复现）**：
- 复刻口径百分比（≈99%）是盘点印象，非逐项 diff 结论。
- 大订阅（数百节点）下列表渲染/去重/启动时间的性能无实测数据。
- 沙箱 git ref 创建拦截的机制解释（§4.12）基于行为实证，但底层拦截者身份未最终确认。
- 审计 C/D 的发现（gRPC 明文 17078、Sentry 上送、14 处逆依赖等）是**审计时点的静态观察**，修复前先重新确认现状。

**发布工程（完全未建）**：签名、版本号策略、release 通道——目前唯一产物形态 = Windows debug 目录便携；msix 打包 CI-only（签名证书），本地 `make windows-zip-release`（需 `dart pub global activate fastforge`）。

---

## 8. 下一个 AI 的第一分钟（操作序列）

1. 读本文 §0 现状 + §3.0 定案清单（12 条）+ §4 大坑实录（尤其 #8 代理变量 / #13 slang deferred / #12 git ref 幻象）。
2. `git -C S:\test\1\hiddify-app status --short` 确认干净；`git log --oneline -3` 应见文档整理提交（≥`c7d8bcbc`，2026-09-30 洗 token 历史重写后 force push 的新尖端，**全量已推送**）在顶；`git ls-remote origin my` 核对推送状态（tracking `[gone]` 是幻象，别信）。
3. 用户说「继续」时：按 §3 剩余 #10 的候选序列选功能②（推荐抽屉核验收口，规格 `S:\test\NekoBoxForAndroid\app\src\main\res\menu\nav_drawer.xml`），**先给方案再动手**；测试写法照抄 `test/features/proxy/proxies_menu_test.dart`（含 §4.13 slang 泵法）。
4. 跑测试前记得 unset 四个代理变量；跑完以输出尾部 `All tests passed` 为准。
