import 'dart:convert';

import 'package:dartx/dartx.dart';
import 'package:fpdart/fpdart.dart';
import 'package:hiddify/core/model/directories.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/utils/exception_handler.dart';
import 'package:hiddify/core/utils/json_merge.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/profile/data/profile_path_resolver.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service.dart';
import 'package:hiddify/singbox/model/core_status.dart';
import 'package:hiddify/singbox/model/singbox_config_option.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:meta/meta.dart';

abstract interface class ConnectionRepository {
  SingboxConfigOption? get configOptionsSnapshot;

  TaskEither<ConnectionFailure, Unit> setup();
  Stream<ConnectionStatus> watchConnectionStatus();
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit);
  TaskEither<ConnectionFailure, Unit> disconnect();
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit);
}

class ConnectionRepositoryImpl with ExceptionHandler, InfraLogger implements ConnectionRepository {
  ConnectionRepositoryImpl({
    required this.ref,
    required this.directories,
    required this.singbox,
    required this.configOptionRepository,
    required this.profilePathResolver,
  });

  final Ref ref;

  final Directories directories;
  final HiddifyCoreService singbox;

  final ConfigOptionRepository configOptionRepository;
  final ProfilePathResolver profilePathResolver;

  SingboxConfigOption? _configOptionsSnapshot;
  @override
  SingboxConfigOption? get configOptionsSnapshot => _configOptionsSnapshot;

  bool _initialized = false;

  @override
  TaskEither<ConnectionFailure, Unit> setup() {
    if (_initialized) return TaskEither.of(unit);
    return exceptionHandler(() {
      loggy.debug("setting up singbox");

      return singbox
          .setup()
          .map((r) {
            _initialized = true;
            return r;
          })
          .mapLeft(UnexpectedConnectionFailure.new)
          .run();
    }, UnexpectedConnectionFailure.new);
  }

  @override
  Stream<ConnectionStatus> watchConnectionStatus() {
    return singbox.watchStatus().map(
      (event) => switch (event) {
        CoreStopped() => Disconnected(event.getCoreAlert()),
        CoreStarting() => const Connecting(),
        CoreStarted() => const Connected(),
        CoreStopping() => const Disconnecting(),
      },
    );
  }

  @override
  TaskEither<ConnectionFailure, Unit> connect(ProfileEntity activeProfile, bool disableMemoryLimit) => setup().flatMap(
    (_) => applyConfigOption(activeProfile).flatMap((_) => _start(activeProfile, disableMemoryLimit)),
  );

  /// 启动内核：**优先用实体层组装出的出站表**，任何一步失败都回落到订阅基准文件。
  ///
  /// 为什么要这样（`docs/design/nekobox-parity.md` §8.6 第 4 步）：内核真正读的是
  /// `configs/<id>.json`，而它只有 `{"outbounds":[…]}` —— 节点集合原本由"订阅原文"决定。
  /// 改由 `proxy_entities` 决定之后，"节点可编辑"才有落脚点。组装产物写在
  /// `configs/<id>.entities.json`，**订阅基准保持不动**。
  ///
  /// 回落路径就是改动前的行为，所以不会比原来更差。回落之所以安全：内核组装/启动失败走
  /// `errorWrapper → StopAndAlert → SetCoreStatus(STOPPED)`（`hcore/custom.go`），
  /// 状态被复位，第二次 start 不会被判成 ALREADY_STARTED。
  ///
  /// 只动节点：组由内核重建（`builder.go:130-371` 会丢弃输入里的组），本层不代劳。
  ///
  /// **custom_config 两阶段启动**（`docs/design/custom-config-2026-09-18.md` §8.3）：
  /// `ConfigOptions.customConfig` 非空时（NekoBox `globalCustomConfig`）：
  /// 1. 先照常组装 entities 文件（失败回落订阅，与现状一致）——得到"合并基准路径"
  /// 2. `generateFullConfigByPath`：内核（raw=false）拼出**完整最终 JSON**
  ///    （HiddifyOptions patch 全部完成：DNS/路由/入站/链式...）
  /// 3. Dart 侧 `deepMergeJson(完整JSON, customConfig)` —— NekoBox `Util.mergeMap`
  ///    同构语义（Map 深合并 / `key+` 追加 / `+key` 前插 / 裸键替换）
  /// 4. `startRawContent`：`EnableRawConfig=true` + 合并结果启动 —— 内核只 unmarshal 不拼装
  /// 5. 任一步失败 ⇒ 记日志回落现状路径（保证「不会比原来更差」）
  ///
  /// customConfig 为空 ⇒ 与改动前逐字节同路径，零行为变化。
  TaskEither<ConnectionFailure, Unit> _start(ProfileEntity profile, bool disableMemoryLimit) =>
      TaskEither(() async {
        final subscriptionPath = profilePathResolver.file(profile.id).path;

        String? entityPath;
        try {
          final assembled = await ref.read(proxyEntityRepositoryProvider).assembleOutboundsForProfile(profile.id);
          if (assembled != null) {
            final file = profilePathResolver.entityFile(profile.id);
            await file.writeAsString(assembled);
            entityPath = file.path;
          }
        } catch (e, stackTrace) {
          loggy.warning("entity config assembly failed, starting from the subscription config instead", e, stackTrace);
        }

        // 合并基准 = 实体组装产物，失败回落订阅基准（与现状一致）
        final basePath = entityPath ?? subscriptionPath;

        final customConfig = ref.read(ConfigOptions.customConfig);
        if (customConfig.isNotBlank) {
          final rawResult = await _startWithCustomConfig(customConfig, basePath, profile.name, disableMemoryLimit).run();
          if (rawResult.isRight()) return rawResult;
          loggy.warning("custom_config raw start failed, falling back to the normal path: $rawResult");
        }

        if (entityPath != null) {
          final result = await singbox.start(entityPath, profile.name, disableMemoryLimit).run();
          if (result.isRight()) return result;
          loggy.warning("start from entity config failed, falling back to the subscription config: $result");
        }

        return singbox.start(subscriptionPath, profile.name, disableMemoryLimit).run();
      });

  /// 两阶段 raw 启动（设计文档 §8.3 b-d）：内核拼装 → Dart 深合并 → raw 通道启动。
  /// 任何一步失败都返回 Left，由调用方回落现状路径。
  ///
  /// 合并基准是**内核拼装的完整最终 JSON**（含全部 patch），不是订阅/实体文件原文——
  /// 否则 `EnableRawConfig=true` 会跳过内核 patch（WARP/静态 IP/DNS/路由构建），
  /// 与 ChangeHiddifySettings 驱动的配置不一致。
  TaskEither<ConnectionFailure, Unit> _startWithCustomConfig(
    String customConfig,
    String basePath,
    String name,
    bool disableMemoryLimit,
  ) => TaskEither(() async {
    // b. 内核正常拼装（raw=false），产出完整最终 JSON
    final fullConfig = await singbox.generateFullConfigByPath(basePath).run();
    final content = fullConfig.fold(
      (err) => throw StateError("generate full config failed: $err"),
      (c) => c,
    );

    // c. Dart 侧 NekoBox 语义深合并（最后改卷权）
    final base = jsonDecode(content) as Map<String, dynamic>;
    final merged = deepMergeJson(base, parseCustomConfig(customConfig));

    // d. raw 通道启动
    return singbox.startRawContent(jsonEncode(merged), basePath, name, disableMemoryLimit).run();
  });

  @override
  TaskEither<ConnectionFailure, Unit> disconnect() => singbox.stop().mapLeft(UnexpectedConnectionFailure.new);

  /// 换配置 = **下发设置 → 等（核心会自己重启）→ 再起一次**。
  ///
  /// 实测日志（02:21:48）说明了一切：
  /// ```text
  /// capture enabled - restarting core to apply it
  /// connection status: CONNECTED            ← 核心自己重启了一次
  /// connection status: DISCONNECTED
  /// [E] error watching proxies: HTTP/2 ... Connection is being forcefully terminated
  /// [W] error applying capture change       ← 15 毫秒后就报错
  /// ```
  /// 也就是说：**`changeHiddifySettings` 本身就会重启核心**，重启期间 gRPC 通道被切断，
  /// 于是 `applyConfigOption` 报 "forcefully terminated" —— 那是**预期行为**，不是失败。
  /// 所以这里：① 忽略这一步的错（只记日志）② 等核心重启完 ③ 按新设置再 start 一次（失败重试一次）。
  /// 之前用核心的 `restart`、以及 `stop` + 立刻 `start`，都是因为卡在这一步之前而失败。
  @override
  TaskEither<ConnectionFailure, Unit> reconnect(ProfileEntity activeProfile, bool disableMemoryLimit) =>
      TaskEither(() async {
        final applied = await applyConfigOption(activeProfile).run();
        applied.match(
          (err) => loggy.info("applyConfigOption reported an error (expected while the core restarts): $err"),
          (_) => unit,
        );

        // 尽力停一下（可能已经在重启中，失败无所谓）
        await singbox.stop().run();

        await Future.delayed(const Duration(milliseconds: 1500));
        var result = await _start(activeProfile, disableMemoryLimit).run();
        if (result.isLeft()) {
          loggy.warning("start after applying options failed, waiting longer and retrying once: $result");
          await Future.delayed(const Duration(milliseconds: 2000));
          result = await _start(activeProfile, disableMemoryLimit).run();
        }
        return result.mapLeft(UnexpectedConnectionFailure.new);
      });

  @visibleForTesting
  TaskEither<ConnectionFailure, Unit> applyConfigOption(ProfileEntity prof) =>
      TaskEither.fromEither(configOptionRepository.fullOptionsOverrided(prof.profileOverride()))
          .mapLeft((l) => ConnectionFailure.invalidConfigOption(null, l))
          .flatMap(
            (overridedOptions) => TaskEither.tryCatch(() async {
              if (!overridedOptions.chainStatus.isOff()) {
                final isWarpLicenseAgreed = ref.read(Preferences.warpConsentGiven) == true;
                final isWarpEnabled =
                    overridedOptions.unblocker.mode.isWarp() || overridedOptions.extraSecurity.mode.isWarp();
                if (!isWarpLicenseAgreed && isWarpEnabled) {
                  final isAgreed = await ref.read(dialogNotifierProvider.notifier).showWarpLicense();
                  if (isAgreed == true) {
                    await ref.read(Preferences.warpConsentGiven.notifier).update(true);
                    // return (await applyConfigOption(prof).run()).match((l) => throw l, (_) => unit);
                  } else {
                    throw const MissingWarpLicense();
                  }
                }

                final isPsiphonLicenseAgreed = ref.read(Preferences.psiphonConsentGiven) == true;
                final isPsiphonEnabled =
                    overridedOptions.unblocker.mode.isPsiphon() || overridedOptions.extraSecurity.mode.isPsiphon();
                if (!isPsiphonLicenseAgreed && isPsiphonEnabled) {
                  final isAgreed = await ref.read(dialogNotifierProvider.notifier).showPsiphonLicense();
                  if (isAgreed == true) {
                    await ref.read(Preferences.psiphonConsentGiven.notifier).update(true);
                  } else {
                    throw const MissingPsiphonLicense();
                  }
                }
              }

              _configOptionsSnapshot = overridedOptions;
              await singbox.changeOptions(overridedOptions).run();
              return unit;
            }, (err, st) => err is ConnectionFailure ? err : ConnectionFailure.unexpected(err, st)),
          );
}
