// K-3 回归（第二层）：落盘日志打不开时必须降级，不能让异常沿 loggy 调用栈逃逸。
//
// 缺陷现场（Windows 真机，2026-10-07，低完整性级别 / `%APPDATA%` 不可写）：
// `FileLogPrinter._sink` 是 `late final` 的 `_logFile.openWrite(...)`，首次
// [onLog] 才求值 —— 于是**任何一条日志调用**都可能把 `PathAccessException`
// 炸到调用方。实测启动链上 `[window controller]` 阶段就炸出一条
// `PlatformDispatcherError: PathAccessException: Cannot open file, path =
// '...\app.log' (OS Error: 拒绝访问。, errno = 5)`（由 `bootstrap.dart` 的
// `platformDispatcher.onError` 钩子记下，logger 名 `[app]`）。
// 日志是纯可观测性：打不开就永久退化成「只走控制台」。
//
// 注意 `IOSink` 的失败**是异步到达的**（走 `sink.done`），所以本测试既验证
// `onLog` 不抛，也验证异步错误被接住 —— 若没接住，它会变成未捕获异步异常，
// 由 flutter_test 的 zone 报成本用例失败。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/core/logger/custom_logger.dart';
import 'package:loggy/loggy.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hiddify_file_log_printer');
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('日志文件路径不可用时 onLog 不抛，只降级为不落盘', () async {
    // 同样用「被普通文件占住」的路径，保证 openWrite 必失败且跨平台确定。
    final blocker = File(p.join(tmp.path, 'blocker'));
    await blocker.writeAsString('not a directory');
    final printer = FileLogPrinter(p.join(blocker.path, 'app.log'));

    for (var i = 0; i < 3; i++) {
      expect(
        () => printer.onLog(LogRecord(LogLevel.info, 'probe $i', 'test')),
        returnsNormally,
        reason: '落盘失败不得打断调用方（日志调用点遍布启动链）',
      );
    }

    // 给异步失败一个送达的机会；未接住的话这里会以未捕获异步异常失败。
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(() => printer.dispose(), returnsNormally);
  });

  test('日志文件可写时正常落盘（降级改动没有弄丢原有能力）', () async {
    final path = p.join(tmp.path, 'app.log');
    final printer = FileLogPrinter(path);

    printer.onLog(LogRecord(LogLevel.warning, 'hello from test', 'test'));
    printer.dispose();

    final content = await File(path).readAsString();
    expect(content, contains('hello from test'));
  });
}
