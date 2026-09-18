import 'package:flutter/foundation.dart';

/// 平台探测（可测试版）。
///
/// 基于 Flutter 的 [defaultTargetPlatform] 而非 `dart:io` 的 [Platform]：
/// - 语义一致：运行时取宿主平台；`kIsWeb` 优先；
/// - 可测试：widget 测试中通过 `debugDefaultTargetPlatformOverride` 可把
///   "平台" 切到任意分支（Android/iOS/Windows/...），dart:io 做不到——
///   它反映的是跑测试的宿主机 OS，在 Windows 上 isAndroid 恒 false，
///   平台分支代码（如 showPlatformWarning）就永远测不到。
///
/// 注意 [isInAppStore] 保留 iOS 判定语义（原实现如此）。
abstract class PlatformUtils {
  static bool get isWindows => !kIsWeb && _target == TargetPlatform.windows;

  static bool get isDesktop =>
      !kIsWeb && (_target == TargetPlatform.windows || _target == TargetPlatform.linux || _target == TargetPlatform.macOS);

  static bool get isInAppStore => !kIsWeb && _target == TargetPlatform.iOS;

  static bool get isMobile => !kIsWeb && (_target == TargetPlatform.android || _target == TargetPlatform.iOS);

  static bool get isWeb => kIsWeb;

  static bool get isLinux => !kIsWeb && _target == TargetPlatform.linux;

  static bool get isMacOS => !kIsWeb && _target == TargetPlatform.macOS;

  static bool get isIOS => !kIsWeb && _target == TargetPlatform.iOS;

  static bool get isAndroid => !kIsWeb && _target == TargetPlatform.android;

  static TargetPlatform get _target => defaultTargetPlatform;
}
