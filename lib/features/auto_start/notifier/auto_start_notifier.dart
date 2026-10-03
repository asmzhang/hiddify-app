import 'dart:async';
import 'dart:io';

import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auto_start_notifier.g.dart';

/// 「跟随系统启动」的平台实现接缝。
///
/// `launch_at_startup` 是私有构造的单例（`lib/src/launch_at_startup.dart:18`），
/// 且**失败条件取决于宿主机策略**（Windows 下 `HKCU\...\CurrentVersion\Run` 被拒、
/// Linux 下 autostart 目录不可写、macOS 下 LaunchAgent 被拒）—— 普通测试机上
/// 复现不出这些拒绝，于是「失败必须降级而不是抛」这条不变量无法回归。
/// 抽出接口后，测试注入一个「调用即抛」的实现即可覆盖该路径。
abstract class AutoStartLauncher {
  void setup({required String appName, required String appPath, String? packageName});

  Future<bool> isEnabled();

  Future<bool> enable();

  Future<bool> disable();
}

class LaunchAtStartupLauncher implements AutoStartLauncher {
  const LaunchAtStartupLauncher();

  @override
  void setup({required String appName, required String appPath, String? packageName}) =>
      launchAtStartup.setup(appName: appName, appPath: appPath, packageName: packageName);

  @override
  Future<bool> isEnabled() => launchAtStartup.isEnabled();

  @override
  Future<bool> enable() => launchAtStartup.enable();

  @override
  Future<bool> disable() => launchAtStartup.disable();
}

final autoStartLauncherProvider = Provider<AutoStartLauncher>((ref) => const LaunchAtStartupLauncher());

@Riverpod(keepAlive: true)
class AutoStartNotifier extends _$AutoStartNotifier with InfraLogger {
  Timer? _timer;

  AutoStartLauncher get _launcher => ref.read(autoStartLauncherProvider);

  @override
  Future<bool> build() async {
    if (!PlatformUtils.isDesktop) return false;
    // 应用信息拿不到（provider 处于 loading/error）时不碰平台、直接降级为「未启用」：
    // `requireValue` 会抛 StateError，而这里在启动链上（bootstrap），抛出去就是 K-2 白屏。
    final appInfo = ref.watch(appInfoProvider).valueOrNull;
    if (appInfo == null) {
      loggy.info("app info unavailable, auto start reported as [Disabled]");
      return false;
    }
    _startTimer();
    ref.onDispose(() => _timer?.cancel());
    final isEnabled = await _guard("read status", () {
      _launcher.setup(
        appName: appInfo.name,
        appPath: Platform.resolvedExecutable,
        packageName: "Hiddify.HiddifyNext",
      );
      return _launcher.isEnabled();
    });
    loggy.info("auto start is [${isEnabled ? "Enabled" : "Disabled"}]");
    return isEnabled;
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (timer) => updateStatus());
  }

  Future<bool> updateStatus() async {
    loggy.debug("update auto start status");
    final isEnabled = await _readEnabled();
    state = AsyncValue.data(isEnabled);
    return isEnabled;
  }

  Future<void> enable() async {
    loggy.debug("enabling auto start");
    await _guard("enable", () => _launcher.enable());
    // 状态一律以平台实际读回为准：写入被拒时不谎报「已开启」。
    state = AsyncValue.data(await _readEnabled());
  }

  Future<void> disable() async {
    loggy.debug("disabling auto start");
    await _guard("disable", () => _launcher.disable());
    state = AsyncValue.data(await _readEnabled());
  }

  Future<bool> _readEnabled() => _guard("read status", () => _launcher.isEnabled());

  /// 平台实现会抛：Windows 下 `HKCU\...\CurrentVersion\Run` 写入被安全策略拒绝
  /// （低完整性级别进程 → `Win32Exception: Error 0x80070005`）、Linux 下 autostart
  /// 目录不可写、macOS 下 LaunchAgent 被拒。桌面规格源在读取失败的每条路径上都
  /// 返回 false（nekoray `sys/AutoRun.cpp:42-50`、Throne `src/sys/windows/AutoRun.cpp:125-140`），
  /// 故此处同样降级为「未启用」，而不是把异常抛出启动链（K-2 白屏根因：
  /// bootstrap 的 `_init` 会 rethrow → `runApp` 永不执行 → 空窗口）。
  Future<bool> _guard(String action, Future<bool> Function() body) async {
    try {
      return await body();
    } catch (e, stackTrace) {
      loggy.warning("auto start [$action] failed, degrade to disabled", e, stackTrace);
      return false;
    }
  }
}
