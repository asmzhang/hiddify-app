import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_summary.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/notifier/connection_test_notifier.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/connection_test_dialog.dart';
import 'package:hiddify/features/proxy/widget/protocol_form_modal.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
import 'package:hiddify/features/settings/overview/quick_settings_modal.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 代理页用列表还是网格。**落盘** —— 否则每次进页面都重置回列表，用户切过网格等于白切。
/// 默认列表：一行一个节点、信息更全，同行（v2rayN / nekoray）都是这个形态。
final proxiesListViewProvider = PreferencesNotifier.createAutoDispose("proxies_list_view", true);

class ProxiesOverviewPage extends HookConsumerWidget with PresLogger {
  const ProxiesOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    // 分组清单来自**统一数据源**：订阅分组（一份订阅 = 一个组）+ 手动分组。
    // 展开成 Tab —— NekoBox 的 `GroupType` 只有 BASIC / SUBSCRIPTION，订阅内的 selector/urltest
    // 不成为分组（`RawUpdater.kt:768-787`），所以不存在"自动选择"这种 Tab。
    final tabs = ref.watch(proxyGroupTabsProvider).valueOrNull ?? const <ProxyGroupTab>[];
    final selectedKey = ref.watch(selectedProxyGroupTagProvider);
    // 选中的键不存在（首次使用 / 订阅被删 / 历史遗留的纯组名）⇒ 落到第一个 Tab，
    // 与 notifier 里的回落规则保持一致，否则高亮和列表会对不上。
    final activeKey = tabs.isEmpty
        ? ""
        : (tabs.any((t) => t.key == selectedKey) ? selectedKey : tabs.first.key);
    final proxies = ref.watch(proxiesOverviewNotifierProvider);
    final sortBy = ref.watch(proxiesSortNotifierProvider);

    // 筛选条件是纯本地的：这个 provider 在连接后会每秒重发一次（核心要刷新每个
    // 出口的字节数），所以不能把输入框内容塞进 provider 里，否则输入焦点会被冲掉。
    final query = useState('');
    final searchController = useTextEditingController();
    // 搜索行显隐（NekoBox：搜索由 toolbar 图标触发，行默认收起）
    final showSearch = useState(false);
    // 列表 / 网格（落盘，见 proxiesListViewProvider）
    final listView = ref.watch(proxiesListViewProvider);

    // 连接状态（给 FAB 四态与底部状态栏用）：区分 已连接 / 连接中 / 错误 / 未连接
    final connectionStatus = ref.watch(connectionNotifierProvider).valueOrNull;
    final NkConnectionState nkState;
    if (connectionStatus is Connected) {
      nkState = NkConnectionState.connected;
    } else if (connectionStatus is Connecting || connectionStatus is Disconnecting) {
      nkState = NkConnectionState.connecting;
    } else if (connectionStatus is Disconnected && connectionStatus.connectionFailure != null) {
      nkState = NkConnectionState.error;
    } else {
      nkState = NkConnectionState.disconnected;
    }

    // 当前 Tab —— 删除/编辑节点要知道"删的是哪个组里的"。
    ProxyGroupTab? activeTab;
    for (final tab in tabs) {
      if (tab.key == activeKey) {
        activeTab = tab;
        break;
      }
    }
    // 照 NekoBox `ConfigurationFragment.kt:1621-1625` 的 `started`：
    // **正在使用的那个节点不允许编辑/删除** —— 条件是"它是当前选中 + 它所在的组
    // 正在被内核加载 + 连接已建立"。手动分组的节点挂在激活那份配置里，
    // 所以判据是"有激活订阅"而不是"组属于激活订阅"。
    final activeProfileId = ref.watch(activeProfileProvider).valueOrNull?.id;
    final bool activeTabIsActive;
    if (activeTab == null) {
      activeTabIsActive = false;
    } else if (activeTab.profileId.isEmpty) {
      activeTabIsActive = activeProfileId != null;
    } else {
      activeTabIsActive = activeTab.profileId == activeProfileId;
    }
    final activeNodeInUse = connectionStatus is Connected && activeTabIsActive;

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    return Scaffold(
      appBar: AppBar(
        // 手机端：汉堡键打开左侧导航抽屉；PC 端无（左侧是常驻 rail）
        // NekoBox 复刻 · Toolbar 主色底（与分组 Tab 连成一体）。
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
        title: Text(t.pages.proxies.title),
        actions: [
          // NekoBox 工具栏三件套：搜索 / ＋ / 更多。
          IconButton(
            onPressed: () => showSearch.value = !showSearch.value,
            icon: const Icon(FluentIcons.search_24_regular),
            tooltip: t.pages.proxies.search,
          ),
          const IconButton(onPressed: showAddProfileSheet, icon: Icon(Icons.add_rounded)),
          // 更多菜单：批量测速 / 排序 / 路由规则（原工具条上的散装按钮收拢于此）。
          // NekoBox 对照（`res/menu/add_profile_menu.xml` ⋮ 八项）：更新订阅、清流量统计、
          // 去重、tcp ping、url test、清结果、删不可用、排序。已补：更新订阅 / 清结果 /
          // 删不可用 / 去重 / tcp ping / url test / 排序 + hiddify 特有的路由入口；
          // 余项（清流量统计）待后续批次。
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'urltest' => () async {
                // NekoBox `urlTest()`（ConfigurationFragment.kt:834-901）：先弹进度框
                // 再开测。本项目的内核 RPC 拿不到逐条进度，对话框只有转圈 + 文案。
                try {
                  await runConnectionTest(
                    context,
                    ref,
                    // runUrlTest：null = 防重入拒绝（对话框随即退回），true = 完成。
                    // 包成 int?：urlTest 无计数语义，完成即 0（对话框不显示计数）。
                    start: () async {
                      final ok = await ref
                          .read(connectionTestNotifierProvider.notifier)
                          .runUrlTest(body: () => ref.read(proxiesOverviewNotifierProvider.notifier).urlTest());
                      return ok == true ? 0 : null;
                    },
                  );
                } catch (_) {
                  if (context.mounted) {
                    ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                  }
                }
              }(),
              'clearResults' => () async {
                final tab0 = activeTab;
                final ok = await ref
                    .read(proxiesOverviewNotifierProvider.notifier)
                    .clearTestResults(
                      profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
                      groupId: tab0?.groupId,
                    );
                if (!ok) {
                  ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                }
              }(),
              'clearTraffic' => () async {
                final tab0 = activeTab;
                // NekoBox `ConfigurationFragment.kt:460-475`：无确认框静默执行，
                // 失败也不弹（本项目失败时提示一次，超出规格的防御性）。
                final ok = await ref
                    .read(proxiesOverviewNotifierProvider.notifier)
                    .clearTrafficStats(
                      profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
                      groupId: tab0?.groupId,
                    );
                if (!ok) {
                  ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                }
              }(),
              'removeDuplicate' => () async {
                final tab0 = activeTab;
                // NekoBox `ConfigurationFragment.kt:545-559`：先列重复者名单确认（上限 20 条），
                // 同意后才真删。空名单不弹框（NekoBox `toClear.isNotEmpty()` 判定）。
                final duplicates = await ref
                    .read(proxiesOverviewNotifierProvider.notifier)
                    .findDuplicateNodes(
                      profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
                      groupId: tab0?.groupId,
                    );
                if (!context.mounted) return;
                if (duplicates.isEmpty) {
                  ref.read(inAppNotificationControllerProvider).showInfoToast(t.pages.proxies.msg.noDuplicates);
                  return;
                }
                final names = [
                  for (final (index, node) in duplicates.indexed)
                    if (index < 20) node.displayName else if (index == 20) '......' else null,
                ].whereType<String>();
                final confirmed = await ref
                    .read(dialogNotifierProvider.notifier)
                    .showConfirmation(
                      title: t.dialogs.confirmation.deduplicate.title,
                      message: '${t.dialogs.confirmation.deduplicate.msg}\n${names.join('\n')}',
                    );
                if (!confirmed || !context.mounted) return;
                final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).deleteNodes(duplicates);
                if (!ok) {
                  ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                  return;
                }
                // 出站表少了节点 ⇒ 内核要换配置（与删组/清空分组同理）。
                if (tab0?.groupId != null) {
                  await ref
                      .read(proxiesOverviewNotifierProvider.notifier)
                      .reloadCoreForGroup(tab0!.groupId!);
                } else if (tab0?.profileId case final String pid) {
                  await ref.read(proxiesOverviewNotifierProvider.notifier).reloadCoreForProfile(pid);
                }
              }(),
              'tcpPing' => () async {
                // NekoBox `pingTest(false)`（ConfigurationFragment.kt:694-832）：
                // 先弹进度框再开测，逐条回报（转圈 + 节点名 + n/N 计数），
                // 取消时已测结果照落库。无确认框，结果写实体列。
                final tab0 = activeTab;
                try {
                  final count = await runConnectionTest(
                    context,
                    ref,
                    start: () => ref
                        .read(proxiesOverviewNotifierProvider.notifier)
                        .tcpPingNodes(
                          profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
                          groupId: tab0?.groupId,
                        ),
                  );
                  if (count != null && count < 0 && context.mounted) {
                    ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                  }
                } catch (_) {
                  if (context.mounted) {
                    ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                  }
                }
              }(),
              'deleteUnavailable' => () async {
                // NekoBox `ConfigurationFragment.kt:495-532`：先确认（一句
                // delete_confirm_prompt，不带名单），同意后真删。
                // 空名单不弹框（toClear.isNotEmpty() 判定），只 toast。
                final tab0 = activeTab;
                final unavailable = await ref
                    .read(proxiesOverviewNotifierProvider.notifier)
                    .findUnavailableNodes(
                      profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
                      groupId: tab0?.groupId,
                    );
                if (!context.mounted) return;
                if (unavailable.isEmpty) {
                  ref.read(inAppNotificationControllerProvider).showInfoToast(t.pages.proxies.msg.noUnavailable);
                  return;
                }
                final confirmed = await ref
                    .read(dialogNotifierProvider.notifier)
                    .showConfirmation(
                      title: t.dialogs.confirmation.deleteUnavailable.title,
                      message: t.dialogs.confirmation.deleteUnavailable.msg,
                    );
                if (!confirmed || !context.mounted) return;
                final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).deleteNodes(unavailable);
                if (!ok) {
                  ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                  return;
                }
                // 出站表少了节点 ⇒ 内核要换配置（与去重同理）。
                if (tab0?.groupId != null) {
                  await ref
                      .read(proxiesOverviewNotifierProvider.notifier)
                      .reloadCoreForGroup(tab0!.groupId!);
                } else if (tab0?.profileId case final String pid) {
                  await ref.read(proxiesOverviewNotifierProvider.notifier).reloadCoreForProfile(pid);
                }
              }(),
              'updateSubscriptions' =>
                ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
              'sort' => () async {
                final selected = await ref
                    .read(dialogNotifierProvider.notifier)
                    .showSettingPicker<ProxiesSort>(
                      title: t.pages.proxies.sort,
                      selected: sortBy,
                      onReset: () => ref.read(proxiesSortNotifierProvider.notifier).update(ProxiesSort.values.first),
                      options: ProxiesSort.values,
                      getTitle: (e) => e.present(t),
                    );
                if (selected != null) {
                  await ref.read(proxiesSortNotifierProvider.notifier).update(selected);
                }
              }(),
              'route' => context.goNamed('routingOptions'),
              _ => null,
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'urltest', child: Text(t.pages.proxies.testAll)),
              PopupMenuItem(value: 'clearResults', child: Text(t.pages.proxies.clearTestResults)),
              PopupMenuItem(value: 'clearTraffic', child: Text(t.pages.proxies.clearTrafficStats)),
              PopupMenuItem(value: 'deleteUnavailable', child: Text(t.pages.proxies.deleteUnavailable)),
              PopupMenuItem(value: 'removeDuplicate', child: Text(t.pages.proxies.removeDuplicate)),
              PopupMenuItem(value: 'tcpPing', child: Text(t.pages.proxies.tcpPing)),
              PopupMenuItem(value: 'updateSubscriptions', child: Text(t.pages.proxies.updateSubscriptions)),
              PopupMenuItem(value: 'sort', child: Text(t.pages.proxies.sort)),
              PopupMenuItem(value: 'route', child: Text(t.pages.settings.routing.title)),
            ],
          ),
          const Gap(8),
        ],
        // NekoBox 复刻 · 分组 Tab 紧贴 Toolbar、同 primary 底、<2 组隐藏（layout_group_list.xml）。
        // 搜索行改为点搜索图标后折叠出现（NekoBox 的搜索也是图标触发的），排序/网格开关收在行尾。
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(
            (tabs.length > 1 ? 46.0 : 0.0) + (showSearch.value || query.value.isNotEmpty ? 56.0 : 0.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tabs.length > 1)
                SizedBox(
                  height: 46,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: tabs.length,
                      separatorBuilder: (context, index) => const Gap(2),
                      itemBuilder: (context, index) {
                        final tab = tabs[index];
                        final selected = tab.key == activeKey;
                        return InkWell(
                          onTap: () => ref.read(selectedProxyGroupTagProvider.notifier).update(tab.key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: selected ? Theme.of(context).colorScheme.onPrimary : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              tab.label,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: selected
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onPrimary.withValues(alpha: .6),
                                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (showSearch.value || query.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: searchController,
                          onChanged: (value) => query.value = value,
                          autofocus: showSearch.value,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: t.pages.proxies.search,
                            prefixIcon: const Icon(FluentIcons.search_16_regular, size: 18),
                            suffixIcon: query.value.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(FluentIcons.dismiss_16_regular, size: 18),
                                    tooltip: t.common.reset,
                                    onPressed: () {
                                      searchController.clear();
                                      query.value = '';
                                    },
                                  ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const Gap(8),
                      // 列表 / 网格切换（视图偏好，收在搜索行尾）
                      IconButton(
                        onPressed: () => ref.read(proxiesListViewProvider.notifier).update(!listView),
                        icon: Icon(listView ? FluentIcons.grid_24_regular : FluentIcons.list_24_regular),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      // NekoBox 复刻 · FAB = 连接开关（对标 ServiceButton 四态）：
      // stopped=播放、connecting/disconnecting=转圈（禁点）、connected=停止。
      // 测速入口不在这 —— 那是配置动作，连接才是这个页面唯一的"大按钮"。
      floatingActionButton: FloatingActionButton(
        onPressed: connectionStatus is Connecting || connectionStatus is Disconnecting
            ? null
            : () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
        // 这个按钮是**连接开关**：未连接时显示「连接」（动作名），不是「点击连接」。
        tooltip: switch (nkState) {
          NkConnectionState.connected => t.connection.connected,
          NkConnectionState.connecting => t.connection.connecting,
          _ => t.connection.connect,
        },
        child: connectionStatus is Connecting || connectionStatus is Disconnecting
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Icon(nkState == NkConnectionState.connected ? FluentIcons.stop_24_filled : FluentIcons.play_24_filled),
      ),
      // 底部状态栏：接管状态 + 当前节点 + 实时速率。
      // 原来这些信息分散在首页（当前代理条）和侧栏，合并后集中在这里常驻。
      // **移动端也保留** —— 同行（NekoBoxForAndroid 的 `StatsBar`）手机端就有这一条：
      // ↑↓ 速率 + 状态。它落在"列表"和"外层底部导航"之间，只是多一条、不重叠。
      bottomNavigationBar: const _CaptureStatusBar(),
      body: proxies.when(
        data: (group) {
          if (group == null) return Center(child: Text(t.pages.proxies.empty));

          final query0 = query.value.trim().toLowerCase();
          // NekoBox 复刻 · 只列订阅原始节点：组类出站（selector/urltest/balancer）由
          // `parseSubscriptionGroup` 在解析阶段就过滤掉了，这里再挡一道，
          // 保证以后万一有组类条目混进来也不会显示成节点。
          final rawItems = group.items.where((e) => !e.isGroup).toList();
          final items = query0.isEmpty
              ? rawItems
              : rawItems
                    .where(
                      (e) =>
                          e.tagDisplay.toLowerCase().contains(query0) ||
                          e.tag.toLowerCase().contains(query0) ||
                          e.type.toLowerCase().contains(query0),
                    )
                    .toList();

          return Column(
            children: [
              // NekoBox 复刻 · 列表上方不加任何"胖卡/横幅"——分组 Tab 之下直接是节点。
              // 旧版的订阅摘要卡（ProfileTile isMain）与配置/分组页的紧凑三行卡信息重复，
              // 拥挤且重复展示，已删；订阅摘要由分组 Tab 的"全部/订阅名"承担。
              // 「未连接」预选横幅同理：当前选中已由卡片左缘主色条标明。
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text(t.pages.proxies.empty))
                    // 列表视图（默认）：一行一个节点，信息更全、扫读更快 ——
                    // 同行（v2rayN / NekoBox）都是列表；网格留给宽屏。
                    : listView
                    ? ListView.builder(
                        padding: const EdgeInsets.only(bottom: 86),
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _tile(context, items[index], group, ref, activeTab, activeNodeInUse, items.length),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final crossAxisCount = PlatformUtils.isMobile && width < 600
                              ? 1
                              : max(1, (width / 268).floor());
                          return GridView.builder(
                            padding: const EdgeInsets.only(bottom: 86),
                            itemCount: items.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              mainAxisExtent: 92,
                            ),
                            itemBuilder: (context, index) =>
                            _tile(context, items[index], group, ref, activeTab, activeNodeInUse, items.length),
                          );
                        },
                      ),
              ),
              // 「快捷设置」把手 —— 原来在首页底部（合并后不能丢）
              if (ref.watch(hasAnyProfileProvider).value ?? false)
                Center(
                  child: Material(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                    child: InkWell(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                      onTap: () => showQuickSettingsSheet(),
                      child: SizedBox(
                        height: 32,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(t.pages.home.quickSettings),
                              const Gap(4),
                              const Icon(Icons.arrow_drop_up_rounded, size: 16),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        error: (error, stackTrace) => Center(child: Text(t.presentShortError(error))),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  /// Tab 标签 = **订阅名**。
  ///
  /// 一份订阅只有一个分组、组名就是订阅名（NekoBox：`GroupType` 只有 BASIC/SUBSCRIPTION，
  /// 订阅内分组不成为分组），所以这里不需要再拼组名 —— 拼了会变成
  /// "云霄 · 云霄"这种重复。
  ///
  /// 列表和网格共用同一个节点项 —— 避免两处各写一遍（改一处漏一处）。
  Widget _tile(
    BuildContext context,
    OutboundInfo proxy,
    OutboundGroup group,
    WidgetRef ref,
    ProxyGroupTab? tab,
    bool nodeInUse,
    int nodeCount,
  ) {
    final isSelected = group.selected == proxy.tag;
    // ✎ 只在"这一行是实体 + 该协议有表单"时给出 —— 与 🗑 同一条判据，
    // 保证"能点到的节点一定能改"（表单的规格查表见 protocol_form.dart）。
    final canEdit = tab != null && protocolFormSpecFor(proxy.type) != null;
    return ProxyTile(
      proxy,
      selected: isSelected,
      onTap: () async {
        await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
      },
      onEdit: canEdit ? () => _editNode(context, ref, tab, proxy) : null,
      // 🗑 只在实体层可用时给出（列表还在走配置回落时没有实体行可删）
      onDelete: tab == null ? null : () => _deleteNode(context, ref, tab, proxy),
      // 正在使用的节点不许编辑/删除（NekoBox `ConfigurationFragment.kt:1624-1625 isEnabled = !started`）
      editEnabled: !(isSelected && nodeInUse),
      // 只剩一个节点时也不许删 —— 空实体集会让组装回落基准（＝节点"复活"），
      // 语义不清，索性禁止（决策 D1，见 docs/audit/2026-09-15-full-logic-audit.md §5）。
      // 编辑不受这条限制（改参数不会让集合变空）。
      deleteEnabled: !(isSelected && nodeInUse) && nodeCount > 1,
    );
  }

  /// 编辑节点 —— 照 NekoBox `ConfigurationFragment.kt:1594` 的 ✎：
  /// 打开**该协议自己的设置页**（`proxyEntity.settingIntent()` → `ui/profile/*SettingsActivity`）。
  ///
  /// 出站 JSON 取 [outboundJsonProvider]（实体优先、配置回落），与节点「分享」同源 ——
  /// 所以"能分享的就能编辑"。真落到保存时，实体行不存在会被写接口拒掉（不会写坏配置）。
  Future<void> _editNode(BuildContext context, WidgetRef ref, ProxyGroupTab tab, OutboundInfo proxy) async {
    final t = ref.read(translationsProvider).requireValue;
    final payload = await ref.read(outboundJsonProvider(proxy.tag).future);
    if (!context.mounted) return;
    if (payload == null) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.form.jsonInvalid);
      return;
    }
    await showProtocolFormSheet(
      tag: proxy.tag,
      type: proxy.type,
      payloadJson: payload,
      profileId: tab.profileId.isEmpty ? null : tab.profileId,
      groupId: tab.groupId,
    );
  }

  /// 删除节点 —— 照 NekoBox `ConfigurationFragment.kt:1602-1608` + `UndoSnackbarManager`：
  /// **立刻从列表移除，并给一条带「撤销」的提示**；撤销则把那一行原样放回。
  ///
  /// 差异说明：NekoBox 是"延迟落库（Snackbar 消失时才 commit）+ 撤销"，这里是
  /// "立即落库 + 撤销时重新插入" —— 用户可见行为一致（都是"删了能撤回"），
  /// 少一层待提交队列，也就不存在"离开页面时漏提交"的风险。
  Future<void> _deleteNode(BuildContext context, WidgetRef ref, ProxyGroupTab tab, OutboundInfo proxy) async {
    final t = ref.read(translationsProvider).requireValue;
    final messenger = ScaffoldMessenger.of(context);
    final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);

    final removed = await notifier.removeNode(
      profileId: tab.profileId.isEmpty ? null : tab.profileId,
      groupId: tab.groupId,
      tag: proxy.tag,
    );
    if (removed == null) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(t.pages.proxies.msg.nodeRemoved),
        action: SnackBarAction(
          label: t.common.undo,
          onPressed: () async {
            final restored = await notifier.restoreNode(removed);
            if (!restored) ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
          },
        ),
      ),
    );
  }
}

/// 底部状态栏（NekoBox `StatsBar` 规格）：主色底 + 白字，
/// 内容 = 接管状态点 + 当前节点 + ↑↓ 实时速率 + 连接状态。
///
/// 这三样原来分散在首页（当前代理条）和左侧栏（统计卡），合并成一页之后集中在这里常驻，
/// 任何滚动位置都能看到"现在到底连上没、走的是谁"。
///
/// 节点/接管状态取自 [connectionSummaryProvider]（与抽屉头共用一份口径），
/// 本组件只负责"速率"这一项自己的数据（[statsNotifierProvider]）。
class _CaptureStatusBar extends ConsumerWidget {
  const _CaptureStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(connectionSummaryProvider);
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();

    // 白字（主色底上），与 NekoBox 的 StatsBar 一致。
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimary);
    return Material(
      color: theme.colorScheme.primary,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // 亮绿点 = 接管中；半透明白点 = 没接管（内核可能仍在跑，只是流量没走代理）
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: summary.capturing
                      ? Colors.lightGreenAccent
                      : theme.colorScheme.onPrimary.withValues(alpha: .4),
                ),
              ),
              const Gap(8),
              if (summary.nodeName != null)
                Flexible(
                  child: Text(summary.nodeName!, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
              const Spacer(),
              Text("↑ ${stats.uplink.toInt().speed()}", style: style),
              const Gap(10),
              Text("↓ ${stats.downlink.toInt().speed()}", style: style),
            ],
          ),
        ),
      ),
    );
  }
}
