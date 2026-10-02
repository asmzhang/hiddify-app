// L1 结构对等测试 —— 日志页 LogsPage 1:1 对照 NekoBox 日志页（内核日志流 + 等级/关键词过滤 +
// 暂停恢复 + 清空 + 分享日志菜单）。断言基准 zh-CN。规格：.workbuddy/spec-logs-page-tests.md
// - 注入面：logRepositoryProvider 必须 fake（真实 build 碰 hiddifyCoreServiceProvider）；
//   logPathResolverProvider 必须 override（真实 build 碰 appDirectoriesProvider.requireValue）；
//   environmentProvider 必须 overrideWithValue(Environment.prod)（DebugModeNotifier._pref 里
//   ref.read(environmentProvider)，app_info_provider.dart:13 是抛异常的桩，不 override 即炸）；
//   debugModeNotifierProvider 不 override（只吃 mock prefs；分享菜单门控 debug || isDesktop，
//   钉 windows 后 desktop 短路为真）。coreRestartSignalProvider 无依赖用真的。
// - repo 预热（notifier build 里 requireValue）+ 提前 read notifier（建立流监听，防首帧丢数据）。
// - 节流坑：watchLogs → rxdart throttle + throttleTime(250ms, trailing) → asyncMap fold → state；
//   测试区 FakeAsync 内 Timer 不走真实时间 → 每次 emit 后 pump(300ms) 推进假时钟触发节流。
// - 禁 pumpAndSettle 于加载态：SliverLoadingBodyPlaceholder 含 CircularProgressIndicator
//   （永不落定，utils/placeholders.dart:28）→ _pump 用 pump()；数据落地后（AsyncData/AsyncError
//   无动画）才能 pumpAndSettle。
// - 收尾坑：logs_overview_notifier.dart:19 ref.disposeDelay(20s)（lib/utils/riverpod_utils.dart:12
//   onCancel 里挂 Timer(duration, link.close)）→ 用例末尾必须先 pumpWidget(SizedBox.shrink())
//   卸树触发 provider onCancel 挂 20s Timer，再 pump(21s) 推假时钟烧掉；否则收尾 invariant 检查
//   报 "A Timer is still pending even after the widget tree was disposed"（binding.dart:1617）。
// 刻意不测：UriUtils.tryShareOrLaunchFile（平台通道）、coreRestartSignal 重启链、
// LogParser proto 解析、clearLogs 失败分支（仅 loggy.warning 状态不变）、节流 250ms 精确时序。
import 'dart:async';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/environment.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/navigation_keys.dart';
import 'package:hiddify/features/log/data/log_data_providers.dart';
import 'package:hiddify/features/log/data/log_path_resolver.dart';
import 'package:hiddify/features/log/data/log_repository.dart';
import 'package:hiddify/features/log/model/log_entity.dart';
import 'package:hiddify/features/log/model/log_failure.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/log/overview/logs_overview_notifier.dart';
import 'package:hiddify/features/log/overview/logs_page.dart';
import 'package:hiddify/utils/placeholders.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeLogRepository implements LogRepository {
  _FakeLogRepository(this._stream);

  final Stream<Either<LogFailure, List<LogEntity>>> _stream;
  int clearCalls = 0;

  @override
  TaskEither<LogFailure, Unit> init() => TaskEither.right(unit);

  @override
  Stream<Either<LogFailure, List<LogEntity>>> watchLogs() => _stream;

  @override
  TaskEither<LogFailure, Unit> clearLogs() {
    clearCalls++;
    return TaskEither.right(unit);
  }
}

/// 标准测试泵：zh-CN + mock 偏好 + fake repo/pathResolver + GoRouter。
/// 不 pumpAndSettle（加载占位含循环动画）；数据由用例经 [stream] 注入。
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  StreamController<Either<LogFailure, List<LogEntity>>>? stream,
  Map<String, Object> prefs = const {},
}) async {
  // PlatformUtils 按 defaultTargetPlatform 判平台（可测试版设计），
  // widget 测试默认 android → 钉 Windows 对齐"Windows 宿主 = desktop OS"前提。
  debugDefaultTargetPlatformOverride = TargetPlatform.windows;
  // 重置不能走 addTearDown：flutter_test 在 test body 内跑 foundation
  // invariant 检查（binding.dart:1062 → :1073-1078），addTearDown 晚于它，
  // 会炸 "The value of a foundation debug variable was changed by the test."
  // → 每个用例 body 末尾显式调 _resetPlatformOverride()。

  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final t = (await tester.runAsync(() => AppLocale.zhCn.build()))!;
  final container = ProviderContainer(
    overrides: [
      translationsProvider.overrideWith((ref) => Future.value(t)),
      sharedPreferencesProvider.overrideWith((ref) => Future.value(sp)),
      environmentProvider.overrideWithValue(Environment.prod),
      logRepositoryProvider.overrideWith((ref) => _FakeLogRepository(stream?.stream ?? const Stream.empty())),
      logPathResolverProvider.overrideWithValue(LogPathResolver(Directory.systemTemp)),
    ],
  );
  addTearDown(container.dispose);
  await container.read(translationsProvider.future);
  await container.read(sharedPreferencesProvider.future);
  // 复刻启动时序：预热 repo（notifier build 里 logRepositoryProvider.requireValue）。
  await container.read(logRepositoryProvider.future);
  // 提前实例化 notifier（build 内建立对流监听），否则 pump 前发出的数据丢失。
  container.read(logsOverviewNotifierProvider.notifier);

  final router = GoRouter(
    initialLocation: '/',
    navigatorKey: rootNavKey,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const LogsPage()),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pump();
  return container;
}

/// 向 fake repo 流注入一批日志并推进假时钟（节流 250ms trailing → fold 落 state）。
Future<void> _emit(
  WidgetTester tester,
  StreamController<Either<LogFailure, List<LogEntity>>> controller,
  List<LogEntity> logs,
) async {
  controller.add(right(logs));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
}

/// 收尾：显式卸树 → ConsumerStatefulElement.unmount → provider onCancel →
/// disposeDelay 挂 20s Timer → 推 21s 假时钟烧掉。不卸树 Timer 不会被创建；
/// 不烧 Timer 则收尾 invariant（binding.dart:1617）报 pending timers。
Future<void> _disposeAndBurn(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 21));
}

void _resetPlatformOverride() => debugDefaultTargetPlatformOverride = null;

LogEntity _log(LogLevel level, String message, [DateTime? time]) =>
    LogEntity(level: level, time: time ?? DateTime(2026, 10, 1, 12, 30, 45), message: message);

void main() {
  group('LogsPage L1（zh-CN，desktop 宿主）', () {
    testWidgets('a 初始渲染：加载占位 → 数据行/标题/筛选/全部/暂停/清空/分享菜单', (tester) async {
      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      await _pump(tester, stream: controller);

      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: '初始 AsyncLoading 占位');

      await _emit(tester, controller, [
        _log(LogLevel.info, 'kernel info msg one'),
        _log(LogLevel.warn, 'kernel warn msg two', DateTime(2026, 10, 1, 12, 30, 46)),
      ]);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('日志'), findsOneWidget, reason: 'AppBar 标题 t.pages.logs.title');
      expect(find.text('筛选'), findsOneWidget, reason: 'filter 输入框 hint t.common.filter');
      expect(find.text('全部'), findsOneWidget, reason: '等级下拉默认值 t.common.all');
      expect(find.text('INFO'), findsOneWidget, reason: 'level.name.toUpperCase + level.color');
      expect(find.text('msg one'), findsOneWidget, reason: 'extractMessage 去掉内核前缀');
      expect(find.text('kernel info msg one'), findsNothing, reason: '原始消息不直接上屏');
      expect(find.text('2026-10-01 12:30:46.000'), findsOneWidget, reason: 'time.toString 右侧');
      expect(find.byIcon(FluentIcons.pause_20_regular), findsOneWidget);
      expect(find.byIcon(FluentIcons.play_20_regular), findsNothing);
      expect(find.byIcon(FluentIcons.delete_lines_20_regular), findsOneWidget);
      expect(find.byType(PopupMenuButton), findsOneWidget, reason: 'desktop OS → 分享菜单可见');
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });

    testWidgets('b extractMessage：多词去前缀/两词取尾/单词原样', (tester) async {
      expect(extractMessage('kernel info msg one'), 'msg one');
      expect(extractMessage('ab cd'), 'cd');
      expect(extractMessage('single'), 'single');
      _resetPlatformOverride();
    });

    testWidgets('c 关键词筛选：命中保留/剔除/清空恢复（防抖 200ms）', (tester) async {
      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      await _pump(tester, stream: controller);
      await _emit(tester, controller, [
        _log(LogLevel.info, 'x alpha-line'),
        _log(LogLevel.info, 'x beta-line'),
        _log(LogLevel.warn, 'x gamma-line'),
      ]);
      expect(find.text('alpha-line'), findsOneWidget);
      expect(find.text('beta-line'), findsOneWidget);
      expect(find.text('gamma-line'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'gamma');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('gamma-line'), findsOneWidget);
      expect(find.text('alpha-line'), findsNothing, reason: '不含筛选词的行被剔除');
      expect(find.text('beta-line'), findsNothing);

      await tester.enterText(find.byType(TextFormField), '');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('alpha-line'), findsOneWidget, reason: '清空筛选 → 全部恢复');
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });

    testWidgets('d 等级筛选：warn 保留 warn 及以上；回"全部"恢复', (tester) async {
      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      await _pump(tester, stream: controller);
      await _emit(tester, controller, [
        _log(LogLevel.trace, 'x t-row'),
        _log(LogLevel.debug, 'x d-row'),
        _log(LogLevel.info, 'x i-row'),
        _log(LogLevel.warn, 'x w-row'),
      ]);

      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('trace'), findsOneWidget, reason: '下拉选项 = LogLevel.choices（trace/debug/info/warn）');
      await tester.tap(find.text('warn'));
      await tester.pumpAndSettle();

      expect(find.text('w-row'), findsOneWidget, reason: 'e.level.index >= warn.index');
      expect(find.text('i-row'), findsNothing);
      expect(find.text('d-row'), findsNothing);
      expect(find.text('t-row'), findsNothing);

      await tester.tap(find.text('warn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部'));
      await tester.pumpAndSettle();
      expect(find.text('t-row'), findsOneWidget, reason: '回"全部"恢复');
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });

    testWidgets('e 暂停/恢复：暂停后新日志不上屏，恢复后补上；图标随 paused 切换', (tester) async {
      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      await _pump(tester, stream: controller);
      await _emit(tester, controller, [
        _log(LogLevel.info, 'x paused-one'),
        _log(LogLevel.info, 'x paused-two'),
      ]);
      expect(find.byIcon(FluentIcons.pause_20_regular), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.pause_20_regular));
      await tester.pumpAndSettle();
      expect(find.byIcon(FluentIcons.play_20_regular), findsOneWidget, reason: 'paused=true → 播放键（恢复）');

      await _emit(tester, controller, [_log(LogLevel.info, 'x paused-three')]);
      expect(find.text('paused-three'), findsNothing, reason: '暂停期间新日志不上屏');
      expect(find.text('paused-one'), findsOneWidget, reason: '旧日志保持');

      await tester.tap(find.byIcon(FluentIcons.play_20_regular));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.text('paused-three'), findsOneWidget, reason: '恢复后缓冲日志补上');
      expect(find.byIcon(FluentIcons.pause_20_regular), findsOneWidget, reason: 'paused=false → 暂停键回归');
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });

    testWidgets('f 清空：repo.clearLogs 调用一次且列表清空', (tester) async {
      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      final container = await _pump(tester, stream: controller);
      await _emit(tester, controller, [_log(LogLevel.info, 'x doomed-row')]);
      expect(find.text('doomed-row'), findsOneWidget);

      await tester.tap(find.byIcon(FluentIcons.delete_lines_20_regular));
      await tester.pumpAndSettle();

      expect(find.text('doomed-row'), findsNothing, reason: '清空后 AsyncData([])');
      final repo = container.read(logRepositoryProvider).requireValue as _FakeLogRepository;
      expect(repo.clearCalls, 1);
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });

    testWidgets('g repo 错误流 → SliverErrorBodyPlaceholder + 意外错误', (tester) async {
      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      await _pump(tester, stream: controller);

      controller.add(left(const LogFailure.unexpected()));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();

      expect(find.byType(SliverErrorBodyPlaceholder), findsOneWidget);
      expect(find.text('意外错误'), findsOneWidget, reason: 'presentShortError(LogFailure.unexpected)');
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });

    testWidgets('h mobile 视口 400×1600：抽屉键出现；分享菜单仍显示（门控按 OS 非视口）', (tester) async {
      tester.view.physicalSize = const Size(400, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final controller = StreamController<Either<LogFailure, List<LogEntity>>>();
      addTearDown(controller.close);
      await _pump(tester, stream: controller);
      await _emit(tester, controller, [_log(LogLevel.info, 'x mobile-row')]);

      expect(find.byType(ShellDrawerButton), findsOneWidget, reason: 'Breakpoint mobile → 抽屉键');
      expect(find.byType(PopupMenuButton), findsOneWidget, reason: 'desktop OS 行仍渲染（同设置页⑦模式）');
      await _disposeAndBurn(tester);
      _resetPlatformOverride();
    });
  });
}
