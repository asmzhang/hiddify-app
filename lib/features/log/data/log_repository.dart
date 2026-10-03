import 'package:flutter/foundation.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/features/log/data/log_parser.dart';
import 'package:hiddify/features/log/data/log_path_resolver.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/model/log_failure.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/utils/custom_loggers.dart';

abstract interface class LogRepository {
  TaskEither<LogFailure, Unit> init();
  Stream<Either<LogFailure, List<LogEntity>>> watchLogs();
  TaskEither<LogFailure, Unit> clearLogs();
}

class LogRepositoryImpl with ExceptionHandler, InfraLogger implements LogRepository {
  LogRepositoryImpl({required this.singbox, required this.logPathResolver});

  final HiddifyCoreService singbox;
  final LogPathResolver logPathResolver;

  @override
  TaskEither<LogFailure, Unit> init() {
    return exceptionHandler(() async {
      if (!kIsWeb) await _prepareLogFiles();
      return right(unit);
    }, LogUnexpectedFailure.new);
  }

  /// 预清空日志文件（`data/box.log` / `app.log`）——**可选**前置步骤。
  ///
  /// 数据目录不可写时必须降级为「本次不预清空」，而不是让 [init] 失败：启动链
  /// （`lib/bootstrap.dart:85`）拿 [init] 的结果决定是否继续，而那里一度是硬失败
  /// 的 `_init`（`:187` rethrow）⇒ 日志文件创建被拒 = `runApp` 永不执行 = 整窗
  /// 白屏。实测触发条件：Windows 上进程继承低完整性级别（workspace 目录带
  /// `Mandatory Label\Low Mandatory Level`）时对 `%APPDATA%\Hiddify\hiddify\`
  /// 的写入被拒（`PathAccessException ... errno = 5`）。
  ///
  /// 日志纯属可观测性，不该拥有「停掉整个应用」的权限——与 K-2 的
  /// 开机自启归一同一判据（见 `docs/design/parity-sequence-log.md` ⑨-d）。
  Future<void> _prepareLogFiles() async {
    try {
      if (!await logPathResolver.directory.exists()) {
        await logPathResolver.directory.create(recursive: true);
      }
      if (await logPathResolver.coreFile().exists()) {
        await logPathResolver.coreFile().writeAsString("");
      } else {
        await logPathResolver.coreFile().create(recursive: true);
      }
      if (await logPathResolver.appFile().exists()) {
        await logPathResolver.appFile().writeAsString("");
      } else {
        await logPathResolver.appFile().create(recursive: true);
      }
    } catch (e, stackTrace) {
      loggy.warning("log files are not writable, skipping pre-clear", e, stackTrace);
    }
  }

  @override
  Stream<Either<LogFailure, List<LogEntity>>> watchLogs() {
    return singbox
        .watchLogs(logPathResolver.coreFile().path)
        .map((event) => event.map(LogParser.parseLogProto).toList())
        .handleExceptions((error, stackTrace) {
          loggy.warning("error watching logs", error, stackTrace);
          return LogFailure.unexpected(error, stackTrace);
        });
  }

  @override
  TaskEither<LogFailure, Unit> clearLogs() {
    return exceptionHandler(() => singbox.clearLogs().mapLeft(LogFailure.unexpected).run(), LogFailure.unexpected);
  }
}
