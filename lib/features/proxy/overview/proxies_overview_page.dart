import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/features/connection/model/connection_status.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/connection/notifier/system_proxy_notifier.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile.dart';
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

    final capturing = ref.watch(capturingProvider);
    // 分组清单来自订阅配置（常驻内容）；当前看哪个分组落盘（照 nekoray 的当前分组）。
    final groups = ref.watch(offlineProxyGroupsProvider).valueOrNull ?? const <OutboundGroup>[];
    final activeGroupTag = ref.watch(selectedProxyGroupTagProvider);
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
          IconButton(
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            icon: const Icon(Icons.add_rounded),
          ),
          // 更多菜单：批量测速 / 排序 / 路由规则（原工具条上的散装按钮收拢于此）。
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'urltest' => ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select"),
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
            (groups.length > 1 ? 46.0 : 0.0) + (showSearch.value || query.value.isNotEmpty ? 56.0 : 0.0),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (groups.length > 1)
                SizedBox(
                  height: 46,
                  child: Material(
                    color: Theme.of(context).colorScheme.primary,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: groups.length,
                      separatorBuilder: (context, index) => const Gap(2),
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        final selected = group.tag == activeGroupTag;
                        return InkWell(
                          onTap: () => ref.read(selectedProxyGroupTagProvider.notifier).update(group.tag),
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
                              group.tag,
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
        tooltip: switch (nkState) {
          NkConnectionState.connected => t.connection.connected,
          NkConnectionState.connecting => t.connection.connecting,
          _ => t.connection.tapToConnect,
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
          final items = query0.isEmpty
              ? group.items
              : group.items
                    .where(
                      (e) =>
                          e.tagDisplay.toLowerCase().contains(query0) ||
                          e.tag.toLowerCase().contains(query0) ||
                          e.type.toLowerCase().contains(query0),
                    )
                    .toList();

          // 当前选中的是谁 —— 未连接时也要能一眼看到（否则点了节点没有任何反馈）
          String? selectedName;
          for (final item in group.items) {
            if (item.tag == group.selected) {
              selectedName = item.isGroup ? item.groupSelectedTagDisplay : item.tagDisplay;
              break;
            }
          }

          return Column(
            children: [
              // 「订阅」摘要 —— 原来在首页，合并后不能丢；点它进订阅页
              switch (ref.watch(activeProfileProvider)) {
                AsyncData(value: final profile?) => ProfileTile(
                  profile: profile,
                  isMain: true,
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  color: Theme.of(context).colorScheme.surfaceContainer,
                ),
                _ => const SizedBox.shrink(),
              },
              // 「接管」开关在工具条上（大圆按钮太占地方，已换掉）
              // 提示条看的是"流量有没有被接管"（不是"内核在不在跑"）——
              // 内核跑着但没接管时，这条依然该出现，因为流量确实还没走代理。
              if (!capturing) _PreselectBanner(text: t.pages.proxies.preselect, selectedName: selectedName),
              // 分组切换已上移为 AppBar 下的 Tab 条（NekoBox layout_group_list.xml）。
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text(t.pages.proxies.empty))
                    // 列表视图（默认）：一行一个节点，信息更全、扫读更快 ——
                    // 同行（v2rayN / NekoBox）都是列表；网格留给宽屏。
                    : listView
                    ? ListView.builder(
                        padding: const EdgeInsets.only(bottom: 86),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _tile(items[index], group, ref),
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
                            itemBuilder: (context, index) => _tile(items[index], group, ref),
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
                      onTap: () => ref.read(bottomSheetsNotifierProvider.notifier).showQuickSettings(),
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

  /// 列表和网格共用同一个节点项 —— 避免两处各写一遍（改一处漏一处）。
  Widget _tile(OutboundInfo proxy, OutboundGroup group, WidgetRef ref) {
    return ProxyTile(
      proxy,
      selected: group.selected == proxy.tag,
      onTap: () async {
        await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
      },
    );
  }
}

/// 底部状态栏（NekoBox `StatsBar` 规格）：主色底 + 白字，
/// 内容 = 接管状态点 + 当前节点 + ↑↓ 实时速率 + 连接状态。
///
/// 这三样原来分散在首页（当前代理条）和左侧栏（统计卡），合并成一页之后集中在这里常驻，
/// 任何滚动位置都能看到"现在到底连上没、走的是谁"。
class _CaptureStatusBar extends ConsumerWidget {
  const _CaptureStatusBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final capturing = ref.watch(capturingProvider);
    final group = ref.watch(proxiesOverviewNotifierProvider).valueOrNull;
    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();

    String? current;
    if (group != null) {
      for (final item in group.items) {
        if (item.isSelected) {
          current = item.tagDisplay;
          break;
        }
      }
    }

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
                  color: capturing ? Colors.lightGreenAccent : theme.colorScheme.onPrimary.withValues(alpha: .4),
                ),
              ),
              const Gap(8),
              if (current != null)
                Flexible(
                  child: Text(current, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
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

/// 未连接时的提示条：**只负责显示"当前选的是谁"**。
///
/// 「选择代理」和「启动代理」是两回事 —— 所以这条**不做点击、不放启动按钮**，
/// 启动有它自己的位置（工具条上那个开关）。同行都是分开的：
/// 选节点是配置决定，启停是运行动作，两者互不依赖。
class _PreselectBanner extends StatelessWidget {
  const _PreselectBanner({required this.text, this.selectedName});

  final String text;
  final String? selectedName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(10)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(FluentIcons.info_16_regular, size: 16, color: theme.colorScheme.onSecondaryContainer),
              const Gap(8),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
                ),
              ),
              const Gap(8),
              Flexible(
                child: Text(
                  selectedName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
