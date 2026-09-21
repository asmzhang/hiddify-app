# 交接文档 — hiddify-app（新机器迁移 + NekoBox UI 复刻）

> 写于 2026-09-14 晚，2026-09-21 刷新（chain 方向修正 + 内核级验证后）。上一份 anytls 修复交接（D:\ 时代）已被本文取代，
> 旧版可在 git 历史找回：`git show d3e958a5~40:HANDOVER.md` 附近。
> 目的：任何人（或没有上下文的 AI）读完就能接着干。

---

## 0. 一句话现状

**工程完整可构建可测（Windows debug 版），NekoBox 复刻推进到批次 14 路由规则 NekoBox 全语义完成 + wireguard endpoint 结构验证通关（主仓库已推送至 01625128，core 至 eb52b62）；
实体层（分组/节点编辑/分享/去重/组装）+ 协议表单（15 类中 13 可用）+ 节点覆写（8.5）+ chain 串联已落地并经 HiddifyCli 实连验证（三断言全过）；
用户路由规则（rules UI → 内核）Go+Dart 双侧贯通并有契约校验；wireguard endpoint 配置结构经 HiddifyCli 真启动验证（`missing allowed ips` 内核契约 bug 已修 eb52b62）；
NekoBox 可做项复刻口径 ≈99%。剩：wireguard 实连（需真实凭据）、审计 B/C/D 三包、上游 PR。**

---

## 1. 环境事实（这台机器，照抄即用）

| 项 | 值 |
|---|---|
| 开发目录 | **`S:\test\1\hiddify-app`**（分支 `my`；老 `S:\test\hiddify-app` 是 git 损坏的历史项目，HEAD `620125ef`，实现可用 `git show 620125ef:<path>` 无损取出） |
| UI 线快照 | `S:\test\1\hiddify-app - 副本`（与主体逐字节一致，回滚用） |
| 规格源 | `S:\test\NekoBoxForAndroid`（Kotlin 源码；menu/preferences XML 是唯一规格准绳） |
| 架构参照 | `S:\test\Throne`（C++；看 configs / database / stats 的组织方式） |
| 仓库 | 顶层 `asmzhang/hiddify-app` + 8 层子模块（hiddify-core / hiddify-sing-box / ray2sing / replace 下 4 个），**全部本地 `my` 分支跟踪 `origin/my`** |
| Flutter | **3.38.5，mise 管理**（`mise use -g flutter@3.38.5`）；pub 走 `pub.flutter-io.cn` 镜像 |
| Go | **1.25.x 硬约束**（`mise use -g go@1.25.6`）。**1.26 会让 psiphon-tls 布局断言 panic**（核心 DLL 加载即崩、App 启动即退 code 2）。`make doctor` 已加检查 |
| cgo 编译器 | `C:\platform\llvm-mingw-20260908-ucrt-x86_64`（`make doctor` 能自动发现） |
| GOMODCACHE | 已固化 `go env -w GOMODCACHE=$env:USERPROFILE/go/pkg/mod2` |
| 网络代理 | `socks5h://127.0.0.1:7890` 可用 —— 核心库下载失败时给 curl 加 `--proxy` |
| proto 工具链 | **protoc 28.0 + protoc-gen-go v1.34.2 + protoc_plugin 23.0.0**（版本必须钉死，见 §4.3） |
| 测试订阅 | cpdd：`https://cpdd.one/sub?token=5514a186947f1120701fbf821ec4d168`（**39 anytls**）；yfjc：`https://yfjc.xyz/api/v1/client/subscribe?token=9cb751f5196c21453de652aea84aa938`（21 vless + 15 hysteria2，**无 anytls 属正常**） |
| 订阅 UA 机制 | App UA（`HiddifyNext/... sing-box v2ray`）→ 面板返回 sing-box JSON（anytls 保留）；浏览器 UA 会返回 Clash YAML（丢 anytls） |
| 深链导入 | `hiddify://import/<订阅URL>` → 弹确认框 + 预填 sheet。**有防零点击 SSRF 的确认设计，需人工点两次，不要绕过** |

---

## 2. 提交清单（2026-09-14 会话 16 个 + 9-16~9-20 批次 1-9，**均未推送 origin/my**）

**环境/修复（换机恢复，09-14）**
- `f904b5e4` Makefile PATH 截断修复 / `25559a81` doctor Go 版本检查 / `92db036d` 钉死代码生成器版本
- 规范：`22f46190` 行尾 LF 唯一化 / `3d3a7ef5` CI 门禁 / `88dfbbde` 镜像版 pubspec.lock（勿回退）
- NekoBox UI 一期（`d3e958a5`→`b786d886`）：主题色板/主壳/卡片分组/设置/拖拽排序/导航命名

**实体线 + 复刻批次（09-16 → 09-20，`cee9d6c2` → `533a5c0d`）**
- 批次 1 `cee9d6c2` 实体层移植（分组/节点实体 + drift v7，211 files）
- 批次 2 `cde4620e` 协议表单 4→10；2.5 `8bc2228b` 路由 per-rule package routing
- 批次 3 `868dd0bf` 节点分享标准链接（8 协议，hiddify-core 侧 ray2sing 往返校验）
- 批次 4 `2fd360fc` 连接测试进度对话框 + FAQ；审计修复 `406a5bdd`（pop 竞态）
- 批次 5 `054b9c1a` 清流量统计（⋮ 菜单 8/8 收官）
- `80aba722` **Windows 构建通关**（hiddify-core.dll + 插件 junction + CMakeLists 注释 install）
- `f9206fa9` Windows 集成测试冒烟（integration_test/main_test.dart 全绿）
- 批次 6 `6abbaba1` trojan + hysteria v1 表单（手动菜单 12 项；valueSuffix 机制）
- 批次 7 `06ac24b7` 设置页 NekoBox 对照审计（38 项：21 覆盖 + 9 等价 + 8 挂起）
- 批次 8 `cac9fb4e` custom_config 全局自定义配置（两阶段 raw 通道，docs/design/custom-config-2026-09-18.md）
- 批次 9 `533a5c0d` wireguard endpoint 表单 + endpoints 通路（docs/design/wireguard-endpoint-2026-09-18.md；手动菜单 13 项）
- 切片 8.5 `43215367` 节点级自定义配置覆写（customOutbound/customConfig 两列；drift v8）
- `3d7423a4` 迁移测试补 v7→v8 覆盖
- **批次 10 `428a2cb9` chain 任意节点串联**（docs/design/chain-2026-09-20.md；type='chain' 实体 + buildChainOutbounds 组装 + ChainSettings 弹窗；手动菜单 +chain；复刻口径 ≈95%）
- **`c0527aa6` chain detour 方向修正**（内核级验证抓出：v1 方向反了会被静默旁路；按 ConfigBuilder.kt:311 + sing-box DialerOptions 语义重写为落地穿中间跳→入口直连 + 同名成员 #N 防撞；HiddifyCli run7/run9 三断言全过——①配置启动 ②curl 出口=落地节点出口≠入口出口 ③§hide§ 不进 select 组。验证通道与坑见 .workbuddy/memory/2026-09-21.md）
- **`2bf37a8b` custom_config raw 通道实机验证闭环 + createService 假失败修复**（integration_test/custom_config_test.dart 全绿：真 Windows 内核全链路 prefs→addLocal(Parse FFI)→节点覆写 DB 直写→reconnect raw 通道→clash API @16990 探针 HTTP 200 = raw 启动 + 节点覆写生效的运行态硬证据；顺带修 core_status.dart 的 ALREADY_STOPPED→createService 误映射——内核 stop.go:32 良性回执被当成假失败日志的根因）
- **批次 12 `a92bd582` http 表单**（协议表单收官，NekoBox HttpBean 移植）：字段照 `StandardV2RaySettingsActivity.kt:103-109` 对 HttpBean 的可见性裁剪 = server/port/username/password + TLS 段（security→tls.enabled，关 ⇒ tls 连根删，同 vless/trojan 构型）。**host/path 不移植**：`V2RayFmt.kt:628-637` HttpBean 分支只搬 server/port/username/password/tls——UI 显示但构建期不读，是死字段；内核 `HTTPOutboundOptions`（simple.go:32-40）也无 Host（host 属 headers map[string][]string，文本表单写不出正确形状）。菜单位 = `action_new_http` 紧跟 socks（add_profile_menu.xml 第 2 项），显示名 HTTP（strings.xml:213）。手动菜单 14 项（NekoBox 17 项里 trojan_go 内核缺出站不移植、其余全齐）
- **批次 11 `a779c2c8` config 类型节点**（NekoBox ConfigBean 双形态移植）：type='config' 实体，payload=用户手写 JSON。**outbound 形态**（顶层有 `type` 键）照普通节点进 outbounds 段 + tag 组装期注入（ConfigBuilder.kt:402 `_hack_config_map` 语义）；**full 形态**（无 `type` 键）= payload 即启动配置本体，旁路整个 outbounds 拼装（ConfigBuilder.kt:66-78 type=0 分支对应物，`assembleConfigEntityConfig`；≥2 个 full 实体=语义无定义→回落常规路径）。UI：ConfigSettings 弹窗（名称+JSON 编辑器+**按内容自动识别形态**提示——NekoBox 的 isOutboundOnly 开关可能与其 JSON 自相矛盾，自动识别让 UI 提示与组装判据永远同一路径）；手动菜单 +config（NekoBox 菜单序 config 紧挨 chain 前）；分享隐藏（haveLink=false）；full 形态不可做 chain 成员（outbound 形态可以）
- **批次 13 `8483aeeb`(core) + `e646299e` Go 侧、`<本提交>` Dart 侧 路由规则活通**（geo 资源管理页**不移植**的等价物；Task #40 重定义）：
  - **Go 侧**（hiddify-core `03f70ba`，4 files +507/−135）：新建 `v2/config/route_rules.go`（proto Rule → sing-box 1.13 option.DefaultRule/DefaultDNSRule 全字段映射；rule-set URL 展开/去重/5 天更新周期）+ `route_rules_test.go`（7 测试钉 Dart JSON 契约：复数键 + 数字枚举）+ builder.go 注释块换 `makeUserRouteRules()` + 删遗留 rules.go。
  - **Dart 侧**：根因 = `config_option_repository.dart:572` 发 `RouteRule.toProto3Json()`——proto3 JSON 单数键（rule_set/package_name）+ 枚举名（"direct"），而 Go pb.go json tag 是复数 + 数字枚举，unmarshal **静默丢弃**（上游注释掉消费点的原始动机）；叠加 freezed kebab rename 后顶层键 `route-rule` ≠ Go tag `rules` 且类型是对象不是数组，双重死亡。修复：模型字段 `routeRule: Map` → `rules: List<Map<String,dynamic>>`（kebab 后顶层键即 `rules`）；新建 `lib/features/route_rules/data/route_rule_json.dart`（routeRuleToCoreJson：只发显式赋值字段、复数 tag、枚举发 .value 数字、network=all 不发键；coreJsonToRules 反向读回供导入流）。
  - **校验**：`tool/check_route_rule_json.dart` 25 断言（契约形状/枚举锚定/空字段不发键/往返幂等/Go fixture 互验）+ `tool/check_route_rules_option_roundtrip.dart`（SingboxConfigOption 层 toJson→fromJson 无损 + 最终 HiddifySettingsJson 片段形状）全绿；flutter test 76/76；dart analyze 0 error 0 warning。
  - **坑**：dart run 直接跑引用 Flutter SDK 的 tool 脚本会撞 Flutter SDK 自身 Dart 版本编译错（text_painter.dart），要用 `flutter test tool/xxx.dart` 跑；flutter test 前必须 unset 代理变量（WebSocketException 老坑）。
- **批次 14 路由规则 NekoBox 全语义（`2b4d08c`(core)+`d7f6dabc` 前半、`eb37a6d`(core)+`78c6e8b7` 后半，均已推送）**：
  - **前半：前缀语义**（NekoBox `SingBoxOptionsUtil.makeSingBoxRule` + `ConfigBuilder.kt:499-603`）。Go `expandUserRuleDomains/expandUserRuleIps`：domains 列吃 `geosite:/full:/domain:/regexp:/keyword:`（裸值→suffix，全 lowercase），ip 列吃 `geoip:`（`geoip:private`→IPIsPrivate 内建条件，其余→rule-set）。geo 引用走 **MetaCubeX meta-rules-dat 远程 .srs**（`geosite:cn`→URL `.../geo/geosite/cn.srs`，tag `geosite-cn`），复用批次 13 注册+去重池（无 geo 资产管线定案的等价通路）。DNS 规则只吃域名桶（NekoBox 只喂 rule.domains）。**关键语义：Domains/IpCidrs 是前缀承载字段，展开结果替代原值**（合并会泄漏原串进规则——测试抓过）；suffix/keyword/regex 显式 pb 值才与展开 mergeUnique。Dart：validators `isDomainInput/isIpInput` 前缀化；**预定义规则裸 tag 启动失败 bug 顺带修复**（原 `geosite-category-ads-all` 等无人注册→选中即启动失败）。
  - **后半：规则指向节点/分组 + 每规则覆写**（NekoBox `RuleEntity.outbound`→`tagMap[id]`（ConfigBuilder.kt:577）与 `RuleEntity.config`→`_hack_custom_config`（:584)）。proto Rule 加 `outbound_tag=19`/`config=20`，钉死工具链按文件定向重生成（protoc `--go_out=.` **不是** `--go_out=./v2/config`——后者 paths=source_relative 会错位产 v2/config/v2/）。Go：outbound_tag 非空⇒路由到该 tag 且**不产 DNS 规则**（NekoBox when 只处理 bypass/proxy/block）；config 走 marshal→mergeMap→unmarshal（可接受键=sing-box 解析器本身，无第二事实源；list REPLACE/map 递归/标量覆盖；坏 JSON fail-open 记日志）。Dart：转换器直通两字段（契约 31 断言）；UI = 「路由到节点」**选择器**（selectableChainMembers 数据源 + None 清空——手输 tag 未知会让 sing-box 启动校验失败，故不做自由文本）+「自定义配置」JSON 编辑（对象校验）；translations en/zh-CN/zh-TW。
  - **校验**：go test 18 全绿（含 outbound_tag 覆盖枚举/不发 DNS、config 覆盖/坏 JSON/未知键）+ dart analyze 0 error 0 warning + 契约 31 断言/option 往返 + DLL 重构建 + Windows 冒烟全绿。
- **wireguard endpoint 结构验证通关 + 内核契约 bug 修复（core `eb52b62`，主仓库 `01625128`，均已推送）**：
  - **HiddifyCli 验证通道摸清**：`bin/HiddifyCli.exe run -c config.json -d settings.json --log info`；`-c` = sing-box 原生配置（顶层 `endpoints` 段直接进 `option.Options.Endpoints`，settings **没有** endpoints 字段——builder.go:220 的 `input.Endpoints` 宿主是 `-c` 配置不是 `-d` settings）；`-d` = HiddifyOptions（log-level/balancer-strategy/remote-dns/direct-dns/region 必给全）；解析链 = `ParseBuildConfig`（非全量只提取 outbounds+endpoints）→ patchWarp → CheckConfigOptions → BuildConfig（endpoint tag 非 `§hide§` 进 selector 组）→ StartService。**构建入口必须 `./cmd/main`**（`./cmd` 产 6MB 无 tag 残废二进制）。
  - **抓到并修复批次 9 遗留 bug**：sing-box 内核对 wireguard endpoint 的每个 peer **硬校验 allowed_ips**（`transport/wireguard/endpoint.go:82` "missing allowed ips for peer N"），而批次 9 表单 8 字段没有 allowed_ips（NekoBox Bean 也没有——它的 legacy 扁平 outbound 形态无此约束）。修复 = 内核 `patchWarp` 给缺失 allowed_ips 的 peer 补默认 `0.0.0.0/0 + ::/0`（full-tunnel，与 WARP builder warp.go:57 同语义），在 parse 与 final 两阶段都生效（parse 阶段的 CheckConfigOptions 也会初始化 endpoint 校验）。
  - **验证闭环**：不带 allowed_ips 的 wg endpoint 配置 → HiddifyCli 真启动成功（`sing-box started 5.05s`）→ endpoint 进 selector 组 → final 配置里 allowed_ips 已自动补上。go test 全绿无回归。
  - **实连清单（剩）**：需用户提供真实 wireguard 凭据（private_key/peer public_key/endpoint host:port/local address CIDR），在 app 表单填入真节点后 FAB 连接验证握手；测试残留已清理（bin/wg-test 删除）。

---

## 3. 进度与剩余（按优先级）

**设计原则（已与用户定案，不要推翻）**：NekoBox 壳 + hiddify 芯 / FAB 四态唯一开关 / 手机 Drawer + PC(≥600dp) NavigationRail / 归一原则 / 每步一提交。规格源唯一 = NekoBoxForAndroid（nekoray 不进决策链）。

**已完成**：主题色板/主壳/主页卡片/分组页（滑删+拖拽）/导航命名 ‖ 实体层（分组+节点+编辑+分享+删除+去重+组装）‖ ⋮ 菜单 8/8、抽屉 10/11 ‖ 协议表单 14/15（socks/http/ss/vless/vmess/trojan/hy1/hy2/tuic/shadowtls/anytls/mieru/naive/ssh/wireguard）‖ 设置页审计归一 ‖ custom_config 全局（两阶段 raw）‖ 节点级覆写（切片 8.5）‖ wireguard endpoint 通路 ‖ **chain 任意串联**（批次 10）‖ **config 类型节点**（批次 11）‖ **http 表单**（批次 12，`a92bd582`）‖ Windows 构建 + 冒烟测试。

**剩余（按优先级）**：
1. ~~实机验证 custom_config raw 通道 + 节点级覆写~~ **已完成**（`2bf37a8b`）。~~wireguard 表单结构验证~~ **已完成**（core `eb52b62`：allowed_ips 缺省契约 bug 修复 + HiddifyCli 真启动验证）。**剩余 wireguard 真实握手**（需用户提供真实凭据/端点，其余链路已全通）
2. ~~切片 8.5~~ **已完成**（`43215367`）
3. ~~chain 任意节点串联~~ **已完成 + 内核级验证闭环**（`428a2cb9` + `c0527aa6`，设计 docs/design/chain-2026-09-20.md §D2 含方向修正记录）
4. ~~config 类型节点~~ **已完成**（`a779c2c8`，批次 11）。~~协议表单剩 http 可选~~ **已完成**（`a92bd582`，批次 12：host/path 是 NekoBox 构建期死字段 V2RayFmt.kt:628-637 不消费、内核 HTTPOutboundOptions 也无 Host，不移植）。~~geo 资源管理~~ **不移植（批次 13 定案）**：sing-box 1.13 内核 legacy geo 已移除（本地 .db 无读取通道）、Throne 同架构也无资产页（2197 条名称→.srs URL 目录编译进 srslist.h）——等价物 = **路由规则活通 + NekoBox 全语义（前缀/指向节点/每规则覆写），已完成**（批次 13 + 14；远程 .srs 缓存进内核 cache.db 无用户可见文件）。路由规则 UI 对照差异仅剩：domain 列可收敛为单一输入框（语义层已生效，纯 UI 形态问题）
5. 审计 B 供应链包：CORE_FETCH 加 sha256、git 依赖锁 ref、启用 flutter-version-file、CI 缓存 core-libs
6. 审计 C 安全包：gRPC 明文+固定端口 17078+`Random()` 非安全随机、Sentry 默认上送订阅内容、3 处空 catch 补日志
7. 审计 D 架构包：core→features 14 处逆依赖、FFI 门面收敛、riverpod 风格统一、json_editor.dart 拆分、3 个业务测试
8. **推送 origin/my**（落后 25+ 提交）+ 上游 PR（anytls 修复 + Makefile PATH 修复提给 hiddify 官方）

---

## 4. 大坑实录（换机/新环境必读）

1. **make 的 sh 里 PATH 被截断**：agent/IDE 注入 `\\?\` 设备路径条目 + Makefile 的 POSIX 前缀（`/usr/bin:/bin:`）→ MSYS 按冒号解析、在盘符冒号处整串切碎 → recipe 里 curl/git 全失踪，但 make 直启的命令正常（极具迷惑性）。已修（Makefile 15-38 行：Windows 格式前缀 + subst 剥离 `\\?\`）。
2. **Go 版本**：1.26 编核心 → 运行时 panic（psiphon-tls 断言）。**永远用 1.25.x**，doctor 会查。
3. **pubspec.lock 与镜像**：`PUB_HOSTED_URL=pub.flutter-io.cn` 与 lock 里 `pub.dev` 来源不匹配 → pub 每次 pub get 重解析（版本在约束内漂移）。已提交镜像版 lock 为基线；pub.dev 机器（CI）自行解析不回写。**不要试图"恢复干净 lock"——那是死循环**。
4. **单实例**：旧实例还在跑时启动新构建 → 新进程握手后 exit 0（像闪退）。烟测前先杀干净 Hiddify 进程。
5. **生成代码不入库**：新机器必须 `dart run build_runner build --delete-conflicting-outputs`（freezed/slang/drift/riverpod 全靠它），否则 analyze 报一堆 undefined。**必须全量跑**：`--build-filter` 会漏掉 slang 真正输出（lib/gen/translations_*.g.dart）。
6. **git submodule update 不带 `--remote` 会锁死在父仓库记录的 SHA**（游离 HEAD）——本项目约定全层跟 `my` 分支，见 docs/BUILD.md「取源码」节。
7. **后台任务里跑 git checkout 会留下半路状态**（index.lock / 半删文件）——git 操作放前台。
8. **flutter test 前必须 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`**——代理变量存在（哪怕指向已关闭的本地端口）就劫持 flutter_tester 本地 WebSocket，全部测试 "Invalid WebSocket upgrade request" 挂载失败。
9. **`for (final x in list ?? const [])` 类型陷阱**：裸 `const []` 让 `??` 的类型 LUB 劣化，循环变量掉成 `Object?` → 4 个 error + dead_code。必须 `const <Map<String, dynamic>>[]` 或 `if (list != null)` 包裹。
10. **全量 flutter analyze 被沙箱 reg.EXE 黑名单拦截** → 用 `dart analyze lib test tool` 分目录替代。
11. **Windows 构建三关**（详见 .workbuddy/memory/MEMORY.md「Windows 构建链」）：hiddify-core.dll 不带 with_ech / 插件 junction 预建（tool/ensure_plugin_junctions.ps1）/ CMakeLists 两条 install 已注释。

### 4.3 proto 生成工具链（改 .proto 才需要；版本必须钉死）

**版本钉子**（改 proto 前先确认，用错版本会产出成百上千行噪声 diff，甚至直接编译失败）：

| 工具 | 版本 | 与仓库关系 |
|---|---|---|
| `protoc` | **28.0** | 仓库多数 `*.pb.go` 头部的 `protoc v5.28.0` 就是它（protoc 28.0 的内部版本号打印为 5.28.0） |
| `protoc-gen-go` | **v1.34.2** | 仓库多数 `*.pb.go` 头部一致（另有 2 个 v1.36.11、1 个 v1.33.0 是历史遗留，**不要重生成那两个**） |
| `protoc_plugin`（protoc-gen-dart） | **23.0.0** | 仓库多数 `*.pb.dart` 一致。**24.0.0 删了 `createRepeated()`**；21.x 产 `@dart = 2.12` 旧风格；22.0.0 自带生成代码要 protobuf 5.x 而其 pubspec 写 `^3.1.0` → `pub global activate` 直接编译失败 |

**换机器准备**（全部走包管理器/源码，无需手动下 zip）：
```bash
mise install                                                      # 按仓库内 .mise.toml：protoc=28.0、protoc-gen-go=1.34.2、go=1.25.6、flutter=3.38.5
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
mise use -g go@1.25.6
go env -w "GOMODCACHE=$env:USERPROFILE/go/pkg/mod2"
# 1) 源码（全层 my）
git clone -b my https://github.com/asmzhang/hiddify-app.git && cd hiddify-app
git submodule update --init --recursive --remote
# 2) 自检（Required 无 FAIL 即可；go module cache 的 FAIL 是保守启发式）
make doctor
# 3) 准备（pub get + 代码生成 + 核心库；本地编核心加 LOCAL_CORE=1）
make windows-prepare LOCAL_CORE=1 CORE_GOPROXY=https://goproxy.cn,direct
# 4) 构建与验收
flutter build windows --release
.\build\windows\x64\runner\Release\Hiddify.exe
# 导入订阅：＋ 粘贴 URL，或（App 运行时）Start-Process "hiddify://import/<订阅URL>"
```

---

## 7. 已知未修（诚实清单）

- CI 上这批提交还没实际跑过（push 后首次 CI 才是最终背书）
- Android/iOS/Linux/macOS 构建链未在新机器实测（流程在 BUILD.md/CI 里）
- 路由页 geo 资源管理、分组手动实体：需模型/后端设计，勿在 UI 层硬凑
- msix 打包永远 CI-only（签名证书）；本地用 `make windows-zip-release`（需 `dart pub global activate fastforge`）
