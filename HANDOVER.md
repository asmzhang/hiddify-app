# 交接文档 — hiddify-app 订阅（anytls）问题

> 写于 2026-09-13 19:45。**这份文档独立于 `.workbuddy/`，删掉助手记忆后仍然可用。**
> 目的：任何人（或没有上下文的 AI）读完就能接着干。

---

> ### 🔄 2026-09-14 状态更新（新机器迁移完成，本文中的 D:\ 路径已全部失效）
>
> - 项目已迁移到 **`S:\test\hiddify-app`**，工具链走 mise（`flutter@3.38.5` / `go@1.25.6`），
>   cgo 用 `C:\platform\llvm-mingw-20260908-ucrt-x86_64`。
> - §4 的全部修复（UA、anytls、balancer、dns detour、ray2sing/sing-box 合并）已提交并编译验证：
>   核心带修复重编成功、App 可启动、`libbox.Setup success` + gRPC 17078 正常。
> - **新增一个环境硬约束：编核心必须 Go 1.25.x**（1.26 触发 psiphon-tls 布局断言 panic，
>   App 启动即退 code 2）。`make doctor` 已加版本检查，详见 `docs/BUILD.md`。
> - 顺带修复 Makefile 在 agent/IDE 环境下 PATH 被截断的 bug（`\\?\` 条目 + POSIX 前缀混拼）。
> - **剩余**：① 实机导入订阅做最终验收（39 anytls + 分组）；② 本地若干提交待 push；
>   ③ B/C/D 行动包（供应链加固 / 安全重构 / 架构演进）见审计记录，未开始。

---

## 0. 一句话现状

**订阅已能正确解析（39 个 anytls 节点 + 分组都造对了），但核心拒绝启动，原因是 `hiddify-core` 的源码缺陷；而要修它必须重编核心，重编又卡在一台机器上 Go 模块缓存损坏。两件事都有明确解法，见 §4。**

---

## 1. 目标

用户订阅里有 **39 条 anytls + 4 条 hysteria2 + 2 条 shadowsocks**（cpdd.one）等节点，
但在 hiddify-app 里只导入成功 6 个节点。目标：**让订阅里的节点全部可用**。

---

## 2. 已查明的事实链（每一条都有实测证据）

### 2.1 面板按「客户端 UA」决定订阅格式

同一 URL 只换 UA 请求（`curl -A '<UA>'`），返回完全不同：

| 订阅 | UA | 面板返回 | 里面有 anytls 吗 |
|---|---|---|---|
| cpdd.one | 浏览器 | base64 分享链接（45 行）| 39 条 |
| cpdd.one | **App 原 UA**（`HiddifyNext/x (windows) like ClashMeta v2ray sing-box`）| **Clash YAML** | 39 处 |
| cpdd.one | `sing-box/1.12.0` | **sing-box JSON** | **39 个 outbound** ✅ |
| yfjc.xyz | App 原 UA | JSON，但 hy2 只有 15 个 | — |
| yfjc.xyz | `sing-box/1.12.0` | JSON，hy2 **17** 个 | ✅ |

**结论**：UA 里只要出现 `clash`（`ClashMeta`），面板就先按 Clash 客户端返回 **Clash YAML**。
把 `sing-box` 提到 `ClashMeta` 前面**没用** —— 两个词在同一个 UA 里，面板仍判成 Clash。

### 2.2 核心的三条解析路径（`hiddify-core/v2/config/parser.go` `parseConfigContent`）

按顺序三选一：

| 顺序 | 输入 | 处理 | anytls |
|---|---|---|---|
| 1 | **JSON**（有 `outbounds`/`endpoints`）| 直接当 sing-box 配置用 | ✅ **内核原生支持** |
| 2 | **Clash YAML**（有 `proxies`）| `xmdhs/clash2singbox` 转换 | ❌ **不认识 anytls → 39 条静默丢弃，日志无报错** |
| 3 | **分享链接**（base64）| `ray2sing` | ❌ 缺 anytls（本地已补，见 §3）|

⚠️ 路径 1 有一个开关：`if fullConfig || configOpt.EnableFullConfig { jsonObj = tmpJsonObj }`
——**打开时整份配置原样使用，且【不会】跑下面的 builder**。这一条在 §4 里很关键。

### 2.3 「核心起不来」的真因：**分组被注入了两次**

`hiddify-core/v2/config/builder.go`：

- 第 151-157 行的跳过表只处理 `TypeBlock/TypeDNS`、`TypeSelector/TypeURLTest`、`TypeCustom`
  —— **漏了 `TypeBalancer`**；
- 第 286-303 行**无条件**创建两个 balancer：`lowest` 和 **`balance`**；第 317 行前置进 outbounds。

流程：App 先让核心 `GenerateConfig`（JSON 路径 → 只取 outbounds → builder 注入自己的
`select`/`balance`/`lowest`）→ 写进 `configs/<id>.tmp.json` → 再让核心 `Start` 读**那份已带分组的配置**
→ JSON 路径**又跑一遍 builder** → 分组注入两次 → `duplicate outbound/endpoint tag: balance`
→ **核心拒绝启动**（UI 上表现为 "failed to start background core" + 没有分组）。

**三组对照（用 `HiddifyCli.exe` 离线复现，见 §5）：**

| 喂给核心 | 结果 |
|---|---|
| 原始订阅内容（只含 outbounds）| ✅ 启动成功 `registered 50 outbounds` |
| 已构建的配置（含 `balance`）| ❌ `duplicate outbound/endpoint tag: balance` |
| 面板完整配置 + `--full-config` | ✅ 启动成功 `registered 50 outbounds` + **`registered 4 outbound groups`** |

**注意**：这个 bug 只在「订阅内容是 JSON」时触发；分享链接 / Clash 路径不触发。

### 2.4 「核心编不出来」= **两道门槛叠加**（2026-09-13 19:55 最终定论）

> ⚠️ **本节经过一次更正**：我一度宣布"与源码配对无关"，那是**错的** —— 当时在配对提交上编失败，
> 是因为撞上了下面的**门槛一**，把它当成了"配对无用"。**两道门槛必须都过。**

#### 门槛一（环境）：`GOMODCACHE` 缓存坏了 ✅ 已解决

症状：`cannot find module providing package X`，而 X 所在模块**已被 go.mod require**、
`go list -m` 也能解析出正确 `Dir=`、磁盘上包文件也在 —— **但 go 扫不到模块里的包**。

最赤裸的证据（最小模块复现）：

```
...\go\pkg\mod\github.com\metacubex\utls@v1.8.4\cipher_suites.go:21:2:
    cannot find module providing package github.com/metacubex/utls/internal/boring
```

**模块自己的文件找不到自己的内部包。**

**解法（已验证有效）**：换一个**全新 `GOMODCACHE` 路径**重新下载 ——
不要重复 `go clean -modcache`（旧路径删不干净会留下"新旧混合"的坏状态）。

```powershell
$env:GOMODCACHE = "C:\Users\Administrator\go\pkg\mod2"
```

**实测结果**：换新缓存后 `[1a] go mod tidy` **通过**、`[1b]` 进入真正编译 ✅

#### 门槛二（源码/API 配对）：`ray2sing` 与 `sing-box` 的 API 版本不匹配

过了门槛一之后，暴露出的真实编译错误：

```
ray2sing\ray2sing\awg.go:180: unknown field Awg in struct literal of type option.AwgEndpointOptions
ray2sing\ray2sing\awg.go:180: undefined: T.AwgOptions        (T = github.com/sagernet/sing-box/option)
ray2sing\ray2sing\warp.go:26: undefined: T.WARPEndpointOptions
```

- `ray2sing@caf5e9ac`（提交名 **"add amnezia for warp"**，正是它引入这段代码）
  需要 sing-box 的 `option.AwgOptions` + `option.WARPEndpointOptions` + `AwgEndpointOptions.Awg` 字段。
- **`170d8315` 有**（`option/awg.go:15/20`、`option/wireguard.go:39`）；
  **`1056d6b2` 没有**（那里 `AwgEndpointOptions` 是扁平的，只有 `AwgPeerOptions`）。
- **血缘**：`1056d6b2..170d8315 = 159`、`170d8315..1056d6b2 = 4`
  ⇒ **`170d8315` 比我们当前的新 159 个提交，只比我们少 4 个**（2 个 masterdns + 我们的 2 个 chore）。

**⇒ 结论：`hiddify-sing-box` 要切到 `170d8315`，这【不是"退源码"，是前进 159 个提交】**，
代价只有 masterdns（将来可以 merge 回来）。

---

## 3. 已经改动的代码（4 处）

| 文件 | 改动 | 生效了吗 |
|---|---|---|
| `lib/core/model/app_info_entity.dart:20` | UA 去掉 `like ClashMeta` → `"HiddifyNext/$version ($operatingSystem) sing-box v2ray"` | ✅ 已编入 zip（二进制验证过）|
| `lib/singbox/model/singbox_proxy_type.dart` | 枚举加 `anytls("AnyTLS")` | ✅ 已编入 zip |
| `lib/features/profile/data/profile_parser.dart` | `protocol()` 加 `'anytls'` | ✅ 已编入 zip |
| `hiddify-core/v2/config/builder.go:151` | 加 `case C.TypeBalancer: continue` | ❌ **未生效（核心没编出来）** |

另有（更早的会话）：
- 顶层 `Makefile`：2 处 `SHELL_FORCE` 修复（`windows-libs-local` 的 `rm`、`android-libs` 的 `ls`
  会被 make 绕过 shell 导致失败）+ 新增 `windows-libs-local` 等源码编译目标 + `scripts/doctor_go_cache.sh`
- `hiddify-core/ray2sing`（本地提交 `2627afe`，未推）：补 anytls 分享链接解析 —— **未编入核心**

**已产出并验证的 zip**：`dist/4.1.2+40102/hiddify-4.1.2+40102-windows.zip`
（50,772,228 字节 / 373 条目 / testzip OK / 5 个关键文件齐全；含 UA 与 anytls 显示名修复，
但**不含** balancer 修复 ⇒ 装上它仍会 "failed to start background core"）。

---

## 4. 正确的修复方案（治本）

> ### ✅ 真实 App 里验证通过（2026-09-13 20:22）—— 三个修复全部生效
>
> 便携版的数据目录在 **`dist/4.1.2+40102/hiddify-4.1.2+40102-windows/Hiddify/hiddify_portable_data/`**
> （`portable=true` ⇒ 数据放在 exe 旁边的 `hiddify_portable_data/`，**不在** `%APPDATA%`）。
> 那里的 `hiddify-core.dll` = 20:13 / 64,548,352 字节 ⇒ **用的确实是新核** ✓
>
> **App 在 20:16 生成的真实配置**（`configs/b31dcfb2-….tmp.json`，18,355 字节）：
> ```
> outbounds = 49：anytls 39 + hysteria2 5 + shadowsocks 2 + selector/urltest/direct
> ★ 重复 tag = 无            ← builder.go 的 balancer 修复【生效】
> 分组：selector '冲上云霄'(48) + urltest '自动选择'(46)   ← 面板自带分组也在
> inbounds: ['tun', 'mixed']  ← 需要 TUN（要提权/服务）
> ```
> ⇒ **UA 修复、anytls、balancer 三者全部确认真实生效** ✓✓✓
>
> ### ★★ 已定位（2026-09-13 20:29）：debug 日志【自我递归】→ 20.4 GB → 核心被拖死
>
> 把日志级别调到 **debug** 后，核心的 `data/box.log` **几分钟涨到 20,417,551,314 字节（20.4 GB）**，
> 内容是**自我递归的日志环**：
> ```
> INFO monitoring: starting outbound monitoring initialize
> DEBUG H SERVICE INFO monitoring: starting outbound monitoring initialize
> DEBUG H SERVICE DEBUG H SERVICE INFO monitoring: starting outbound monitoring initialize
>         ↑ 每轮把前面全部内容再嵌一次 → 长度指数级增长
> ```
> ⇒ **磁盘 I/O 打满 → App 界面卡死；核心被日志风暴拖住、无法响应 gRPC**
> → App 报 `status Canceled` / `ProxyFailure.serviceNotRunning()` / **"failed to start background core"**。
>
> **这是 hiddify-core 在 debug 级别下的真实 bug**（与订阅、与本次三个修复都无关）。
>
> **处理**：① **日志级别改回 `info`（或 warn），绝不要 debug**；② 删掉那个 20.4 GB 的
> `…/hiddify_portable_data/data/box.log`（App 已退出后它不再增长；当时磁盘还剩 705G，无紧急危险）。
> **注意**：`info` 级别下核心仍会写 `data/box.log`（配置里有 `log.output`）——
> **保留它但别用 debug**，这样既有核心日志、又不会爆炸 ✓
>
> **从 app.log 里看到的完整生效配置（20:26，确认无误）**：
> ```
> log: {level: debug, output: data/box.log}        ← 就是这个 debug 惹的祸
> inbounds: mixed 12334 (set_system_proxy=true) ×2 + direct 12337 ×2
>           ← ★ system-proxy 模式，【没有 tun】⇒ 不需要管理员权限 ✓
> outbounds: selector "select" → ["lowest","balance", <45 个节点>…]   ← hiddify 自己的分组 + 我们的 anytls 节点
> ```
>
> ### ★★★ 真正拒启的原因（2026-09-13 20:38）：dns 的 detour 指向【空的 direct outbound】
> 开了 info 级别后核心终于吐出了真实报错：
> ```
> failed to start bg core: gRPC Error (code: 2, UNKNOWN, message:
>   start dns/tcp[dns-remote-no-warp]: detour to an empty direct outbound makes no sense)
> ```
> **成因**：`v2/config/builder.go:347-362` 造 `direct-fragment §hide§` 时
> **`TLSFragment` 那段被注释掉了**（只剩 `TCPFastOpen: false` = 零值）⇒ 序列化成
> `{"type":"direct","tag":"direct-fragment §hide§"}`（**空**）。而 `v2/config/dns.go`
> 有两处把 `detour` 指向它 ⇒ sing-box ≥1.13 判定"detour 到空 direct 没意义"⇒ 拒绝启动。
> 为什么会注释掉：**新版 sing-box 把 fragment 从 `DirectOutboundOptions` 移到了 route action**
> （`option/rule_action.go:183 TLSFragment bool`），旧字段没有了 ✗ —— 又一处"合并 170d8315 带来的 API 漂移"。
>
> **修复（已应用，`v2/config/dns.go` 3 处）**：
> | 位置 | 原值 | 改为 |
> |---|---|---|
> | `remote_no_warp_dns` | `OutboundWARPConfigDetour`（=fragment outbound）| `""` |
> | `trick_dns` | `OutboundDirectFragmentTag` | `""` |
> | `direct_detour` 默认值 | `OutboundDirectFragmentTag`（DoH 地址时生效）| `""` |
>
> **为什么删掉 detour 是安全的**：fragment 本来就在 **DNS 服务器自己的 TLS 选项**里
> （`tls.fragment: true` / URL 的 `#fragment=300`），那个 detour 是多余的；
> 而 `dns.go` 原本在"直连 DNS 是 IP"时就传 `""` —— 说明 `""` = 直连是既有的正确写法 ✓
>
> ### ⏳ 待验证：重编核心后应能连上
> **注意**：`builder.go:105/197` 还有 `Detour: OutboundDirectTag`（那个 outbound 也是空的），
> 如果重编后报同类错误（"detour to an empty direct outbound"），按同样思路处理即可。
> `app.log`（20:16–20:21）：
> ```
> CoreInterfaceDesktop: message: Hello, test
> Hiddify-core setup done
> [E] HiddifyCoreService: status → Canceld        ← 状态调用被 CANCEL
> [W] ProxyFailure.serviceNotRunning()
> （日志里【没有】任何 connect 尝试；CoreInterfaceDesktop 的 box.log 是 0 字节）
> ```
> **线索**：
> 1. 核心 gRPC 绑**固定端口 `127.0.0.1:17078`** —— 我 19:0x 跑 CLI 时见过
>    `WARN H CORE grpcServer already started`（当时 App 正占着它）⇒ **多实例/残留会造成冲突**
> 2. 20:22 复查：**无任何 Hiddify 进程、17078/12334 均空闲** ⇒ 值得做一次干净启动
> 3. App 生成随机密码走 mTLS 连核心（`core_interface_desktop.dart:70` 附近），握手失败同样是 CANCELED
> 4. **`box.log` 是空的** ⇒ 核心日志没开 ⇒ **目前对核心侧报错是盲的**
>
> **下一步（按优先级）**：① App 设置里把**日志级别调到 debug/trace**（拿到核心的真实报错）；
> ② 完全退出（含托盘）后**只开一个实例**；③ 试**以管理员身份运行**（`tun` inbound 需要提权）；
> ④ 或把服务模式改成 **系统代理 / 仅代理**（不用 TUN 就不需要提权和独立服务）。
>
> ### CLI 在本机跑不了（环境限制）
> 新编的 `HiddifyCli.exe` 被执行策略拦（`应用程序控制策略已阻止此文件`）⇒
> **无法用 `HiddifyCli run` 离线验收**，只能靠 App 本身 + 日志。
>
> ### ✅ 进度更新（2026-09-13 20:14）—— **全链路已打通**
>
> | 环节 | 结果 |
> |---|---|
> | 门槛一：换全新 `GOMODCACHE` | ✅ 有效 |
> | 门槛二：合并 `170d8315` 进 `my` | ✅ `c9bd6f6a` |
> | `MasterDnsVPN` 依赖钉版 | ✅ `hiddify-core/go.mod:278` |
> | `[1b]` 编 DLL | ✅ 64,548,352 字节 |
> | `[1c]` 编 CLI | ✅ 1,601,024 字节 |
> | `[2/3]` 打包 | ✅ `hiddify-lib-windows-amd64.tar.gz` 27,940,986 字节
>   （**修过一次**：`$(CURDIR)` = `D:/…` 的冒号被 GNU tar 当远程主机 → 改用相对路径 `../.cache/…`）|
> | `[3/3]` | ✅ done |
> | `flutter build windows --release` | ✅ |
> | `make windows-zip-release` | ✅ `dist/4.1.2+40102/hiddify-4.1.2+40102-windows.zip` |
>
> **⚠️ 唯一的环境限制**：**新编出来的 `HiddifyCli.exe` 被执行策略拦截**
> （`应用程序控制策略已阻止此文件`，同 `WinError 4551`）⇒ **CLI 无法在本机跑**，
> 所以不能用 `HiddifyCli run` 做离线验收。**但不影响 App**：App 走 `hiddify-core.dll` 进程内加载。
> **⇒ 验收改为：跑新打包出来的 App，导入订阅，看能否启动 + 是否有分组 + 节点数。**
>
> **仍未做**：① 用新 App 实测；② 把 `builder.go` 的 balancer 修复提给上游。

> ### 📌 进度更新（2026-09-13 20:10）—— 已走通到"只差最后一步"
>
> | 步骤 | 状态 |
> |---|---|
> | 门槛一：换全新 `GOMODCACHE` | ✅ **已验证有效**（tidy 通了）|
> | 门槛二：合并 `170d8315` 进 `my` | ✅ **已完成** = `c9bd6f6a Merge commit '170d8315' into my`，工作区干净 |
> | API 检查 | ✅ `option/awg.go` 有 `AwgOptions`、`option/wireguard.go` 有 `WARPEndpointOptions` |
> | `MasterDnsVPN` 依赖 | ✅ **已在 `hiddify-core/go.mod` 钉住正确版本**（见下）|
> | 编译 | ✅ **成功**（20:11）：`hiddify-core.dll` 64,548,352 字节、`HiddifyCli.exe` 1,601,024 字节 |
> | 打包 `[2/3]` | ✅ 已修（`tar` 把 `D:/…` 的冒号当远程主机 → 改用相对路径 `../.cache/…`）|
>
> **`MasterDnsVPN` 那一行（已在 `hiddify-core/go.mod` 第 278 行）**：
> ```
> github.com/hiddifydeveloper/MasterDnsVPN v0.0.0-20260725182012-6d0aba10b2f0
> ```
> 为什么必须是这个版本：`go mod tidy` 自己会挑 `@latest = …20260718230342`，
> **而那个版本里根本没有 `pkg/client` / `pkg/config`**（实测：目标版本有 31 + 7 个 .go 文件，
> 自选版本一个都没有）⇒ 必须显式钉住。
>
> **合并用的命令（已执行，留档）**：
> ```powershell
> git -C $S switch my
> git -C $S merge 170d8315
> git -C $S checkout --theirs -- go.mod     # 直接采用 170d8315 的 go.mod（更新、依赖更全）
> git -C $S add go.mod
> git -C $S commit --no-edit
> ```
> **下一步就是重跑 `make windows-libs-local`**，可能还剩最后一个坑（masterdns 代码对新 API 的适配）。


### 步骤 0 —— 把 `170d8315` **合并**进 `my`（**不是切换**；一次合并，两边内容都留下）

> 为什么不切换：`170d8315` 有 159 个我们没有的提交（含 ray2sing 需要的
> `09088b9b "add amnezia, warp with amnezia"`，还有 MASQUE、VLESS encryption、xhttp…），
> 我们也有 4 个它没有的（2 个 masterdns + 2 个 chore）。
> **合并 = 两边都要** ⇒ `my` 变成并集，既满足 ray2sing 的 API 又保住 masterdns。

```powershell
$S    = "D:\test\hiddify-app\hiddify-core\hiddify-sing-box"
$lock = "D:\test\hiddify-app\.git\modules\hiddify-core\modules\hiddify-sing-box\index.lock"

# 0-a) 工作区若被环境删掉了（本机反复发生），先重建
if (-not (Test-Path "$S\option")) {
  Remove-Item -Force $lock -ErrorAction SilentlyContinue
  New-Item -ItemType Directory -Force -Path $S | Out-Null
  Set-Content -Path "$S\.git" -Value "gitdir: ../../.git/modules/hiddify-core/modules/hiddify-sing-box"
  git -C $S switch my
  git -C $S reset --hard HEAD
}

# 0-b) 确认在 my 上，然后合并
git -C $S switch my
git -C $S merge 170d8315
```

**预期：只有 `go.mod` 一个冲突**（`constant/proxy.go`、`go.sum`、`include/registry.go` 都会自动合并）。

**解冲突（就一处：两边都加了 require，保留双方即可）：**
打开 `D:\test\hiddify-app\hiddify-core\hiddify-sing-box\go.mod`，找到

```
<<<<<<< HEAD
   ...我们这边的 require...
=======
   ...170d8315 那边的 require...
>>>>>>> 170d8315
```

**把两段内容都留着，只删掉 `<<<<<<<` / `=======` / `>>>>>>>` 这三行**，然后：

```powershell
git -C $S add go.mod
git -C $S commit --no-edit        # 避免弹编辑器
```

**验收这次合并：**
```powershell
git -C $S log --oneline -3                     # 应看到合并提交（Merge ...）
git -C $S status --short                       # 期望：空
Select-String -Path "$S\option\awg.go" -Pattern 'AwgOptions'      # 期望有命中
Select-String -Path "$S\option\wireguard.go" -Pattern 'WARPEndpointOptions'  # 期望有命中
```

（要放弃这次合并：`git -C $S merge --abort` → 回到 `1056d6b2`）

### 步骤 1 —— 修模块缓存（环境，不改源码）

**用全新路径当 GOMODCACHE，不要去删旧缓存：**

```powershell
$env:GOMODCACHE = "C:\Users\Administrator\go\pkg\mod2"   # 全新路径（已存在的话换个名字）
cd D:\test\hiddify-app
$env:PATH = "D:\Platform\llvm-mingw-20260908-ucrt-x86_64\bin;$env:PATH"
$env:GOPROXY = "https://goproxy.cn,direct"
$env:GOSUMDB  = "off"
$env:GOTOOLCHAIN = "local"
Remove-Item Env:http_proxy,Env:https_proxy,Env:HTTP_PROXY,Env:HTTPS_PROXY -ErrorAction SilentlyContinue

make windows-libs-local CORE_GOPROXY=https://goproxy.cn,direct
```

预期：`[1a] go mod tidy` **这次应该能过**（缓存正常了）；→ `[1b]` 编出
`hiddify-core/bin/hiddify-core.dll`（时间戳变新）→ `[1c] HiddifyCli.exe` → `[2/3]` 打包进
`.cache/core-libs/` → `[3/3] done`。

### 步骤 2 —— 让 App 用上带修复的核心

```powershell
cd D:\test\hiddify-app
flutter build windows --release
make windows-zip-release
```

### 步骤 3 —— 验收（必须做）

```powershell
# 用 CLI 离线验核心行为（最能说明问题）
cd D:\test\hiddify-app\hiddify-core\bin
# 把订阅内容（只含 outbounds 的 JSON）存成 C:\temp\sub.json，然后：
.\HiddifyCli.exe run -c C:\temp\sub.json --log-level info --in-proxy-port 21334
```

**期望**：不再出现 `duplicate outbound/endpoint tag`，而是
`registered N outbounds` + `registered M outbound groups`。

### 备选方案（不改核心，改 App）

把 `enableFullConfig` 暴露成设置项（或按内容自动判断：JSON 含 `inbounds`/`route` 时开启）。
实测 `--full-config` 能启动 + 有分组。**代价**：整份用面板配置 ⇒ 面板自带 inbounds 生效，
App 的端口/TUN 设置可能被覆盖，**必须实测**。

---

## 5. 排错方法论（本次踩过的，可复用）

1. **判断订阅格式问题，必须用「客户端真实 UA」复现，不能用浏览器。**
   同一 URL 换 UA 会返回完全不同的格式，而只有分享链接和 Clash 两条路会丢新协议。
2. **`HiddifyCli.exe` 是强大的离线复现工具**（不受网、不受 UI 影响）：
   - `HiddifyCli.exe build -c <config> -o out.json` 只看构建结果
   - `HiddifyCli.exe run -c <config> --log-level info --in-proxy-port 21334` 真启动
   - 参数：`-c` 配置 / `-d` HiddifyOptions JSON 路径 / `--full-config` / `--tun` / `--system-proxy`
   - 注意：`-c` 必须是 **Windows 路径**（`C:\...`），MSYS 路径（`/c/...`）会报找不到
3. **模块解析类怪病，先做三连**：`最小模块` + `pin 版本` + `换全新 GOMODCACHE`。
   别一上来就查 go.mod / 源码。
4. **读二进制字符串**（本机无 `strings`）：`grep -aoc '关键字' file`。

---

## 6. 环境关键事实（容易反复踩）

| 项 | 值 |
|---|---|
| Flutter（正确）| `D:\Platform\flutter`（3.38.5）；**Machine PATH 里那套 3.47.4 已移除** |
| make | `C:\Users\Administrator\.local\bin\make.exe`（4.3，来自 Android NDK） |
| git | `D:\Platform\Git\cmd\git.exe` —— **`export PATH=` 覆盖后 `git` 会找不到，要用绝对路径** |
| C 工具链（cgo）| `D:\Platform\llvm-mingw-20260908-ucrt-x86_64\bin`（`x86_64-w64-mingw32-gcc`）；**MSVC 不能当 cgo 的 CC** |
| Go | mise 装的：`mise\shims\go.exe`，`GOROOT=...\mise\installs\go\1.25.6`，`GOMODCACHE=C:\Users\Administrator\go\pkg\mod` |
| 沙箱代理 | 环境里有 `http_proxy/https_proxy`（本地回环）；**go 会读它、git 不读** → 跑 go 前 `unset`/`Remove-Item Env:` |
| `git submodule update` | **在这台机器上会挂住**（疑似联网 fetch）→ 还原只用 `switch <branch>` + `reset --hard`（纯本地）|
| 子模块文件"失踪" | `hiddify-sing-box` 的工作区**会被环境反复吃掉文件甚至整个目录**（今天 3 次）。修复：删 `.git/modules/hiddify-core/modules/hiddify-sing-box/index.lock` → `reset --hard HEAD`；判据是 `cmd/`、`option/`、`route/`、`test/`、`include/`、`protocol/` 的文件数（`my`/`1056d6b2` 下应为 14/38/74/72/61/29/86）|
| **不要在后台任务里跑 `git checkout`** | 后台任务被掐断会把 git 中断在半路，留下"删一半 + index.lock" |

---

## 7. 当前工作区状态（2026-09-13 19:45 核对）

```
顶层:      M Makefile
           M lib/core/model/app_info_entity.dart
           M lib/features/profile/data/profile_parser.dart
           M lib/singbox/model/singbox_proxy_type.dart
           ?? scripts/doctor_go_cache.sh
           ?? _diag.sh                    ← 来历不明，建议你自己看一眼
           m hiddify-core
hiddify-core:  M ray2sing                 ← 你的 anytls 修复（提交 2627afe，未推）
               M v2/config/builder.go     ← balancer 修复（1 行）
sing-box:      branch=my  1056d6b2  dirty=0   ✅
```

**8 层子模块全在各自 `my` 分支**，仓库：
`asmzhang/{hiddify-app, hiddify-core, hiddify-sing-box, ray2sing, tailscale,
psiphon-quic-go, psiphon-tls, wireguard-go}`，
外加本次新 fork 的 `asmzhang/{MasterDnsVPN, cronet-go}`。

---

## 8. 关于删除助手记忆

- 助手的记忆全在 **`D:\test\hiddify-app\.workbuddy\`**（3 个 md 文件，148K，只有 `memory/`）。
- **删掉它不影响项目**：不参与构建、不影响 git（已在 `.gitignore`）、不参与 CI。
- 里面确实有过一条**已被推翻的错误结论**（"核心编不出来是因为 go.mod 与 sing-box 源码不成套"），
  容易误导后续判断 —— **这份 §2.4 就是那条的正确版**。
- 删除方式：直接删 `D:\test\hiddify-app\.workbuddy\` 整个目录即可。
- 另外可删我实验建的缓存：`C:\Users\Administrator\go\pkg\mod2`（§4 步骤 1 要用的那个路径，
  想复用它就别删）。

---

## 9. 还有两条「今天就能用」的旁路

1. **换客户端**：用 v2rayN / NekoBox / sing-box 官方 GUI 吃同一份 sing-box JSON —— 它们没有上述 bug。
   这也能**立刻验证「这份订阅本身是好的、39 个 anytls 可用」**，把「订阅问题」和「hiddify 客户端问题」切开。
2. **订阅地址加 `&flag=singbox`**：绕过 UA 判断，强制面板返回 sing-box JSON（本地实测两个订阅都有效）。
   但它**只解决"节点识别"**，不解决 §2.3 的核心启动 bug。
