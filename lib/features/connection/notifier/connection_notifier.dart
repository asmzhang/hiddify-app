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
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/hiddifycore/hiddify_core_service_provider.dart';
import 'package:hiddify/hiddifycore/init_signal.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
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
      // **只在真的换了订阅时重连**（id 变了）。订阅内容更新走 `profile_notifier`
      // 那条路径（`updateProfile` → `reconnect`），不在这里重复触发。
      //
      // 注意（本条此前写反过）：下面 `reconnect` 现在只保证「内核在有就跑新配置」，
      // **不碰接管状态** —— 更新订阅不会让连接断开或接管。
      final shouldReconnect = next == null || previous.id != next.id;
      if (shouldReconnect) {
        loggy.info("active profile changed (id: ${previous.id} -> ${next?.id}) - reconnecting");
        await reconnect(next);
      }
    });
    ref.watch(coreRestartSignalProvider);

    // **应用启动时从"不接管"开始** ——「不要自动连接」。
    // 接管状态是落盘的，用户上次试过之后下次打开就会自动接管，所以启动时复位一次。
    // （内核照旧静默起来，所以"没连接也能测速"不受影响。）
    //
    // ⚠️ 只能做一次：captureEnabled 一变化就会重建本 notifier（下面 watch 了
    // capturingProvider），若复位挂在每次 build 上，用户刚打开的开关会被自己的
    // 重建清掉 —— 这是「开了关不了」的第一环。
    if (!_captureResetDone) {
      _captureResetDone = true;
      Future.microtask(() => ref.read(Preferences.captureEnabled.notifier).update(false));
    }

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

  /// 「启动时不接管」的复位**只做一次**。
  /// 挂在每次 build 上会清掉用户刚打开的开关（captureEnabled 一变化就重建本 notifier）。
  bool _captureResetDone = false;

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
  /// 但那只对**系统代理**成立。另外两种模式里，「连接」就等于「内核在不在跑」：
  /// - **TUN**：`capturing == coreUp`（网卡和路由只能在启动时建）
  /// - **仅代理**：根本没有"接管"这回事，内核只是等着被程序连
  ///
  /// 所以这两种模式：**开 = 启内核，关 = 停内核**。
  /// （审计发现：原来只有 TUN 分支这么处理，仅代理模式会一路走到最后的
  ///  "重启内核"路径 —— 但重启后 `capturing` 仍为 false，于是白重启一次、
  ///  状态还永远停在"未连接"。）
  Future<void> setCapture(bool enabled) async {
    final mode = ref.read(ConfigOptions.serviceMode);

    if (mode != ServiceMode.systemProxy) {
      if (enabled) {
        if (!_coreStarted) await _connect();
      } else if (_coreStarted) {
        await _disconnect();
      }
      return;
    }

    // 幂等判断看**实际接管状态**，并与落盘开关一起确认 ——
    // 只看 captureEnabled 的话，它一旦与实际接管错位（如启动复位的时序），
    // 「关闭」就会被这行静默吞掉。
    if (ref.read(capturingProvider) == enabled && ref.read(Preferences.captureEnabled) == enabled) return;
    await ref.read(Preferences.captureEnabled.notifier).update(enabled);

    // 内核还没跑：启动它就行，这次启动会带上刚改好的接管设置
    if (!_coreStarted) {
      await _connect();
      return;
    }

    // **系统代理可以运行时切换，不必重启内核** —— core 提供了 `SetSystemProxyEnabled`，
    // 它直接改系统代理设置（注册表级），内核继续跑、连接不断。
    // 成功即结束；失败则**自动落到下面"重启内核"的路径兜底**，行为不会比原来更差。
    final applied = await ref.read(hiddifyCoreServiceProvider).setSystemProxyEnabled(enabled).run();
    if (applied.isRight()) {
      loggy.info("capture ${enabled ? "enabled" : "disabled"} - applied at runtime (no core restart)");
      return;
    }
    loggy.warning("runtime system-proxy switch failed, falling back to core restart: $applied");

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

  /// 让内核用上「当前的订阅配置」—— 换订阅、订阅内容更新都走这里。
  ///
  /// **契约：只动内核，不动接管状态。** 内核在跑就重载成新配置；接管与否由用户
  /// 的开关决定，不因为这个调用而变化。
  ///
  /// 历史（重要）：这里原来只有 `state == Connected`（= **接管中**）才重连。于是
  /// 桌面默认（`captureEnabled=false`，内核常驻但不接管）下，更新订阅内容或切换
  /// 激活订阅都**不会**让内核换成新配置。代理页的清单现在来自内核（见
  /// `docs/design/proxy-model-root-fix.md`），内核不重载就意味着：列表滞后于订阅，
  /// 而且「选择了别的订阅的节点」落盘的那笔 pending 永远等不到新内核来应用。
  Future<void> reconnect(ProfileEntity? profile) async {
    if (state is! AsyncData) return;

    // 没有激活订阅：接管中就断开；没接管则无事可做（内核也不该继续跑）。
    if (profile == null) {
      if (state.value == const Connected()) {
        loggy.info("no active profile, disconnecting");
        return _disconnect();
      }
      return;
    }

    // 内核没跑：什么都不用做 —— 下次启动（用户点连接或 `_autoStartOnce`）自然读到新配置。
    if (!_coreStarted) {
      loggy.debug("core is not running, nothing to reload (the next start picks up the new config)");
      return;
    }

    final capturing = state.value == const Connected();
    if (capturing) {
      await ref.read(Preferences.startedByUser.notifier).update(true);
    }
    loggy.info(
      capturing
          ? "active profile changed, reconnecting"
          : "reloading core with the new config (not capturing - capture state untouched)",
    );
    await _connectionRepo.reconnect(profile, ref.read(Preferences.disableMemoryLimit)).mapLeft((err) async {
      loggy.warning(capturing ? "error reconnecting" : "error reloading core", err);
      // 未接管时不动 state：那是由内核状态流驱动、且当前就是 Disconnected，
      // 抢着写 AsyncError 只会让界面闪烁；错误用对话框告知即可。
      if (capturing) state = AsyncError(err, StackTrace.current);
      await ref
          .read(dialogNotifierProvider.notifier)
          .showCustomAlertFromErr(err.present(ref.read(translationsProvider).requireValue));
    }).run();
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
