import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';

/// 常驻底部速度条（对标 NekoBox 的 `binding.stats`）：
/// 左侧 ↑ 上行 / ↓ 下行 实时速率，右侧可选累计总流量；可点（如触发测速）。
///
/// **纯展示组件**：速率文本由调用方传入。
class TrafficSpeedBar extends StatelessWidget {
  const TrafficSpeedBar({
    required this.up,
    required this.down,
    this.total,
    this.onTap,
    super.key,
  });

  final String up;
  final String down;
  final String? total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: NkMetrics.pad, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.arrow_upward_rounded, size: 14, color: NkColors.latencyMid),
          const SizedBox(width: 3),
          Text(up, style: theme.textTheme.bodySmall),
          const SizedBox(width: NkMetrics.gap + 4),
          Icon(Icons.arrow_downward_rounded, size: 14, color: NkColors.latencyOk),
          const SizedBox(width: 3),
          Text(down, style: theme.textTheme.bodySmall),
          const Spacer(),
          if (total != null)
            Text(
              total!,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );

    return Material(
      color: theme.colorScheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
        child: onTap == null ? row : InkWell(onTap: onTap, child: row),
      ),
    );
  }
}
