import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/features/stats/model/traffic_split.dart';
import 'package:hiddify/utils/number_formatters.dart';

/// 一根双色占比条：左边是走代理的部分，右边是直连的部分。
///
/// 抽出来单独一个 widget 是因为折叠态（只有一根细条）和展开态（卡片里的条）
/// 都要用它。总量为 0 时退化成一条中性灰条，避免 flex 计算出现 0。
class TrafficShareBar extends StatelessWidget {
  const TrafficShareBar({super.key, required this.split, this.height = 4});

  final TrafficSplit split;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final proxiedColor = theme.colorScheme.primary;
    final directColor = theme.colorScheme.outlineVariant;

    final Widget bar;
    if (split.total <= 0) {
      bar = ColoredBox(color: directColor);
    } else {
      final proxiedFlex = (split.proxiedFraction * 1000).round();
      final directFlex = 1000 - proxiedFlex;
      bar = Row(
        children: [
          if (proxiedFlex > 0) Expanded(flex: proxiedFlex, child: ColoredBox(color: proxiedColor)),
          if (directFlex > 0) Expanded(flex: directFlex, child: ColoredBox(color: directColor)),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: SizedBox(height: height, width: double.infinity, child: bar),
    );
  }
}

/// 把总流量拆成"走代理 / 直连"两条，并给出各自占比。
///
/// 数据来自 [trafficSplitProvider]，也就是核心每个出口的累计用量之和 ——
/// 所以这里两行加起来恒等于总流量（见 `traffic_split.dart` 的注释）。
class TrafficSplitCard extends StatelessWidget {
  const TrafficSplitCard({
    super.key,
    required this.title,
    required this.proxiedLabel,
    required this.directLabel,
    required this.split,
    this.showRate = true,
  });

  final String title;
  final String proxiedLabel;
  final String directLabel;
  final TrafficSplit split;

  /// 展开态显示实时速率；折叠态只留一条细条，不需要速率。
  final bool showRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w300);
    final dataStyle = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w300);

    return Card(
      margin: EdgeInsets.zero,
      shadowColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.bodySmall),
            const Gap(4),
            _ChannelRow(
              color: theme.colorScheme.primary,
              label: proxiedLabel,
              channel: split.proxied,
              labelStyle: labelStyle,
              dataStyle: dataStyle,
              showRate: showRate,
            ),
            const Gap(6),
            _ChannelRow(
              color: theme.colorScheme.outline,
              label: directLabel,
              channel: split.direct,
              labelStyle: labelStyle,
              dataStyle: dataStyle,
              showRate: showRate,
            ),
            const Gap(6),
            TrafficShareBar(split: split),
          ],
        ),
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({
    required this.color,
    required this.label,
    required this.channel,
    required this.labelStyle,
    required this.dataStyle,
    required this.showRate,
  });

  final Color color;
  final String label;
  final TrafficChannel channel;
  final TextStyle? labelStyle;
  final TextStyle? dataStyle;
  final bool showRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 第一次采样没有参照物，速率宁可显示 — 也不显示假的 0
    final up = channel.measured ? channel.upRate.toInt().speed() : '—';
    final down = channel.measured ? channel.downRate.toInt().speed() : '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const Gap(6),
            Expanded(child: Text(label, style: labelStyle, overflow: TextOverflow.ellipsis)),
            // 这一行右侧是累计量（单位是 size，KB/MB/GB），和下一行的 /s 区分开
            Text(channel.total.size(), style: dataStyle),
          ],
        ),
        if (showRate)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 14),
            child: Row(
              children: [
                Text("↑", style: dataStyle?.copyWith(color: Colors.green)),
                const Gap(3),
                Expanded(child: Text(up, style: dataStyle, overflow: TextOverflow.ellipsis)),
                const Gap(8),
                Text("↓", style: dataStyle?.copyWith(color: theme.colorScheme.error)),
                const Gap(3),
                Expanded(child: Text(down, style: dataStyle, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    );
  }
}

/// 折叠态用的一行摘要：两条通道各自的**实时**速率（上+下）。
///
/// 折叠态只给一根占比条的话，用户根本看不出"现在走的是代理还是直连"，
/// 而这一行正好是那个问题的答案，所以放最外层不折叠。
class TrafficSplitLiveLine extends StatelessWidget {
  const TrafficSplitLiveLine({
    super.key,
    required this.split,
    required this.proxiedLabel,
    required this.directLabel,
  });

  final TrafficSplit split;
  final String proxiedLabel;
  final String directLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w300);
    final measured = split.proxied.measured || split.direct.measured;
    String rate(TrafficChannel c) => measured ? c.rate.toInt().speed() : '—';

    // 两半都用 Flexible：其它语言（如 Proxied/Direct）比中文长，硬排会溢出
    Widget channel(Color color, String label, TrafficChannel c) => Expanded(
      child: Row(
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const Gap(4),
          Flexible(child: Text(label, style: style, overflow: TextOverflow.ellipsis)),
          const Gap(4),
          Flexible(
            child: Text(rate(c), style: style, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
          ),
        ],
      ),
    );

    return Row(
      children: [
        channel(theme.colorScheme.primary, proxiedLabel, split.proxied),
        channel(theme.colorScheme.outline, directLabel, split.direct),
      ],
    );
  }
}
