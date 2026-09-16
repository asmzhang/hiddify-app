# 底层对照：NekoBox for Android vs hiddify-app（2026-09-15）

> 问题：两边都用 sing-box 系内核，那除了这一点，底层还有哪些不一样？
> 本文只写**经源码核对**的事实，标注文件位置。对照源码：`S:\test\NekoBoxForAndroid`（Kotlin）、本仓库（Flutter + hiddify-core）。

---

## 0. 结论

相同点只有一条：**内核都是 sing-box 系**。

不同点在六个维度，其中**第 2 条（配置真源方向相反）**才是"功能对不上、像硬套"的根：

| # | 维度 | NekoBox for Android | hiddify-app |
|---|---|---|---|
| 1 | 内核形态 | **libcore**：sing-box 编成 Android 库，配置由**应用自己**生成 | **hiddify-core**：sing-box 的 fork（自带 builder + ray2sing），配置由**内核自己**生成 |
| 2 | **配置真源（方向相反）** | **Room DB 是唯一真源**；启动时 `ConfigBuilder` 从 DB 生成配置 | **订阅内容是唯一真源**；drift DB 只存订阅元数据，配置由内核产出后缓存 |
| 3 | 进程 / 调用模型 | 同进程 **JNI** 直调 libcore；UI↔后台走 **AIDL** binder | 桌面 **FFI 同进程加载** + loopback **gRPC**；移动端独立进程 + mTLS |
| 4 | 接口与序列化 | AIDL（4 个 .aidl）+ Room + Kryo/Gson + 本地 clash_api（内置 yacd 网页面板） | protobuf/gRPC 多服务 + drift + freezed；clash api 只是可选开关 |
| 5 | 接管流量 | Android `VpnService` 平台 API 给 tun fd | 桌面靠 sing-box 自带 tun（Windows wintun）+ 运行时改系统代理；移动走各自 VPN 抽象 |
| 6 | 平台范围 | 仅 Android；设置用 Preference XML | 8 端（Win/macOS/Linux/Android/iOS/web）；设置走 ConfigOptions + `HiddifyOptions` protobuf |

---

## 1. 内核形态：库 vs fork

**NekoBox**
- `app/build.gradle.kts:28` `aidl = true`、`:43` `implementation(fileTree("libs"))` —— 内核是**预编译产物**（`app/libs` 由 CI 提供，`app/executableSo` 被 gitignore）
- `bg/proto/BoxInstance.kt:22` `import libcore.Libcore`、`:52` `box = Libcore.newSingBoxInstance(config.config, LocalResolverImpl)` —— 内核以**库**形式在进程内运行
- 配置**不由内核生成**：`fmt/ConfigBuilder.kt`（**756 行**，`:62 fun buildConfig(`）把 DB 里的实体拼成 sing-box 配置，`BoxInstance.kt:47-48` 调它

**hiddify-app**
- 内核是仓库的 8 层子模块之一（`hiddify-core/`，Go 源码全在）
- 配置**由内核生成**：`fgClient.parse` / `profileRepository.generateConfig(profile.id)` → 落成 `configs/<id>.tmp.json`
- 应用侧没有"配置构建器"这个概念（没有 ConfigBuilder 的对应物）

**影响**：NekoBox 能改配置的每一个字段，因为拼装逻辑在应用手里；hiddify 的配置形态由内核决定，应用只能"请求 + 读取"。

---

## 2. 配置真源：方向相反（最关键）

**NekoBox**
```
Room DB（proxy_groups / ProxyEntity.groupId / RuleEntity / SubscriptionBean）
        ↓ ConfigBuilder.kt 生成
   sing-box 配置 → libcore 启动
```
- `database/SagerDatabase.kt` + `app/schemas/...SagerDatabase/*.json`（7 个迁移版本）
- 节点有**完整凭据**（`ProxyEntity` + 各协议 bean），所以"节点编辑表单"天然成立
- 订阅只是**往 DB 里写实体的一个入口**（`bg/SubscriptionUpdater.kt:88` → `GroupUpdater.executeUpdate`）

**hiddify-app**
```
订阅 URL / 面板内容（真源）
        ↓ hiddify-core 解析 + 生成
   configs/<id>.tmp.json → 内核加载 → gRPC 回吐展示信息
```
- `lib/core/db/db.dart:12` `@DriftDatabase(tables: [ProfileEntries, AppProxyEntries])` —— **只有两张表**，`:79 ProfileEntries` 全是订阅元数据（id/type/url/lastUpdate/流量/到期…）
- 节点凭据不落应用侧 DB，也不在内核 gRPC 的 `OutboundInfo` 里（只有 tag/type/host/port/延迟/用量/ipinfo）

**影响（这就是"硬套感"的底层原因）**：
| NekoBox 里自然的功能 | 在 hiddify 侧为什么别扭 |
|---|---|
| 节点编辑表单（改 uuid/传输/TLS） | 凭据不在应用手里，`OutboundInfo` 不吐 → 必须动 core |
| 手动分组 / 手动加节点 / `ungrouped` | 没有节点与分组实体表 → 必须动模型 |
| 分组是"实体的集合" | 分组是"配置里解析出来的结构"，每次重新推 |
| 选中项存分组 id | 只能存 `<profileId>::<groupTag>` 复合键（组名会撞车） |

---

## 3. 进程 / 调用模型

**NekoBox（Android 平台级 IPC）**
- `bg/BaseService.kt:92` `class Binder(...) : ISagerNetService.Stub()` —— UI 通过 **AIDL binder** 与后台 Service 通信，带 Android binder 生命周期
- `bg/VpnService.kt:21` `class VpnService : BaseVpnService()` —— 建 VPN 走 Android 平台 API
- `bg/GuardedProcessPool.kt:40` `ProcessBuilder(cmd)` —— 独立进程池，**只用于外挂可执行文件**（崩溃隔离），sing-box 本身在进程内

**hiddify-app（桌面：FFI + loopback gRPC）**
- `core_interface_desktop.dart:41` `DynamicLibrary.open("hiddify-core.dll")` —— **把内核载入同一进程**
- `:88-97` `_box.setup(..., SetupMode.GRPC_NORMAL_INSECURE.value, "127.0.0.1:17078", secret, ...)` —— 在进程内起 gRPC 服务
- `:106-118` `bgClient = fgClient = CoreClient(ClientChannel('localhost', port: 17078, ... ChannelCredentials.insecure()))` —— Dart 再连回本地端口（**mTLS 那段被注释掉了**；`:59-65` 的随机密钥是用 `Random()` 生成的）
- 移动端 `core_interface_mobile.dart` 才是**独立进程 + gRPC + mTLS**（`mtls_channel_cred.dart`）

**影响**：
- 桌面端"解析 / 测速 / 选节点 / 看清单"共用同一条 core 连接（所以三层依赖里桌面只需一个 core 进程）
- 桌面 core 在进程内 → 内核崩 = 应用崩，没有 Android 那种 Service 隔离
- loopback 明文 gRPC + 固定端口 17078 是已记录的安全项（审计 C 包）

---

## 4. 接口与序列化

| | NekoBox | hiddify-app |
|---|---|---|
| 应用↔内核 | AIDL binder（`app/src/main/aidl/...` 4 个 .aidl） | protobuf/gRPC（`hcore_service.pbgrpc.dart` 的 `CoreClient`） |
| 其他服务 | — | 另有 `profile_service` / `ezytel_service` / `tunnel_service` / `hello_service` / `extension_service` |
| 本地存储 | Room（KSP 编译期校验，7 个 schema 迁移） | drift（`schemaVersion 6`，`db.steps.dart`） |
| 实体序列化 | Kryo（`fmt/KryoConverters.java`）+ Gson | freezed + protobuf |
| 仪表盘 | 内置 `assets/yacd.zip`（Clash 网页面板） | 自己的 Flutter 统计页；clash api 仅可选开关 |

---

## 5. 接管流量

| | NekoBox | hiddify-app |
|---|---|---|
| TUN | Android `VpnService`（平台建 tun，`:205 setUnderlyingNetworks`） | 桌面：sing-box 自带 tun（Windows = wintun）；移动走平台 VPN 抽象（`tunnel_service.proto`） |
| 系统代理 | Android 无此概念 | 有，且内核提供**运行时**接口 `SetSystemProxyEnabled`（无需重启内核） |
| 每应用分流 | Android API（`assets/proxy_packagename.txt` 列出待保护/排除包名） | `features/per_app_proxy/`（Android），桌面无 |
| 三档概念 | 基本只有"连/不连"（VpnService 一开就是全局） | proxy / systemProxy / tun 三档，语义分离（见 `connection-model.md`） |

---

## 6. 对项目的实际启示

1. **不要按 NekoBox 的模型去补 UI。** 它的"功能自然"来自 DB 是准绳、凭据在应用手里；照搬 UI 只会得到同一套别扭。
2. **hiddify 侧的 UI 数据源应统一到内核 gRPC**（`outboundsInfo` 已提供全部组 + 全部成员 + 实时数据，见 `2026-09-15-logic-layer-audit.md`），而不是"解析配置 JSON"重建。
3. **NekoBox 值得抄的是交互与视觉**（抽屉三组、Tab 隐藏规则、点节点热切换、排序随分组），这些与数据模型无关；**不该抄的是它的数据模型**（分组实体、手动节点）——那要先改 hiddify 的模型层。
4. 真正要把"节点可编辑 / 手动分组"做出来，等于把 hiddify 的数据模型往 NekoBox 的方向搬（DB 变成配置的真源）——**这是一个立项级的决定，不属于 UI 复刻**。

---

## 7. 功能面宽度的实测对照（回答"是不是 NekoBox 功能更强"）

> 结论：**不是谁更强，是强的方向不同**；而 NekoBox 的优势集中在"应用侧把配置当真源"才能给的那一类功能上。

### 7.1 量化的设置面

| | NekoBox | hiddify-app |
|---|---|---|
| 设置项总数（近似） | **≈194 项** | ≈82 项（`ConfigOptions` 60 + `Preferences` 22） |
| 其中协议级字段表单 | **≈150 项**（14 个协议/功能各一份 Preference XML） | **0** —— 用 `profile_details_page` 的 JSON 编辑器代替 |
| 设置载体 | `res/xml/*.xml` 24 个文件 | Flutter 代码内的偏好定义 |

NekoBox 的 14 份表单：anytls 10 / hysteria 16 / mieru 7 / naive 12 / shadowsocks 9 / shadowtls 10 / socks 8 / ssh 9 / standard_v2ray 28 / trojan_go 12 / tuic 12 / wireguard 10 / balancer 1 / group 9 / route 8 / global 29。

### 7.2 各有独占的能力

| 能力 | NekoBox | hiddify-app |
|---|---|---|
| 协议级编辑表单（逐字段） | ✅ 14 份表单 | ❌ 仅 JSON 编辑器 |
| 本地节点库 / 手动加节点 / 手动分组 / ungrouped | ✅ DB 实体 | ❌ 无实体 |
| 插件机制（SS 插件、trojan-go 插件） | ✅ `PluginEntry.kt`（29 文件命中） | ❌ |
| 内置 Clash 网页面板 | ✅ `assets/yacd.zip` + WebviewFragment | ❌ 仅有自研统计页 |
| geo 资源管理页 / 备份恢复 | ✅ AssetsActivity / BackupFragment | ⚠️ 模型层缺口 / 无 |
| 协议覆盖 | 15 类 bean + 插件 | `ProxyType` 33 项，**多出 AmneziaWG、xray-core 系（xVLESS/xVMess/xTrojan/xFragment）、Warp** |
| TLS 调优（fragment / padding / mixed SNI） | ❌ | ✅ |
| FakeDNS / 独立 DNS 缓存 / strict route / MTU | 部分（route/global 内） | ✅ 独立成项 |
| 增强出站链（WARP / Psiphon unblocker） | ❌ | ✅ |
| 按地区自动勾选分流应用 | ❌ | ✅ |
| 跨平台 | ❌ 仅 Android | ✅ 8 端（含桌面 TUN / 系统代理） |
| 订阅体验（多订阅并排、流量/到期展示、深链导入） | ⚠️ 基础 | ✅ |

### 7.3 差距的性质

- NekoBox 强的那一栏，**全部落在同一个前提上**：应用侧持有完整实体并能自己组装配置。这不是"功能实现得更努力"，而是**架构把它托起来了**。
- hiddify 弱的那一栏（协议表单、手动节点、分组管理），**内核其实不缺能力**：`Parse` 回的配置文本里就有完整凭据，`Start` 的 `enable_raw_config` 也允许应用提供配置（见 `2026-09-15-logic-layer-audit.md` §7）。缺的是"应用侧实体化 + 接管组装"这一层。
- hiddify 强的那一栏（跨平台、TLS 调优、增强出站、订阅体验）**NekoBox 短期不可能追**——它只有 Android，也没有那套内核扩展。

**所以"要不要更像 NekoBox"这个问题的实质是**：你愿不愿意为了那一栏功能，把 hiddify 的应用层改造成 NekoBox 的架构（DB 为真源 + 自建配置组装）。愿意 → 第 3 档；只想要够用的代理客户端 → hiddify 现有的功能面并不缺，缺的只是"暴露层"（比如协议字段只能用 JSON 编辑器改）。

