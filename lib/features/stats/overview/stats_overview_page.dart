import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/stats/model/traffic_split.dart';
import 'package:hiddify/features/stats/notifier/stats_notifier.dart';
import 'package:hiddify/features/stats/widget/connection_stats_card.dart';
import 'package:hiddify/features/stats/widget/stats_card.dart';
import 'package:hiddify/features/stats/widget/traffic_split_card.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 流量面板（融合版）。
///
/// NekoBox 这里是内嵌 Clash 的网页仪表盘；hiddify 本来就有更丰富的原生 stats 组件，
/// 所以这张页面**直接组合现有组件**（连接信息 / 实时速率 / 累计流量 / 代理-直连拆分），
/// 不新造数据、不依赖外部网页。
class StatsOverviewPage extends HookConsumerWidget {
  const StatsOverviewPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final stats = ref.watch(statsNotifierProvider).asData?.value ?? SystemInfo.create();
    // 和侧栏一致：只有"确实在接管流量"时才显示拆分卡，否则全是 0 是噪声。
    final showSplit = stats.trafficAvailable && ref.watch(serviceRunningProvider);
    final split = ref.watch(trafficSplitProvider);

    return Scaffold(
      appBar: AppBar(
        // 手机端：汉堡键打开左侧导航抽屉；PC 端无（左侧是常驻 rail）
        leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
        title: Text(t.pages.traffic.title),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ConnectionStatsCard(),
          const Gap(16),
          StatsCard(
            title: t.components.stats.trafficLive,
            stats: [
              (
                label: const Text("↑", style: TextStyle(color: Colors.green)),
                data: Text(stats.uplink.toInt().speed()),
                semanticLabel: t.components.stats.uplink,
              ),
              (
                label: Text("↓", style: TextStyle(color: theme.colorScheme.error)),
                data: Text(stats.downlink.toInt().speed()),
                semanticLabel: t.components.stats.downlink,
              ),
            ],
          ),
          const Gap(16),
          StatsCard(
            title: t.components.stats.trafficTotal,
            stats: [
              (
                label: const Text("↑", style: TextStyle(color: Colors.green)),
                data: Text(stats.uplinkTotal.toInt().size()),
                semanticLabel: t.components.stats.uplink,
              ),
              (
                label: Text("↓", style: TextStyle(color: theme.colorScheme.error)),
                data: Text(stats.downlinkTotal.toInt().size()),
                semanticLabel: t.components.stats.downlink,
              ),
            ],
          ),
          if (showSplit) ...[
            const Gap(16),
            TrafficSplitCard(
              title: t.components.stats.traffic,
              proxiedLabel: t.components.stats.trafficProxied,
              directLabel: t.components.stats.trafficDirect,
              split: split,
            ),
          ],
        ],
      ),
    );
  }
}
