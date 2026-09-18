import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fpdart/fpdart.dart';
import 'package:grpc/grpc.dart';
import 'package:hiddify/core/directories/directories_provider.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/utils/serial_async_lock.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/log/model/log_level.dart' as config_log_level;
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper_stub.dart'
    if (dart.library.io) 'package:hiddify/hiddifycore/core_interface/core_interface_wrapper.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcommon/common.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore_service.pbgrpc.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:loggy/loggy.dart' as loggyl;
import 'package:path/path.dart' as p;
import 'package:rxdart/rxdart.dart';

class HiddifyCoreService with InfraLogger {
  HiddifyCoreService(this.ref);
  final Ref ref;

  // CoreHiddifyCoreService() {}
  final core = getCoreInterface();

  CoreStatus currentState = const CoreStatus.stopped();
  final statusController = BehaviorSubject<CoreStatus>();
  final logController = BehaviorSubject<List<LogMessage>>();
  final CallOptions? grpcOptions = null; //CallOptions(timeout: const Duration(milliseconds: 10000));
  final Map<String, StreamSubscription?> subscriptions = {};
  List<OutboundGroup> latest = [];

  // ---------------------------------------------------------------------------
  // 「重建 sing-box 注册表」类 RPC 的串行化 —— 这是崩溃的直接修复。
  //
  // 崩溃证据（`%APPDATA%\Hiddify\hiddify\crash_reports\2026-09-15T05-37-20\go.log`）：
  //
  //   internal/runtime/maps.fatal                        ← Go 运行时的「并发写 map」，进程直接 abort
  //    → sing-box/protocol/hiddify/dnstt.loadResolvers()      tools.go:26   ← 无锁地写**包级 map**
  //    → dnstt.RegisterOutbound → include.OutboundRegistry()  registry.go:116
  //    → libbox.baseContextWithParent / baseContext
  //    → libbox.CheckConfigOptions
  //    ← 一个来自 `Parse`（`v2/config/parser.go:153`），
  //      一个来自 `Start`（`v2/hcore/service.go:31`，以及 `start.go:131` 的 `libbox.FromContext`）
  //
  // 两份 dump 里各有**恰好 2 个** goroutine 停在 `loadResolvers` ⇒ 就是这两个 RPC 撞的。
  //
  // 会走到这条路的 RPC（全库枚举）：`Parse` / `Start` / `StartService` / `Restart`
  // （`v2/hcore/restart.go:40` 的 Restart 也是调 StartService）。
  // 内核这段**不可重入**，而应用是唯一客户端 ⇒ 由这里串行化。
  // 见 docs/design/nekobox-parity.md §8.6.9。
  //
  // 实现是 `SerialAsyncLock`（`lib/core/utils/serial_async_lock.dart`），
  // 它的三个性质（不重叠 / 保序 / **一次失败不破坏锁**）由 `tool/check_async_lock.dart` 断言覆盖。
  final _registryLock = SerialAsyncLock();

  Future<T> _serializeRegistryAccess<T>(Future<T> Function() action) => _registryLock.run(action);

  Future<void> init() async {
    await setup()
        .mapLeft((e) {
          loggy.error(e);
          if (PlatformUtils.isIOS) return;
          statusController.add(const CoreStatus.stopped());
          ref.read(inAppNotificationControllerProvider).showErrorToast(e);
        })
        .map((_) {
          loggy.info("Hiddify-core setup done");
          ref.read(coreRestartSignalProvider.notifier).restart();
        })
        .run();
  }

  /// validates config by path and save it
  ///
  /// [path] is used to save validated config
  /// [tempPath] includes base config, possibly invalid
  /// [debug] indicates if debug mode (avoid in prod)

  TaskEither<String, Unit> validateConfigByPath(String path, String tempPath, bool debug) {
    // 走 `Parse` ⇒ 必须与 `Start` 串行（见 _serializeRegistryAccess 的崩溃证据）
    return TaskEither(() => _serializeRegistryAccess(() async {
      try {
        final response = await core.fgClient.parse(ParseRequest(tempPath: tempPath, configPath: path, debug: false));
        if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      } catch (e) {
        await setup().run();
        final response = await core.fgClient.parse(ParseRequest(tempPath: tempPath, configPath: path, debug: false));
        if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      }
      return right(unit);
    }));
  }

  TaskEither<String, String> generateFullConfigByPath(String path) {
    // 走 `Parse` ⇒ 必须与 `Start` 串行
    return TaskEither(() => _serializeRegistryAccess(() async {
      final response = await core.fgClient.parse(ParseRequest(configPath: path, debug: false));
      if (response.responseCode != ResponseCode.OK) return left("${response.responseCode} ${response.message}");
      return right(response.content);
    }));
  }

  TaskEither<String, Unit> setup() {
    return TaskEither(() async {
      try {
        final directories = ref.read(appDirectoriesProvider).requireValue;
        final debug = ref.read(debugModeNotifierProvider);
        final setupResponse = await core.setup(directories, debug, 3);

        if (setupResponse.isNotEmpty) {
          return left(setupResponse);
        }

        await startListeningLogs("fg", core.fgClient);
        // await startListeningStatus("fg", core.fgClient);
        if (!core.isSingleChannel()) {
          await startListeningLogs("bg", core.bgClient);
        }
        statusController.add(currentState);
        await startListeningStatus("bg", core.bgClient);
        // ref.read(coreRestartSignalProvider.notifier).restart();
        return right(unit);
      } catch (e) {
        return left(e.toString());
      }
    });
  }

  TaskEither<String, Unit> changeOptions(SingboxConfigOption options) {
    return TaskEither(() async {
      loggy.debug("changing options");
      // latestOptions = options;
      try {
        final res = await core.fgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson())),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
        await core.bgClient.changeHiddifySettings(
          ChangeHiddifySettingsRequest(hiddifySettingsJson: jsonEncode(options.toJson())),
        );
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unavailable) {
          loggy.debug("background core is not started yet! $e");
        } else {
          // **不要用 `rethrow`** —— 见 setSystemProxyEnabled 里的说明：
          // TaskEither 体内抛出会变成"被拒绝的 Future"而不是 Left，
          // 调用方的 isRight()/match() 全部失效。这里必须如实返回 Left。
          return left("${e.code} ${e.message}");
        }
      } catch (e) {
        return left("change options failed: $e");
      }

      return right(unit);
    });
  }

  TaskEither<ConnectionFailure, Unit> start(String path, String name, bool disableMemoryLimit) {
    // 走 `Start`/`StartService` ⇒ 必须与 `Parse` 串行（见 _serializeRegistryAccess 的崩溃证据）
    return TaskEither(() => _serializeRegistryAccess(() async {
      statusController.add(currentState = const CoreStatus.starting());
      loggy.debug("starting");
      final background = await core.setupBackground(path, name);
      if (background != const CoreStatus.started()) {
        statusController.add(currentState = const CoreStatus.stopped());
        return left(background.getCoreAlert() ?? const ConnectionFailure.unexpected("failed to start core"));
      }
      if (!core.isSingleChannel()) {
        await startListeningLogs("bg", core.bgClient);
        await startListeningStatus("bg", core.bgClient);
      }
      try {
        final res = await core.bgClient.start(
          StartRequest(
            configPath: path,
            configName: name,
            // configContent: content,
            disableMemoryLimit: disableMemoryLimit,
          ),
        );
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (res.messageType != MessageType.ALREADY_STARTED && res.messageType != MessageType.EMPTY) {
          final alert = res.message.contains("denied") ? CoreAlert.requestVPNPermission : CoreAlert.startFailed;
          currentState = CoreStatus.stopped(
            alert: alert,
            message: "failed to start core ${res.messageType} ${res.message}",
          );

          statusController.add(currentState);

          return left(
            currentState.getCoreAlert() ??
                ConnectionFailure.unexpected("failed to start core ${res.messageType} ${res.message}"),
          );
        }
      } on GrpcError catch (e) {
        loggy.error("failed to start bg core: $e");
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (e.code == StatusCode.unavailable) {
          return left(const ConnectionFailure.unexpected("background core is not started yet!"));
        }
        // throw InvalidConfig(e.message);
        // throw DioException.connectionError(requestOptions: RequestOptions(), reason: e.codeName, error: e);

        // throw DioException(requestOptions: RequestOptions(), error: e);
        return left(const ConnectionFailure.unexpected("failed to start background core"));
      }

      // if (res.messageType != MessageType.EMPTY) return left(res);

      return right(unit);
    }));
  }

  /// raw 内容启动（custom_config 模式，docs/design/custom-config-2026-09-18.md §8.3）：
  /// `enableRawConfig=true` 时内核跳过拼装，直接用 [content]（完整 sing-box JSON，
  /// 已由 Dart 侧完成 custom_config 深合并）unmarshal 后启动。
  ///
  /// [path] 仍须传真实配置文件路径（订阅/实体配置）：① `setupBackground` 在 Android
  /// 侧只是把它记进 `Settings.activeConfigPath`，但 `BoxService.startService`
  /// （BoxService.kt:147-151）对它有**非空校验**，空值直接 `EmptyConfiguration` 停机；
  /// ② 内核 `ReadSingOptions` 只读 [content]（`ReadContent` 中 Content 优先于 Path），
  /// path 不会影响启动内容。
  /// 与 [start] 同样走 `Start`/`StartService` ⇒ 必须与 `Parse` 串行。
  TaskEither<ConnectionFailure, Unit> startRawContent(String content, String path, String name, bool disableMemoryLimit) {
    return TaskEither(() => _serializeRegistryAccess(() async {
      statusController.add(currentState = const CoreStatus.starting());
      loggy.debug("starting core from raw config content");
      final background = await core.setupBackground(path, name);
      if (background != const CoreStatus.started()) {
        statusController.add(currentState = const CoreStatus.stopped());
        return left(background.getCoreAlert() ?? const ConnectionFailure.unexpected("failed to start core"));
      }
      if (!core.isSingleChannel()) {
        await startListeningLogs("bg", core.bgClient);
        await startListeningStatus("bg", core.bgClient);
      }
      try {
        final res = await core.bgClient.start(
          StartRequest(
            configContent: content,
            configName: name,
            enableRawConfig: true,
            disableMemoryLimit: disableMemoryLimit,
          ),
        );
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (res.messageType != MessageType.ALREADY_STARTED && res.messageType != MessageType.EMPTY) {
          currentState = CoreStatus.stopped(
            alert: res.message.contains("denied") ? CoreAlert.requestVPNPermission : CoreAlert.startFailed,
            message: "failed to start core ${res.messageType} ${res.message}",
          );
          statusController.add(currentState);
          return left(
            currentState.getCoreAlert() ??
                ConnectionFailure.unexpected("failed to start core ${res.messageType} ${res.message}"),
          );
        }
      } on GrpcError catch (e) {
        loggy.error("failed to start bg core from raw content: $e");
        ref.read(coreRestartSignalProvider.notifier).restart();
        if (e.code == StatusCode.unavailable) {
          return left(const ConnectionFailure.unexpected("background core is not started yet!"));
        }
        return left(const ConnectionFailure.unexpected("failed to start background core"));
      }
      return right(unit);
    }));
  }

  TaskEither<String, Unit> stop() {
    return TaskEither(() async {
      loggy.debug("stopping");
      var errMsg = "";
      try {
        await core.bgClient.stop(Empty());
      } on GrpcError catch (e) {
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2") ?? false)) {
          errMsg = e.message ?? "failed to stop core: $e";

          loggy.error("failed to stop bg core: $e");
        }
      } catch (e) {
        loggy.error("failed to stop bg core: $e");
        // left("failed to stop core: $e");
      }
      if (!await core.stop()) {}
      statusController.add(currentState = const CoreStatus.stopped());
      if (errMsg.isNotEmpty) return left(errMsg);
      return right(unit);
    });
  }

  /// 系统代理的当前状态（`available` = 这个平台支不支持设系统代理）。
  ///
  /// 「内核常驻」模式靠它判断"到底有没有接管流量"—— 因为**内核在跑 ≠ 流量被接管**：
  /// 那个模式下「连接」是系统代理开关，不是启停内核。
  TaskEither<String, SystemProxyStatus> getSystemProxyStatus() {
    return TaskEither(() async {
      try {
        return right(await core.bgClient.getSystemProxyStatus(Empty()));
      } catch (e) {
        loggy.error("failed to get system proxy status: $e");
        return left("failed to get system proxy status: $e");
      }
    });
  }

  /// 运行时开关系统代理 —— **不用重启内核**。这是「内核常驻」模式的基础。
  ///
  /// ⚠️ **本仓库的内核根本起不来命令服务器**，所以这条路现在必然失败：
  ///   · 实现走 `libbox.NewStandaloneCommandClient()`（`v2/hcore/system_proxy.go:42`），
  ///     它去连 `<workingDir>/command.sock`（`command_client.go:125-126`）；
  ///   · 那个 socket 由 `libbox.CommandServer.Start()` 创建（`command_server.go:119`），
  ///     而**唯一的那句调用在内核里被注释掉了**（`v2/hcore/service.go:48-50`，
  ///     且 `startCommandServer` 这个函数已经不存在），所以 socket 永远不出现；
  ///   · 于是客户端 probe 失败 → 连接被拒 → 直到超时。
  ///
  /// 所以超时压到 3 秒（原来是 10 秒）：既然是注定失败的尝试，不该让用户每次
  /// 点「连接」都干等 10 秒。真正生效的是调用方的兜底 —— `ConnectionNotifier.setCapture`
  /// 收到 Left 后会**重启内核**，由 sing-box 自己设系统代理
  /// （`common/listener/listener.go:109-117` → `common/settings/proxy_windows.go:28`
  /// 的 `wininet.SetSystemProxy`）。若将来内核把命令服务器恢复起来，这条路会自动重新可用。
  TaskEither<String, Unit> setSystemProxyEnabled(bool enabled) {
    return TaskEither(() async {
      loggy.debug("setting system proxy enabled: $enabled");

      // 先探测命令服务器的 socket（审计 F4）：本项目内核**从不创建**它
      // （见上面的说明），所以没必要去连、更没必要白等 3 秒超时 —— 直接返回 Left，
      // 让调用方（`ConnectionNotifier.setCapture`）**立刻**走"重启内核"兜底。
      // 只在桌面端探测：移动端是另一套（独立进程 + mTLS），不走 command.sock。
      if (PlatformUtils.isDesktop) {
        final socketPath = p.join(ref.read(appDirectoriesProvider).requireValue.workingDir.path, 'command.sock');
        if (!File(socketPath).existsSync()) {
          loggy.debug("command server unavailable (no $socketPath) - caller should fall back to core restart");
          return left("command server unavailable: $socketPath");
        }
      }

      try {
        final res = await core.bgClient.setSystemProxyEnabled(
          SetSystemProxyEnabledRequest(isEnabled: enabled),
          options: CallOptions(timeout: const Duration(seconds: 3)),
        );
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");
        return right(unit);
      } catch (e) {
        loggy.error("failed to set system proxy: $e");
        // **绝不能 `rethrow`**：TaskEither 体内抛出会变成"被拒绝的 Future"而不是 Left，
        // 于是 `ConnectionNotifier.setCapture` 里的 `applied.isRight()` 根本执行不到、
        // 「失败则重启内核兜底」永不触发，异常还会逃到平台层变成 PlatformDispatcherError。
        // 实测就是这条让系统代理永远开不起来 ⇒ 没有流量（2026-09-15 13:49:07 的日志）。
        return left("failed to set system proxy: $e");
      }
    });
  }

  TaskEither<String, Unit> restart(String path, String name, bool disableMemoryLimit) {
    // 走 `Restart` ⇒ 内部就是 Stop + StartService ⇒ 同样必须与 `Parse` 串行
    return TaskEither(() => _serializeRegistryAccess(() async {
      loggy.debug("restarting");
      // if (!await core.restart(path, name)) {
      try {
        final res = await core.bgClient.restart(
          StartRequest(configPath: path, configName: name, disableMemoryLimit: disableMemoryLimit, delayStart: true),
        );
        if (res.messageType != MessageType.EMPTY) return left("${res.messageType} ${res.message}");
      } on GrpcError catch (e) {
        loggy.error("failed to restart bg core: $e");
        if (e.code == StatusCode.unknown && !(e.message?.contains("HTTP/2 error") ?? false)) {
          return left("${e.message}");
        }
      }

      return right(unit);
    }));
  }

  TaskEither<String, Unit> resetTunnel() {
    return TaskEither(() async {
      // only available on iOS (and macOS later)
      if (!PlatformUtils.isIOS) {
        throw UnimplementedError("reset tunnel function unavailable on platform");
      }

      // loggy.debug("resetting tunnel");
      final res = await core.resetTunnel();
      if (res) {
        return right(unit);
      }
      return left("failed to reset tunnel");
    });
  }

  /// **全部分组**（每组带全部成员 + 实时数据）—— 代理页的运行期**唯一真源**。
  ///
  /// 与 `watchGroup` 走同一个 `OutboundsInfo` RPC，区别只在这里**不丢组**：
  /// 内核 `GetAllProxiesInfo` 本来就返回全量（`v2/hcore/proxy_info.go:128-161`，
  /// 每个 group 逐个 append；`:144-156` 装 `group.All()` 并逐项标 `IsSelected`），
  /// 应用侧曾经只取 `.first`，于是不得不另写一套「解析 generateConfig 的 JSON」来
  /// 重建分组，造成两份模型 + 一层 `_mergeLive` 缝合 —— 列表随连接变化、
  /// `selectProxy` 下发错组都长在那条缝上。恢复全量即可让内核做唯一来源。
  Stream<List<OutboundGroup>> watchGroups() async* {
    loggy.debug("watching groups");
    // interrupt managed by core

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }
    try {
      yield* core.bgClient.outboundsInfo(Empty()).map((event) => event.items.toList());
    } catch (e) {
      loggy.error("error watching groups: $e");
      rethrow;
    }
  }

  Stream<List<OutboundGroup>> watchActiveGroups() async* {
    loggy.info("watching active groups");

    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty group stream");
      return;
    }

    try {
      yield* core.bgClient
          .mainOutboundsInfo(Empty())
          .map((event) {
            return latest = event.items.toList();
          })
          .startWith(latest);
    } catch (e) {
      loggy.error("error watching active groups: $e");
      rethrow;
    }
  }

  //
  // Stream<SingboxStatus> watchStatus() => _status;

  ResponseStream<SystemInfo> watchStats() {
    loggy.debug("watching stats");
    try {
      return core.bgClient.getSystemInfoStream(Empty());
    } catch (e) {
      loggy.error("error watching stats: $e");
      rethrow;
    }
  }

  TaskEither<String, Unit> selectOutbound(String groupTag, String outboundTag) {
    return TaskEither(() async {
      loggy.debug("selecting outbound");
      try {
        final res = await core.bgClient.selectOutbound(
          SelectOutboundRequest(groupTag: groupTag, outboundTag: outboundTag),
          options: CallOptions(timeout: const Duration(seconds: 1)),
        );
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error selecting outbound: $e");
        // 同 setSystemProxyEnabled：TaskEither 体内不能抛，必须返回 Left
        return left("error selecting outbound: $e");
      }
    });
  }

  TaskEither<String, Unit> urlTest(String tag) {
    return TaskEither(() async {
      loggy.debug("url test");
      try {
        final res = await core.bgClient.urlTest(UrlTestRequest(tag: tag));
        if (res.code != ResponseCode.OK) return left("${res.code} ${res.message}");

        return right(unit);
      } catch (e) {
        loggy.error("error in url test: $e");
        // 同 setSystemProxyEnabled：TaskEither 体内不能抛，必须返回 Left
        return left("error in url test: $e");
      }
    });
  }

  List<LogMessage> logBuffer = [];

  // SingboxConfigOption? latestOptions;

  Stream<List<LogMessage>> watchLogs(String path) async* {
    if (!core.isInitialized()) {
      loggy.debug("core is not initialized, returning empty log stream");
      return;
    }
    await startListeningLogs("bg", core.bgClient);
    await startListeningLogs("fg", core.fgClient);
    try {
      yield* logController.stream;
    } catch (e) {
      loggy.error("error watching logs: $e");
      rethrow;
    }
  }

  TaskEither<String, Unit> clearLogs() {
    return TaskEither(() async {
      loggy.debug("clearing logs");
      logBuffer.clear();
      return right(unit);
    });
  }

  Stream<CoreStatus> watchStatus() async* {
    await startListeningStatus("bg", core.bgClient);
    yield* statusController.stream;
    // .endWith(const CoreStatus.stopped());
  }

  Future<void> startListeningStatus(String key, CoreClient cc) async {
    await listenSingle<CoreStatus>(
      "${key}StatusListener",
      () => cc
          .coreInfoListener(Empty(), options: grpcOptions)
          .doOnCancel(() {
            loggy.error("status", "Canceld");
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .doOnData((event) {
            loggy.debug("status", event);
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .doOnDone(() {
            loggy.error("status", "done");
            if (currentState == const CoreStatus.started()) currentState = const CoreStatus.stopped();
          })
          .endWith(CoreInfoResponse(coreState: CoreStates.STOPPED))
          .map((event) {
            currentState = CoreStatus.fromCoreInfo(event);
            statusController.add(currentState);
            return currentState;
          }),
      // .endWith(const CoreStatus.stopped())
      onError: (error) {
        loggy.error("Stream error in ${key}StatusListener: $error");

        // currentState = const CoreStatus.stopped();
        // statusController.add(currentState);

        // startListeningStatus(key, cc);
      },
    );
  }

  Future<void> startListeningLogs(String key, CoreClient cc) async {
    final logLevel = ref.read(ConfigOptions.logLevel);
    final coreLogLevel = getCoreLogLevel(logLevel);
    final listenKey = "${key}LogListener";
    // await stopListenSingle(listenKey);
    await listenSingle<LogMessage>(listenKey, () {
      return cc.logListener(LogRequest(level: coreLogLevel), options: grpcOptions).map((event) {
        // Handle incoming event
        logBuffer.add(event);
        if (logBuffer.length > 300) {
          logBuffer.removeAt(0);
        }
        logController.add(logBuffer);
        // loggy.log(getLogLevel(event.level), event.message);
        event.message.split('\n').forEach((line) {
          loggy.log(getLogLevel(event.level), line);
        });
        return event;
      });
    });
  }

  Future<void> stopListenSingle(String key) async {
    // Collect keys to remove first
    final keysToRemove = subscriptions.entries
        .where((entry) => entry.key.startsWith(key))
        .map((entry) => entry.key)
        .toList();

    // Cancel and remove
    for (final k in keysToRemove) {
      final sub = subscriptions[k];
      await sub?.cancel(); // cancel the subscription

      subscriptions.remove(k);
    }
  }

  Future<StreamSubscription<T>?> listenSingle<T>(
    String key,
    Stream<T> Function() stream, {
    Function(dynamic error)? onError,
  }) async {
    if (subscriptions.containsKey(key)) {
      // return subscriptions[key] as StreamSubscription<T>?;
      await stopListenSingle(key);
    }
    subscriptions[key] = null;
    subscriptions[key] = stream().listen(
      (event) {
        // loggy.debug(event);
      },
      cancelOnError: true,
      onError: (error) {
        loggy.log(loggyl.LogLevel.error, 'Stream error: $error');
        onError?.call(error);
        subscriptions[key]?.cancel();
        subscriptions.remove(key);
      },
    );
    return subscriptions[key] as StreamSubscription<T>?;
  }

  loggyl.LogLevel getLogLevel(LogLevel level) {
    return switch (level) {
      LogLevel.DEBUG => loggyl.LogLevel.debug,
      LogLevel.INFO => loggyl.LogLevel.info,
      LogLevel.WARNING => loggyl.LogLevel.warning,
      LogLevel.ERROR => loggyl.LogLevel.error,
      LogLevel.FATAL => loggyl.LogLevel.error,
      _ => loggyl.LogLevel.info, // Default case
    };
  }

  LogLevel getCoreLogLevel(config_log_level.LogLevel level) {
    return switch (level) {
      config_log_level.LogLevel.trace => LogLevel.TRACE,
      config_log_level.LogLevel.debug => LogLevel.DEBUG,
      config_log_level.LogLevel.info => LogLevel.INFO,
      config_log_level.LogLevel.warn => LogLevel.WARNING,
      config_log_level.LogLevel.error => LogLevel.ERROR,
      config_log_level.LogLevel.fatal => LogLevel.FATAL,
      config_log_level.LogLevel.panic => LogLevel.FATAL,
    };
  }

  Future<void> closeFront() async {
    if (!core.isInitialized()) {
      return;
    }
    if (!core.isSingleChannel()) {
      await stopListenSingle("fg");
      await stopListenSingle("bg");
      // try both channel modes; failures mean "already closed" and are safe to swallow
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL_INSECURE));
      } catch (_) {}
      try {
        await core.fgClient.close(CloseRequest(mode: SetupMode.GRPC_NORMAL));
      } catch (_) {}
    }
  }

  TaskEither<String, LANIPResponse> getLANIP() {
    return TaskEither(() async {
      try {
        final response = await core.fgClient.getLANIP(Empty());
        return right(response);
      } catch (e) {
        loggy.error("failed to get LAN IP: $e");
        return left(e.toString());
      }
    });
  }
}
