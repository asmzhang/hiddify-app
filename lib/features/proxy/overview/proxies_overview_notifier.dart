import 'dart:async';

import 'package:dartx/dartx.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/notifier/system_proxy_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/live_proxy_join.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/runtime_outbound_tags.dart';
import 'package:hiddify/features/proxy/data/selected_proxy_store.dart';
import 'package:hiddify/features/proxy/data/tcp_ping.dart';
import 'package:hiddify/features/proxy/model/proxy_failure.dart';
import 'package:hiddify/features/proxy/notifier/connection_test_notifier.dart';
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
  /// 排序是**分组自己的属性**，不是全局的 —— 这点照 NekoBox：
  /// `ProxyGroup.order`（`GroupOrder.ORIGIN / BY_NAME / BY_DELAY`）随分组存库，
  /// 切 Tab 时菜单勾选跟着换的就是它。
  ///
  /// 这里存成 `"<groupKey>=<sortName>"` 的分号串联串；默认不排序（对应 ORIGIN，
  /// 即订阅给的顺序）。原来是个**全局**排序，且默认按延迟 —— 于是内核一自动测速
  /// 整张表就重排，看着像"总是自动测速排列"。
  late final _pref = PreferencesEntry<String, String>(
    preferences: ref.watch(sharedPreferencesProvider).requireValue,
    key: "proxies_sort_by_group",
    defaultValue: "",
  );

  @override
  ProxiesSort build() {
    // 跟随当前分组：换分组 ⇒ 本 notifier 重建 ⇒ 读到那个分组自己的排序。
    final groupKey = ref.watch(selectedProxyGroupTagProvider);
    final sortBy = _readFor(groupKey);
    loggy.info("sort proxies by: [${sortBy.name}] (group: [${groupKey.isEmpty ? "-" : groupKey}])");
    return sortBy;
  }

  Future<void> update(ProxiesSort value) async {
    final groupKey = ref.read(selectedProxyGroupTagProvider);
    state = value;
    if (groupKey.isEmpty) return;
    final kept = _pref.read().split(";").where((part) {
      final i = part.lastIndexOf("=");
      return i > 0 && part.substring(0, i) != groupKey;
    });
    await _pref.write([...kept, "$groupKey=${value.name}"].join(";"));
  }

  ProxiesSort _readFor(String groupKey) {
    if (groupKey.isEmpty) return ProxiesSort.unsorted;
    for (final part in _pref.read().split(";")) {
      final i = part.lastIndexOf("=");
      if (i <= 0 || part.substring(0, i) != groupKey) continue;
      final name = part.substring(i + 1);
      return ProxiesSort.values.firstWhere((e) => e.name == name, orElse: () => ProxiesSort.unsorted);
    }
    return ProxiesSort.unsorted;
  }
}

@riverpod
class ProxiesOverviewNotifier extends _$ProxiesOverviewNotifier with AppLogger {
  /// **「选择代理」和「启动代理」是两件事。**
  ///
  /// 选择是**持久偏好**（不是"待应用一次的临时值"）——这点照 NekoBox：
  ///   · `ConfigurationFragment.kt:1504-1517` 用户点节点 = `DataStore.selectedProxy = id`
  ///     然后 `SagerNet.reloadService()`，**先落盘再通知服务**，从不清空；
  ///   · 服务侧由 `BaseService.reload()` 把它应用到内核（本项目落在
  ///     `ActiveProxyNotifier` 的校准里，因为内核把 selector 的 `default` 写死成
  ///     `balance`，应用拿不到构建期的口子）。
  ///
  /// 之前这里是"写 pending → 内核 ready 时应用一次 → 清空"，于是**重启/重连后选中就丢了**；
  /// 且这个 notifier 是 autoDispose + 15s 延迟回收，也扛不住页面来回切。
  SelectedProxyStore get _selection => SelectedProxyStore(ref.watch(sharedPreferencesProvider).requireValue);

  @override
  Stream<OutboundGroup?> build() async* {
    ref.disposeDelay(const Duration(seconds: 15));
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    // 当前看的是哪份订阅的哪个分组（落盘，复合键）。放同步段是规范性写法：
    // 避免在 async gap 之后读依赖（riverpod 2.x 对 await 之后的 watch 语义不直观）。
    final selectedKey = ref.watch(selectedProxyGroupTagProvider);
    final coreAsync = ref.watch(coreRunningProvider);
    final coreRunning = coreAsync.hasValue ? coreAsync.requireValue : ref.watch(serviceRunningProvider);

    // **两个数据面，职责不同**（见 docs/design/proxy-model-root-fix.md）：
    //   · **可切换范围** = 订阅：Tab 要展示"所有订阅的所有组"，而内核一次只加载
    //     一份配置 ⇒ 跨订阅的信息只有离线解析能给。这是本 provider 的用途。
    //   · **当前组的内容** = 内核（下面的 live 分支）：组、成员、选中、延迟、用量
    //     全部来自 `OutboundsInfo` —— 不再由应用解析配置 JSON 重建、也不再缝合。
    //
    // 只有激活订阅那份能拿内核的实时数据，其余订阅是纯离线清单，见下面的 isActive。
    final tabs = await ref.watch(proxyGroupTabsProvider.future);
    if (tabs.isEmpty) {
      yield* Stream.error(const ServiceNotRunning());
      return;
    }

    // 选中解析：键对不上（首次使用、历史遗留的纯组名、订阅被删）就落到第一个 Tab。
    final tab = tabs.where((t) => t.key == selectedKey).firstOrNull ?? tabs.first;

    // **实时数据只属于"内核当前加载的那份配置"**，两个来源分别判定：
    //  · 订阅 Tab —— 只有它是激活订阅时才有实时值（内核一次只加载一份配置）；
    //  · 手动 Tab —— 手动节点被**追加进每一份**订阅的出站表（见
    //    `assembleOutboundsForProfile`），所以只要内核在跑且有激活订阅就有实时值。
    final activeProfile = await ref.watch(activeProfileProvider.future);
    final bool isActive;
    if (tab.profileId.isEmpty) {
      isActive = activeProfile != null;
    } else {
      isActive = tab.profileId == activeProfile?.id;
    }
    // `_sortOutbounds` 会**原地重排** items，而 `tab.group` 来自 provider 缓存 ——
    // 传副本进去，别把缓存里的顺序改了（审计发现的副作用）。
    final offlineGroup = _withExpectedSelection(tab.group.deepCopy(), tab.profileId);
    if (!coreRunning || !isActive) {
      yield await _sortOutbounds(offlineGroup, sortBy);
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
        .asyncMap((liveGroups) async {
          // 「把持久化的选中应用到内核」不在这里做 —— 那是**服务侧**的事
          // （NekoBox 也在 `BaseService.reload()` 里做，不在 UI 层）。
          // 本项目落在 `ActiveProxyNotifier`：它是 keepAlive 且被 bootstrap eager listen，
          // 内核一起来就被驱动，比这个 autoDispose 的页面 notifier 更合适。
          // 见 lib/features/proxy/data/selection_reconcile.dart。
          //
          // **列表取自骨架（订阅/实体），实时值按「节点 tag」从内核贴上。**
          //
          // 讲清为什么不是"直接显示内核那一组"（`live_proxy_join.dart` 有完整推导）：
          // 内核返回的组是它自己重建的常量表 —— `select` / `balance` / `lowest`，
          // 其中 `select` 的成员是 `[balance, lowest, …全部节点]`（并集表），
          // 与订阅里的分组根本不是一回事；而 `balance`/`lowest` 会被当成节点显示出来。
          //
          // 这不是"双数据源"：NekoBox 也是这个分工 —— 列表来自 DB
          // （`ConfigBuilder.kt:131` 的 `proxyDao.getByGroup`），每节点实时值来自
          // `TrafficLooper`（按 tag 取，`TrafficData(id = ent.id, …)`），选中来自
          // `DataStore.selectedProxy`。**组 tag 不参与匹配，只有节点 tag 两侧一致。**
          final joined = joinLiveIntoGroup(skeleton: offlineGroup, liveGroups: liveGroups);
          if (joined.matched == 0) {
            loggy.debug(
              "kernel has no live data for this list yet (${joined.missing} nodes pending) - "
              "showing the subscription list",
            );
          }
          return await _sortOutbounds(_withExpectedSelection(joined.group, tab.profileId), sortBy);
        });
  }

  /// 把**持久化的"期望选中"**贴到展示用清单上（只在必要时代替当前选中）。
  ///
  /// 为什么需要：选中是**独立于内核状态的持久偏好**（NekoBox `DataStore.selectedProxy`，
  /// `ConfigurationFragment.kt:1504-1517` 先落盘再通知服务）。而内核侧那个 selector 的
  /// `default` 被写死成 `balance`（`builder.go:311-341`），于是"内核还没校准过来"的窗口里，
  /// 内核报的选中项（`balance`）**不是我们列表里的任何节点** —— 直接照抄就会整列没有高亮，
  /// 看起来像"选中的节点丢了"。
  ///
  /// 规则（只在"内核没给出可用选中"时兜底，不覆盖内核的实时事实）：
  /// - 期望值属于**别的订阅** ⇒ 不贴（归属校验，同 `selection_reconcile.dart`）
  /// - 期望值不在本清单里 ⇒ 不贴（可能是订阅更新后下线的节点）
  /// - 当前选中已经是本清单里的一个节点 ⇒ 保持不动
  /// - 否则 ⇒ 用期望值
  OutboundGroup _withExpectedSelection(OutboundGroup group, String profileId) {
    final selection = SelectedProxyStore(ref.read(sharedPreferencesProvider).requireValue);
    final belongsHere = selection.profileId.isEmpty || selection.profileId == profileId;
    final expected = belongsHere ? selection.outboundTag : '';
    bool isNode(String tag) => tag.isNotEmpty && group.items.any((e) => e.tag == tag);

    if (!isNode(group.selected) && isNode(expected)) {
      group.selected = expected;
    }
    for (final item in group.items) {
      item.isSelected = item.tag == group.selected;
    }
    return group;
  }

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
    final items = <OutboundInfo>[...sortedItems];
    proxies.items.clear();
    proxies.items.addAll(items);
    return proxies;
  }

  Future<void> changeProxy(String groupTag, String outboundTag) async {
    loggy.debug("changing proxy, group: [$groupTag] - outbound: [$outboundTag]");
    if (!state.hasValue) return;
    final outbounds = state.value!;
    await ref.read(hapticServiceProvider.notifier).lightImpact();

    // **下发的组 tag 必须是运行期 selector 的常量，不是订阅组名。**
    //
    // 内核 `commands.go` 的 `SelectOutbound` 实现是 `box.Outbound().Outbound(in.GroupTag)`，
    // 传订阅组名会返回 `selector not found: <订阅组名>` —— 也就是"点了没反应"。
    // 运行期那个 selector 的 tag 由内核写死为 `select`（`builder.go:37-42`、`:341`）。
    //
    // NekoBox 的等价做法：常量 `TAG_PROXY = "proxy"` + 构建期产出的
    // `ConfigBuildResult.profileTagMap`（实体 id → 配置 tag），运行期用它把选中实体
    // 翻译成 `selectOutbound(tag)`。**映射靠构建期的绑定，不靠名字相等。**
    // 详见 runtime_outbound_tags.dart / docs/design/nekobox-parity.md 8.6.8。
    const runtimeGroupTag = kRuntimeSelectorTag;

    // 当前列表属于哪份订阅：内核**只认激活订阅**，所以选别的订阅的节点
    // 必须先把它设为激活（激活变化会自动触发重连，已有逻辑）。
    final parsed = parseGroupKey(ref.read(selectedProxyGroupTagProvider));
    final activeProfile = await ref.read(activeProfileProvider.future);
    final String? targetProfileId = parsed?.profileId;
    final bool belongsToActive = targetProfileId == null || targetProfileId == activeProfile?.id;
    final bool coreRunning = ref.read(coreRunningProvider).valueOrNull ?? ref.read(serviceRunningProvider);

    if (belongsToActive && coreRunning) {
      await ref.read(proxyRepositoryProvider).selectProxy(runtimeGroupTag, outboundTag).getOrElse((err) {
        loggy.warning("error selecting outbound", err);
        throw err;
      }).run();
    }

    // **期望值一律落盘**（持久）—— 照 `ConfigurationFragment.kt:1506`：
    // 先写 `DataStore.selectedProxy`，再通知服务。内核没跑 / 换订阅 / 重连之后，
    // 由 `ActiveProxyNotifier` 的校准在合适时机应用它。
    //
    // 顺带修掉旧的"跨订阅窗口期竞态"：那时是"写 pending → 等事件 → 应用并清空"，
    // 旧内核还在推事件就会把选择吃到自己身上；现在期望值不会被清空，
    // 由 `decideSelectionReconcile` 的归属校验把关（期望值属于别的订阅时一律等待）。
    await _selection.save(outboundTag: outboundTag, profileId: targetProfileId ?? "");
    if (!(belongsToActive && coreRunning)) {
      if (targetProfileId != null && !belongsToActive) {
        loggy.info("selection belongs to another profile [$targetProfileId] - switching active profile");
        await ref.read(profilesNotifierProvider.notifier).selectActiveProfile(targetProfileId);
      }
      loggy.debug("selection saved (coreRunning=$coreRunning, active=$belongsToActive): [$runtimeGroupTag] -> $outboundTag");
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

  /// 删除节点（NekoBox 节点行的 🗑，`ConfigurationFragment.kt:1602-1608`）。
  ///
  /// 归属组用 `profileId`（订阅派生的组）或 `groupId`（手动组）指定 —— 手动分组的节点
  /// 也要能删。返回被删掉的那一行（调用方用它做"撤销"）；失败返回 null。
  /// 写完 invalidate 列表 —— 列表以实体为准，所以删除立刻可见。
  Future<ProxyEntityEntry?> removeNode({String? profileId, int? groupId, required String tag}) async {
    loggy.debug("removing node: [$tag] (profile: ${profileId ?? '-'}, group: ${groupId ?? '-'})");
    final removed = await ref
        .read(proxyEntityRepositoryProvider)
        .removeNode(profileId: profileId, groupId: groupId, tag: tag);
    if (removed != null) {
      ref.invalidate(proxyGroupTabsProvider);
      // 组被删空（且是未分组那种）它就该从 Tab 消失；此时选中键会失效，
      // 由页面与 notifier 的"键对不上就落到第一个 Tab"兜底。
    }
    return removed;
  }

  /// 撤销上一步删除（NekoBox `UndoSnackbarManager` 的 undo 分支）。
  Future<bool> restoreNode(ProxyEntityEntry row) async {
    final ok = await ref.read(proxyEntityRepositoryProvider).restoreNode(row);
    if (ok) ref.invalidate(proxyGroupTabsProvider);
    return ok;
  }

  /// 保存节点行 ✎ 改过的出站定义（NekoBox `*SettingsActivity` 的保存按钮）。
  ///
  /// 三件事，缺一不可（与删节点只有前两件不同）：
  /// 1. 实体表落库；
  /// 2. invalidate 列表 —— 地址行/协议名取自实体，不刷新就还是旧值；
  /// 3. **让内核换上新出站表** —— 组装产物 `<id>.entities.json` 由 `ConnectionRepository._start()`
  ///    现场生成，所以重载一次内核即可生效。用 `reconnect()` 而不是重启接管：它的契约是
  ///    「只动内核、不动接管状态」（`connection_notifier.dart:226`），编辑节点不该让用户掉线。
  ///
  /// 编辑的不是激活订阅 ⇒ 不用重载（内核一次只加载一份配置，下次切过去自然读到新值）。
  /// 手动分组的节点**总是**要重载 —— 它被追加进激活那份配置里，改完就该生效。
  Future<bool> updateNodePayload({
    String? profileId,
    int? groupId,
    required String tag,
    required String payload,
  }) async {
    loggy.debug("updating node payload: [$tag]");
    final ok = await ref
        .read(proxyEntityRepositoryProvider)
        .updateNodePayload(profileId: profileId, groupId: groupId, tag: tag, payload: payload);
    if (!ok) return false;
    ref.invalidate(proxyGroupTabsProvider);
    await _reloadCoreIfAffected(profileId: profileId, groupId: groupId);
    return true;
  }

  /// 手动新建分组（NekoBox `GroupSettingsActivity` 的保存 → `GroupManager.createGroup`）。
  /// 返回新组的主键；失败返回 null。
  Future<int?> createGroup({String? name, bool ungrouped = false}) async {
    final id = await ref
        .read(proxyEntityRepositoryProvider)
        .createGroup(name: name, ungrouped: ungrouped);
    if (id != null) ref.invalidate(proxyGroupTabsProvider);
    return id;
  }

  /// 确保存在「未分组」手动组（懒创建，照 NekoBox `DataStore.kt:56`），返回它的 id。
  ///
  /// 手动新建节点要用：节点必须有归属组，而库里可能一个手动组都没有。
  Future<int?> ensureUngroupedGroup() async {
    final id = await ref.read(proxyEntityRepositoryProvider).ensureUngroupedGroup();
    if (id != null) ref.invalidate(proxyGroupTabsProvider);
    return id;
  }

  /// 改分组名 / 删分组（含组内节点）。
  Future<bool> renameGroup({required int groupId, required String? name}) async {
    final ok = await ref.read(proxyEntityRepositoryProvider).renameGroup(groupId: groupId, name: name);
    if (ok) ref.invalidate(proxyGroupTabsProvider);
    return ok;
  }

  Future<bool> removeGroup(int groupId) async {
    final ok = await ref.read(proxyEntityRepositoryProvider).removeGroup(groupId);
    if (ok) {
      ref.invalidate(proxyGroupTabsProvider);
      // 组没了 ⇒ 它作为 Tab 立即消失；若当前正看着它，选中键会失效并落到第一个 Tab。
      // 组内节点随组一起删了，所以内核必须换配置（否则那些出站还挂在激活配置里）。
      await _reloadCoreIfAffected(groupId: groupId);
    }
    return ok;
  }

  /// 分组排序落库（NekoBox `GroupFragment` 拖拽 → `commitMove`）。
  ///
  /// [idsInDisplayOrder] = 拖拽结束后的分组 id 顺序（`ungrouped` 不在内 ——
  /// NekoBox 的 `getDragDirs` 对它返回 0）。只影响分组列表/Tab 的展示次序，
  /// 不改成员与节点 ⇒ 内核配置无关，不触发重载。
  Future<bool> moveGroups({required List<int> idsInDisplayOrder}) async {
    final ok = await ref.read(proxyEntityRepositoryProvider).moveGroups(idsInDisplayOrder: idsInDisplayOrder);
    if (ok) ref.invalidate(proxyGroupTabsProvider);
    return ok;
  }

  /// 清空分组（NekoBox 分组动作菜单的 `clear`：确认框 → `GroupManager.clearGroup`）。
  ///
  /// 与 [removeGroup] 不同：**组行保留**，只删组内节点（见 repo 的语义注释）。
  /// 但对内核的影响与删组相同 —— 出站表少了一整段节点，激活配置必须重载
  /// （订阅组只有那份订阅正被加载时才需要；手动组节点总在配置里 ⇒ 总要重载）。
  Future<bool> clearGroup(int groupId) async {
    final count = await ref.read(proxyEntityRepositoryProvider).clearGroupNodes(groupId);
    if (count < 0) return false;
    if (count > 0) {
      ref.invalidate(proxyGroupTabsProvider);
      await _reloadCoreIfAffected(groupId: groupId);
    }
    return true;
  }

  /// **手动新建节点**（NekoBox 节点页工具栏 Manual Settings → `ProfileSettingsActivity` 的
  /// `editingId == 0` 分支 → `ProfileManager.createProfile(groupId, bean)`）。
  ///
  /// 落组规则照 NekoBox `DataStore.selectedGroupForImport()`：手动节点进**手动组**
  /// （`type = BASIC`）—— 本项目的入口直接问用户"进哪个手动组"，
  /// 没有手动组时由调用方先建「未分组」（`ensureUngroupedGroup`）。
  ///
  /// 成功后把选中 Tab 切到目标组，让用户立刻看见新节点（NekoBox 的 `currentGroup()`
  /// 也是把 `selectedGroup` 指到当前组）。返回新节点行；重名 / 失败返回 null。
  Future<ProxyEntityEntry?> createNode({
    required int groupId,
    required String tag,
    required String type,
    required String payload,
  }) async {
    final created = await ref
        .read(proxyEntityRepositoryProvider)
        .createNode(groupId: groupId, tag: tag, type: type, payload: payload);
    if (created == null) return null;

    ref.invalidate(proxyGroupTabsProvider);
    await ref.read(selectedProxyGroupTagProvider.notifier).update(manualGroupTabKey(groupId));
    await _reloadCoreIfAffected(groupId: groupId);
    return created;
  }

  /// 写操作之后决定要不要让内核换配置。
  ///
  /// - 动的是**手动组**：[groupId] 非空 ⇒ 手动节点被追加进激活那份配置 ⇒ 总是要重载。
  /// - 动的是**订阅组**：只有那份订阅正在被内核加载时才重载。
  Future<void> _reloadCoreIfAffected({String? profileId, int? groupId}) async {
    final activeProfile = await ref.read(activeProfileProvider.future);
    if (activeProfile == null) return;
    final bool affected;
    if (groupId != null) {
      affected = true;
    } else {
      affected = profileId != null && profileId == activeProfile.id;
    }
    if (!affected) return;
    await ref.read(connectionNotifierProvider.notifier).reconnect(activeProfile);
  }

  /// UI 层的批量节点删除（去重）之后的重载入口 —— [_reloadCoreIfAffected] 的公开壳。
  Future<void> reloadCoreForGroup(int groupId) => _reloadCoreIfAffected(groupId: groupId);

  /// 同上，订阅组版本（只有那份订阅正被加载时才真重载）。
  Future<void> reloadCoreForProfile(String profileId) => _reloadCoreIfAffected(profileId: profileId);

  /// 测整组 / 测全部（内核 URL test）。
  ///
  /// **必须传空 tag**：内核 `commands.go` 的 `UrlTest` 在 `in.Tag == ""` 时走
  /// `UrlTestActive()`（内部硬编码用常量 `select`）；传组名会被当成**节点 tag**
  /// 去 `monitor.TestNow(组名)` —— 测一个不存在的出站。
  ///
  /// 所以这里不再接收组名：NekoBox 侧也没有"按组测速"这个概念，
  /// 组只是订阅（`GroupType` 只有 BASIC/SUBSCRIPTION），测速是工具栏的 URL Test。
  ///
  /// 进度对话框接线：防重入走 [connectionTestNotifierProvider]（NekoBox
  /// `DataStore.runningTest`）。NekoBox 的 urlTest 是应用侧逐节点 HTTP 探测、
  /// 有逐条 update；本项目的对应物是内核 RPC 空 tag 一次测全部 —— 拿不到
  /// 逐条回调，对话框只显示转圈 + 文案（计数不显示）。
  Future<void> urlTest() async {
    loggy.debug("testing all nodes of the active config");
    if (state case AsyncData()) {
      await ref.read(hapticServiceProvider.notifier).lightImpact();
      await ref
          .read(connectionTestNotifierProvider.notifier)
          .runUrlTest(
            body: () => ref
                .read(proxyRepositoryProvider)
                .urlTest('')
                .getOrElse((err) {
                  loggy.error("error testing group", err);
                  throw err;
                })
                .run(),
          );
    }
  }

  /// 清除测试结果（NekoBox ⋮ 菜单 `Clear test results`）。
  ///
  /// 清的是**实体列**（`status`/`ping`/`error`）——断开状态下列表显示的就是它们；
  /// 连接状态下的实时延迟来自内核贴值，重测一遍即可覆盖（不提供"内核清历史"）。
  /// 归属组照 [removeNode] 的约定：`profileId`（订阅组）或 `groupId`（手动组）。
  Future<bool> clearTestResults({String? profileId, int? groupId}) async {
    final count = await ref
        .read(proxyEntityRepositoryProvider)
        .clearTestResults(profileId: profileId, groupId: groupId);
    if (count >= 0) {
      // 离线骨架的行来自实体 —— invalidate 让列表立刻回到"未测速"显示。
      ref.invalidate(proxyGroupTabsProvider);
      return true;
    }
    return false;
  }

  /// 清空流量统计（NekoBox ⋮ 菜单 `Clear traffic statistics`，
  /// `ConfigurationFragment.kt:460-475`）。
  ///
  /// 清的是**实体列**（`tx`/`rx`）——与 [clearTestResults] 同理，连接中的实时流量
  /// 来自内核贴值，不受此影响。NekoBox 对此动作**无确认框也无 toast**，静默执行；
  /// 失败时才由调用方提示。
  /// 归属组照 [removeNode] 的约定：`profileId`（订阅组）或 `groupId`（手动组）。
  Future<bool> clearTrafficStats({String? profileId, int? groupId}) async {
    final count = await ref
        .read(proxyEntityRepositoryProvider)
        .clearTrafficStats(profileId: profileId, groupId: groupId);
    if (count >= 0) {
      // 节点卡当前不读实体 tx/rx（流量显示走内核实时值），但照 [clearTestResults]
      // 的同一逻辑 invalidate：未来实体列上屏时这里已经是对的。
      ref.invalidate(proxyGroupTabsProvider);
      return true;
    }
    return false;
  }

  /// 删除重复的服务器（NekoBox ⋮ 菜单 `action_remove_duplicate`，
  /// `ConfigurationFragment.kt:534-580`）。
  ///
  /// 纯应用侧 DB 操作，不碰内核 RPC（NekoBox 也是直接 `ProfileManager.deleteProfile2`）。
  /// 判重口径见 repo 的 `findDuplicateNodes`（地址 + 端口 + 类型，名字不参与）。
  /// 归属组照 [removeNode] 的约定。交互照 NekoBox：**先确认后删** ——
  /// UI 先调 [findDuplicateNodes] 拿名单弹确认框，同意后再调 [deleteNodes]。
  Future<List<ProxyEntityEntry>> findDuplicateNodes({String? profileId, int? groupId}) async {
    final repo = ref.read(proxyEntityRepositoryProvider);
    final nodes = switch ((profileId, groupId)) {
      (_, final int g) => (await repo.groupWithNodes(g))?.nodes ?? const <ProxyEntityEntry>[],
      (final String p, null) => (await repo.groupForProfile(p))?.nodes ?? const <ProxyEntityEntry>[],
      _ => const <ProxyEntityEntry>[],
    };
    return repo.findDuplicateNodes(nodes).duplicates;
  }

  /// 删除不可用节点（NekoBox ⋮ 菜单 `action_connection_test_delete_unavailable`，
  /// `ConfigurationFragment.kt:495-532`）。
  ///
  /// 判据照 NekoBox：`status != 0 && status != 1` —— 只有**测过且失败**的算不可用，
  /// 未测速（status=0）不误删。交互同去重：**先确认后删**，但 NekoBox 的确认框
  /// 只有一句 `delete_confirm_prompt`，不带名单（与去重不同）。
  /// 空名单不弹框（NekoBox `toClear.isNotEmpty()` 判定）。
  Future<List<ProxyEntityEntry>> findUnavailableNodes({String? profileId, int? groupId}) async {
    final repo = ref.read(proxyEntityRepositoryProvider);
    final nodes = switch ((profileId, groupId)) {
      (_, final int g) => (await repo.groupWithNodes(g))?.nodes ?? const <ProxyEntityEntry>[],
      (final String p, null) => (await repo.groupForProfile(p))?.nodes ?? const <ProxyEntityEntry>[],
      _ => const <ProxyEntityEntry>[],
    };
    return repo.findUnavailableNodes(nodes);
  }

  /// 去重的执行端（确认框同意之后）。删除后让内核换配置 —— 出站表少了节点。
  Future<bool> deleteNodes(List<ProxyEntityEntry> nodes) async {
    if (nodes.isEmpty) return true;
    // 手动组节点被追加进激活配置 ⇒ 删了必须重载；订阅组节点同理（还在出站表里）。
    // 但这里不知道各节点的归属 —— 由调用方（菜单处理器持有 activeTab）传参重载。
    final count = await ref.read(proxyEntityRepositoryProvider).deleteNodes(nodes);
    if (count < 0) return false;
    ref.invalidate(proxyGroupTabsProvider);
    return true;
  }

  /// TCP ping（NekoBox ⋮ 菜单的 tcp ping 项，`ConfigurationFragment.kt:694-832`
  /// 的 `pingTest(false)`）。
  ///
  /// **纯应用侧测速**：`Socket.connect(host, port)` 直连目标，不碰内核 RPC
  /// （NekoBox 同样是应用侧 `Socket`，不经 VPN 内部路由）。测的是"这台服务器
  /// 的 TCP 层通不通"，与连接状态无关，断开状态下也能测。
  ///
  /// 流程照 NekoBox：取节点 → 过滤不可测协议（`canTCPing` 白名单）→
  /// 并发 5（`connectionTestConcurrent`）→ 逐条写实体列 → invalidate 刷新列表。
  ///
  /// 与 NekoBox 的差异：它把"测试"和"进度"都放在 TestDialog 内部类里；本项目把
  /// 进度抽到 [connectionTestNotifierProvider]（对话框只是视图）。防重入也由它承担
  /// （NekoBox `DataStore.runningTest`）：`state.running` 为真时直接拒绝并返回 null。
  /// 取消语义照 `test.cancel`：worker 池见取消标记即停，**已测结果照常落库**。
  ///
  /// 返回测过的节点数；被防重入拒绝返回 null；失败返回 -1（调用方提示）。
  Future<int?> tcpPingNodes({String? profileId, int? groupId}) async {
    final testNotifier = ref.read(connectionTestNotifierProvider.notifier);
    // 防重入统一由 runTcpPing 承担（NekoBox `if (DataStore.runningTest) return`）——
    // 它返回 null 即被拒绝；这里不再重复判 state.running（判完到开测之间仍有窗口）。

    final repo = ref.read(proxyEntityRepositoryProvider);
    final nodes = switch ((profileId, groupId)) {
      (_, final int g) => (await repo.groupWithNodes(g))?.nodes ?? const <ProxyEntityEntry>[],
      (final String p, null) => (await repo.groupForProfile(p))?.nodes ?? const <ProxyEntityEntry>[],
      _ => const <ProxyEntityEntry>[],
    };
    // canTCPing 白名单：QUIC/UDP 系协议 TCP 握手无意义（hysteria/tuic/wireguard…）
    final testable = nodes.where((n) => canTcpPing(n.type)).toList();
    if (testable.isEmpty) return 0;

    return await testNotifier.runTcpPing(
      total: testable.length,
      body: (isCancelled, onProgress) async {
        // 并发 5 照 NekoBox `connectionTestConcurrent`：worker 池消费同一条队列。
        final results = <({int id, int status, int ping, String? error})>[];
        var cursor = 0;
        Future<void> worker() async {
          while (cursor < testable.length) {
            // 取消（NekoBox `if (!isActive) break`）：队列指针推到底即全员退出。
            if (isCancelled()) {
              cursor = testable.length;
              break;
            }
            final node = testable[cursor++];
            final address = serverAddressOfPayload(node.payload);
            // 地址解析不出的节点（怪 payload）跳过 —— 与 NekoBox 的 displayAddress 空值一致
            if (address.host.isEmpty || address.port <= 0) continue;
            final result = await tcpPingHost(address.host, address.port);
            // 取消发生在测速中途：这条结果丢弃（NekoBox 的 worker 被 cancel 后
            // 不再 update）。已完成的照常保留，收尾统一落库。
            if (isCancelled()) break;
            results.add((id: node.id, status: result.status, ping: result.ping, error: result.error));
            // 逐条推进度（NekoBox `test.update(profile)`）：节点名 + 结果摘要。
            // 文案用分类键（与 proxy_tile 状态位同一套），延迟直接给数字。
            onProgress(node.displayName, connectionTestResultKey(result));
          }
        }
        await Future.wait([for (var i = 0; i < 5; i++) worker()]);

        // 落库（NekoBox `ProfileManager.updateProfile(it)` + postReload 的等价物）：
        // 正常结束与取消都走到这里 —— NekoBox 的 cancel 路径同样把 test.results 落库。
        final count = await repo.updateTestResults(results);
        if (count < 0) return -1;
        // 离线骨架的延迟显示来自实体列 —— invalidate 让结果立刻上屏（同 clearTestResults）。
        ref.invalidate(proxyGroupTabsProvider);
        return results.length;
      },
    );
  }
}
