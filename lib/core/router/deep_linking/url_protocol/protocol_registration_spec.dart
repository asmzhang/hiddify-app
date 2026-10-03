// 桌面端「URL 协议关联」的注册决策。
//
// ## 问题：Android 的声明式清单被照搬成了 Windows 的独占接管
//
// 上游 `lib/core/router/deep_linking/my_app_links.dart:11-15` 在 Windows 上把
// `LinkParser.protocols` 整表无条件写进注册表。那张表来自 **Android** 的
// `android/app/src/main/AndroidManifest.xml:77-83`（hiddify 自己也是这么声明
// `NekoBoxForAndroid/app/src/main/AndroidManifest.xml:118-138` 的），内容是：
//
//     hiddify / v2ray / v2rayn / v2rayng / clash / clashmeta / sing-box
//
// 这张表在 Android 上无害，**因为 Android 的 intent-filter 是声明式的**：
// 多个应用可以声明同一个 scheme，系统按优先级给候选、由用户选，谁也灭不掉谁。
//
// Windows 的协议关联却是**独占的**：`HKCU\Software\Classes\<scheme>` 一个 scheme
// 只能有一个 `shell\open\command`，**后写的赢**。于是同一份清单在 Windows 上
// 语义完全变了 —— 每次启动都无条件重写 6 个**别人的**命名空间：
//
//   · `clash://install-config?url=...` 是 Clash for Windows / Clash Verge 的入口，
//     装了 hiddify 之后被静默接管，谁后启动谁赢；
//   · `sing-box://import-remote-profile` 同理（sing-box 官方客户端的 scheme）；
//   · `v2ray://` / `v2rayn://` / `v2rayng://` 是三个不同客户端的名字。
//
// 附带两个次生问题：注册的是 `Platform.resolvedExecutable`（开发构建即
// `build\windows\x64\runner\Release\Hiddify.exe`），`flutter clean` 之后这些键
// 变成指向不存在文件的孤儿；而 `unregisterProtocolHandler` 全仓无人调用，
// 卸载后键永远留下。
//
// ## 根治原则
//
// **只主张自己的命名空间。** 链接**解析**能力（收到 `clash://...` 能读懂）和
// 协议**关联**（让系统把 `clash://` 路由给我们）是两件事，前者不需要写注册表：
// 剪贴板导入、手动导入、拖拽、argv（`routing_config_notifier.dart:68` 的
// `LinkParser.protocols.contains`）都照旧工作。只有"点系统里的 `clash://` 链接"
// 这一个入口依赖关联键 —— 而那恰恰是不该拿的。
//
// 纯 Dart（不 import Flutter / dart:io），可被单测直接校验：
// `test/core/deep_linking/protocol_registration_spec_test.dart`。
//
// 规格源：`NekoBoxForAndroid/app/src/main/AndroidManifest.xml:95-138`（声明表）、
// `nekoray/main/main.cpp:81`（桌面规格源收链接走 argv，**一个 scheme 都不注册**）。

/// 本应用**自己的**命名空间。只有这里的 scheme 会在桌面端写注册表。
///
/// `hiddify` 对应 NekoBox 的 `sn`（`AndroidManifest.xml:103`）—— 各自产品的
/// 短链前缀，是唯一无歧义归属自己的名字。
const Set<String> kOwnedProtocolSchemes = {'hiddify'};

/// 只**解析**、不**主张**的 scheme：上游从 Android 清单照搬过来的外来命名空间。
///
/// 这些名字属于别的客户端。保留解析能力（粘贴/拖拽/argv 都能导入），
/// 但桌面端不再写注册表，也不再抢占。
const Set<String> kForeignProtocolSchemes = {
  'v2ray',
  'v2rayn',
  'v2rayng',
  'clash',
  'clashmeta',
  'sing-box',
};

/// 全部可解析的 scheme，顺序与上游 `LinkParser.protocols` 保持一致
/// （自有在前，外来在后），避免改动 `routing_config_notifier.dart:68` 的既有行为。
///
/// `const` 是刻意的：`LinkParser.protocols` 直接引用它，保持原来的编译期常量语义。
const List<String> kAllProtocolSchemes = [
  ...kOwnedProtocolSchemes,
  ...kForeignProtocolSchemes,
];

/// 对一个 scheme 该做的动作。四种状态互斥且穷尽。
enum ProtocolRegistrationAction {
  /// 自有命名空间且注册表里没有 ⇒ 写入本 exe 路径。
  claim,

  /// 已经正确指向本 exe ⇒ 一个字都不写。
  ///
  /// 幂等是硬要求：稳态下每次启动应当产生 **0 次注册表写**，
  /// 而不是像上游那样每次启动重写 7 个键。
  keep,

  /// 注册表里是我们自己写下的、但属于外来命名空间的键 ⇒ 删掉。
  ///
  /// 这是对历史误占的**自愈**：老版本写下的 6 个键会在下次启动时被清掉，
  /// 用户不需要手动改注册表。
  revoke,

  /// 不是我们的东西（外来命名空间且不是我们写的，或已被别的 exe 占用）⇒ 不碰。
  leave,
}

/// 从 `shell\open\command` 的值里抽出可执行文件路径。
///
/// 注册表里存的是命令行，形如：
///   `"S:\path\Hiddify.exe" "%1"`   （带引号，本应用与绝大多数安装器都这么写）
///   `C:\Program Files\Foo\foo.exe %1`  （不带引号但路径含空格）
///
/// 返回 null 表示"没有注册"（空值或无法解析）。
String? protocolCommandExecutable(String? command) {
  final raw = command?.trim();
  if (raw == null || raw.isEmpty) return null;

  if (raw.startsWith('"')) {
    final end = raw.indexOf('"', 1);
    if (end <= 1) return null;
    return raw.substring(1, end);
  }

  // 不带引号：以 `.exe` 为界切开，这样含空格的路径也能整段取出。
  final exe = raw.toLowerCase().indexOf('.exe');
  if (exe >= 0) return raw.substring(0, exe + 4);

  // 极罕见：没有 .exe 扩展名 ⇒ 退化为"第一个空白之前"。
  final space = raw.indexOf(' ');
  return space < 0 ? raw : raw.substring(0, space);
}

/// 两个路径是否指向同一个可执行文件。
///
/// Windows 路径大小写不敏感、分隔符 `\` 与 `/` 等价。**不做** 8.3 短名
/// （`ADMINI~1`）解析 —— 那需要文件系统访问，会把纯规格拖成 IO 依赖；
/// 代价是极少数短名注册会被判为"别人的"，落到 [ProtocolRegistrationAction.leave]，
/// 即**偏保守**（不写、不删），不会造成回退到抢占行为。
bool sameExecutablePath(String a, String b) {
  String normalize(String p) => p.trim().replaceAll('/', r'\').toLowerCase();
  return normalize(a) == normalize(b);
}

/// 取路径里的文件名部分（`C:\a\b\Hiddify.exe` → `hiddify.exe`）。
String executableFileName(String path) {
  final normalized = path.trim().replaceAll('/', r'\');
  final slash = normalized.lastIndexOf(r'\');
  final name = slash < 0 ? normalized : normalized.substring(slash + 1);
  return name.toLowerCase();
}

/// 注册表里记的那个 exe 是不是**我们自己**。
///
/// 判据是**文件名**，不只是全路径 —— 这一条是真机实测逼出来的：
/// 开发构建把 6 个外来键写成 `S:\...\Release\Hiddify.exe`，改用 `%TEMP%` 副本
/// 运行后全路径对不上，一个都没归还，自愈形同虚设。全路径在**升级、换安装目录、
/// 绿色版、开发构建与正式版并存**之间都会变，只比它就会让老键永远变成"别人的"。
///
/// 文件名 `hiddify.exe` 是只有本产品会用的名字，误伤别的客户端的概率为零，
/// 而它让自愈跨路径生效。仍然接受全路径完全一致的情况（同一个文件）。
bool isOurRegisteredExecutable(String registered, String executable) {
  if (sameExecutablePath(registered, executable)) return true;
  return executableFileName(registered) == executableFileName(executable);
}

/// 决定对 [scheme] 该做什么。**判断顺序即优先级**（都有断言覆盖）：
///
/// 1. 自有命名空间（`hiddify`）：
///    a. 注册表为空 → [ProtocolRegistrationAction.claim]
///    b. 已指向本 exe → [ProtocolRegistrationAction.keep]（幂等）
///    c. 指向别的 exe → [ProtocolRegistrationAction.claim]（自己的名字，拿回来）
/// 2. 外来命名空间（`clash` / `sing-box` / `v2ray*`）：
///    a. 注册表为空 → [ProtocolRegistrationAction.leave]（**绝不抢**）
///    b. 指向别的 exe → [ProtocolRegistrationAction.leave]（**绝不覆盖**）
///    c. 指向本产品（同名 exe，含旧路径）→ [ProtocolRegistrationAction.revoke]
///
/// 「是不是本产品」用 [isOurRegisteredExecutable] 判（比文件名，不只比全路径），
/// 这样换安装目录 / 用开发构建跑过之后，历史误占仍能被归还。
///
/// [registeredCommand] 是注册表 `shell\open\command` 的原始值（null = 没注册）。
/// [executable] 是本进程的可执行文件路径（`Platform.resolvedExecutable`）。
ProtocolRegistrationAction protocolRegistrationAction({
  required String scheme,
  required String? registeredCommand,
  required String executable,
}) {
  final current = protocolCommandExecutable(registeredCommand);
  final owned = kOwnedProtocolSchemes.contains(scheme.toLowerCase());

  if (owned) {
    if (current == null) return ProtocolRegistrationAction.claim;
    if (sameExecutablePath(current, executable)) {
      return ProtocolRegistrationAction.keep;
    }
    // 自有命名空间被别人占了 —— 包括另一个 hiddify 构建（正式版 vs 开发版）。
    // 这是我们的名字，取回；调用方会记一条日志让这件事可见。
    return ProtocolRegistrationAction.claim;
  }

  if (current == null) return ProtocolRegistrationAction.leave;
  if (isOurRegisteredExecutable(current, executable)) {
    return ProtocolRegistrationAction.revoke;
  }
  return ProtocolRegistrationAction.leave;
}
