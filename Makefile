# .ONESHELL:
include dependencies.properties

# ---------------------------------------------------------------------------
# Windows：自动切换到 Git 自带的 POSIX shell
#
# 本 Makefile 的 recipe 是 POSIX shell 脚本（$(...) / rm -rf / unzip ...），
# 而 Windows 上 make 默认会用 cmd.exe 解释它们，必然失败。
# 这里自动从 PATH 推导出 Git for Windows 的 sh.exe 并设成 SHELL，
# 同时把它配套的 usr\bin（tr / head / ls / unzip / rm ...）挂到 PATH 上。
#
# 结果：在 PowerShell 或 cmd 里直接 `make windows-release` 就能正常工作，
# 不需要用户自己去开 Git Bash。前提是装过 Git for Windows（Flutter 开发者基本都有）。
# ---------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
    ifeq ($(IS_GITHUB_ACTIONS),)
        _PATH_DIRS := $(subst ;, ,$(PATH))
        GIT_SH := $(abspath $(firstword $(foreach d,$(_PATH_DIRS),\
            $(wildcard $(d)/../usr/bin/sh.exe) \
            $(wildcard $(d)/../bin/sh.exe) \
            $(wildcard $(d)/sh.exe))))
        ifneq ($(GIT_SH),)
            SHELL := $(GIT_SH)
            # 只把一个 POSIX 格式的前缀加进 PATH。
            # /usr/bin 和 /bin 在 sh 眼里就是 Git 自带的 usr/bin（tr/head/unzip 等），
            # 而后面仍保留原始的 Windows 格式 PATH —— 由 MSYS 在启动 sh 时
            # 自行转换成 POSIX 格式。
            #
            # 不要在这里拼接 D:/... 这类 Windows 正斜杠路径：一旦 PATH 变成
            # 「Windows 项 + POSIX 项」的混合体，MSYS 会放弃转换，
            # bash 就把整条 PATH 当成一项，PATH 里的 dart / flutter 全部失效。
            export PATH := /usr/bin:/bin:$(PATH)
        else ifeq ($(shell uname),)
            $(error No POSIX shell found. Install Git for Windows, or run make from Git Bash / WSL. See docs/BUILD.md)
        endif
    endif
endif

# --- Log Colors ---
blue   := \033[1;34m
green  := \033[1;92m
yellow := \033[1;33m
reset  := \033[0m
# --- Log helpers ---
# Usage: $(BLUE) <text> $(DONE)
#
# 用 printf 而不是 `echo -e`：POSIX 的 echo 不保证支持 -e，
# Ubuntu 的 /bin/sh（dash）会把它当普通字符输出，日志里就会冒出
# `-e \033[1;34m` 这种东西。printf 是 POSIX 标准且本身就解释 \033。
BLUE   := printf "$(blue)
GREEN  := printf "$(green)
YELLOW := printf "$(yellow)
DONE   := $(reset)\n"

# ---------------------------------------------------------------------------
# SHELL_FORCE: 强制让这一行经过 POSIX shell
#
# 坑（仅 Windows 版 make 有）：make 判断是否走 shell 只看两件事 ——
#   ① 整行里有没有 shell 元字符（&& ; | > " 等）
#   ② 第一个词是不是它已知的 sh 内建命令（cd / command / export / exec …）
# 两条都不满足时，make **不调 shell**，改用 Windows 的 PATH + PATHEXT 直接执行。
# 于是 mkdir / rm / ls / echo / pwd 这些 POSIX 工具就找不到了，报：
#     process_begin: CreateProcess(NULL, mkdir -p xxx, ...) failed.
#     make (e=2): 系统找不到指定的文件。
# 此时 SHELL 变量设得再对也没用 —— make 根本不打算调它。
#
# 为什么根因是 PATH 而不是"用了 PowerShell"：
#   标准 Git for Windows 安装只往 PATH 里加 `Git\cmd`（git.exe 在那儿），
#   而 mkdir.exe / ls.exe / rm.exe 在 `Git\usr\bin` —— 不在 PATH 上。
#   所以**在 cmd 里跑一样会挂**，与用哪个终端无关。
#   从 bash 里跑之所以没事，是因为 bash 本身是 MSYS 的，
#   会把 PATH 里的 `/usr/bin` 解析成 Git 的 `usr\bin` 再交给 make。
# 实测（PATH 里无 Git\usr\bin 时）：
#   mkdir -p x            -> 失败      mkdir -p x && true -> 成功
#   ls build / pwd / true / 裸 echo   -> 全都失败
#   cd build / command -v mkdir       -> 成功（走了 shell，属于 ② 那类）
#
# 解法：给这类命令行尾补一个恒真的 `&& true`（属于 ①），
# 同时不改变失败语义（前一条命令失败则整行仍然失败）。
#
# 注意：只能加在**整行末尾**，不能塞进 MKDIR/RM 这类"命令前缀"里 ——
# 那会变成 `mkdir -p && true dir`，目录反而建不出来。
#
# 适用范围 —— 只给"用 POSIX 工具"的命令加：
#   mkdir / rm / ls / echo 这类，Windows 上没有能直接执行的文件。
# **不要**给 flutter / dart / make 这些命令加：它们有 .bat/.exe，
# make 直接 exec 本来就能跑通；强行改走 shell 反而会去依赖 sh 眼中的 PATH，
# 把本来好的搞坏（实测：给 `flutter pub get` 加了之后变成
# `/usr/bin/sh: line 1: flutter: command not found`）。
# ---------------------------------------------------------------------------
_empty :=
_space := $(_empty) $(_empty)
SHELL_FORCE := $(_space)&& true

MKDIR := mkdir -p
RM  := rm -rf
SEP :=/

# 本 Makefile 的所有 recipe 都使用 POSIX 命令（$(...) / rm -rf / unzip / tar …），
# 因此必须在 POSIX shell 中执行：Linux、macOS、Git Bash、WSL 都可以，
# PowerShell / cmd.exe 不行。不要在这里添加 cmd 专用写法（例如 rmdir /s /q），
# 那会与上面这个前提自相矛盾。


# Define sed command based on the OS
ifeq ($(OS),Windows_NT)
    # Windows (Assume Git Bash or similar sed is available, or standard syntax)
    SED := sed -i
else
	ifeq ($(shell uname),Darwin) # macOS
    	SED :=sed -i ''
	else # Linux
    	SED :=sed -i
	endif
endif


BINDIR=hiddify-core$(SEP)bin
ANDROID_OUT=android$(SEP)app$(SEP)libs
IOS_OUT=ios$(SEP)Frameworks
DESKTOP_OUT=hiddify-core$(SEP)bin
GEO_ASSETS_DIR=assets$(SEP)core

CORE_PRODUCT_NAME=hiddify-core
CORE_NAME=hiddify-lib
LIB_NAME=hiddify-core

ifeq ($(CHANNEL),prod)
	CORE_URL=https://github.com/hiddify/hiddify-core/releases/download/v$(core.version)
else
	CORE_URL=https://github.com/hiddify/hiddify-core/releases/download/draft
endif

ifeq ($(CHANNEL),prod)
	TARGET=lib/main_prod.dart
else
	TARGET=lib/main.dart
endif

BUILD_ARGS=--dart-define sentry_dsn=$(SENTRY_DSN)
DISTRIBUTOR_ARGS=--skip-clean --build-target $(TARGET) --build-dart-define sentry_dsn=$(SENTRY_DSN)

# ---------------------------------------------------------------------------
# 下载核心库
#
# 原实现是 `curl -L ... | tar xz`：没有重试，且 curl 失败时 tar 会跟着报错，
# 真正的错误（网络 / HTTP 状态）反而被淹没。这里改为：
#   -f         HTTP 错误直接返回非零退出码
#   --retry    网络抖动自动重试
#   先落盘再解压，任一步失败即中止
#
# 另外上游还有个浪费：每次都无条件重新下载（Windows 包 26MB），下完立刻把
# tarball 删掉，连缓存都不留 —— 所以每跑一次 prepare 就白下一次。这里把
# tarball 存到 .cache/core-libs/（.cache/ 已在 .gitignore 中，不会污染仓库）。
# 刻意不用 build/ 下的位置：`flutter clean` 会连 build/ 一起删掉，
# 缓存放那儿就白建了。
# 并在旁边记一份来源 URL 当"这个文件是从哪来的"指纹：
#   指纹一致                          -> 直接复用，跳过下载
#   指纹变了（换 CHANNEL / 换核心库版本）-> 自动重新下载
# 需要无条件刷新时：make <platform>-libs FORCE=1
#
# tarball 刻意不放在各平台的产物目录（如 android/app/libs）里 ——
# 那些目录会被后续打包步骤读取，不该混入缓存文件。
#
# 用法: $(call CORE_FETCH,<目标目录>,<包文件名>)
# ---------------------------------------------------------------------------
CURL := curl -fL --retry 3 --retry-delay 2 --connect-timeout 30
CORE_CACHE := .cache/core-libs
CORE_FETCH = $(MKDIR) "$(CORE_CACHE)" && \
  if [ -z "$(FORCE)" ] && [ -f "$(CORE_CACHE)/$(2)" ] && [ "$$(cat "$(CORE_CACHE)/$(2).url" 2>/dev/null)" = "$(CORE_URL)/$(2)" ]; then \
    printf "    cached: %s  (FORCE=1 to re-download)\n" "$(2)"; \
  else \
    printf "    downloading: %s\n" "$(2)"; \
    $(CURL) -o "$(CORE_CACHE)/$(2)" "$(CORE_URL)/$(2)" && printf "%s" "$(CORE_URL)/$(2)" > "$(CORE_CACHE)/$(2).url"; \
  fi && \
  tar xzf "$(CORE_CACHE)/$(2)" -C "$(1)"

# ---------------------------------------------------------------------------
# 生成 zip 包
#
# bsdtar（Windows 自带、macOS 自带）支持 `tar -a -cf x.zip` 写出真正的 zip；
# GNU tar（Linux、Git Bash）不支持写 zip —— 它会生成一个 tar 格式的文件，
# 却仍然命名为 .zip，而且不报任何错。所以必须先探测能力，再选择工具：
#   bsdtar  -> tar -a
#   其它    -> zip 命令
#   都没有  -> 明确失败（而不是静默产出一个坏掉的包）
#
# 用法: $(call MAKE_ZIP,<输出 zip>,<要打包的目录名>)
# ---------------------------------------------------------------------------
# 定位 bsdtar：Windows 自带的那份在 System32，即使 PATH 里 GNU tar 排在它前面
# 也要显式指向它 —— 否则 `tar -a` 会静默产出 tar 格式的假 zip。
# 非 Windows 平台直接交给 PATH（macOS 自带的就是 bsdtar）。
#
# 注意：这里刻意只用 make 内置的 $(wildcard)，不调用任何外部命令。
# $(shell ...) 依赖 shell 与 PATH，在从 PowerShell 启动 make 的场景下
# 可能连 ls/tr 都找不到，导致变量静默变空。
ifeq ($(OS),Windows_NT)
  BSDTAR ?= $(firstword \
      $(wildcard $(SystemRoot)/System32/tar.exe) \
      $(wildcard $(windir)/System32/tar.exe) \
      $(wildcard C:/Windows/System32/tar.exe) \
      tar)
else
  BSDTAR ?= tar
endif

MAKE_ZIP = if "$(BSDTAR)" --version 2>/dev/null | grep -qi bsdtar; then "$(BSDTAR)" -a -cf "$(1)" "$(2)"; elif command -v zip >/dev/null 2>&1; then zip -qr "$(1)" "$(2)"; else echo "ERROR: creating $(1) needs bsdtar or the zip command" >&2; exit 1; fi

# ---------------------------------------------------------------------------
# fastforge（打包器，由 `dart pub global activate fastforge` 安装）
#
# Windows 上 pub 只生成 fastforge.bat，其所在目录默认不在 PATH，
# 而且 sh 的 PATH 搜索不认 .bat 扩展名。这里直接解析出可执行文件的
# 完整路径交给 make 调用，无需改 PATH，也无需额外造 shim。
# 解析不到时回退为裸 `fastforge`，交由 PATH 决定。
# ---------------------------------------------------------------------------
# 同样只用 $(wildcard)，不依赖外部命令。
ifeq ($(OS),Windows_NT)
  FASTFORGE ?= $(firstword $(wildcard \
      $(LOCALAPPDATA)/Pub/Cache/bin/fastforge.bat \
      $(APPDATA)/Pub/Cache/bin/fastforge.bat \
      $(HOME)/AppData/Local/Pub/Cache/bin/fastforge.bat) fastforge)
else
  FASTFORGE ?= fastforge
endif

# ---------------------------------------------------------------------------
# Windows 打包 exe 安装程序 需要 Inno Setup（fastforge 的 exe target 会调用它）。
#
# 注意：**不能用 $(wildcard) 探测**。$(wildcard) 的实参语义是
# "空格分隔的多个 pattern"，而 Inno Setup 的路径里就有空格
# （`Program Files` / `Inno Setup 6`），会被切成若干无效 pattern 而
# **永远匹配不到**。这个 bug 实测在 CI 上暴露过：runner 上明明已经装了
# Inno Setup v6.7.1，探针却报 not found，于是 exe 被无谓地跳过。
#
# 因此改用 $(shell)，并且**只用 shell 内建**（for / [ -f ] / echo），
# 不调用 ls / head 之类外部命令 —— 那些在从 PowerShell 启动 make 时可能不存在。
# 同时把 fastforge 也认的 INNO_SETUP_PATH 纳入考虑。
# ---------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
  ISCC := $(firstword $(shell for p in \
      "$${INNO_SETUP_PATH:+$$INNO_SETUP_PATH/ISCC.exe}" \
      "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
      "/c/Program Files/Inno Setup 6/ISCC.exe" \
      "/c/Program Files (x86)/Inno Setup 5/ISCC.exe"; \
      do [ -f "$$p" ] && echo "$$p"; done))
endif

# ---------------------------------------------------------------------------
# 打包目标的"早失败"前置检查。
#
# windows-release 是 zip + exe + msix 三合一，任一前置缺失就会整条失败 ——
# 而前面的产物其实已经成功产出了。不检查的话，失败发生在 fastforge 内部，
# 报的是一段 Dart 栈，和真实原因（没装 Inno Setup / 没有签名证书）隔了一层，
# 还白跑一遍 flutter build。所以在这里先检查、先停下、把原因说清楚。
# ---------------------------------------------------------------------------
ifeq ($(OS),Windows_NT)
    ifeq ($(ISCC),)
        EXE_PREREQ := echo "ERROR: Inno Setup 6 is required by windows-exe-release."; echo "       winget install JRSoftware.InnoSetup  (then re-open the terminal)"; echo "       Only the .exe installer needs it - 'make windows-zip-release' does not."; echo "       See docs/BUILD.md [Packaging]."; exit 1
    else
        EXE_PREREQ := true
    endif
    # msix 需要微软商店签名证书 windows/sign.pfx。它不在仓库里，也不该进仓库：
    # CI 在打包前从机密 WINDOWS_SIGNING_KEY 解出 base64 写到这个路径
    # （.github/workflows/build.yml），密码同理来自 WINDOWS_SIGNING_PASSWORD。
    # 且 make_config.yaml 里的 publisher 是商店身份，自签证书签不出来。
    # => msix 是 CI 专属目标，本地请用 windows-zip-release。
    ifeq ($(wildcard windows/sign.pfx),)
        MSIX_PREREQ := echo "ERROR: windows/sign.pfx not found - msix is a CI-only artifact."; echo "       CI writes it from the WINDOWS_SIGNING_KEY secret."; echo "       For a local build use:  make windows-zip-release"; echo "       See docs/BUILD.md [Packaging]."; exit 1
    else
        MSIX_PREREQ := true
    endif
else
    EXE_PREREQ := true
    MSIX_PREREQ := true
endif



get:	
	flutter pub get

gen:
	dart run build_runner build --delete-conflicting-outputs

translate:
	dart run slang



# ---------------------------------------------------------------------------
# doctor: 构建环境自检
#
# 上游原本没有任何检查目标，缺东西时会一路跑到最后一步才失败，而且报错
# 往往与真实原因无关（典型例子：缺核心库，却在 CMake 的 INSTALL 阶段报错）。
# 先跑这个，把问题提前暴露出来。
# ---------------------------------------------------------------------------
# doctor 的输出刻意使用 ASCII：中文在 Windows 控制台（GBK 代码页）会乱码，
# 在 CI 日志里也不友好。所有 recipe 一律避开多行 if/fi，改成单行形式 ——
# 多行写法容易因为续行与引号嵌套出错。
ifeq ($(OS),Windows_NT)
    ifeq ($(ISCC),)
        DOCTOR_ISCC := echo "    WARN Inno Setup       - needed only by windows-exe-release: winget install JRSoftware.InnoSetup"
    else
        DOCTOR_ISCC := echo "    OK   Inno Setup"
    endif
    ifeq ($(wildcard windows/sign.pfx),)
        DOCTOR_MSIX := echo "    WARN msix cert        - windows/sign.pfx absent: msix is CI-only (CI injects the signing secret)"
    else
        DOCTOR_MSIX := echo "    OK   msix cert"
    endif
    DOCTOR_PLATFORM_EXTRA := $(DOCTOR_ISCC) && $(DOCTOR_MSIX)
else
    DOCTOR_PLATFORM_EXTRA := true
endif

.PHONY: doctor
doctor:
	@echo "==> Required"
	@command -v make >/dev/null 2>&1 && echo "    OK   make" || echo "    FAIL make            - see docs/BUILD.md"
	@command -v git >/dev/null 2>&1 && echo "    OK   git" || echo "    FAIL git             - install Git for Windows (recipes need its sh)"
	@command -v curl >/dev/null 2>&1 && echo "    OK   curl" || echo "    FAIL curl            - needed to download core libs"
	@command -v tar >/dev/null 2>&1 && echo "    OK   tar" || echo "    FAIL tar             - needed to extract core libs"
	@command -v unzip >/dev/null 2>&1 && echo "    OK   unzip" || echo "    WARN unzip           - needed by windows-zip-release"
	@V=$$(dart --version 2>&1 | head -n 1); case "$$V" in *"Dart SDK"*) echo "    OK   $$V";; *) echo "    FAIL dart            - cannot run: $${V:-not found in PATH}"; echo "         resolved to: $$(command -v dart 2>/dev/null || echo '<nothing>')";; esac
	@V=$$(flutter --version 2>&1 | head -n 1); case "$$V" in *Flutter*) echo "    OK   $$V";; *) echo "    FAIL flutter         - cannot run: $${V:-not found in PATH}"; echo "         resolved to: $$(command -v flutter 2>/dev/null || echo '<nothing>')";; esac
	@echo "==> Packaging (only needed for make <platform>-release)"
	@if "$(FASTFORGE)" --version >/dev/null 2>&1; then echo "    OK   fastforge"; else echo "    WARN fastforge       - run: make windows-install-deps"; fi
	@if "$(BSDTAR)" --version 2>/dev/null | grep -qi bsdtar; then echo "    OK   zip tool: bsdtar"; elif command -v zip >/dev/null 2>&1; then echo "    OK   zip tool: zip command"; else echo "    WARN zip tool missing - packaging will fail"; fi
	@$(DOCTOR_PLATFORM_EXTRA)
	@echo "==> Core libs"
	@if [ -n "$$(ls -A $(DESKTOP_OUT) 2>/dev/null | grep -v '^\.gitkeep$$')" ]; then echo "    OK   present ($(DESKTOP_OUT))"; else echo "    WARN missing         - run: make <platform>-prepare"; fi

prepare:
	@echo use the following commands to prepare the library for each platform:$(SHELL_FORCE)
	@echo    make android-prepare$(SHELL_FORCE)
	@echo    make windows-prepare$(SHELL_FORCE)
	@echo    make linux-prepare $(SHELL_FORCE)
	@echo    make macos-prepare$(SHELL_FORCE)
	@echo    make ios-prepare$(SHELL_FORCE)

common-prepare:  get gen translate
windows-prepare: common-prepare windows-libs
	
ios-prepare: common-prepare ios-libs 
	cd ios; pod repo update; pod install;echo "done ios prepare"
	
macos-prepare: common-prepare macos-libs
linux-prepare: common-prepare linux-amd64-libs


linux-amd64-prepare: common-prepare linux-amd64-libs
linux-arm64-prepare: common-prepare linux-arm64-libs
linux-amd64-musl-prepare: common-prepare linux-amd64-musl-libs
linux-arm64-musl-prepare: common-prepare linux-arm64-musl-libs


linux-appimage-prepare:linux-prepare
linux-rpm-prepare:linux-prepare
linux-deb-prepare:linux-prepare

android-prepare:common-prepare android-libs	
android-apk-prepare:android-prepare
android-aab-prepare:android-prepare

.PHONY: generate_kotlin_protos
generate_kotlin_protos: 
	# Run protoc to generate Kotlin files
	# protoc \
	# 	--proto_path=hiddify-core/ \
	# 	--java_out=./android/app/src/main/java/ \
	# 	--grpc-java_out=./android/app/src/main/java/ \
	# 	$(shell find hiddify-core/v2 hiddify-core/extension -name "*.proto")
	rsync -av --delete \
		--include='*/' \
		--include='*.proto' \
		--exclude='*' \
		hiddify-core/v2 hiddify-core/extension ./android/app/src/main/protos/
	# # Find .proto files and update package declarations
	# find "./android/app/src/main/java/com/hiddify/hiddify/protos" -type f -name "*.java" | while read -r proto_file; do \
	#     if grep -q "^package " "$$proto_file"; then \
	#         $(SED) 's/^package \([\w\.]*\)/package com.hiddify.hiddify.protos.\1/g' "$$proto_file"; \
	#     fi \
	# done

generate_go_protoc:
	make -C hiddify-core -f Makefile protos
	echo "SED: $(SED)"
generate_dart_protoc:
	mkdir -p lib/hiddifycore/generated$(SHELL_FORCE)
	protoc --dart_out=grpc:lib/hiddifycore/generated --proto_path=hiddify-core/  $(shell find hiddify-core/v2 hiddify-core/extension -name "*.proto") 	google/protobuf/timestamp.proto ; \

.PHONY: protos
protos: generate_go_protoc generate_kotlin_protos generate_dart_protoc
	
	
	

macos-install-deps:
	brew install create-dmg tree 
	npm install -g appdmg
	dart pub global activate fastforge

ios-install-deps: 
	if [ "$(flutter)" = "true" ]; then \
		curl -L -o ~/Downloads/flutter_macos_3.19.3-stable.zip https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_3.22.3-stable.zip; \
		mkdir -p ~/develop; \
		cd ~/develop; \
		unzip ~/Downloads/flutter_macos_3.22.3-stable.zip; \
		export PATH="$$PATH:$$HOME/develop/flutter/bin"; \
		echo 'export PATH="$$PATH:$$HOME/develop/flutter/bin"' >> ~/.zshrc; \
		export PATH="$PATH:$HOME/develop/flutter/bin"; \
		echo 'export PATH="$PATH:$HOME/develop/flutter/bin"' >> ~/.zshrc; \
		curl -sSL https://rvm.io/mpapis.asc | gpg --import -; \
		curl -sSL https://rvm.io/pkuczynski.asc | gpg --import -; \
		curl -sSL https://get.rvm.io | bash -s stable; \
		brew install openssl@1.1; \
		PKG_CONFIG_PATH=$(brew --prefix openssl@1.1)/lib/pkgconfig rvm install 2.7.5; \
		sudo gem install cocoapods -V; \
	fi
	brew install create-dmg tree 
	npm install -g appdmg
	
	dart pub global activate fastforge
	

android-install-deps: 
	dart pub global activate fastforge
android-apk-install-deps: android-install-deps
android-aab-install-deps: android-install-deps
# loads the package list from linux_deps.list
LINUX_DEPS = $(shell grep -vE '^\s*#|^\s*$$' linux_deps.list)
# reads the Flutter version from pubspec.yaml
REQUIRED_VER = $(shell sed -n '/environment:/,/flutter:/ s/.*flutter:[[:space:]]*//p' pubspec.yaml | tr -d " '^\"")

linux-amd64-install-deps:linux-install-deps
linux-amd64-musl-install-deps:linux-install-deps
linux-arm64-install-deps:linux-install-deps
linux-arm64-musl-install-deps:linux-install-deps

linux-install-deps:
	@$(BLUE)Installing Debian/Ubuntu dependencies...$(DONE)
	sudo apt-get update -y
	sudo apt-get install -y $(LINUX_DEPS)
#	loading fuce kernel module
	@$(BLUE)Loading fuce kernel module$(DONE)
	sudo modprobe fuse
# 	tools for appimage
	@$(BLUE)Installing appimagetool$(DONE)
	if [ "$$(uname -m)" = "aarch64" ]; then \
		wget -O /tmp/appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-aarch64.AppImage"; \
	else \
		wget -O /tmp/appimagetool "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"; \
	fi
	chmod +x /tmp/appimagetool
	sudo mv /tmp/appimagetool /usr/local/bin/
#   cloning flutter sdk
	@$(BLUE)Cloning Flutter SDK$(DONE); \
	mkdir -p ~/develop; \
	cd ~/develop; \
	\
	if [ ! -d "flutter/.git" ]; then \
		$(BLUE)Flutter not found. cloning stable channel$(DONE); \
		rm -rf flutter; \
		git clone https://github.com/flutter/flutter.git -b stable flutter; \
	fi; \
	\
	git config --global --add safe.directory $$HOME/develop/flutter; \
	\
	export PATH="$$HOME/develop/flutter/bin:$$PATH"; \
	if ! grep -q 'flutter/bin' ~/.bashrc; then \
		echo 'export PATH="$$HOME/develop/flutter/bin:$$PATH"' >> ~/.bashrc; \
	fi
# 	syncing flutter version
	$(MAKE) linux-flutter-sync
# 	installing fastforge https://pub.dev/packages/fastforge
	@$(BLUE)Installing fastforge$(DONE); \
	export PATH="$$HOME/develop/flutter/bin:$$HOME/.pub-cache/bin:$$PATH"; \
	if ! grep -q '.pub-cache/bin' ~/.bashrc; then \
		echo 'export PATH="$$HOME/.pub-cache/bin:$$PATH"' >> ~/.bashrc; \
	fi; \
	dart pub global activate fastforge; \
	dart pub global activate protoc_plugin; \
	echo ""; \
	echo "============================================================"; \
	echo "NOTE: After first setup, use the following command to update the PATH"; \
	echo "source ~/.bashrc"; \
	echo "============================================================"

# 	syncing 'flutter sdk' version with pubspec.yaml flutter version
linux-flutter-sync:
	@$(BLUE)Syncing Flutter version with pubspec.yaml flutter version$(DONE); \
	export PATH="$$HOME/develop/flutter/bin:$$PATH"; \
	$(BLUE)Downloading Flutter SDK components...$(DONE); \
	flutter --version > /dev/null; \
	\
	$(BLUE)Checking Flutter version...$(DONE); \
	CURRENT_VER=$$(flutter --version | head -n 1 | awk '{print $$2}'); \
	$(BLUE)Target: $(REQUIRED_VER) | Current: $$CURRENT_VER$(DONE); \
	\
	if [ "$$CURRENT_VER" != "$(REQUIRED_VER)" ]; then \
		$(BLUE)Version mismatch! switching to $(REQUIRED_VER)...$(DONE); \
		cd ~/develop/flutter; \
		git fetch --tags; \
		git checkout $(REQUIRED_VER); \
		$(BLUE)Switched to $(REQUIRED_VER)$(DONE); \
		flutter doctor; \
	else \
		$(GREEN)Flutter SDK is ready.$(DONE); \
	fi

windows-install-deps:
	dart pub global activate fastforge
	@echo ""
	@echo "fastforge installed. Its bin directory does NOT need to be added to PATH:"
	@echo "this Makefile resolves the executable path automatically (see FASTFORGE)."
	@echo ""
	@echo "Note: packaging the .exe installer additionally requires Inno Setup:"
	@echo "  choco install innosetup    (or: winget install JRSoftware.InnoSetup)"
	@echo ""
	@$(MAKE) --no-print-directory doctor
	
gen_translations: #generating missing translations using google translate
	cd .github && bash sync_translate.sh
	make translate

android-release: android-apk-release android-aab-release

android-apk-release:
	"$(FASTFORGE)" package \
	  --platform android \
	  --targets apk \
	  --skip-clean \
	  --build-target=$(TARGET) \
	  --build-target-platform=android-arm,android-arm64,android-x64 \
	  --build-dart-define=sentry_dsn=$(SENTRY_DSN)
	ls -R build/app/outputs$(SHELL_FORCE)

android-aab-release:
	"$(FASTFORGE)" package \
	  --platform android \
	  --targets aab \
	  --skip-clean \
	  --build-target=$(TARGET) \
	  --build-dart-define=sentry_dsn=$(SENTRY_DSN) \
	  --build-dart-define=release=google-play

# ---------------------------------------------------------------------------
# windows-release = zip + exe + msix。
#
# 但 exe 需要 Inno Setup、msix 需要商店签名证书 —— 这两样通常只有发布环境才有
# （GitHub 的 windows runner 现在连 Inno Setup 都不预装了）。所以这个**聚合**
# 目标改成"尽力而为"：能做的都做，做不了的**明确打印跳过原因**，整体仍以 0 退出。
#
# 单独的 windows-exe-release / windows-msix-release **保持严格** ——
# 你明确要的就是那一个包，缺前置就应当报错停下（见 EXE_PREREQ / MSIX_PREREQ）。
# ---------------------------------------------------------------------------
windows-release:
	@$(MAKE) --no-print-directory windows-zip-release
	@if [ -n "$(ISCC)" ]; then \
	  $(MAKE) --no-print-directory windows-exe-release; \
	else \
	  printf "    SKIP windows-exe-release   (Inno Setup 6 not found)\n"; \
	fi
	@if [ -f windows/sign.pfx ]; then \
	  $(MAKE) --no-print-directory windows-msix-release; \
	else \
	  printf "    SKIP windows-msix-release  (windows/sign.pfx not found - store signing cert)\n"; \
	fi

windows-zip-release:
	"$(FASTFORGE)" package \
	  --platform windows \
	  --targets zip \
	  --skip-clean \
	  --build-target=$(TARGET) \
	  --build-dart-define=sentry_dsn=$(SENTRY_DSN) \
	  --build-dart-define=portable=true
	@FULL_PATH=$$(ls dist/*/*.zip | head -n 1); \
	ZIP_DIR=$$(dirname "$$FULL_PATH"); \
	ZIP_FILE=$$(basename "$$FULL_PATH"); \
	FILE_NAME=$${ZIP_FILE%.*}; \
	$(YELLOW)Post-processing Windows portable$(DONE); \
	cd "$$ZIP_DIR"; \
	$(BLUE)Extracting and Repacking...$(DONE); \
	mkdir -p Hiddify; \
	unzip -oq "$$ZIP_FILE" -d Hiddify/; \
	rm "$$ZIP_FILE"; \
	$(call MAKE_ZIP,$$FILE_NAME.zip,Hiddify); \
	rm -rf Hiddify; \
	$(GREEN)Successful$(DONE)

windows-exe-release:
	@$(EXE_PREREQ)
	"$(FASTFORGE)" package \
	  --platform windows \
	  --targets exe \
	  --skip-clean \
	  --build-target=$(TARGET) \
	  --build-dart-define=sentry_dsn=$(SENTRY_DSN)

windows-msix-release:
	@$(MSIX_PREREQ)
	"$(FASTFORGE)" package \
	  --platform windows \
	  --targets msix \
	  --skip-clean \
	  --build-target=$(TARGET) \
	  --build-dart-define=sentry_dsn=$(SENTRY_DSN)

linux-release: linux-deb-release linux-appimage-release

linux-amd64-release: linux-release
linux-arm64-release: linux-release
linux-amd64-musl-release: linux-release 
linux-arm64-musl-release: linux-release


linux-deb-release:
	"$(FASTFORGE)" package \
	--platform linux \
	--targets deb \
	--skip-clean \
	--build-target=$(TARGET) \
	--build-dart-define=sentry_dsn=$(SENTRY_DSN)


# ==============================================================================
# REFERENCE: MANUAL LIBRARY BUNDLING (INJECTION)
# ==============================================================================
# Use this method only if you need to manually force specific shared libraries 
# (e.g., libcurl.so.4) into the AppImage bundle.
#
# IMPLEMENTATION STEPS:
#
# 1. PRE-BUILD SCRIPT (Add to Makefile before build command):
#    Create a temporary directory and copy the target library there.
#    ---------------------------------------------------------------------------
#    mkdir -p linux/bundled_libs
#    cp /usr/lib/x86_64-linux-gnu/libcurl.so.4 linux/bundled_libs/
#    ---------------------------------------------------------------------------
#
# 2. CMAKE CONFIGURATION (Add to linux/CMakeLists.txt):
#    Instruct CMake to include the copied file in the final bundle.
#    ---------------------------------------------------------------------------
#    install(FILES "${CMAKE_CURRENT_SOURCE_DIR}/bundled_libs/libcurl.so.4"
#       DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
#       COMPONENT Runtime)
#    ---------------------------------------------------------------------------
#
# ! WARNING !
# This approach is generally DISCOURAGED. Manually bundling libraries can lead to
# "Dependency Hell," where bundled libs conflict with system libraries or have
# their own unresolved dependencies. It increases maintenance cost and may cause
# runtime instability. Use only for specific edge cases where standard linking fails.
# ==============================================================================
linux-appimage-release:
	"$(FASTFORGE)" package \
	--platform linux \
	--targets appimage \
	--skip-clean \
	--build-target=$(TARGET) \
	--build-dart-define=sentry_dsn=$(SENTRY_DSN)
	@$(YELLOW)Post-processing AppImage$(DONE); \
	$(BLUE)Extracting AppImage$(DONE); \
	cd dist/* && ./*.AppImage --appimage-extract > /dev/null; \
	$(BLUE)Replacing AppRun$(DONE); \
	cp ../../linux/packaging/appimage/AppRun squashfs-root/AppRun; \
	$(BLUE)Granting permissions$(DONE); \
	chmod +x squashfs-root/AppRun; \
	$(BLUE)Adding StartupWMClass to hiddify.desktop$(DONE); \
	sed -i '/^\[Desktop Entry\]/a StartupWMClass=app.hiddify.com' "squashfs-root/hiddify.desktop"; \
	$(BLUE)Removing old AppImage$(DONE); \
	rm *.AppImage; \
	$(BLUE)Deleting bundled libstdc++ to fix Arch Linux compatibility...$(DONE); \
	find squashfs-root/usr/lib -name "libstdc++.so.6" -delete; \
	$(BLUE)Rebuilding AppImage$(DONE); \
	ARCH=x86_64 appimagetool --no-appstream squashfs-root Hiddify.AppImage > /dev/null; \
	$(BLUE)Cleaning up squashfs$(DONE); \
	rm -rf squashfs-root; \
	$(YELLOW)Creating Portable Package$(DONE); \
	PKG_DIR_NAME="hiddify-linux-appimage"; \
	$(BLUE)Creating dir: $$PKG_DIR_NAME$(DONE); \
	mkdir -p "$$PKG_DIR_NAME"; \
	$(BLUE)Moving Hiddify.AppImage$(DONE); \
	cp -p "Hiddify.AppImage" "$$PKG_DIR_NAME/Hiddify.AppImage"; \
	$(BLUE)Creating Portable Home directory$(DONE); \
	mkdir -p "$$PKG_DIR_NAME/Hiddify.AppImage.home"; \
	$(BLUE)Compressing to .tar.gz$(DONE); \
	tar -czf "$$PKG_DIR_NAME.tar.gz" -C . "$$PKG_DIR_NAME"; \
	$(BLUE)Removing intermediate directory$(DONE); \
	rm -rf "$$PKG_DIR_NAME"; \
	$(GREEN)Successful$(DONE)

DOCKER_IMAGE_NAME := hiddify-linux-builder
DOCKER_FLUTTER_VOL := hiddify-flutter-sdk-cache
DOCKER_PUB_VOL := hiddify-pub-cache

ifeq ($(OS),Windows_NT)
    FIX_OWNERSHIP := echo \"Windows detected: Skipping chown\"
else
    FIX_OWNERSHIP := chown -R $(shell id -u):$(shell id -g) /host/dist_docker
endif

DOCKER_CMD := \
	set -e; \
	echo '** Copying source code to container...'; \
	mkdir -p /app; \
	tar -cf - --exclude='build' --exclude='.dart_tool' --exclude='dist' --exclude='dist_docker' --exclude='android' --exclude='windows' --exclude='ios' --exclude='macos' --exclude='.git' -C /host . | tar -xf - -C /app; \
	cd /app; \
	make linux-flutter-sync; \
	make linux-prepare; \
	echo '** Building Release (linux-release)...'; \
	make linux-release; \
	echo '** Copying artifacts to host...'; \
	rm -rf /host/dist_docker; \
	if [ -d \"dist\" ]; then \
		cp -r dist /host/dist_docker; \
		echo '** Fixing permissions for dist_docker...'; \
		$(FIX_OWNERSHIP); \
	else \
		echo 'Error: dist folder not found!'; \
		exit 1; \
	fi;

linux-docker-release:	
	@$(BLUE)Building docker image (Cached)$(DONE)
	docker build -t $(DOCKER_IMAGE_NAME) -f Dockerfile .
	
	@$(BLUE)Ensuring cache volumes exist$(DONE)
	docker volume create $(DOCKER_FLUTTER_VOL) || true
	docker volume create $(DOCKER_PUB_VOL) || true

	@$(YELLOW)Running build inside container$(DONE)
	@docker run --rm \
		-v "$(CURDIR)://host" \
		-v $(DOCKER_FLUTTER_VOL)://root/develop/flutter \
		-v $(DOCKER_PUB_VOL)://root/.pub-cache \
		-e APPIMAGE_EXTRACT_AND_RUN=1 \
		$(DOCKER_IMAGE_NAME) \
		//bin/bash -c "$(DOCKER_CMD)"

	@$(GREEN)Successful. Output is in 'dist_docker' folder.$(DONE)

macos-release:
	"$(FASTFORGE)" package --platform macos --targets dmg,pkg $(DISTRIBUTOR_ARGS)

ios-release: #not tested
	"$(FASTFORGE)" package --platform ios --targets ipa --build-export-options-plist  ios/exportOptions.plist $(DISTRIBUTOR_ARGS)

android-libs:
	$(MKDIR) $(ANDROID_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(ANDROID_OUT),$(CORE_NAME)-android.tar.gz)
	@ls -la $(ANDROID_OUT)

android-apk-libs: android-libs
android-aab-libs: android-libs

windows-libs:
	$(MKDIR) $(DESKTOP_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(DESKTOP_OUT),$(CORE_NAME)-windows-amd64.tar.gz)
	@ls -la $(DESKTOP_OUT)$(SHELL_FORCE)
	

linux-amd64-libs:
	$(MKDIR) $(DESKTOP_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(DESKTOP_OUT),$(CORE_NAME)-linux-amd64.tar.gz)

linux-arm64-libs:
	$(MKDIR) $(DESKTOP_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(DESKTOP_OUT),$(CORE_NAME)-linux-arm64.tar.gz)

linux-amd64-musl-libs:
	$(MKDIR) $(DESKTOP_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(DESKTOP_OUT),$(CORE_NAME)-linux-amd64-musl.tar.gz)

linux-arm64-musl-libs:
	$(MKDIR) $(DESKTOP_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(DESKTOP_OUT),$(CORE_NAME)-linux-arm64-musl.tar.gz)


macos-libs:
	$(MKDIR) $(DESKTOP_OUT)$(SHELL_FORCE)
	$(call CORE_FETCH,$(DESKTOP_OUT),$(CORE_NAME)-macos.tar.gz)

ios-libs: #not tested
	$(MKDIR) $(IOS_OUT)$(SHELL_FORCE)
	$(RM) $(IOS_OUT)/HiddifyCore.xcframework$(SHELL_FORCE)
	$(call CORE_FETCH,$(IOS_OUT),$(CORE_NAME)-ios.tar.gz)

get-geo-assets:
	echo ""
	# curl -L https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db -o $(GEO_ASSETS_DIR)/geoip.db
	# curl -L https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db -o $(GEO_ASSETS_DIR)/geosite.db

build-headers:
	make -C hiddify-core -f Makefile headers && mv $(BINDIR)/$(CORE_NAME)-headers.h $(BINDIR)/hiddify-core.h

build-android-libs:
	make -C hiddify-core -f Makefile android 
	mv $(BINDIR)/$(LIB_NAME).aar $(ANDROID_OUT)/

build-windows-libs:
	make -C hiddify-core -f Makefile windows-amd64

build-linux-libs:
	make -C hiddify-core -f Makefile linux-amd64 

build-macos-libs:
	make -C hiddify-core -f Makefile macos

build-ios-libs: 
	rm -rf $(IOS_OUT)/HiddifyCore.xcframework 
	make -C hiddify-core -f Makefile ios  
	mv $(BINDIR)/HiddifyCore.xcframework $(IOS_OUT)/HiddifyCore.xcframework

release: # Create a new tag for release.
	@CORE_VERSION=$(core.version) bash -c ".github/change_version.sh "



ios-temp-prepare: 
	make ios-prepare
	flutter build ios-framework
	cd ios
	pod install
	