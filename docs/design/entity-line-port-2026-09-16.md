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

### 待拍板项
- **SN Link 需逆向转换**（出站 → 分享链接）。本项目只有正向 `ray2sing`，没有反向
  → 要么新写，要么该功能退化为"导出标准链接 + JSON"。
- **路由：补 NekoBox 规则集管线 vs 保留 hiddify 规则模型 + 补编辑 UI**。这是两边差异最大的一块。

---

## 6. 下一步

- [ ] `dart analyze` 确认移植后 0 error
- [ ] 跑 12 个 `check_*.dart` 回归
- [ ] 语义化提交
- [ ] 按 §5 顺序分批次推进（每批一提交，改前先核对 `nekobox-parity.md` 原版行为）
