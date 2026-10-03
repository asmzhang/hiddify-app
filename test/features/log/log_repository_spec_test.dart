// K-3 回归：日志仓库的初始化必须**降级**而不是硬失败。
//
// 缺陷现场（Windows 真机，2026-10-07）：进程继承低完整性级别（workspace 目录带
// `Mandatory Label\Low Mandatory Level:(OI)(CI)(NW)`）时 `%APPDATA%\Hiddify\hiddify\`
// 不可写，`LogRepositoryImpl.init` 抛
// `LogFailure.unexpected(error: PathAccessException: Cannot open file, path =
// '...\hiddify\data\box.log' (OS Error: 拒绝访问。, errno = 5))`；而启动链
// （`lib/bootstrap.dart:85`）当时走硬失败的 `_init`（`:187` rethrow）⇒ `runApp`
// 永不执行 ⇒ **整窗白屏**（用户可见症状与 ⑨-d 的 K-2 完全同形，但这是另一条独立的
// 触发路径 —— K-2 修完后白屏仍在，正是它）。
// 判据同 K-2（见 `docs/design/parity-sequence-log.md` ⑨-d）：日志属可观测性能力，
// 不拥有「停掉整个应用」的权限；写不进去就退化成「本次没有日志」。
//
// 不可写目录的构造技巧：先建一个**普通文件**，再把该文件路径当目录用 ——
// `Directory.exists()` 为 false、`create()` 必抛，确定且跨平台，不依赖权限模型。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/log/data/log_path_resolver.dart';
import 'package:hiddify/features/log/data/log_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path/path.dart' as p;

/// [LogRepositoryImpl] 只要一个 [HiddifyCoreService] 实例；`init()` 根本不碰内核
/// （只有 `watchLogs`/`clearLogs` 才用），所以这里拿一个最小 provider 造实例即可。
final _serviceProvider = Provider<HiddifyCoreService>((ref) => HiddifyCoreService(ref));

void main() {
  late Directory tmp;
  late HiddifyCoreService singbox;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hiddify_log_repo');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    singbox = container.read(_serviceProvider);
  });

  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  test('数据目录不可写时 init 仍然成功（降级为不预清空），不抛异常', () async {
    // 用一个「被普通文件占住」的路径当日志目录：exists()=false，create() 必抛。
    final blocker = File(p.join(tmp.path, 'blocker'));
    await blocker.writeAsString('not a directory');
    final resolver = LogPathResolver(Directory(p.join(blocker.path, 'logs')));

    final repo = LogRepositoryImpl(singbox: singbox, logPathResolver: resolver);

    // 修复前：init() 返回 left(LogFailure.unexpected(PathAccessException))，
    // 启动链上的 _init 随即 rethrow ⇒ 白屏。
    final result = await repo.init().run();

    result.match(
      (failure) => fail('日志文件写不进去只能降级，绝不能把失败沿启动链抛出去：$failure'),
      (_) {},
    );
  });
  test('数据目录可写时 init 仍按原语义预清空 box.log 与 app.log', () async {
    final workingDir = Directory(p.join(tmp.path, 'work'));
    await workingDir.create(recursive: true);
    final resolver = LogPathResolver(workingDir);
    // 用 resolver 自己的取值建立期望，顺带钉住真实落盘位置：
    // 内核日志在 <workingDir>/data/box.log（log_path_resolver.dart:12-18），
    // 应用日志在 <workingDir>/app.log（:20-22）。
    await resolver.coreFile().create(recursive: true);
    await resolver.appFile().create(recursive: true);
    await resolver.coreFile().writeAsString('stale core log');
    await resolver.appFile().writeAsString('stale app log');

    final repo = LogRepositoryImpl(singbox: singbox, logPathResolver: resolver);
    final result = await repo.init().run();

    expect(result.isRight(), isTrue);
    expect(await resolver.coreFile().readAsString(), isEmpty);
    expect(await resolver.appFile().readAsString(), isEmpty);
  });

  test('数据目录可写但文件不存在时 init 会创建它们', () async {
    final workingDir = Directory(p.join(tmp.path, 'work'));
    await workingDir.create(recursive: true);
    final resolver = LogPathResolver(workingDir);
    expect(resolver.coreFile().existsSync(), isFalse);
    expect(resolver.appFile().existsSync(), isFalse);

    final repo = LogRepositoryImpl(singbox: singbox, logPathResolver: resolver);
    final result = await repo.init().run();

    expect(result.isRight(), isTrue);
    expect(resolver.coreFile().existsSync(), isTrue);
    expect(resolver.appFile().existsSync(), isTrue);
  });
}
