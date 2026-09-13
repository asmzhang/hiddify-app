import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';

/// 延迟徽标（对标 NekoBox 节点项的 ping 状态）：小圆点 + 数值。
///
/// - `delayMs <= 0`：未测速 → 灰色 "—"
/// - `delayMs > 65000`：超时 → 红色 "×"
/// - 其余按 绿(<800)/黄(<1500)/红 分档
class PingBadge extends StatelessWidget {
  const PingBadge(this.delayMs, {super.key, this.dot = true});

  final int delayMs;

  /// 是否显示左侧小圆点。
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = NkColors.latencyColor(context, delayMs) ?? theme.disabledColor;
    final text = delayMs <= 0
        ? '—'
        : delayMs > NkColors.latencyTimeoutMs
        ? '×'
        : '$delayMs';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dot) ...[
          Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
          const SizedBox(width: 5),
        ],
        Text(text, style: theme.textTheme.bodySmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
