import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/common/qr_code_scanner_screen.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_summary.dart';
import 'package:hiddify/features/connection/widget/connection_fab.dart';
import 'package:hiddify/features/profile/add/add_profile_modal.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart'
    show chainProxiesOf, kChainEntityType, kConfigEntityType;
import 'package:hiddify/features/proxy/data/node_import.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/overview/add_profile_menu_spec.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/chain_settings_page.dart';
import 'package:hiddify/features/proxy/widget/config_settings_page.dart';
import 'package:hiddify/features/proxy/widget/connection_test_dialog.dart';
import 'package:hiddify/features/proxy/widget/manual_node_flow.dart';
import 'package:hiddify/features/proxy/widget/nk_capture_status_bar.dart';
import 'package:hiddify/features/proxy/widget/protocol_form_modal.dart';
import 'package:hiddify/features/proxy/widget/proxies_menu_button.dart';
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
    final activeKey = tabs.isEmpty ? "" : (tabs.any((t) => t.key == selectedKey) ? selectedKey : tabs.first.key);
    final proxies = ref.watch(proxiesOverviewNotifierProvider);

    // 筛选条件是纯本地的：这个 provider 在连接后会每秒重发一次（核心要刷新每个
    // 出口的字节数），所以不能把输入框内容塞进 provider 里，否则输入焦点会被冲掉。
    final query = useState('');
    final searchController = useTextEditingController();
    // 搜索行显隐（NekoBox：搜索由 toolbar 图标触发，行默认收起）
    final showSearch = useState(false);
    // ＋ 菜单控制器（NekoBox action_add）
    final addMenuController = useMemoized(MenuController.new);
    // 列表 / 网格（落盘，见 proxiesListViewProvider）
    final listView = ref.watch(proxiesListViewProvider);

    // 连接状态（给 FAB 四态与底部状态栏用）。四态展示归一映射在
    // connectionSummaryProvider（底部状态栏/抽屉头共用）与 connectionFabSpec（FAB），
    // 页面不再双写。
    final connectionStatus = ref.watch(connectionNotifierProvider).valueOrNull;

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
    final activeNodeInUse = connectionNodeInUse(connectionStatus) && activeTabIsActive;
    // NekoBox `StatsBar.changeState` 用 postWhenStarted + 100ms 延迟显示/隐藏。
    // 这也避免 Connected 的同一 build 帧里首次挂载 StatsBar 时，新建 stats
    // 订阅同步通知已经建好的侧栏（Flutter 会报 markNeedsBuild during build）。
    final statsBarVisible = useState(false);
    useEffect(() {
      final timer = Timer(const Duration(milliseconds: 100), () {
        statsBarVisible.value = captureStatsBarVisible(connectionStatus);
      });
      return timer.cancel;
    }, [connectionStatus]);
    final showStatsBar = statsBarVisible.value;

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
          // ＋ 菜单：NekoBox 复刻 · add_profile_menu.xml 的 action_add 子树
          //（扫码/剪贴板/文件/手动输入▸16协议；末项「添加订阅」为本项目
          // 架构差异追加——订阅是一等实体，NekoBox 走分组设置）。规格投影 =
          // add_profile_menu_spec.dart（L1 测试打它）。
          MenuAnchor(
            controller: addMenuController,
            menuChildren: [
              for (final entry in nkAddProfileMenu(showScanQr: !PlatformUtils.isDesktop))
                _buildAddProfileMenuEntry(context, ref, entry),
            ],
            child: IconButton(
              onPressed: addMenuController.open,
              tooltip: t.pages.proxies.addMenu.addProfile,
              icon: const Icon(Icons.note_add_rounded),
            ),
          ),
          // 更多菜单：NekoBox 复刻 · 1:1 八项（规格 = add_profile_menu.xml 的
          // action_misc，顺序/文案/排序 radio 子菜单全照源）。结构与行为抽到
          // [ProxiesMenuButton] —— 可独立做结构对等测试（无路由/无搜索依赖）。
          ProxiesMenuButton(activeTab: activeTab),
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
      // NekoBox `ServiceButton`：Idle/Stopping 禁用，Connecting/Connected 可点停止。
      floatingActionButton: ConnectionFab(
        status: connectionStatus,
        t: t,
        onPressed: () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
      ),
      // 底部状态栏（NekoBox `StatsBar` 规格）：**仅已连接时显示**（StatsBar.changeState
      // 非 Connected 一律 performHide）；内容 = 状态文本（含点击测连接提示）+ 当前节点
      // + ▲▼ 实时速率。未连接时整条隐藏（列表底部 padding 随之收窄）。
      bottomNavigationBar: showStatsBar ? const _CaptureStatusBar() : null,
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
                        padding: EdgeInsets.only(bottom: showStatsBar ? 86 : 24),
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
                            padding: EdgeInsets.only(bottom: showStatsBar ? 86 : 24),
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
    // ✎ 只在"这一行是实体 + （该协议有表单 或 是 chain / config）"时给出 —— 与 🗑 同一条
    // 判据，保证"能点到的节点一定能改"（表单的规格查表见 protocol_form.dart）。
    final canEdit =
        tab != null &&
        (protocolFormSpecFor(proxy.type) != null || proxy.type == kChainEntityType || proxy.type == kConfigEntityType);
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
    // chain 走自己的编辑页（NekoBox `ProxyEntity.settingIntent()` 按 type 分发到
    // `ChainSettingsActivity` 的对应物）：不读出站 JSON —— 它的 payload 是成员清单。
    if (proxy.type == kChainEntityType) {
      final chainNode = await ref.read(proxyEntityRepositoryProvider).nodeByTagAnyGroup(proxy.tag);
      if (!context.mounted) return;
      if (chainNode == null) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      final members = chainProxiesOf(chainNode.payload) ?? const <String>[];
      await showChainSettingsSheet(tag: chainNode.tag, chainGroupId: chainNode.groupId, initialProxies: members);
      return;
    }
    // config 走 ConfigSettings（NekoBox `settingIntent()` 的 `ConfigSettingsActivity`
    // 对应物）：payload 是用户手写的整份 JSON（出站或完整配置），字段表单不适用。
    // 不读出站 JSON —— `outboundJsonProvider` 的"配置回落"只对出站有意义，
    // config 实体以库里的 payload 为唯一权威（与 chain 同一原则）。
    if (proxy.type == kConfigEntityType) {
      final configNode = await ref.read(proxyEntityRepositoryProvider).nodeByTagAnyGroup(proxy.tag);
      if (!context.mounted) return;
      if (configNode == null) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      await showConfigSettingsSheet(
        tag: configNode.tag,
        configGroupId: configNode.groupId,
        initialPayload: configNode.payload,
      );
      return;
    }
    final payload = await ref.read(outboundJsonProvider(proxy.tag).future);
    if (!context.mounted) return;
    if (payload == null) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.form.jsonInvalid);
      return;
    }
    // 节点级覆写初值（切片 8.5 ⋮ 菜单回显）：列表以实体为准，覆写列同源
    final node = await ref.read(proxyEntityRepositoryProvider).nodeByTagAnyGroup(proxy.tag);
    if (!context.mounted) return;
    await showProtocolFormSheet(
      tag: proxy.tag,
      type: proxy.type,
      payloadJson: payload,
      profileId: tab.profileId.isEmpty ? null : tab.profileId,
      groupId: tab.groupId,
      initialOverrides: NodeOverrides(
        customOutbound: node?.customOutbound ?? '',
        customConfig: node?.customConfig ?? '',
      ),
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

  Widget _buildAddProfileMenuEntry(BuildContext context, WidgetRef ref, NkAddProfileMenuEntry entry) {
    final t = ref.read(translationsProvider).requireValue;
    final children = entry.children;
    if (children != null) {
      return SubmenuButton(
        menuChildren: [for (final child in children) _buildAddProfileMenuEntry(context, ref, child)],
        child: Text(entry.label(t)),
      );
    }
    return MenuItemButton(onPressed: () => _runAddProfileAction(context, ref, entry), child: Text(entry.label(t)));
  }

  /// ＋ 菜单执行器 —— NekoBox `ConfigurationFragment` 的 action_add 对应路径：
  /// 节点输入走 BASIC 组导入；HTTP(S) 等订阅输入转入独立订阅表单。
  Future<void> _runAddProfileAction(BuildContext context, WidgetRef ref, NkAddProfileMenuEntry entry) async {
    switch (entry.action!) {
      case NkAddProfileAction.scanQr:
        final content = await showQrCodeScanner();
        if (content == null || content.isEmpty || !context.mounted) return;
        await _importNodeInput(context, ref, content);
      case NkAddProfileAction.importClipboard:
        final content = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text ?? '');
        if (!context.mounted) return;
        await _importNodeInput(context, ref, content);
      case NkAddProfileAction.importFile:
        final result = await FilePicker.platform.pickFiles();
        if (result == null || result.files.single.path == null || !context.mounted) return;
        final file = File(result.files.single.path!);
        if (!await file.exists()) return;
        if (!context.mounted) return;
        final bytes = await file.readAsBytes();
        if (!context.mounted) return;
        final inputs = decodeNodeImportFile(result.files.single.name, bytes);
        if (inputs == null) {
          ref
              .read(inAppNotificationControllerProvider)
              .showErrorToast(ref.read(translationsProvider).requireValue.errors.unexpected);
          return;
        }
        await _importNodeFiles(context, ref, inputs);
      case NkAddProfileAction.manualNode:
        await startManualNodeFlow(context, ref, initialProtocol: entry.protocol);
      case NkAddProfileAction.addSubscription:
        await showAddProfileSheet(manual: true);
    }
  }

  Future<void> _importNodeInput(BuildContext context, WidgetRef ref, String raw) =>
      _importNodeInputs(context, ref, [raw]);

  Future<void> _importNodeFiles(BuildContext context, WidgetRef ref, Iterable<NodeImportFileEntry> files) async {
    final t = ref.read(translationsProvider).requireValue;
    final outcome = await ref.read(proxiesOverviewNotifierProvider.notifier).importNodeFiles(files);
    if (!context.mounted) return;
    await _handleNodeImportOutcome(context, ref, t, outcome);
  }

  Future<void> _importNodeInputs(BuildContext context, WidgetRef ref, Iterable<String> rawInputs) async {
    final t = ref.read(translationsProvider).requireValue;
    final outcome = await ref.read(proxiesOverviewNotifierProvider.notifier).importNodeInputs(rawInputs);
    if (!context.mounted) return;
    await _handleNodeImportOutcome(context, ref, t, outcome);
  }

  Future<void> _handleNodeImportOutcome(
    BuildContext context,
    WidgetRef ref,
    TranslationsEn t,
    NodeImportOutcome outcome,
  ) async {
    if (!context.mounted) return;
    switch (outcome) {
      case NodeImportSucceeded(:final count):
        ref.read(inAppNotificationControllerProvider).showSuccessToast('${t.pages.proxies.form.created} ($count)');
      case NodeImportNeedsSubscription(:final url):
        final confirmed = await ref
            .read(dialogNotifierProvider.notifier)
            .showConfirmation(
              title: t.dialogs.confirmation.addProfileByDeepLinkWarning.title,
              message: t.dialogs.confirmation.addProfileByDeepLinkWarning.message(host: Uri.parse(url).host),
            );
        if (confirmed && context.mounted) await showAddProfileSheet(url: url);
      case NodeImportFailed():
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
    }
  }
}

/// 底部状态栏页面薄壳：订阅三面 provider（翻译/连接摘要/stats 流）后交给公共
/// 部件 [NkCaptureStatusBar]（纯参数注入，规格注释见该部件头）。
class _CaptureStatusBar extends ConsumerWidget {
  const _CaptureStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final summary = ref.watch(connectionSummaryProvider);
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    return NkCaptureStatusBar(
      t: t,
      summary: summary,
      uplink: stats.uplink.toInt(),
      downlink: stats.downlink.toInt(),
      onTap: () => unawaited(
        runConnectionTest(
          context,
          ref,
          // 进度 = 逐节点独立探针（n/N + 当前节点 + 可取消），由 urlTest
          // 内部的 runTcpPing 承担（守卫纪律：一次用户动作一层守卫）。
          start: () => ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(),
        ),
      ),
    );
  }
}
