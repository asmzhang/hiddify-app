import 'package:flutter/foundation.dart';
import 'package:loggy/loggy.dart';

class Logger {
  static final app = Loggy("app");
  static final bootstrap = Loggy("bootstrap");

  /// 记录 Flutter 框架异常。
  ///
  /// **本函数只负责「记录」，不负责「独占」**：框架错误钩子是全局单点，
  /// 可能已经被别的消费者装上（flutter_test 的测试 binding 靠
  /// `FlutterError.onError` 把异常记进 `_pendingExceptionDetails`；Sentry、
  /// 无障碍工具同理）。一旦被顶掉，它们就收不到错误——测试里的表现是
  /// `binding.dart:1017` 抛「A test overrode FlutterError.onError ...」断言，
  /// 整条测试会话随之「did not complete」。
  /// 所以转发责任交给安装方（见 bootstrap.dart 的 installErrorHooks）。
  /// 注意 `silent` 只跳过**日志**，不能跳过转发——silent 是框架用来抑制
  /// 控制台输出的，测试框架仍需要拿到它。
  static void logFlutterError(FlutterErrorDetails details) {
    if (details.silent) return;

    final description = details.exceptionAsString();

    app.error('Flutter Error: $description', details.exception, details.stack);
  }

  static bool logPlatformDispatcherError(Object error, StackTrace stackTrace) {
    app.error('PlatformDispatcherError: $error', error, stackTrace);
    return true;
  }
}
