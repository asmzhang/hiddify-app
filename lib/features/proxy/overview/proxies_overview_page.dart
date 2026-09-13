import 'dart:math';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
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

    final serviceRunning = ref.watch(serviceRunningProvider);
    // 「内核在跑」≠「流量被接管」：测速按钮看内核，提示条看接管。
    final coreRunning = ref.watch(coreRunningProvider).valueOrNull ?? serviceRunning;
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
    // 列表 / 网格（落盘，见 proxiesListViewProvider）
    final listView = ref.watch(proxiesListViewProvider);

    // final selectActiveProxyMutation = useMutation(
    //   initialOnFailure: (error) => CustomToast.error(t.presentShortError(error)).show(context),
    // );

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.proxies.title),
        actions: [
          // 添加订阅（原来在首页的 AppBar 上）—— 合并后这里不能丢
          IconButton(
            icon: Icon(Icons.add_rounded, color: Theme.of(context).colorScheme.primary),
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
          ),
          // 列表 / 网格切换
          IconButton(
            onPressed: () => ref.read(proxiesListViewProvider.notifier).update(!listView),
            icon: Icon(listView ? FluentIcons.grid_24_regular : FluentIcons.list_24_regular),
          ),
          // 「绕过中国 / 直连规则」就是设置里的「路由」页，规则编辑器本身是既有的，
          // 只是埋在 设置 → 路由 里没有就近入口。这里给一个，省得找不到。
          IconButton(
            onPressed: () => context.goNamed('routingOptions'),
            icon: const Icon(FluentIcons.arrow_routing_24_regular),
            tooltip: t.pages.settings.routing.title,
          ),
          const Gap(8),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                // 「接管」开关：**全页只有这一处**。
                // 原来那个大圆按钮在合并页里占掉半屏（订阅摘要 + 它 + 工具条 + 状态栏），
                // 换成工具条上一个紧凑开关 —— 绿点表示接管中。
                FilledButton.tonal(
                  onPressed: () => ref.read(connectionNotifierProvider.notifier).toggleConnection(),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 40),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: capturing ? Colors.green : Theme.of(context).disabledColor,
                        ),
                      ),
                      const Gap(6),
                      Icon(capturing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                    ],
                  ),
                ),
                const Gap(8),
                Expanded(
                  child: TextField(
                    controller: searchController,
                    onChanged: (value) => query.value = value,
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
                // 排序做成"带当前值"的按钮：原来只是个裸图标，看不出点了会变什么、
                // 也看不出现在按什么排（用户反馈"排列要能看得到"就是这个）
                PopupMenuButton<ProxiesSort>(
                  initialValue: sortBy,
                  onSelected: ref.read(proxiesSortNotifierProvider.notifier).update,
                  tooltip: t.pages.proxies.sort,
                  itemBuilder: (context) {
                    return [...ProxiesSort.values.map((e) => PopupMenuItem(value: e, child: Text(e.present(t))))];
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(FluentIcons.arrow_sort_24_regular, size: 18),
                        const Gap(4),
                        Text(sortBy.present(t), style: Theme.of(context).textTheme.labelLarge),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      // 未连接时留着按钮但禁用（onPressed=null 会自动变灰）：
      // 直接隐藏会让人以为"测速功能没了"，灰着反而说明"连接后可用"
      floatingActionButton: FloatingActionButton(
        onPressed: !coreRunning
            ? null
            : () async => await ref.read(proxiesOverviewNotifierProvider.notifier).urlTest("select"),
        tooltip: coreRunning ? t.pages.proxies.testAll : t.pages.proxies.testAfterConnect,
        child: const Icon(FluentIcons.flash_24_filled),
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
              // 分组切换（照 nekoray 的分组树 / Clash Verge 的分组面板）。
              // 分组清单来自**订阅配置** —— 更新订阅分组也跟着变，与连接状态无关。
              if (groups.length > 1)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: groups.length,
                    separatorBuilder: (context, index) => const Gap(6),
                    itemBuilder: (context, index) {
                      final group = groups[index];
                      return ChoiceChip(
                        label: Text(group.tag),
                        selected: group.tag == activeGroupTag,
                        onSelected: (_) => ref.read(selectedProxyGroupTagProvider.notifier).update(group.tag),
                      );
                    },
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text(t.pages.proxies.empty))
                    // 列表视图（默认）：一行一个节点，信息更全、扫读更快 ——
                    // 同行（v2rayN / NekoBox）都是列表；网格留给宽屏。
                    : listView
                    ? ListView.builder(
                        padding: const EdgeInsets.only(bottom: 86),
                        itemCount: items.length,
                        itemBuilder: (context, index) => _tile(items[index], group, ref, index),
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
                              mainAxisExtent: 72,
                            ),
                            itemBuilder: (context, index) => _tile(items[index], group, ref, index),
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
  Widget _tile(OutboundInfo proxy, OutboundGroup group, WidgetRef ref, int index) {
    return ProxyTile(
      proxy,
      index: index,
      selected: group.selected == proxy.tag,
      onTap: () async {
        await ref.read(proxiesOverviewNotifierProvider.notifier).changeProxy(group.tag, proxy.tag);
      },
    );
  }
}

/// 底部状态栏：**接管状态 + 当前节点 + 实时速率**。
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

    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Material(
      color: theme.colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // 绿点 = 接管中；灰点 = 没接管（内核可能仍在跑，只是流量没走代理）
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: capturing ? Colors.green : theme.disabledColor,
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
