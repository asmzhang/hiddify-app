// L1 回归 —— 「开机自启」平台调用失败必须降级为「未启用」，绝不抛。
//
// 这是 K-2 白屏的回归线：工作区目录带 Low Mandatory Level 标签 → Hiddify.exe 继承低完整性
// 级别 → 写 HKCU\...\CurrentVersion\Run 被拒（Win32Exception: Error 0x80070005）→
// launch_at_startup 抛 → bootstrap 的 `_init` rethrow → `runApp` 永不执行 → 空窗口。
//
// 为什么必须注入假实现：真机上的拒绝条件是**宿主安全策略**，普通测试机上
// `launchAtStartup.isEnabled()` 正常返回 false、不抛（已用探针验证过），
// 所以环境复现不出红色 —— 只有把平台实现换成「调用即抛」才能覆盖这条路径。
//
// ⚠ 读 provider 的顺序有讲究：auto-start 的 build 里 `ref.watch(appInfoProvider)`，
// 若在 appInfo 产出首值之前直接 `await container.read(autoStartNotifierProvider.future)`，
// riverpod 2.6.1 下会永久挂起（探针实测：先读 appInfo 或先 listen 均正常）。
// 生产顺序本来就是 appInfo 在前（bootstrap.dart:49 → :83），故测试同样先预热。
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/model/app_info_entity.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 模拟被系统策略拒绝的平台实现：每个方法都抛（对齐 Windows 注册表被拒 / Linux 目录不可写）。
class _ThrowingLauncher implements AutoStartLauncher {
  int calls = 0;

  Never _deny() {
    calls++;
    throw Exception('Win32Exception: Error 0x80070005 (模拟注册表写入被拒)');
  }

  @override
  void setup({required String appName, required String appPath, String? packageName}) => _deny();

  @override
  Future<bool> isEnabled() async => _deny();

  @override
  Future<bool> enable() async => _deny();

  @override
  Future<bool> disable() async => _deny();
}

/// 正常平台实现（读得回状态），用来确认降级逻辑没把正常路径也吃掉。
class _WorkingLauncher implements AutoStartLauncher {
  _WorkingLauncher({this.enabled = false});

  bool enabled;
  bool setupCalled = false;

  @override
  void setup({required String appName, required String appPath, String? packageName}) {
    setupCalled = true;
    expect(appName, isNotEmpty, reason: 'AppInfo 必须被透传给平台实现');
  }

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> enable() async => enabled = true;

  @override
  Future<bool> disable() async => enabled = false;
}

const _appInfo = AppInfoEntity(
  name: 'Hiddify',
  version: '4.0.0',
  buildNumber: '1',
  release: Release.general,
  operatingSystem: 'windows',
  operatingSystemVersion: '10.0',
  environment: Environment.prod,
);

/// AppInfo 是本仓库的 @Riverpod class provider，override 只能换成子类（回调签名对不上）。
class _FixedAppInfo extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => _appInfo;
}

class _FailingAppInfo extends AppInfo {
  @override
  Future<AppInfoEntity> build() async => throw StateError('no package info');
}

Future<ProviderContainer> _container({required AutoStartLauncher launcher, bool appInfoThrows = false}) async {
  final container = ProviderContainer(
    overrides: [
      autoStartLauncherProvider.overrideWithValue(launcher),
      appInfoProvider.overrideWith(() => appInfoThrows ? _FailingAppInfo() : _FixedAppInfo()),
    ],
  );
  addTearDown(container.dispose);
  // 复刻启动顺序（bootstrap.dart:49 appInfo → :83 auto start）；顺序原因见文件头注释。
  await container
      .read(appInfoProvider.future)
      .then<void>((_) {}, onError: (Object _) {}); // 失败场景下把错误收掉，避免未处理异常
  return container;
}

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.windows);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('平台调用抛异常 → build 解析为 false（AsyncData），不是 AsyncError', () async {
    final launcher = _ThrowingLauncher();
    final container = await _container(launcher: launcher);

    final value = await container.read(autoStartNotifierProvider.future);

    expect(value, isFalse, reason: '读取失败降级为「未启用」（nekoray sys/AutoRun.cpp:42-50 同口径）');
    expect(container.read(autoStartNotifierProvider), isA<AsyncData<bool>>());
    expect(container.read(autoStartNotifierProvider).hasError, isFalse, reason: 'K-2：异常绝不允许逃出 provider');
    expect(launcher.calls, greaterThan(0), reason: '确实走到了平台实现（不是被提前短路跳过）');
  });

  test('enable/disable 写入被拒 → 状态回到平台读回值 false，不抛、不谎报已开启', () async {
    final launcher = _ThrowingLauncher();
    final container = await _container(launcher: launcher);
    await container.read(autoStartNotifierProvider.future);

    await expectLater(container.read(autoStartNotifierProvider.notifier).enable(), completes);
    expect(container.read(autoStartNotifierProvider).valueOrNull, isFalse, reason: '写入被拒不得显示为已开启');

    await expectLater(container.read(autoStartNotifierProvider.notifier).disable(), completes);
    expect(container.read(autoStartNotifierProvider).valueOrNull, isFalse);

    await expectLater(container.read(autoStartNotifierProvider.notifier).updateStatus(), completes);
    expect(container.read(autoStartNotifierProvider).valueOrNull, isFalse);
  });

  test('appInfo 不可用 → 不碰平台、直接降级 false（requireValue 在此会抛 StateError）', () async {
    final launcher = _WorkingLauncher(enabled: true);
    final container = await _container(launcher: launcher, appInfoThrows: true);

    final value = await container.read(autoStartNotifierProvider.future);

    expect(value, isFalse);
    expect(container.read(autoStartNotifierProvider).hasError, isFalse, reason: '启动链上不得继承 appInfo 的错误');
    expect(launcher.setupCalled, isFalse, reason: '拿不到应用名/路径时不得写平台状态（可能写错注册表项）');
  });

  test('正常路径不受降级影响：读回 true 并透传 appName', () async {
    final launcher = _WorkingLauncher(enabled: true);
    final container = await _container(launcher: launcher);

    expect(await container.read(autoStartNotifierProvider.future), isTrue);
    expect(launcher.setupCalled, isTrue);

    await container.read(autoStartNotifierProvider.notifier).disable();
    expect(container.read(autoStartNotifierProvider).valueOrNull, isFalse, reason: '关闭后读回 false');
  });

  test('非桌面平台恒为 false 且不初始化平台实现', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final launcher = _WorkingLauncher(enabled: true);
    final container = await _container(launcher: launcher);

    expect(await container.read(autoStartNotifierProvider.future), isFalse);
    expect(launcher.setupCalled, isFalse);
  });
}
