// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';

import 'package:loggy/loggy.dart';

class ConsolePrinter extends LoggyPrinter {
  const ConsolePrinter({this.showColors = false});

  final bool showColors;

  static final _levelColors = {
    LogLevel.debug: AnsiColor(foregroundColor: AnsiColor.grey(0.5), italic: true),
    LogLevel.info: AnsiColor(foregroundColor: 35),
    LogLevel.warning: AnsiColor(foregroundColor: 214),
    LogLevel.error: AnsiColor(foregroundColor: 196),
  };

  @override
  void onLog(LogRecord record) {
    final colorize = showColors && stdout.supportsAnsiEscapes;
    final time = record.time.toIso8601String().split('T')[1];
    final callerFrame = record.callerFrame == null ? ' ' : ' (${record.callerFrame?.location}) ';

    final String logLevel;
    if (colorize) {
      logLevel = record.level.name.toUpperCase().padRight(8);
    } else {
      logLevel = "[${record.level.name.toUpperCase()}]".padRight(10);
    }

    final color = showColors ? levelColor(record.level) ?? AnsiColor() : AnsiColor();

    print(color('$time $logLevel [${record.loggerName}]$callerFrame${record.message}'));

    if (record.stackTrace != null) {
      print(record.stackTrace);
    }
  }

  AnsiColor? levelColor(LogLevel level) {
    return _levelColors[level];
  }
}

class FileLogPrinter extends LoggyPrinter {
  FileLogPrinter(String filePath, {this.minLevel = LogLevel.debug}) : _logFile = File(filePath);

  final File _logFile;
  final LogLevel minLevel;

  IOSink? _sink;
  bool _failed = false;

  /// 惰性打开日志文件；**打不开就永久降级为不落盘**（只走控制台）。
  ///
  /// 落盘日志是纯可观测性能力，不该有任何权限去打断调用方：本方法曾让
  /// [onLog] 里的 `openWrite` 异常沿 `loggy` 调用栈逃逸。实测在进程继承低完整性
  /// 级别、`%APPDATA%` 不可写时，启动链上的日志调用直接炸出
  /// `PlatformDispatcherError: PathAccessException ... errno = 5`（`bootstrap.dart`
  /// 的 `platformDispatcher.onError` 钩子记的，logger 名 `[app]`）。
  /// 注意 `openWrite` 的开文件错误**是异步的**（先走 `_sink.done`再被当成未捕获
  /// 异步异常），所以两条路都要兜：同步 catch + `done` 上的 error handler。
  /// 同 K-2 判据：可选能力失败只降级。
  void _ensureSink() {
    if (_failed || _sink != null) return;
    try {
      final sink = _logFile.openWrite(mode: FileMode.writeOnly);
      // 写盘错误在 IOSink 上异步到达；不接住就会变成未捕获异步异常。
      unawaited(sink.done.catchError((Object _, StackTrace _) => _markFailed()));
      _sink = sink;
    } catch (_) {
      _markFailed();
    }
  }

  void _markFailed() {
    _failed = true;
    _sink = null;
  }

  @override
  void onLog(LogRecord record) {
    _ensureSink();
    final sink = _sink;
    if (sink == null) return;

    try {
      final time = record.time.toIso8601String().split('T')[1];
      sink.writeln("$time - $record");
      if (record.error != null) {
        sink.writeln(record.error);
      }
      if (record.stackTrace != null) {
        sink.writeln(record.stackTrace);
      }
    } catch (_) {
      _markFailed();
    }
  }

  void dispose() {
    final sink = _sink;
    _sink = null;
    if (sink != null) {
      try {
        sink.close();
      } catch (_) {
        // 关不掉也不必惊动调用方（同上：落盘失败只降级）。
      }
    }
  }
}
