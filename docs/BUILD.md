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
| 构建 | Flutter 3.38.5 | 解压后把 `<sdk>\bin` 加进 PATH |
| 构建 | `curl` `tar` `unzip` | Windows 10 1803+ 自带 / Git 自带 |
| 编译 | Visual Studio 2022 + C++ 工作负载 | 官网安装 |
| 打包 | `fastforge` | `make windows-install-deps` |
| 打包 exe | Inno Setup 6 | `winget install JRSoftware.InnoSetup` |
| 打包 msix | `makeappx`（Windows SDK）+ **签名证书** | 证书只有 CI 有，见「打包安装包」 |

构建 `.zip` 只需要前两组（**这也是 Windows 本地唯一推荐使用的目标**）；
`.exe` 额外需要 Inno Setup 6；`.msix` 本地做不了。

Makefile 的 recipe 是 POSIX shell 脚本。

- Linux / macOS：直接用。
- **Windows：也是直接 `make`**，在 PowerShell 或 cmd 里都行。
  Makefile 会自动定位 Git for Windows 自带的 sh 并接管 recipe 的解释，
  你不需要自己去开 Git Bash（前提是装了 Git for Windows，Flutter 环境基本都有；
  找不到时会明确报错而不是丢一堆莫名其妙的命令错误）。

```powershell
make windows-prepare
```

获取 make 与 fastforge 见文末。

---

## 构建

```bash
make doctor                 # 自检环境，缺什么会直接指出
make <platform>-prepare     # 拉依赖 + 代码生成 + 下载核心库
flutter build <platform> --release
```

产物在 `build/<platform>/...`。

## 打包安装包

```bash
dart pub global activate fastforge
make <platform>-release

# 或按需只打一种
make windows-zip-release    # portable zip —— Windows 本地推荐
make windows-exe-release    # 安装程序（需 Inno Setup 6）
make windows-msix-release   # 仅 CI 可跑，见下
```

> `make windows-release` 是 **zip + exe + msix 三合一**。任一前置缺失，整条命令
> 以失败退出 —— **但前面的产物已经成功写出了**，去 `dist/` 里拿。
> 本地只想要便携包就单跑 `make windows-zip-release`，不要用三合一目标。

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
| Windows | `make windows-release` | zip + exe + msix |
| Android | `make android-release` | apk + aab |
| Linux | `make linux-release` | deb + AppImage |
| macOS | `make macos-release` | dmg + pkg |
| iOS | `make ios-release` | ipa |

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
`dependencies.properties` 里的 `core.version` 对应版本。

下载的包会缓存到 `build/core-libs/`，**同一来源不会重复下载**
（换 `CHANNEL` 或换核心库版本会自动重新下载）。需要强制刷新时：

```bash
make windows-libs FORCE=1      # 或对应平台的 *-libs
```

Windows 无法从源码编译核心库（需要 WSL + mingw64）。

---

## 各平台命令

```bash
# Linux（含 arm64 / musl 变体，见 Makefile）
make linux-prepare       && make linux-release

# Windows
make windows-prepare     && flutter build windows --release && make windows-release

# macOS
make macos-prepare       && make macos-release

# Android
make android-prepare     && make android-release

# iOS
make ios-prepare         && make ios-release
```

VSCode 里也可直接按 F5，`.vscode/launch.json` 已配好调试入口
（含 Windows 桌面版专用配置）。

---

## 排错

**编译全部成功，最后报 `Build process failed.`**
核心库缺失。先 `make doctor` 确认，然后重跑 `make <platform>-libs`。

**产物目录里只有一个孤立的 exe（Windows）**
CMake 缓存脏了，删掉重来：

```bash
rm -rf build/windows && flutter build windows --release
```

**下载核心库失败**
访问 GitHub 不稳定所致。可用镜像下载 `hiddify-lib-<平台>.tar.gz`
后解压到上表对应目录。

**打包时刷 `Can't load Kernel binary: Invalid kernel binary format version`**
`fastforge` 的启动脚本由 pub 生成，里面按**激活时那个 Dart 版本**写死了快照名。
若之后换用别的 Dart，二者版本号对不上（如 125 vs 138），VM 拒绝加载快照，
脚本只好退回「重新编译源码再跑」—— 所以命令不会挂，只是**每次打包白编译一遍**。

```bash
dart pub global activate fastforge    # 用当前 PATH 里那个 Dart 重新激活
```

前提：**PATH 里只有一个 Flutter**，且**改完 PATH 必须开新终端**再激活。
旧终端里缓存的环境变量会把另一个 SDK 的 Dart 带进来 —— 这个报错就是这么来的。

**`make windows-release` 报 exe / msix 失败**
这两个目标的前置条件本地通常不具备（Inno Setup 6、商店签名证书），
Makefile 会**立刻停下并说明原因**，不会跑到 fastforge 里抛 Dart 栈。
zip 一般已经成功产出，去 `dist/` 拿即可；只想拿便携包就单跑
`make windows-zip-release`。

---

## Windows 上获取 make 和 fastforge

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
