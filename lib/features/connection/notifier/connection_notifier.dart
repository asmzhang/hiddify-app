import 'dart:io';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/connection/data/connection_data_providers.dart';
import 'package:hiddify/features/connection/data/connection_repository.dart';
import 'package:hiddify/features/connection/model/connection_failure.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/system_proxy_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:rxdart/rxdart.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

part 'connection_notifier.g.dart';

@Riverpod(keepAlive: true)
class ConnectionNotifier extends _$ConnectionNotifier with AppLogger {
  @override
  Stream<ConnectionStatus> build() async* {
    if (Platform.isIOS) {
      await _connectionRepo.setup().mapLeft((l) {
        loggy.error("error setting up connection repository", l);
      }).run();
    }

    listenSelf((previous, next) async {
      if (previous == next) return;
      if (previous case AsyncData(:final value) when !value.isConnected) {
        if (next case AsyncData(value: final Connected _)) {
          await ref.read(hapticServiceProvider.notifier).heavyImpact();

          if (Platform.isAndroid && !ref.read(Preferences.storeReviewedByUser)) {
            if (await InAppReview.instance.isAvailable()) {
              InAppReview.instance.requestReview();
              ref.read(Preferences.storeReviewedByUser.notifier).update(true);
            }
          }
        }
      }
    });

    ref.listen(activeProfileProvider.select((value) => value.asData?.value), (previous, next) async {
      if (previous == null) return;
      // **只在真的换了订阅时重连**（id 变了）。
      //
      // 更新订阅（同一个 id，只有内容变了）**不碰连接** —— 照 nekoray：
      // 订阅更新是纯数据操作（`GroupUpdater::Update` 全程不 restart、不 start），
      // 列表直接来自数据层所以立刻就变，跟连接状态完全分开。
      // （我之前用 lastUpdate 触发重连，等于把"更新订阅"和"重启连接"焊在一起，是错的。）
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        loggy.info("active profile changed (id: ${previous.id} -> ${next?.id}) - reconnecting");
        await reconnect(next);
      }
    });
    ref.watch(coreRestartSignalProvider);

    // **每次启动都从"不接管"开始** ——「不要自动连接」。
    // 接管状态是落盘的，用户上次试过之后下次打开就会自动接管，所以这里显式复位。
    // （内核照旧静默起来，所以"没连接也能测速"不受影响。）
    Future.microtask(() => ref.read(Preferences.captureEnabled.notifier).update(false));

    // **内核默认常驻**：应用起来（且有订阅）就把它拉起来 —— 但**不接管流量**
    // （`captureEnabled` 默认 false）。这样"没连接也能测速、挑节点"成立，
    // 而且用户什么都不用点。列表/延迟/测速都靠它。
    if (!_coreStarted) _autoStartOnce();
    // 订阅导入/切换后补一次。用 listen 而不是 watch：watch 会让 DB 每次写入都重建
    // 这个 notifier、连带重启状态流。
    ref.listen(activeProfileProvider, (previous, next) {
      if (next.valueOrNull != null) _autoStartOnce();
    });

    // 对外状态 = **流量有没有被接管**（首页那个大按钮就是这个意思）。
    // 内核常驻之后"内核在跑吗"恒为真，拿它当"已连接"就没意义了。
    // （代理页的清单来自订阅、延迟看 `coreRunningProvider`，已经不依赖这个枚举，
    //  所以这次重映射不会再有上一版那种副作用。）
    final capturing = ref.watch(capturingProvider);

    yield* _connectionRepo
        .watchConnectionStatus()
        .map((event) {
          _coreStarted = event is Connected;
          return switch (event) {
            Connected() => capturing ? const Connected() : const Disconnected(),
            _ => event,
          };
        })
        .doOnData((event) {
          if (event case Disconnected(connectionFailure: final _?) when PlatformUtils.isDesktop) {
            Future.microtask(() => ref.read(Preferences.startedByUser.notifier).update(false));
          }
          loggy.info("connection status: ${event.format()}");
        });
  }

  ConnectionRepository get _connectionRepo => ref.read(connectionRepositoryProvider);

  /// 内核是否真的起来了（对外状态现在表达"接管"，所以要单独记这一个）。
  bool _coreStarted = false;

  bool _autoStartAttempted = false;

  /// 静默把内核拉起来（**不接管**，因为 `captureEnabled` 默认 false）。
  ///
  /// **只尝试一次**：`build()` 会被 `coreRestartSignal` 和订阅变化反复触发，
  /// 无脑重试会和别的 start 互相打断，变成 CONNECTING↔DISCONNECTED 每秒抖七八次
  /// （实测日志 6 秒 1900 条）。失败就罢了，用户点「连接」时自然会看到错误。
  void _autoStartOnce() {
    if (_autoStartAttempted || _coreStarted) return;
    _autoStartAttempted = true;
    Future.microtask(() async {
      if (_coreStarted) return;
      final profile = await ref.read(activeProfileProvider.future);
      if (profile == null) {
        // 还没订阅：留着下一次机会，等订阅导入了再来
        _autoStartAttempted = false;
        return;
      }
      loggy.info("starting core in the background (no traffic capture yet)");
      await _connectionRepo.connect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) {
        loggy.warning("background core start failed (won't auto-retry)", err);
      }).run();
    });
  }

  Future<void> mayConnect() async {
    if (state case AsyncData(:final value)) {
      if (value case Disconnected()) return _connect();
    }
  }

  /// 「连接」= **接管流量**（首页那个大按钮）。
  ///
  /// 内核默认常驻，所以这里不启停内核：没接管就接管，接管中就不接管。
  /// 内核万一没跑（没订阅/刚启动），[setCapture] 会先把它启动起来。
  Future<void> toggleConnection() async {
    final capturing = ref.read(capturingProvider);
    final haptic = ref.read(hapticServiceProvider.notifier);
    if (capturing) {
      await haptic.mediumImpact();
      await ref.read(Preferences.startedByUser.notifier).update(false);
    } else {
      await haptic.lightImpact();
      await ref.read(Preferences.startedByUser.notifier).update(true);
    }
    await setCapture(!capturing);
  }

  /// 切换**是否接管流量** —— 与"内核在不在跑"完全独立的一个量。
  ///
  /// 接管与否只在启动时生效（TUN 更是只能在启动时决定），所以内核已经在跑的时候
  /// 要**重启内核**才能应用。nekoray 切 TUN 也是这么做的（`neko_start(started_id)`）。
  Future<void> setCapture(bool enabled) async {
    if (ref.read(Preferences.captureEnabled) == enabled) return;
    await ref.read(Preferences.captureEnabled.notifier).update(enabled);

    // 内核还没跑：启动它就行，这次启动会带上刚改好的接管设置
    if (!_coreStarted) {
      await _connect();
      return;
    }

    final profile = await ref.read(activeProfileProvider.future);
    if (profile == null) return;

    loggy.info("capture ${enabled ? "enabled" : "disabled"} - restarting core to apply it");
    await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) async {
      loggy.warning("error applying capture change", err);
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
    }).run();
  }

  Future<void> reconnect(ProfileEntity? profile) async {
    if (state case AsyncData(:final value) when value == const Connected()) {
      if (profile == null) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      loggy.info("active profile changed, reconnecting");
      await ref.read(Preferences.startedByUser.notifier).update(true);
      await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) async {
        loggy.warning("error reconnecting", err);
        state = AsyncError(err, StackTrace.current);
        await ref
            .read(dialogNotifierProvider.notifier)
            .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      }).run();
    }
  }

  Future<void> abortConnection() async {
    if (state case AsyncData(:final value)) {
      switch (value) {
        case Connected() || Connecting():
          loggy.debug("aborting connection");
          await _disconnect();
        default:
      }
    }
  }

  final _singleStart = SingleCall();

  Future<void> _connect() async {
    _singleStart.run(
      () async {
        await _connectThrottled();
      },
      onIgnored: () {
        loggy.debug("connect called while another connect/disconnect is still running, ignoring");
      },
    );
  }

  Future<void> _connectThrottled() async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) {
      loggy.info("no active profile, not connecting");
      return;
    }
    await _connectionRepo.connect(activeProfile, ref.read(Preferences.disableMemoryLimit)).mapLeft((
      ConnectionFailure err,
    ) async {
      loggy.warning("error connecting", err);
      //Go err is not normal object to see the go errors are string and need to be dumped
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      loggy.warning(err);
      if (err.toString().contains("panic")) {
        await Sentry.captureException(Exception(err.toString()));
      }
      await ref.read(Preferences.startedByUser.notifier).update(false);
      state = AsyncError(err, StackTrace.current);
    }).run();
  }

  Future<void> _disconnect() async {
    await _connectionRepo.disconnect().mapLeft((err) {
      loggy.warning("error disconnecting", err);
      ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
      state = AsyncError(err, StackTrace.current);
    }).run();
  }
}

@Riverpod(keepAlive: true)
bool serviceRunning(Ref ref) {
  // ref.watch(coreRestartSignalProvider);
  return ref.watch(connectionNotifierProvider).valueOrNull?.isConnected ?? false;
}

class SingleCall {
  bool _running = false;

  Future<T> run<T>(Future<T> Function() task, {required T onIgnored}) async {
    if (_running) return onIgnored;

    _running = true;
    try {
      return await task();
    } finally {
      _running = false;
    }
  }
}
