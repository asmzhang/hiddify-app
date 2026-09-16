import 'dart:async';

import 'package:dio/dio.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/throttler.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_repository.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';
import 'package:hiddify/features/proxy/data/selected_proxy_store.dart';
import 'package:hiddify/features/proxy/data/selection_reconcile.dart';
import 'package:hiddify/features/proxy/model/ip_info_entity.dart' as oldipinfo;
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'active_proxy_notifier.g.dart';

@riverpod
class IpInfoNotifier extends _$IpInfoNotifier with AppLogger {
  @override
  Future<oldipinfo.IpInfo> build() async {
    ref.disposeDelay(const Duration(seconds: 20));
    final cancelToken = CancelToken();
    ref.onDispose(() {
      loggy.debug("disposing");
      cancelToken.cancel();
    });

    final autoCheck = ref.watch(Preferences.autoCheckIp);
    final serviceRunning = ref.watch(serviceRunningProvider);

    // 只有**手动刷新**（`refresh()` 置 `_forceCheck`）或**开了自动检查**才去查。
    // 原先还挂了一个 10 秒定时器把结果 invalidateSelf 掉 —— 那会「自动刷新成空白」，
    // 与「刷新不要自动」直接冲突，已删。
    if (!_forceCheck) {
      if (!serviceRunning) throw const ServiceNotRunning();
      if (!autoCheck) throw const UnknownIp();
    }

    _forceCheck = false;
    final info = await ref.watch(proxyRepositoryProvider).getCurrentIpInfo(cancelToken).getOrElse((err) {
      loggy.warning("error getting proxy ip info", err, StackTrace.current);
      throw const UnknownIp();
    }).run();

    return info;
  }

  bool _forceCheck = false;

  Future<void> refresh() async {
    if (state.isLoading) return;
    loggy.debug("refreshing");
    state = const AsyncLoading();
    await ref.read(hapticServiceProvider.notifier).lightImpact();
    _forceCheck = true;
    ref.invalidateSelf();
  }
}

@Riverpod(keepAlive: true)
class ActiveProxyNotifier extends _$ActiveProxyNotifier with AppLogger {
  @override
  Stream<OutboundInfo> build() {
    // ref.disposeDelay(const Duration(seconds: 20));
    final serviceRunning = ref.watch(serviceRunningProvider);
    if (!serviceRunning) {
      return Stream.error(const ServiceNotRunning());
    }
    return _proxyRepo
        .watchActiveProxies()
        .map((event) => event.getOrElse((l) => List<OutboundGroup>.empty()))
        .asyncMap((groups) async {
          // 这里是"服务侧"。NekoBox 把"把持久化的选中应用到内核"放在服务里
          // （`bg/BaseService.kt:180-212` 的 `reload()`），不放 UI 层。
          // 本 notifier 是 keepAlive 且在 bootstrap 被 eager listen（`bootstrap.dart:104`），
          // 所以内核一起来它就被驱动 —— 等价于 NekoBox 的 reload()。
          await _reconcileSelection(groups);
          return _activeOutbound(groups);
        });
  }

  /// 「期望选中的节点」+「它属于哪份订阅」—— NekoBox 的 `DataStore.selectedProxy` /
  /// `DataStore.currentProfile`（见 `selected_proxy_store.dart`）。
  SelectedProxyStore get _selection => SelectedProxyStore(ref.read(sharedPreferencesProvider).requireValue);

  /// 把持久化的「期望选中」校准到内核 —— 对应 NekoBox `BaseService.kt:180-212` 的 `reload()`。
  ///
  /// 为什么需要它：NekoBox 的选中项在**构建期**被写成 selector 的 `default`
  /// （`ConfigBuilder.kt:471`），重启后自然还在；hiddify 内核把那个 `default` 写死成
  /// `balance`（`builder.go:311-341`），应用拿不到口子 ⇒ 只能每次内核 ready 后补一刀。
  ///
  /// 决策（含"采纳外部改选"的方向）在纯函数 [decideSelectionReconcile] 里，有断言覆盖
  /// （`tool/check_selection_reconcile.dart`）；这里只负责执行。
  Future<void> _reconcileSelection(List<OutboundGroup> groups) async {
    final selector = groups.where((g) => g.tag == kRuntimeSelectorTag).firstOrNull;
    if (selector == null) return;

    final store = _selection;
    final activeProfileId = ref.read(activeProfileProvider).valueOrNull?.id;
    final action = decideSelectionReconcile(
      desiredTag: store.outboundTag,
      desiredProfileId: store.profileId,
      activeProfileId: activeProfileId,
      kernelSelectedTag: selector.selected,
      kernelNodeTags: selector.items.where((i) => !i.isGroup && !isHiddenTag(i.tag)).map((i) => i.tag),
    );

    switch (action) {
      case SelectionReconcileAction.none:
        return;
      case SelectionReconcileAction.waitForProfile:
        loggy.debug(
          "saved selection belongs to another profile, waiting for the core to load it "
          "(kernel now has ${activeProfileId ?? "none"})",
        );
      case SelectionReconcileAction.applyDesired:
        loggy.info("applying saved selection [${store.outboundTag}] (kernel was on its default [${selector.selected}])");
        await _proxyRepo.selectProxy(kRuntimeSelectorTag, store.outboundTag).run();
      case SelectionReconcileAction.adoptKernel:
        // 外部改了选中（yacd / webui 等）⇒ 采纳并回写，别把它按回去。
        // 对应 NekoBox `NativeInterface.kt:84-105` selector_OnProxySelected →
        // `MainActivity.kt:416-423` 回写 DataStore.selectedProxy。
        loggy.info("kernel selection changed externally: [${selector.selected}] - adopting it");
        await store.save(outboundTag: selector.selected, profileId: activeProfileId ?? "");
    }
  }

  /// 当前活跃出站 = 内核主 selector（常量 tag）里**被选中的那个节点**。
  ///
  /// 原来取的是 `firstOrNull?.items.first`：内核第一组是 `select`，而它的第一个成员是
  /// `balance`（一个 balancer，不是节点）—— 于是仪表盘显示的是一行组名，而不是真正在跑的节点。
  /// 选中项才是事实。见 `runtime_outbound_tags.dart`。
  OutboundInfo _activeOutbound(List<OutboundGroup> groups) {
    final selector = groups.where((g) => g.tag == kRuntimeSelectorTag).firstOrNull;
    if (selector == null) {
      // 内核还没建好组：退化为"第一个非组条目"
      return groups
              .expand((g) => g.items)
              .where((i) => !i.isGroup && !isHiddenTag(i.tag))
              .firstOrNull ??
          OutboundInfo();
    }
    return selector.items.where((i) => !i.isGroup && i.tag == selector.selected).firstOrNull ??
        selector.items.where((i) => !i.isGroup && i.isSelected).firstOrNull ??
        OutboundInfo();
  }

  ProxyRepository get _proxyRepo => ref.read(proxyRepositoryProvider);

  final _urlTestThrottler = Throttler(const Duration(seconds: 1));

  /// 测整组：**必须传空 tag** —— 内核 `commands.go` 的 `UrlTest` 在 `in.Tag == ""` 时走
  /// `UrlTestActive()`（内部硬编码用常量 `select`）；传组名会被当成节点 tag 去测。
  Future<void> urlTest() async {
    _urlTestThrottler(() async {
      if (state case AsyncData()) {
        await ref.read(hapticServiceProvider.notifier).lightImpact();
        await ref.read(proxyRepositoryProvider).urlTest('').getOrElse((err) {
          loggy.warning("error testing group", err);
          throw err;
        }).run();
      }
    });
  }
}
