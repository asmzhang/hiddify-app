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

**四份记录各写什么（2026-10-02 定案，写之前先对表，别再重复）**：

| 文件 | 只写 | 不写 | 入库 |
|---|---|---|---|
| **`HANDOVER.md`（本文）** | 现状快照 / 定案清单 / 大坑 / 未验证项 / **状态与锚点** | **任何过程推理与逐条明细** | ✅ |
| `docs/design/*.md` | 分主题的设计与逐功能明细（如 `parity-sequence-log.md`） | 易变状态（状态放本文） | ✅ |
| `.workbuddy/memory/MEMORY.md` | 长期稳定事实（环境 / 约定 / 规程） | 逐次收口细节 | ❌ gitignored |
| `.workbuddy/memory/YYYY-MM-DD.md` | 当日发生了什么（可含完整推理） | 稳定事实（会与 MEMORY 重复） | ❌ gitignored |
| `.workbuddy/spec-*.md` | 规格矩阵与缺口表 | 实现过程 | ❌ gitignored |

**硬约束**：本文是**唯一入库**的记录（`.workbuddy/` 整个 gitignored，`.gitignore:54`），所以它必须保持
**「一小时读完」**。明细一律外链 —— 本文出现「需要工具取样才能读」的超长行（历史峰值单行 9298 字符）
即为结构失败的信号。

**不再写记账提交**（2026-10-02 定案）：`docs: anchor X (SHA)` 这类提交零信息熵（`git log` 本身就记 SHA），
历史里曾占 53%。改为：功能提交的 message 自带锚点，本文随下一次功能提交一起更新。

**如果你是新会话的 AI 且用户只说「继续」**：先读完本文与 MEMORY.md，按上表分层采信，然后从 §3「剩余」清单顶部选活，**先给方案再动手**；方案分歧按「NekoBox 规格 → 复用已有机制 → 参考 Throne → 自己实现」自行推导定案，不要把可推导的问题退回给用户。

快速验证工具（A 层结论的复现入口）：`make doctor`（环境）/ `flutter test test/`（Dart，**先 unset 代理变量**）/ `dart analyze lib test tool`（分目录）/ `go test ./...`（在 hiddify-core/）/ `HiddifyCli.exe run -c <cfg> -d <settings> --log info`（内核配置验证）。

**文档地图（2026-10-03 精简后；`docs/` 现有 8 份）**：

| 文件 | 写什么 |
|---|---|
| `HANDOVER.md`（本文） | 状态快照 / 定案 / 大坑 / 未验证 / 锚点 |
| `docs/design/nekobox-parity.md` | NekoBox 逐项对照规格（导航 / 工具栏 / 菜单 / 设置 / 协议表单 / 实体） |
| `docs/design/parity-sequence-log.md` | 1:1 序列逐功能记录 + 方法纪律 + **附录：批次 1–14 落地记录**（原本文 §2） |
| `docs/design/implementation-notes.md` | 批次 8–10 落地特性实现笔记（custom_config / 节点级覆写 / wireguard endpoint / chain） |
| `docs/design/core-architecture-comparison.md` | 与 NekoBox 的底层架构差异（为何 fork） |
| `docs/design/proxy-model-root-fix.md` | 三处真相源模型与根治路线（Phase 1 已完成，2/3 未做） |
| `docs/design/connection-model.md` | 连接模型（三档接管 / 订阅切换 / 依赖关系） |
| `docs/design/layering.md` | 分层规则与逆依赖收敛 |
| `docs/BUILD.md` | 构建指南 |

> **已删除的文档**（2026-10-03 精简，内容已折入上表对应文件）：`docs/audit/` 三份 2026-09-15 审计（↔ `nekobox-parity.md` /
> `proxy-model-root-fix.md`）、`docs/design/nekobox-priority.md`（批次顺序已消费）、`docs/design/ui-real-device-observations-2026-09-22.md`
> （被真机证据取代）、以及并入 `implementation-notes.md` 的四份带日期实现笔记。
> **找回**：`git log --diff-filter=D -- docs/` 列出删除提交，`git show <sha>^:<path>` 取回原文。

---

## 0. 一句话现状

**工程完整可构建可测（Windows debug 版）；NekoBox 复刻的可做项已全部落地**——批次 1-14 + 审计 B/C/D + Go 1.27 升级 +
**「1:1 逐功能对比」序列 20 项已完成 19 项**（**明细与逐项锚点见下方 §3.0#10 状态表**，本文不重复）。
**八项真缺口全部收敛**（6 修 + 2 有意不行动）。主仓库与 core 子模块均已全量推送（core 远端 my = `1075e82`）。
**推送态以实测为准**：`git ls-remote origin my` 比对本地 HEAD——本文随功能提交一起推送，所以**不要用本文件里写的 SHA 判断是否落后**，
也不要信 `git status` 的 `ahead N` / `[gone]`（沙箱里 tracking ref 会静默失写，见 §4#12）。

**唯一未做项**：⑨ 终验收的 **Windows 真机窗口**部分（需真机上肉眼观察，自动化到此为止）。
（安卓真机侧的 1:1 对比已完成 —— 八项真缺口在真机 NekoBox 旁逐条复验通过，证据在 `.workbuddy/device/`。
其余「未验证通道」性质不同 —— CI 首跑背书 / Android·iOS 构建链 / wireguard 真实握手 / 发布工程，
见 §7 未验证清单，那些不是本序列的剩余项。）

以下三条是长期定案，不随进度变化：
- **「1:1 逐功能对比」阶段口径**（用户定案，§3.0#11）：按用户真实使用顺序逐功能对比，每项 = 抽规格 → L1 红灯 → 修正 → 全绿提交 → 记档。
- **翻译策略**（§3.0#12）：测试与验收一律以 **zh-CN** 为基准，en 仅作 slang base_locale 保键同步；①功能①阶段其余 8 语言键曾脱节，**已于 `17f32a0b` 全量补齐清零**。
- **暂缓/不做**：wireguard 真实握手（无凭据，用户定案暂缓）、上游 PR（anytls + Makefile PATH 提给 hiddify 官方；前置「洗 token 历史」已完成，本身未做）。

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

## 2. 提交清单（索引）

> 逐批明细（环境修复 / 批次 1–14 / 各次根因修复）已移入 `docs/design/parity-sequence-log.md` 附录「批次 1–14 落地记录」；
> 本节只留索引。找回历史提交用 `git log --oneline`，找回被删文档用 `git log --diff-filter=D -- docs/`。

- **环境/修复（换机恢复 09-14）**：`8c931843` Makefile PATH 截断 · `62da695b` doctor Go 版本检查 · `a961021a` 钉死代码生成器版本
- **规范**：`5bb8e28a` LF 唯一化 · `b3373c53` CI 门禁 · `64ed0e5e` mirror 版 pubspec.lock（**勿回退**）· AGP 8.6.0 敏感插件精确钉版（`pubspec.yaml` + `dependency_overrides`，见 §4 大坑 #3）
- **NekoBox UI 一期**：`117f5397` → `560b65b5`（色板 / 主壳 / 卡片分组 / 设置 / 拖拽排序 / 导航命名）
- **实体线 + 复刻批次（09-16 → 09-20）**：B1 `d9fc1aa8` 实体层（211 文件）· B2 `69c33934` 协议表单 4→10 · 2.5 `d387adfe` 每规则分应用 · B3 `e5d05926` 节点分享链接 · B4 `1ea4c8d6` 连接测试对话框 · B5 `56b8699b` 清空流量 · `15e27935` Windows 构建通过 · `3c2708e7` Windows 集成冒烟 · B6 `db8ee6f0` trojan+hysteria1 · B7 `39f6075a` 设置页对照审计 · B8 `b86d57f7` 全局 custom_config · B9 `c0cc2171` wireguard endpoint
- **实体层续**：8.5 `1fc06b58` 节点级自定义配置覆写（drift v8）· `7b10a467` v7→v8 迁移测试 · B10 `b13d7a16` chain 任意节点串联 + `142cfa29` 方向修正 · `98060f8d` raw 通道实机闭环 + createService 假失败
- **B11 `db8e1f1a` config 类型节点**（outbound 形态 / full 形态双形态）· **B12 `b07830af` http 表单**（host/path 不移植：内核无该字段）
- **B13 路由规则活通** `8483aeeb`(core) + `99f9c6f8`(Go) + Dart 侧：根因 `config_option_repository.dart:572` proto3 单数键 + 枚举名 vs Go 复数键 + 数字枚举 → 静默丢弃
- **B14 路由规则 NekoBox 全语义** `2b4d08c`/`eb37a6d`(core) + `78981c8a`/`d5268ad1`(Dart)：前缀语义（geosite:/full:/domain:/regexp:/keyword:、geoip:）+ 规则指向节点/分组 + 每规则覆写
- **wireguard endpoint 结构验证 + 内核契约修复** core `eb52b62` + 主仓 `c58b70af`（内核硬校验 allowed_ips；`patchWarp` 补 `0.0.0.0/0 + ::/0`）
- **各次根因修复**：`e86dfaa6` URL 测速双层 guard · `82a39b20` 节点页 ⋮ 菜单 1:1 八项 · `05c4e7a4` 日志页 + 测速闪帧 · `ee6ca57f` raw 通道 selector 归一化 · `15b41d37` 协议表单六缺口 · `6309e141` socks 密码按协议版本置灰
- **路由预置规则 1:1（fork A）** `bf78eb19`：新增 `lib/features/route_rules/data/predefined_rules.dart` 纯函数 `buildNekoBoxPresetRules(Translations, Region)`；删除 `predefined_rules_modal.dart` 及其 FAB 入口；`rules_notifier` 加 `ensureSeeded()`（以「规则文件是否存在」等价 NekoBox `rulesFirstCreate`）、`addRule` 去掉 `enabled = true` 硬编码、`resetRules()` 改无条件；`rule_notifier.dart:90` 新建分支补 `enabled: true`。顺带修掉旧弹窗把「拦截广告」写成 `Outbound.direct` 的语义 bug
- **验收期两处缺陷收口**：`92402771` 差异清单 D-1（分组页 AppBar 补移动端抽屉键）+ `d1969a87` 缺陷 K-1（配置页数据层出错不再整页替换列表）。两者都由 ⑨ 终验收的窄屏 sweep 抓出，明细见 `docs/design/parity-sequence-log.md`（D-1 见 `.workbuddy/acceptance_checklist.md`，该文件 gitignored；K-1 见该文 ⑨-b 节）

> 推送状态以 `git ls-remote origin my` 为准（本地 `git status` 的 ahead/behind 在沙箱里不可信）。

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
11. **UI 复刻新阶段 = 「1:1 逐功能对比」**（2026-09-22 拍板）：逐功能抽 NekoBox 规格 → L1 结构测试红灯 → 修正 → 全绿提交。节奏 = 一个功能一个功能推进。**当前进度见 §3.0#10 状态表**（不在此处维护）。
12. **翻译基准 = zh-CN**（2026-09-22 拍板）：**先只考虑 zh-CN，翻译放最后**。测试断言直接用 zh-CN 文案（对齐 NekoBox values-zh-rCN 词表）；en 仅作 slang base_locale 保持键同步；其余 8 语言（ar/es/fa/fr/id/pt-BR/ru/tr）本轮不碰，runtime 靠 `fallback_strategy: base_locale` 回退 en 不炸。
13. **「1:1 序列按用户使用顺序推进」**（2026-09-22 拍板）：功能对照顺序 = 用户真实动线（首启 → 添加配置 → 配置页 → 连接 → 抽屉/分组/订阅 → 路由 → 设置 → 日志/仪表板/工具/关于），不按界面架构排。已完成的 ⋮ 菜单/抽屉/分组页/分组设置视为按此序"提前完成"的条目，后续从序列最前端未完成项续作。

**设计原则（同 B 层，浓缩版）**：NekoBox 壳 + hiddify 芯 / FAB 四态唯一开关 / 手机 Drawer + PC(≥600dp) NavigationRail / 归一原则 / 每步一提交。规格源唯一 = NekoBoxForAndroid（nekoray 不进决策链）。

**已完成**：主题色板/主壳/主页卡片/分组页（滑删+拖拽）/导航命名 ‖ 实体层（分组+节点+编辑+分享+删除+去重+组装）‖ ⋮ 菜单 8/8（功能①1:1 收口 `82a39b20`）、抽屉 10/11 ‖ 协议表单 14/15（socks/http/ss/vless/vmess/trojan/hy1/hy2/tuic/shadowtls/anytls/mieru/naive/ssh/wireguard）‖ 设置页审计归一 ‖ custom_config 全局（两阶段 raw）‖ 节点级覆写（切片 8.5）‖ wireguard endpoint 通路 ‖ **chain 任意串联**（批次 10）‖ **config 类型节点**（批次 11）‖ **http 表单**（批次 12，`b07830af`）‖ Windows 构建 + 冒烟测试 ‖ 审计 B/C/D + Go 1.27.1 升级。

**剩余（按优先级）**：
1. ~~实机验证 custom_config raw 通道 + 节点级覆写~~ **已完成**（`98060f8d`）。~~wireguard 表单结构验证~~ **已完成**（core `eb52b62`：allowed_ips 缺省契约 bug 修复 + HiddifyCli 真启动验证）。**剩余 wireguard 真实握手**（需用户提供真实凭据/端点，其余链路已全通）
2. ~~切片 8.5~~ **已完成**（`1fc06b58`）
3. ~~chain 任意节点串联~~ **已完成 + 内核级验证闭环**（`b13d7a16` + `142cfa29`，设计见 docs/design/implementation-notes.md 批次 10（§D2 含方向修正记录））
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
10. **「1:1 逐功能对比」序列（§3.0#13：按用户使用顺序排）** —— **明细已移至
    `docs/design/parity-sequence-log.md`**（每功能的规格抽取 / 测试用例 / 对比收口裁定 / 测试坑）。
    本节只留状态与锚点：

    | 功能 | 状态 | 锚点 |
    |---|---|---|
    | 节点页 ⋮ 菜单 ① | ✅ 8 项权威顺序 | `82a39b20` |
    | 抽屉核验收口 ② | ✅ | `3931652e` |
    | 分组页 ③ | ✅ | `32783b20` |
    | 分组设置 ④ | ✅ | `82f19327` |
    | 配置页主体（NkProfileTile） | ✅ 无修正项 | `567a45f4` |
    | 连接链路（状态条/FAB 四态） | ✅ 通知面=平台差异 | `c7d8bcbc` |
    | 添加配置流（AddProfileModal） | ✅ 无修正项 | `5fc3cb35` |
    | 订阅页 | ✅ | `ec4dd8ec` |
    | 路由页 | ✅ 增强面非缺口 | `4136b3c0` |
    | 设置页 | ✅ 无修正项 | `e0339608` |
    | 日志页 | ✅ 原生组合无对位 | `006b50b3` |
    | 仪表板/工具/关于 | ⏸️ 定性不立测 | `docs/design/parity-sequence-log.md` ⑥ |
    | 首启引导 ⑦ | ⏸️ NekoBox 无 onboarding 不移植 | — |
    | 手动新建节点链 ① | ✅ 12 用例 | `9231100c` + `429bf873` |
    | ⑤协议表单字段级 P0 | ✅ 12 用例 | `ba21921d` |
    | ⑤协议表单字段级 P1 | ✅ 15 用例 | `4c0c1da0` |
    | ⑤协议表单字段级 P2 | ✅ 20 用例 | `1a750b50` |
    | 协议表单六缺口修复 | ✅ 见 §2 | `15b41d37` |
    | 真缺口 #5 socks 密码置灰 | ✅ 见 §2 | `6309e141` |
    | ⑧ 9 语言翻译补全 | ✅ i18n 缺口清零 | `17f32a0b` |
    | 路由页预置规则 1:1（fork A：自动种 + 默认关 + 删弹窗） | ✅ 13+4 用例 | `bf78eb19` |
    | ⑨ 小屏形态（360/320dp） | ✅ 10 用例 | `4f77caee` |
    | ⑨ 安卓真机 1:1 对比（vs NekoBox） | ✅ 八项真缺口全部真机复验通过 | 证据 `.workbuddy/device/`（gitignored） |
    | ⑨ Windows 真机窗口验收 | ❌ **未做**（工具已就位） | 见下方「真机自测工具链」 |

    **方法纪律**（每功能的执行口径与「对比收口」三种结论、缺口定性顺序）见
    `docs/design/parity-sequence-log.md` 末两节；widget 测试横切六坑亦在该文。
- **`6309e141` socks 密码随协议置灰（2026-10-01，真缺口 #5 收口）**：八项真缺口的**最后一项**。定性 → 实现 → 测试全链见 `docs/design/parity-sequence-log.md` 与 `.workbuddy/spec-protocol-forms-tests.md` §5。**一句话结论**：内核 4/4a 只传 username（`sing protocol/socks/client.go:128-135` `ClientHandshake4(..., c.username)`）⇒ password 是惰性字段，这正是 NekoBox 隐藏它的理由 ⇒ 我方**不移植隐藏、统一置灰**（`disabledWhen` 机制），值保留且照写 ⇒ **两边 payload 等价，差异仅在显示**。全量 `flutter test` **274/274 passed**，analyze lib+test 零 info（tool/ 17 info 基线）。

**真机自测工具链**（⑨ 用；10 个脚本全在 `.workbuddy/`，gitignored 不入库；四步链路 = 截图 → 像素定位 → 点击 → 数据库校验，见 `docs/design/nekobox-parity.md:890-895` §8.6.15）：

| 脚本 | 调用 | 作用与关键点 |
|---|---|---|
| `win.py` | `python win.py list` / `show <hwnd>` / `shot <hwnd> <out.png>` | 枚举 Hiddify.exe **全部**顶层窗口（含托盘/不可见）。**按 pid 枚举，不要按 `IsWindowVisible`**——本应用可能静默启动到托盘 |
| `shot.py` | `python shot.py list` / `shot <hwnd> <out.png>` | GDI `PrintWindow(hwnd, hdc, **2**)` 截窗口；**必须传 2**（PW_RENDERFULLCONTENT），否则 Flutter GPU 合成面全黑。自写 zlib PNG，无 PIL |
| `px.py` | `python px.py <png> <y> [x0] [x1]` | 解自写 PNG（filter=0/RGB），在指定行找深色像素区间 → 量图标 x 坐标 |
| `click.py` | `python click.py <hwnd> <x> <y> [--move-only]` | 先置前并核对 `GetForegroundWindow()`，**非前台绝不点**；坐标以窗口左上角为原点、与截图同尺度 |
| `kbd.py` | `unicode <hwnd> <退格数> <文本>` / `replace <hwnd> <退格数> <数字>` | 文本注入。本机**中文输入法**会截获 `keybd_event` 的 ASCII 虚拟键（实测 `testnodeb3` → 『特色t'no'de'b』）⇒ 必须走 `KEYEVENTF_UNICODE`；`SendInput` 的 `INPUT` 在 x64 上是 **40 字节**，少声明则返回 0 + `GetLastError()==87` 且**静默不报错** |
| `grab_screen.py` | `tour` / `click <ix> <iy> [out]` / `app\|window\|mockup\|shot` | 启动 Release 构建并自动巡游截图（`shot_1_config.png`…`shot_10_profile_details.png`）；`WAIT_S`(16/18)、`CLICK_WAIT`(1.5) 可控 |
| `verify_tcp_ping.py` | `python verify_tcp_ping.py` | 代理页 ⋮ → TCP 测速 → 断 DB：部分 status=1 / 部分 2-3 且 error 非空；**hysteria2/tuic/wireguard 不被测**（`canTcpPing` 白名单，status 保持 0） |
| `verify_delete_e2e.py` | `python verify_delete_e2e.py [profileId]` | 审计 F1「删除的节点被订阅基准复活」端到端回归（默认 profileId `e2d4f850-47c7-41e1-92b8-e1708a0cecd8`） |
| `undo_test.py` | `python undo_test.py` | 删除→截图→撤销→截图，每步读 DB 计数（含硬编码坐标 `(1191,156)` 删除 / `(1166,639)` 撤销） |

**另两条实测纪律**：①`Ctrl+A` 在 Flutter `TextField` 上不可靠（实测变成追加）⇒ **退格清空再输入**；②聊天窗显示的截图被缩放过（实测显示宽 1092 vs 实际 1230）⇒ **按显示坐标点会偏 ~11%**，一律用 `px.py` 从原始 PNG 量。
**⚠️ 自测会改真实数据**（`%APPDATA%\Hiddify\hiddify\db.sqlite`）：收尾必须按订阅原文把数据补回并在日志/DB 复核（前例：48 → 46 → 补齐回 48）。
**待办**：`grab_screen.py` 的 `tour()`/`launch` 分支用 `DETACHED_PROCESS|CREATE_NEW_PROCESS_GROUP` 启动，与其文件头注释「用 `DETACHED_PROCESS` 启动会静默失败」（`nekobox-parity.md:885` 同）**矛盾，首次实跑需核实**；其 5 处老仓硬编码路径已改 `__file__` 相对（冒烟 `shot` 通过 868x668/7848 bytes）。

---

## 4. 大坑实录（换机/新环境必读）

1. **make 的 sh 里 PATH 被截断**：agent/IDE 注入 `\\?\` 设备路径条目 + Makefile 的 POSIX 前缀（`/usr/bin:/bin:`）→ MSYS 按冒号解析、在盘符冒号处整串切碎 → recipe 里 curl/git 全失踪，但 make 直启的命令正常（极具迷惑性）。已修（Makefile 15-38 行：Windows 格式前缀 + subst 剥离 `\\?\`）。
2. **Go 版本**：**用 1.27.x**（1.26 编核心 → 运行时 panic，psiphon-tls 布局断言；1.27 已修，2026-09-22 实测）。doctor 会查。CI 依赖解析失败时以 CI 报错为准重锁 lock，不手工猜版本。
3. **pubspec.lock 与镜像 + AGP 8.6.0 硬约束**：本机 `pub.dev` 不可达，走 `PUB_HOSTED_URL=pub.flutter-io.cn`，已提交的**镜像版 lock 是基线**（`64ed0e5e`，**勿回退**）。**不要试图"恢复干净 lock"——那是死循环**：pub.dev 来源的 lock（例如 `main` 的）在本机每次 `pub get` 都会按镜像重解析、在约束内漂版本，自己退化成现状。
    同一处还压着一条硬约束：`android/` 与上游 `main` 逐字一致 ⇒ AGP 固定 **8.6.0**；镜像解析到的新版插件（`camera-core 1.6.1` / `browser 1.9.0` / `androidx.core 1.17.0`）在各自 AAR 的 `META-INF/.../aar-metadata.properties` 里要求 **AGP ≥ 8.9.1** → `:app:checkReleaseAarMetadata` 报 7 项、安卓构建失败。**根因是依赖漂移，不是 AGP 欠债。**
    处置 = 7 个 AGP 敏感包精确钉版：4 个直接依赖在 `pubspec.yaml` 去掉 `^`（`shared_preferences 2.5.2` / `mobile_scanner 7.2.0` / `url_launcher 6.3.1` / `dynamic_color 1.7.0`），3 个传递依赖用 `dependency_overrides`（`flutter_plugin_android_lifecycle 2.0.27` / `shared_preferences_android 2.4.8` / `url_launcher_android 6.3.15`）。升 AGP 属于「有一天该做」：会打破 `android/` 逐字一致，且 Gradle wrapper 下载需绕行。
    仍会被 `pub upgrade` 推动的 4 个包（`googleapis_auth 2.3.4` / `pointer_interceptor 0.10.1+3` / `jni 1.1.0` / `jni_flutter 1.0.4`）已逐个核查**与 AGP 无关**：前两个纯 Dart、无 `android/`；后两个 `android/build.gradle` 新旧逐行只差 Groovy 赋值语法（`group '…'` → `group = '…'`），都无 `dependencies` 块、不引 androidx。⇒ 不需再钉。
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

1. 读 §0 现状（3 段读完，**别跳过**）+ §3.0 定案清单（13 条；#8 不移植清单尤其别重开讨论）+ §4 大坑实录
   （尤其 #8 代理变量 / #13 slang deferred / #12 git ref 幻象 / #5 生成代码不入库）。
2. `git -C S:\test\1\hiddify-app status --short` 确认干净；`git log --oneline -5` 看顶端；
   **推送状态一律用 `git ls-remote origin my` 核对**（tracking `[gone]` / `ahead N` 是 §4.12 沙箱幻象，别信）。
3. **序列已到 19/20**：§3.0#10 状态表里只剩「⑨ Windows 真机窗口验收」一项 ❌。
   真机验收需要跑起来的 Windows 构建 + 肉眼观察，**没有上下文的话先向用户要观察清单与截图**，不要自己编验收标准。
   **工具链已就位**：§3 末尾「真机自测工具链」表（`.workbuddy/` 10 个脚本 + 四步链路 + 六条实测纪律），先读它再动手。
   其余仍在桌面的活（性质不同，非序列剩余项）：上游 PR（§3 剩余 #8）、CI 首跑背书、Android/iOS 构建链、发布工程（§7）。
4. 若要新增功能对照：先读 `docs/design/parity-sequence-log.md`（逐功能记录 + **方法纪律** + 横切六坑），
   照该文的执行口径做，**不要另起一套记法**；测试样板照抄 `test/features/proxy/proxies_menu_test.dart`（含 §4.13 slang 泵法）。
5. 跑测试前 unset 四个代理变量；跑完以输出尾部 `All tests passed` 为准（§4.14）。
6. **写文档前先读「接手须知」的四份记录分工表**（本文只写状态与锚点；明细进 `docs/design/`；日记进 `.workbuddy/memory/`）。
   **不要写 `docs: anchor ...` 这类记账提交**（2026-10-02 定案，见「接手须知」）。
