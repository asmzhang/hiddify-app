# 构建指南

## 环境要求

| 依赖 | 要求 |
|---|---|
| Flutter | **3.38.5**（与 `pubspec.yaml` 绑定，不要升级） |
| GNU Make | 4.3+ |
| Windows | Visual Studio 2022 + **C++ 桌面开发**工作负载 |

### 全新机器上需要什么

按阶段分，只有第一组是**必须手装的**，其余 `make doctor` 会告诉你缺哪个：

| 阶段 | 依赖 | 怎么来 |
|---|---|---|
| 构建 | Git for Windows | 官网安装（recipe 靠它自带的 sh 解释） |
| 构建 | GNU Make | `winget install ezwinports.make` |
| 构建 | Flutter 3.38.5 | `mise use -g flutter@3.38.5`；或解压后把 `<sdk>\bin` 加进 PATH |
| 构建 | `curl` `tar` | Windows 10 1803+ 自带 |
| 构建 | `unzip` | Git for Windows 自带（系统不带） |
| 编译 | Visual Studio 2022 + C++ 工作负载 | 官网安装 |
| 编核心 | Go **1.25.x**（全平台）+ 各平台工具链 | `mise use -g go@1.25.6`。**不要用 1.26+**：psiphon-tls 的布局断言会让核心在加载时 panic（App 启动即退 code 2），`make doctor` 会检查。见「从源码编译核心库」 |
| 打包 | `fastforge` | `make windows-install-deps` |
| 打包 exe | Inno Setup 6 | `winget install JRSoftware.InnoSetup` |
| 打包 msix | `makeappx`（Windows SDK）+ **签名证书** | 证书只有 CI 有，见「打包安装包」 |

构建 `.zip` 只需要前两组 + `fastforge`（**这也是 Windows 本地唯一推荐使用的目标**）；
`.exe` 额外需要 Inno Setup 6；`.msix` 本地做不了。

> Visual Studio **不在** `make doctor` 的检查范围内 —— 它由 `flutter doctor` 负责。

Makefile 的 recipe 是 POSIX shell 脚本。

- Linux / macOS：直接用。
- **Windows：也是直接 `make`**，在 PowerShell 或 cmd 里都行。
  Makefile 会自动定位 Git for Windows 自带的 sh 并接管 recipe 的解释，
  你不需要自己去开 Git Bash（前提是装了 Git for Windows，Flutter 环境基本都有；
  找不到时会明确报错而不是丢一堆莫名其妙的命令错误）。

### Windows 上获取 make 和 fastforge

**make** —— Windows 不带，但系统里大概率已有（Android SDK 的 NDK 自带）：

```bash
ls "<Android SDK>/ndk/<版本>/prebuilt/windows-x86_64/bin/make.exe"
# 验证后复制到 PATH 内的任一目录即可
```

没有 Android SDK 时：`winget search make` 或 `mise use -g make`。

**fastforge** —— 打包才需要：

```bash
dart pub global activate fastforge
```

装完**不需要**把它的目录加进 PATH，Makefile 会自动解析路径。
如果提示找不到，用 `make windows-install-deps` 安装并自检。

---

## 从零到能跑：完整编译指令

按顺序照抄。每步后面写的是"怎么算通过"。细节和排错在后面各节。

### 0. 装工具（一次性）

按上面「环境要求」那张表装：**Git for Windows、GNU Make、Flutter 3.38.5、
Visual Studio 2022（C++ 桌面开发）** 四样是编译必需；要源码编核心再加 **Go 1.25.6**，
要打包再加 **`fastforge`**（`make windows-install-deps`）。

```powershell
go env -w "GOMODCACHE=$env:USERPROFILE/go/pkg/mod2"
```

> 这条只做一次，但必须做 —— 否则源码编核心时会随窗口"时好时坏"。原因见「Go 模块缓存必须固化」。

### 1. 取源码（**每一层都要在 `my` 分支**）

```powershell
git clone -b my https://github.com/asmzhang/hiddify-app.git
cd hiddify-app

# ① 把各层内容拉到 my 的尖端
git submodule update --init --recursive --remote

# ② 把各层 HEAD 真正挂到 my 分支上（① 不做这件事）
git submodule foreach --recursive "git checkout -B my origin/my"
```

三层 `.gitmodules` 里 **7 个声明全写的 `branch = my`**（`hiddify-core`；`hiddify-sing-box`、`ray2sing`；
`replace/` 下 4 个），所以 `--remote` 保证「拿到的是各层 `my` 尖端的提交」。

> **① 只决定"内容"，不决定"HEAD 挂在哪个分支"。** `submodule update` 无论带不带
> `--remote`，内部都是 `git checkout <sha>`，结束在**游离 HEAD**；`--remote` 也不会替你
> 建出本地 `my` 分支（已逐层实测：7 层的 `rev-parse --abbrev-ref HEAD` 全是 `HEAD`）。
> 少跑 ② 的后果：那层没有本地 `my`，你 `git commit` 会提交到游离头指针上，很容易丢。
>
> ② 会**重置**各层 `my` 到远端尖端。若某层 `my` 上有未推送的提交，先
> `git -C <那一层> push -u origin my`，或把 ② 换成 `git switch my` 只做切换、不对齐远端。

> **不带 `--remote` 的原生行为是锁在父仓库记录的 SHA 上**（游离 HEAD），而父仓库的指针
> 可能已经旧了 —— 本仓库真踩过：`ray2sing` 的 anytls 修复、`hiddify-sing-box` 的
> `170d8315` 合并都被这样切掉过。**做了下面那次配置后这个坑就没了**：plain update
> 也会自动拉取远端 `my` 并对齐。

#### 可选：一次性配置，之后一条命令就是"一键"

git **不允许**把自定义命令写进 `.gitmodules`（会直接
`fatal: invalid value for 'submodule.<name>.update'` —— 版本控制的文件里放任意命令
等于 "clone 即执行代码"，是刻意的安全设计），所以它只能落在 `.git/config`。
写全局配置，本机所有 clone 一次性生效：

```powershell
$c = '!f() { git fetch -q --no-recurse-submodules origin "+refs/heads/my:refs/remotes/origin/my" >/dev/null 2>&1 || true; if ! git rev-parse --verify -q refs/remotes/origin/my >/dev/null 2>&1; then git checkout -q --detach "$1"; return; fi; if git rev-parse --verify -q refs/heads/my >/dev/null 2>&1 && ! git merge-base --is-ancestor refs/heads/my refs/remotes/origin/my 2>/dev/null; then echo "warn: 子模块 my 有未推送提交，已跳过自动对齐" >&2; git checkout -q my; else git checkout -q -B my origin/my; fi; }; f'
'hiddify-core','hiddify-sing-box','ray2sing','replace/tailscale','replace/psiphon-quic-go','replace/psiphon-tls','replace/wireguard-go' |
  ForEach-Object { git config --global "submodule.$_.update" $c }
```

配好之后 **`my` 成为权威源**：命令先自动 fetch 远端 `my`，再把各层 HEAD 对齐到 `origin/my`。

| 命令 | 各层内容 | HEAD |
|---|---|---|
| `git submodule update --init --recursive` | **各层 `my` 尖端**（自动拉取） | **在 `my` 上** |
| `git submodule update --init --recursive --remote` | 各层 `my` 尖端 | **在 `my` 上** |

要点：

- **父仓库记录的 gitlink 不再是内容来源。** 好处是改完子模块不必再回父仓库 `git add`
  更新指针；代价是 `git submodule status` 会常显 `+`（属预期），构建不再钉在某个固定提交上。
- 命令**必须自带 fetch**（显式 `+refs/heads/my:refs/remotes/origin/my`，`+` 允许强推覆盖）。
  `git submodule update` 自己那次 fetch 靠不住 —— 记录的提交已在本地时它会整个跳过，
  于是 `origin/my` 是陈旧的。
- **未推送提交有保护**：某层 `my` 有远端没有的提交时，打印 warning、只切回 `my` 而不重置；
  推走之后下次自动恢复对齐。
- 离线（fetch 失败）时静默降级，用本地已知的 `origin/my` 落位，不中断。
- 撤销：`git config --global --remove-section submodule.<name>`，逐条。

核对（每层都该回显 `my`，一条命令看全部 7 层）：

```powershell
git submodule foreach --recursive "git rev-parse --abbrev-ref HEAD"
```

> 别用 `git submodule status` 的括号内容来判断 —— 那是 `describe` 的启发式结果，
> 会在同提交的多个 ref 里随便挑一个（实测会显示 `heads/master`、`remotes/origin/my` 等），
> 和 HEAD 实际挂在哪个分支无关。

**已经切到游离 HEAD 了怎么修**：

```powershell
# 只想把 7 层挂回 my、不对齐远端（纯离线，不动各层 my 指针）
git submodule foreach --recursive "git switch my 2>/dev/null || git switch -c my --track origin/my"

# 想同时对齐到远端 my 尖端（会重置各层 my 指针，见上面 ② 的提醒）
git submodule foreach --recursive "git checkout -B my origin/my"
```

> ① 八层 fork 的**远端都已有 `my` 分支**（已逐层核实），所以 `--remote` 可用。
> ② 但 `--remote` 拿到的是**远端的 `my`**，可能落后于你本地 —— 本地有未推的提交时，
> 先 `git -C <那一层> push -u origin my`，否则新 clone 会缺东西。
> ③ **父仓库记录的指针也要跟着更新**（在 `hiddify-core` 里 `git add hiddify-sing-box ray2sing` 后提交，
> 顶层再 `git add hiddify-core` 提交），否则任何不带 `--remote` 的 `submodule update` 都会切回旧指针。

### 2. 自检

```powershell
make doctor
```

**通过标准：`Required` / `Packaging` / `Core libs` / `Core from source` 四段里没有 `FAIL`。**
`WARN fastforge` / `WARN Inno Setup` / `WARN msix cert` 与编译无关。
Visual Studio 不在 `make doctor` 里查，用 `flutter doctor` 确认。

> `go module cache` 那条报 FAIL **不一定是真问题**。它统计的是"已解压但缺 `.info`"的模块数，
> 是个偏保守的启发式 —— 缺 `.info` 只在 go 需要**重新解析那个模块**时才致命。
> 实测本机推荐的那个缓存就是 327 个里有 188 个缺，所以这条会稳定报 FAIL。
> 真正的判据是第 3 步能不能过；卡在 `[1a]` 了再回来看它。

### 3. 准备：拉依赖 + 代码生成 + 核心库

```powershell
make windows-prepare LOCAL_CORE=1
```

日志里依次会看到：

```
flutter pub get                     Dart 依赖
dart run build_runner build ...     生成 *.g.dart / *.freezed.dart
dart run slang                      生成翻译
== [1/3] building hiddify-core from source ==
  [1a] go mod tidy                  Go 依赖（首次最久，之后走缓存）
  [1b] building hiddify-core.dll    cgo，需要 x86_64-w64-mingw32-gcc
  [1c] building HiddifyCli.exe
  [1d] go.mod/go.sum must be untouched    下面应该是空的
== [2/3] packing the core-libs package ==
== [3/3] done ==
```

**通过标准：走到 `[3/3] done`，且 `[1d]` 下面是空的。**
不碰 `hiddify-core` 源码、只用上游预编译核心时，去掉 `LOCAL_CORE=1`。

### 4. 编译

```powershell
flutter build windows --release
```

**通过标准：退出码 0。** 产物：

```
build\windows\x64\runner\Release\Hiddify.exe
```

### 5. 跑一下

```powershell
.\build\windows\x64\runner\Release\Hiddify.exe
```

### 6. 打包便携版（可选）

```powershell
make windows-zip-release
```

**通过标准：**`dist\<版本>\hiddify-<版本>-windows.zip`。

### 其它平台

第 0-2、5 步相同，只换第 3、4、6 步：

| 平台 | 3. 准备 | 4. 编译 | 6. 打包 |
|---|---|---|---|
| Windows | `make windows-prepare LOCAL_CORE=1` | `flutter build windows --release` | `make windows-zip-release` |
| Linux | `make linux-prepare && make build-linux-libs` | `flutter build linux --release` | `make linux-release` |
| macOS | `make macos-prepare && make build-macos-libs` | `flutter build macos --release` | `make macos-release` |
| Android | `make android-prepare && make build-android-libs` | `flutter build apk --release` | `make android-release` |
| iOS | `make ios-prepare && make build-ios-libs` | `flutter build ios --release` | `make ios-release` |

Linux 还有 arm64 / musl 变体（`make linux-arm64-prepare`、`make linux-amd64-musl-prepare`、
`make linux-arm64-musl-prepare`）；源码编的对应规则见 `hiddify-core/Makefile` 的 `linux-%`。

非 Windows 平台**源码编必须放在 `<platform>-libs` 之后**（上表就是这么排的）——
`<platform>-libs` 会把 `.cache/core-libs/` 里的上游包解压覆盖上去。原因见「从源码编译核心库」。

---

## 核心库

核心库不进代码仓库（`hiddify-core/bin/` 被 gitignore），
**clone 后必须下载**，由 `<platform>-prepare` 自动完成。

落地位置：

| 平台 | 目录 |
|---|---|
| Windows、macOS | `hiddify-core/bin/` |
| Linux | `hiddify-core/bin/`（动态库在 `bin/lib/hiddify-core.so`） |
| Android | `android/app/libs/`（`hiddify-core.aar`） |
| iOS | `ios/Frameworks/`（`HiddifyCore.xcframework`） |

默认从 GitHub 的 `draft` release 下载；`CHANNEL=prod` 时改用
`dependencies.properties` 里的 `core.version` 对应版本（当前 `4.1.0`）。
`CHANNEL=prod` 同时把构建入口从 `lib/main.dart` 换成 `lib/main_prod.dart`。

下载的包会缓存到 `.cache/core-libs/`（**刻意放在 `build/` 之外** ——
放 `build/` 里会被 `flutter clean` 一起删掉），**同一来源不会重复下载**
（换 `CHANNEL` 或换核心库版本会自动重新下载）。需要强制刷新时：

```bash
make windows-libs FORCE=1      # 或对应平台的 *-libs
```

核心库**可以从源码编**（全平台）—— 见下一节。

---

## 从源码编译核心库

改了 `hiddify-core` / `hiddify-sing-box` / `ray2sing` 之后必须走这条 ——
`<platform>-libs` 默认是**下载**上游编好的核心，你的改动不会进去。

| 平台 | 命令 | 产物落到 |
|---|---|---|
| Windows | `make windows-prepare LOCAL_CORE=1` | `hiddify-core/bin/`：`hiddify-core.dll` + `HiddifyCli.exe` + `libcronet.dll` |
| Linux | `make linux-prepare && make build-linux-libs` | `hiddify-core/bin/lib/hiddify-core.so` + `bin/HiddifyCli` |
| macOS | `make macos-prepare && make build-macos-libs` | `hiddify-core/bin/hiddify-core.dylib` |
| Android | `make android-prepare && make build-android-libs` | `android/app/libs/hiddify-core.aar` |
| iOS | `make ios-prepare && make build-ios-libs` | `ios/Frameworks/HiddifyCore.xcframework` |

Windows 之外的平台，真正的实现在 `hiddify-core` 自己的 Makefile 里
（`windows-amd64` / `linux-<arch>` / `macos` / `android` / `ios`），顶层 `build-*-libs` 只是转发。

> **顺序很重要。** 非 Windows 平台要把源码编放在 `<platform>-libs` **之后**，或者干脆只跑
> `common-prepare` —— `<platform>-libs` 每次都会把 `.cache/core-libs/` 里的上游包**解压覆盖**上去，
> 先编再跑 prepare 会把你的产物冲掉。Windows 没这个问题：`windows-libs-local` 会把自己的产物
> 打回缓存，`windows-libs` 再解压出来的就是源码编的那个。

`make doctor` 会检查这节需要的东西：Go 版本、mingw gcc（Windows）、Go 模块缓存。

### Windows 的这条为什么是本地定制的

`hiddify-core/Makefile` 第 10-12 行**故意**写成非法语法（`Not available for Windows! use bash in WSL`），
所以在 Windows 上 `make -C hiddify-core` 必然失败。**被挡的是 make，不是 go。**
顶层 `windows-libs-local` 把它第 68-83 行的命令搬了过来，并处理四个坑：

| 坑 | 处理 |
|---|---|
| cgo 需要 gcc | 用 `MINGW_BIN`（默认 llvm-mingw 的 `x86_64-w64-mingw32-gcc`）；**MSVC 不能当 CC** |
| go 会读 `HTTP(S)_PROXY`，环境里的本地代理会拖慢且不走你实际线路 | 先 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY` |
| `-mod=mod` 遇到 go.mod 里没有的 import 会去挑 `@latest`（实测把 gvisor 拉到当天主干，要求 go ≥ 1.26.3） | 用 `go mod tidy`，也就是上游的 `prepare` |
| `tidy` / `build` 会写脏 `go.mod`、`go.sum` | 全程走 `-modfile=go.verify.mod` 替身，原文件不动 |

完整步骤（出问题就对着这几行看日志）：

```
[1a] go mod tidy                                              # = 上游的 prepare
[1b] go build -buildmode=c-shared
       GOOS=windows GOARCH=amd64 CGO_ENABLED=1 CC=x86_64-w64-mingw32-gcc
       -trimpath -ldflags="-w -s -checklinkname=0 -buildid="
       -tags <CORE_TAGS>,with_purego                          # -> bin/hiddify-core.dll
[1c] 同一套，另加 CGO_LDFLAGS=hiddify-core.dll，-tags <CORE_TAGS>
       ./cmd/bydll                                            # -> bin/HiddifyCli.exe
[1d] git status --short -- go.mod go.sum                      # 与构建前一致就正常（见下）
[2/3] 把 hiddify-core.dll / HiddifyCli.exe / libcronet.dll
      重新打回 .cache/core-libs/hiddify-lib-windows-amd64.tar.gz
[3/3] 完成 —— .url 指纹没动，所以 windows-prepare 会命中缓存
```

> `[1d]` 那行要跟**构建前**比，不是要求"一定为空"。`go.mod` 本来就可能带着未提交的改动
> （本仓库就有：`MasterDnsVPN` 的版本 pin），那它会稳定打印 ` M go.mod` —— 实测就是这样。
> 关键是**构建前后清单一致**；脚本用 `-modfile` 替身就是为了保证这一点。

`<CORE_TAGS>` = `with_gvisor,with_quic,with_wireguard,with_utls,with_clash_api,with_grpc,with_awg,tfogo_checklinkname0,with_naive_outbound,with_conntrack`（即 Makefile 的 `CORE_TAGS`）。

`libcronet.dll` 是**唯一没有源码路径**的东西 —— Google 预编译二进制，上游用
`go run github.com/sagernet/cronet-go/cmd/build-naive@<ver> extract-lib --target windows/amd64` 抽出来。
`[2/3]` 会从旧包里把它保留下来，所以**这台机器上第一次必须先成功下过一次上游包**。

可覆盖：`MINGW_BIN=<dir>`、`CORE_GOPROXY`（默认官方；国内 `CORE_GOPROXY=https://goproxy.cn,direct`）。

### 其它平台的前置

| 平台 | 额外要求 |
|---|---|
| Linux | 先 `make -C hiddify-core cronet-amd64` —— 它生成 `cronet/cronet.env`，而 `build-linux` 依赖这个文件（这一步会下载 toolchain） |
| macOS | Xcode 命令行工具（clang + `lipo`）；会分别编 amd64 / arm64 再用 `lipo` 合成 |
| Android / iOS | `gomobile` + `gobind` + npm —— `lib_install` 目标会自动 `go install` 那两个工具并跑 `npm install` |

### Go 模块缓存必须固化

全平台同理（路径各自不同）。不固化就会"时好时坏"：某个终端里临时设过 `GOMODCACHE`，
换个窗口就丢，于是退回一个被 `@latest` 扫描污染过的默认缓存，`tidy` 撞 `requires go >= 1.26.3`。

```powershell
go env -w "GOMODCACHE=$env:USERPROFILE/go/pkg/mod2"   # 全局生效；go env -u 撤销
go env GOMODCACHE                                      # 确认回显
```

---

## 打包安装包

```bash
dart pub global activate fastforge
make <platform>-release

# 或按需只打一种
make windows-zip-release    # portable zip —— Windows 本地推荐
make windows-exe-release    # 安装程序（需 Inno Setup 6）
make windows-msix-release   # 仅 CI 可跑，见下
```

> `make windows-release` 是 **zip + exe + msix 三合一**，但它是「尽力而为」：
> zip 一定做；exe / msix 缺前置就打印 `SKIP …(原因)` 后跳过，**整体仍以成功退出**。
> 只有单独的 `windows-exe-release` / `windows-msix-release` 是严格的 —— 缺前置直接失败。
> 本地只想要便携包就单跑 `make windows-zip-release`。

**msix 为什么本地做不了**：它是微软商店交付物，必须用证书签名。证书不在仓库里，
由 CI 在打包前从机密 `WINDOWS_SIGNING_KEY` 解出写到 `windows\sign.pfx`
（`.github/workflows/build.yml`）。且 `windows/packaging/msix/make_config.yaml`
里的 `publisher` 是**商店身份**，自签证书签不出来。所以 msix 只在 CI 出。

需要本地侧载测试包时：生成一张 subject 与 `publisher` **完全一致**的自签名证书
（msix 只校验 subject 匹配）放到 `windows\sign.pfx` 即可，`make_config.yaml` 的
`certificate_password:` 本来就是空的，**不用改**。
**不要改 `publisher`** —— CI 只替换 `certificate_password`，改了 `publisher`
会把 CI 出的 msix 一起弄坏。

产物在 `dist/`。各平台 release 目标：

| 平台 | 命令 | 产出 |
|---|---|---|
| Windows | `make windows-zip-release` | portable zip（`make windows-release` 是三合一，见上） |
| Android | `make android-release` | apk + aab |
| Linux | `make linux-release` | deb + AppImage |
| macOS | `make macos-release` | dmg + pkg |
| iOS | `make ios-release` | ipa |

---

## 排错

**编译全部成功，最后报 `Build process failed.`**
核心库缺失。先 `make doctor` 确认，然后重跑 `make <platform>-libs`。
（若核心是你自己源码编的，重跑这一步会把下载的包解压覆盖上去 —— 见「从源码编译核心库」。）

**产物目录里只有一个孤立的 exe（Windows）**
CMake 缓存脏了，删掉重来：

```powershell
Remove-Item -Recurse -Force build\windows
flutter build windows --release
```

**下载核心库失败**
访问 GitHub 不稳定。手动下同名包解压到上表目录即可，包名就是 Makefile 里那几个：
`hiddify-lib-windows-amd64.tar.gz`、`-macos`、`-ios`、`-android`、
`-linux-amd64`（另有 `-linux-arm64` / `-linux-amd64-musl` / `-linux-arm64-musl`）。
地址即 `CORE_URL`：默认 `…/releases/download/draft`，`CHANNEL=prod` 时为 `…/download/v4.1.0`。
本机有代理时给 curl 加 `--proxy socks5h://127.0.0.1:<端口>`，或在环境里设 `HTTPS_PROXY` 后重跑
`make <platform>-libs`。

**编核心成功、但 App 启动即退（code 2）或 CLI 报
`panic: tls: ConnectionState ... struct field mismatch`**
Go 版本不是 1.25.x（1.26 新增字段破坏了 psiphon-tls 的布局断言）。
`go version` 确认后换 `mise use -g go@1.25.6` 重编核心，重跑 `flutter build windows --release`。

**编核心时报 `finding module for package ...` 或 `requires go >= 1.26.3`**
不是源码或版本问题，是 Go 用错了模块缓存：

```powershell
go env GOMODCACHE
go env -w GOMODCACHE=C:/Users/Administrator/go/pkg/mod2
```

详见「Go 模块缓存必须固化」。注意 `make doctor` 的 Go 缓存体检查的是
「已解压的模块缺不缺 `.info`」，**查不出"用错缓存"这一种**。

**打包时刷 `Can't load Kernel binary: Invalid kernel binary format version`**
`fastforge` 的启动脚本由 pub 生成，里面按**激活时那个 Dart 版本**写死了快照名。
若之后换用别的 Dart，二者版本号对不上（如 125 vs 138），VM 拒绝加载快照，
脚本只好退回「重新编译源码再跑」—— 所以命令不会挂，只是**每次打包白编译一遍**。

```bash
dart pub global activate fastforge    # 用当前 PATH 里那个 Dart 重新激活
```

前提：**PATH 里只有一个 Flutter**，且**改完 PATH 必须开新终端**再激活。
旧终端里缓存的环境变量会把另一个 SDK 的 Dart 带进来 —— 这个报错就是这么来的。

**`make windows-exe-release` / `make windows-msix-release` 直接失败**
这两个目标的前置条件本地通常不具备（Inno Setup 6、商店签名证书），
Makefile 会**在调 fastforge 之前就停下并说清原因**，不会抛 Dart 栈。
`make windows-release` 聚合目标不会因此失败 —— 它把这两个 `SKIP` 掉。
只想拿便携包就单跑 `make windows-zip-release`。
