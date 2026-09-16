# 交接文档 — hiddify-app（新机器迁移 + NekoBox UI 复刻）

> 写于 2026-09-14 晚。上一份 anytls 修复交接（D:\ 时代）已被本文取代，
> 旧版可在 git 历史找回：`git show d3e958a5~40:HANDOVER.md` 附近。
> 目的：任何人（或没有上下文的 AI）读完就能接着干。

---

## 0. 一句话现状

**工程在新机器上已完整恢复并验证（构建/运行/订阅数据流全通），NekoBox UI 复刻一期已完成并推送（16 个提交）；剩：yfjc 订阅确认入库（深链已发，等人工点确认）、少量实体级补齐、审计 B/C/D 三包。**

---

## 1. 环境事实（这台机器，照抄即用）

| 项 | 值 |
|---|---|
| 开发目录 | `S:\test\hiddify-app`（分支 `my`） |
| 对照快照 | `S:\test\hiddify-app-ui`（worktree，detached 在 `d3e958a5`，**静态参考**，勿在上面开发） |
| 仓库 | 顶层 `asmzhang/hiddify-app` + 8 层子模块（hiddify-core / hiddify-sing-box / ray2sing / replace 下 4 个），**全部本地 `my` 分支跟踪 `origin/my`** |
| Flutter | **3.38.5，mise 管理**（`mise use -g flutter@3.38.5`）；pub 走 `pub.flutter-io.cn` 镜像 |
| Go | **1.25.x 硬约束**（`mise use -g go@1.25.6`）。**1.26 会让 psiphon-tls 布局断言 panic**（核心 DLL 加载即崩、App 启动即退 code 2）。`make doctor` 已加检查 |
| cgo 编译器 | `C:\platform\llvm-mingw-20260908-ucrt-x86_64`（`make doctor` 能自动发现） |
| GOMODCACHE | 已固化 `go env -w GOMODCACHE=$env:USERPROFILE/go/pkg/mod2` |
| 网络代理 | `socks5h://127.0.0.1:7890` 可用 —— 核心库下载失败时给 curl 加 `--proxy` |
| 测试订阅 | cpdd：`https://cpdd.one/sub?token=5514a186947f1120701fbf821ec4d168`（**39 anytls**）；yfjc：`https://yfjc.xyz/api/v1/client/subscribe?token=9cb751f5196c21453de652aea84aa938`（21 vless + 15 hysteria2，**无 anytls 属正常**） |
| 订阅 UA 机制 | App UA（`HiddifyNext/... sing-box v2ray`）→ 面板返回 sing-box JSON（anytls 保留）；浏览器 UA 会返回 Clash YAML（丢 anytls） |
| 深链导入 | `hiddify://import/<订阅URL>` → 弹确认框 + 预填 sheet。**有防零点击 SSRF 的确认设计，需人工点两次，不要绕过** |

---

## 2. 本次会话提交清单（16 个，全部已推送 origin/my）

**环境/修复（换机恢复）**
- `f904b5e4` **Makefile PATH 截断修复**（本次最大坑，见 §4.1）
- `25559a81` doctor 增加 Go 版本检查（防 1.26 panic 复发）
- `92db036d` 钉死代码生成器版本（flutter_gen_runner 5.10.0 / slang 4.8.1 / slang_build_runner 4.8.1）

**规范（审计 A 包）**
- `22f46190` .gitattributes + .editorconfig + 全库行尾重整（LF 唯一化）
- `6bc26f32` 恢复 flutter_test 声明
- `3d3a7ef5` CI：publish 门控修复 + analyze 门禁 + 清理过期引用/死脚本
- `81f2b090` BUILD.md / HANDOVER.md 同步
- `88dfbbde` 提交镜像版 pubspec.lock + 插件注册文件（**勿回退成 pub.dev 版**，见 §4.3）

**NekoBox UI 复刻**
- `d3e958a5` 原型页 `docs/ui-mockup/nekobox_replica.html`（活进度板，浏览器直接看）
- `8653d8ff` 步骤1 主题色板（5 色 × 日/夜/AMOLED，退役 Material You）
- `c259702d` 步骤2 主壳（抽屉/Rail 三组、FAB 四态=连接开关、StatsBar 主色底）
- `fe2b0286` 步骤3 卡片与分组 Tab 1:1（layout_profile.xml / layout_group_list.xml）
- `2861ca2b` 步骤4 设置补服务模式入口（五类覆盖已核实）
- `aefbd117` 步骤4 分组页滑动删除 + 撤销
- `e4cbcc3c` 步骤5 分组拖拽排序持久化（prefs 存 id 序列，零 schema 迁移）
- `a216ec5b` 导航命名对齐（代理→配置 / 订阅→分组 / 流量→仪表盘）
- `b786d886` dart format 收尾

---

## 3. NekoBox UI 复刻蓝图与进度

设计原则（已与用户定案，**不要推翻**）：
1. **NekoBox 壳 + hiddify 芯**：先 1:1 对照 NekoBox（源文件级：layout_profile.xml / layout_group_list.xml / main_drawer_menu.xml / themes.xml），hiddify 功能作为最后一批"补充"
2. **FAB = 唯一连接开关**（四态：stopped=▶ / connecting=转圈禁点 / connected=⏹ / disconnecting=转圈）；系统代理模式选择放设置，不放主页卡片
3. **多平台**：手机 = NavigationDrawer（复刻 NekoBox 抽屉三组）；PC ≥600dp = NavigationRail 常驻左侧（同三组，平铺不分组）
4. **归一原则**：每个能力只允许一个数据源/入口；退役 UI 不删码只降权；每步一提交

**已完成**：主题色板 / 导航三组+命名（配置/分组/路由/设置‖日志/仪表盘/工具‖关于）/ 主页（Toolbar 三件套+分组 Tab 连体+1:1 卡片+StatsBar）/ 分组页（滑删+撤销+拖拽排序持久化）/ 设置五类覆盖+服务模式入口。

**剩余（按优先级）**：
1. **yfjc 订阅确认入库**（深链已发，等人工点两次确认；cpdd 已验证 39 anytls 全链路 ✓）
2. 实体级补齐（需动模型/后端）：手动分组实体、geo 资源管理、卡片动作图标（编辑/分享/删除）、路由细粒度字段（domain/ip/port）
3. 审计 B 供应链包：CORE_FETCH 加 sha256、git 依赖锁 ref（circle_flags/installed_apps）、启用 flutter-version-file、CI 缓存 core-libs
4. 审计 C 安全包：gRPC 明文+固定端口 17078+`Random()` 非安全随机（core_interface_desktop.dart:60-94）、Sentry 默认上送订阅内容（profile_details_notifier.dart:59 → analytics）、3 处空 catch 补日志
5. 审计 D 架构包：core→features 14 处逆依赖、FFI 门面收敛（15 文件直用 hcore.pb.dart）、riverpod 风格统一、json_editor.dart 1592 行拆分、3 个业务测试
6. 上游 PR：anytls 修复 + Makefile PATH 修复提给 hiddify 官方

---

## 4. 大坑实录（换机/新环境必读）

1. **make 的 sh 里 PATH 被截断**：agent/IDE 注入 `\\?\` 设备路径条目 + Makefile 的 POSIX 前缀（`/usr/bin:/bin:`）→ MSYS 按冒号解析、在盘符冒号处整串切碎 → recipe 里 curl/git 全失踪，但 make 直启的命令正常（极具迷惑性）。已修（Makefile 15-38 行：Windows 格式前缀 + subst 剥离 `\\?\`）。
2. **Go 版本**：1.26 编核心 → 运行时 panic（psiphon-tls 断言）。**永远用 1.25.x**，doctor 会查。
3. **pubspec.lock 与镜像**：`PUB_HOSTED_URL=pub.flutter-io.cn` 与 lock 里 `pub.dev` 来源不匹配 → pub 每次 pub get 重解析（版本在约束内漂移）。已提交镜像版 lock 为基线；pub.dev 机器（CI）自行解析不回写。**不要试图"恢复干净 lock"——那是死循环**。
4. **单实例**：旧实例还在跑时启动新构建 → 新进程握手后 exit 0（像闪退）。烟测前先杀干净 Hiddify 进程。
5. **生成代码不入库**：新机器必须 `dart run build_runner build --delete-conflicting-outputs`（freezed/slang/drift/riverpod 全靠它），否则 analyze 报一堆 undefined。
6. **git submodule update 不带 `--remote` 会锁死在父仓库记录的 SHA**（游离 HEAD）——本项目约定全层跟 `my` 分支，见 docs/BUILD.md「取源码」节。
7. **后台任务里跑 git checkout 会留下半路状态**（index.lock / 半删文件）——git 操作放前台。

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
