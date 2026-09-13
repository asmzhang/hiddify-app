import 'dart:async';

import 'package:dartx/dartx.dart';

import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/notifier/system_proxy_notifier.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';

import 'package:hiddify/utils/riverpod_utils.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'proxies_overview_notifier.g.dart';

enum ProxiesSort {
  unsorted,
  name,
  delay,
  usage;

  String present(TranslationsEn t) => switch (this) {
    ProxiesSort.unsorted => t.pages.proxies.sortOptions.unsorted,
    ProxiesSort.name => t.pages.proxies.sortOptions.name,
    ProxiesSort.delay => t.pages.proxies.sortOptions.delay,
    ProxiesSort.usage => t.pages.proxies.sortOptions.usage,
  };
}

@Riverpod(keepAlive: true)
class ProxiesSortNotifier extends _$ProxiesSortNotifier with AppLogger {
  late final _pref = PreferencesEntry(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "proxies_sort_mode",
    defaultValue: ProxiesSort.delay,
    mapFrom: ProxiesSort.values.byName,
    mapTo: (value) => value.name,
  );

  @override
  ProxiesSort build() {
    final sortBy = _pref.read();
    loggy.info("sort proxies by: [${sortBy.name}]");
    return sortBy;
  }

  Future<void> update(ProxiesSort value) {
    state = value;
    return _pref.write(value);
  }
}

/// 代理页**当前在看哪个分组**（落盘，照 nekoray 的"当前分组"）。
/// 分组清单来自订阅配置（`offlineProxyGroupsProvider`），和连接状态无关。
final selectedProxyGroupTagProvider = PreferencesNotifier.createAutoDispose("selected_proxy_group", "");

@riverpod
class ProxiesOverviewNotifier extends _$ProxiesOverviewNotifier with AppLogger {
  /// **「选择代理」和「启动代理」是两件事。**
  ///
  /// 选择是**配置层**的决定：内核在跑就直接下发；没跑就**记在磁盘上**，等内核哪天
  /// ready 再应用。它不能挂在 notifier 的内存里 —— 这个 notifier 是 autoDispose
  /// + 15s 延迟回收，用户在设置页待一会儿，那个"选择"就蒸发了（同行都是持久的）。
  late final _pendingGroup = PreferencesEntry(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "pending_proxy_group",
    defaultValue: "",
  );
  late final _pendingOutbound = PreferencesEntry(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "pending_proxy_outbound",
    defaultValue: "",
  );

  @override
  Stream<OutboundGroup?> build() async* {
    ref.disposeDelay(const Duration(seconds: 15));
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    final coreAsync = ref.watch(coreRunningProvider);
    final coreRunning = coreAsync.hasValue ? coreAsync.requireValue : ref.watch(serviceRunningProvider);

    // 清单**始终以订阅解析为准** —— 这就是"常驻内容"，和连接状态完全分开：
    //   · 更新订阅 ⇒ 它立刻变（数据层的事）
    //   · 启停内核 / 切换接管 ⇒ 它不动（只有延迟在变）
    // 内核**不提供清单**，只提供"跑起来才知道"的延迟和用量。
    final groups = await ref.watch(offlineProxyGroupsProvider.future);
    if (groups.isEmpty) {
      yield* Stream.error(const ServiceNotRunning());
      return;
    }
    // 当前看的是哪个分组（落盘）。分组清单来自订阅配置，所以**更新订阅后分组也跟着变**。
    final selectedGroupTag = ref.watch(selectedProxyGroupTagProvider);
    final offline = groups.firstWhere((group) => group.tag == selectedGroupTag, orElse: () => groups.first);

    // 内核没跑：纯订阅清单（延迟那列显示 —）
    if (!coreRunning) {
      yield await _sortOutbounds(offline, sortBy);
      return;
    }

    yield* ref
        .watch(proxyRepositoryProvider)
        .watchProxies()
        .map(
          (event) => event.getOrElse((err) {
            loggy.warning("error receiving proxies", err);
            throw err;
          }),
        )
        .asyncMap((live) async {
          // 内核 ready：把「选择」阶段记下的节点应用过去（只做一次）。
          // 这是**选择**的落地，跟"启动"无关 —— 启动是另一条完全独立的路径。
          final pendingGroup = _pendingGroup.read();
          final pendingOutbound = _pendingOutbound.read();
          if (pendingOutbound.isNotEmpty) {
            loggy.debug("applying saved selection: [$pendingGroup] -> $pendingOutbound");
            await ref.read(proxyRepositoryProvider).selectProxy(pendingGroup, pendingOutbound).run();
            _pendingGroup.write("");
            _pendingOutbound.write("");
          }
          return await _sortOutbounds(_mergeLive(offline, live), sortBy);
        });
  }

  /// 把内核的**延迟 / 用量 / 选中**合并到订阅清单上。
  ///
  /// 谁在列表里、按什么顺序 —— 以**订阅**为准；内核只补充"跑起来才知道"的那几个字段。
  /// 这样两份数据各司其职，就不会出现"更新了订阅但页面不动"（那份清单不在内核手里）。
  OutboundGroup _mergeLive(OutboundGroup base, OutboundGroup? live) {
    if (live == null) return base;

    final byTag = <String, OutboundInfo>{for (final item in live.items) item.tag: item};
    final merged = OutboundGroup()
      // 组 tag 用内核的：真正下发 `selectProxy(groupTag, ...)` 的是内核，它得认这个 tag
      ..tag = live.tag.isNotEmpty ? live.tag : base.tag
      ..type = base.type
      ..selected = live.selected.isNotEmpty ? live.selected : base.selected;

    for (final item in base.items) {
      final matched = byTag.remove(item.tag) ?? item;
      matched.isSelected = matched.tag == merged.selected;
      merged.items.add(matched);
    }
    // 内核里有、订阅清单里没有的（面板临时加的之类）也带上，别丢东西
    for (final extra in byTag.values) {
      extra.isSelected = extra.tag == merged.selected;
      merged.items.add(extra);
    }
    return merged;
  }

  // Future<List<OutboundGroup>> _sortOutbounds(
  //   List<OutboundGroup> proxies,
  //   ProxiesSort sortBy,
  // ) async {
  //   final groupWithSelected = {
  //     for (final o in proxies) o.tag: o.selected,
  //   };
  //   final sortedProxies = <OutboundGroup>[];
  //   for (final group in proxies) {
  //     final sortedItems = switch (sortBy) {
  //       ProxiesSort.name => group.items.sortedWith((a, b) {
  //           if (a.isGroup && !b.isGroup) return -1;
  //           if (!a.isGroup && b.isGroup) return 1;
  //           return a.tag.compareTo(b.tag);
  //         }),
  //       ProxiesSort.delay => group.items.sortedWith((a, b) {
  //           if (a.isGroup && !b.isGroup) return -1;
  //           if (!a.isGroup && b.isGroup) return 1;

  //           final ai = a.urlTestDelay;
  //           final bi = b.urlTestDelay;
  //           if (ai == 0 && bi == 0) return -1;
  //           if (ai == 0 && bi > 0) return 1;
  //           if (ai > 0 && bi == 0) return -1;
  //           return ai.compareTo(bi);
  //         }),
  //       ProxiesSort.unsorted => group.items,
  //     };
  //     final items = <OutboundInfo>[];
  //     for (final item in sortedItems) {
  //       // if (groupWithSelected.keys.contains(item.tag)) {
  //       //   items.add(item.copyWith(selectedTag: groupWithSelected[item.tag]));
  //       // } else {
  //       items.add(item);
  //       // }
  //     }
  //     group.items.clear();
  //     group.items.addAll(items);
  //     sortedProxies.add(group);
  //   }
  //   return sortedProxies;
  // }

  Future<OutboundGroup?> _sortOutbounds(OutboundGroup? proxies, ProxiesSort sortBy) async {
    if (proxies == null) return null;

    final sortedItems = switch (sortBy) {
      ProxiesSort.name => proxies.items.sortedWith((a, b) {
        if (a.isGroup && !b.isGroup) return -1;
        if (!a.isGroup && b.isGroup) return 1;
        return a.tag.compareTo(b.tag);
      }),
      ProxiesSort.delay => proxies.items.sortedWith((a, b) {
        if (a.isGroup && !b.isGroup) return -1;
        if (!a.isGroup && b.isGroup) return 1;

        final ai = a.urlTestDelay;
        final bi = b.urlTestDelay;
        // 两个都没测速时必须回落到确定的次序（按名称）。
        // 原来这里 return -1 —— 对任意一对都成立 a<b 且 b<a，比较器不自洽，
        // List.sort 的结果就是"看起来随机"（未连接时全都没延迟，正好整列都乱）。
        if (ai == 0 && bi == 0) return a.tag.compareTo(b.tag);
        if (ai == 0 && bi > 0) return 1;
        if (ai > 0 && bi == 0) return -1;
        return ai.compareTo(bi);
      }),
      ProxiesSort.unsorted => proxies.items,
      ProxiesSort.usage => proxies.items.sortedWith((a, b) {
        if (a.isGroup && !b.isGroup) return -1;
        if (!a.isGroup && b.isGroup) return 1;

        final ai = a.upload + a.download;
        final bi = b.upload + b.download;
        // 用量相同（绝大多数情况：全都是 0）时回落到名称 ——
        // List.sort 不稳定，同样用量若不兜底，每次刷新顺序都可能不一样。
        if (ai == bi) return a.tag.compareTo(b.tag);
        return bi.compareTo(ai);
      }),
    };
    final items = <OutboundInfo>[];
    for (final item in sortedItems) {
      // if (groupWithSelected.keys.contains(item.tag)) {
      //   items.add(item.copyWith(selectedTag: groupWithSelected[item.tag]));
      // } else {
      items.add(item);
      // }
    }
    proxies.items.clear();
    proxies.items.addAll(items);
    return proxies;
  }

  // Future<void> changeProxy(String groupTag, String outboundTag) async {
  //   loggy.debug(
  //     "changing proxy, group: [$groupTag] - outbound: [$outboundTag]",
  //   );
  //   if (state case AsyncData(value: final outbounds)) {
  //     await ref.read(hapticServiceProvider.notifier).lightImpact();
  //     await ref.read(proxyRepositoryProvider).selectProxy(groupTag, outboundTag).getOrElse((err) {
  //       loggy.warning("error selecting outbound", err);
  //       throw err;
  //     }).run();
  //     final outboundg = outbounds.where((e) => e.tag == groupTag).firstOrNull;
  //     if (outboundg != null) {
  //       final newselected = outboundg.items.where((e) => e.tag == outboundTag).firstOrNull;
  //       if (newselected != null) {
  //         newselected.isSelected = true;
  //         outboundg.selected = newselected;
  //       }
  //     }
  //     state = AsyncData(
  //       [...outbounds],
  //     ).copyWithPrevious(state);
  //   }
  // }

  Future<void> changeProxy(String groupTag, String outboundTag) async {
    loggy.debug("changing proxy, group: [$groupTag] - outbound: [$outboundTag]");
    if (!state.hasValue) return;
    final outbounds = state.value!;
    await ref.read(hapticServiceProvider.notifier).lightImpact();

    if (ref.read(coreRunningProvider).valueOrNull ?? ref.read(serviceRunningProvider)) {
      await ref.read(proxyRepositoryProvider).selectProxy(groupTag, outboundTag).getOrElse((err) {
        loggy.warning("error selecting outbound", err);
        throw err;
      }).run();
    } else {
      // 内核没跑：**只记录选择，不碰启动**。这两件事分家 ——
      // 选择现在就定下来（落盘，下次内核起来带着它走），启动是用户另外的显式动作。
      _pendingGroup.write(groupTag);
      _pendingOutbound.write(outboundTag);
      loggy.debug("core not running - selection saved: [$groupTag] -> $outboundTag");
    }

    final newselected = outbounds.items.where((e) => e.tag == outboundTag).firstOrNull;
    if (newselected != null) {
      for (final item in outbounds.items) {
        item.isSelected = item.tag == outboundTag;
      }
      outbounds.selected = newselected.tag;
      state = AsyncValue.data(outbounds);
    }
  }

  Future<void> urlTest(String groupTag) async {
    loggy.debug("testing group: [$groupTag]");
    if (state case AsyncData()) {
      await ref.read(hapticServiceProvider.notifier).lightImpact();
      await ref.read(proxyRepositoryProvider).urlTest(groupTag).getOrElse((err) {
        loggy.error("error testing group", err);
        throw err;
      }).run();
    }
  }
}
