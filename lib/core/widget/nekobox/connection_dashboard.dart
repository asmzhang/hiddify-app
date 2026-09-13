import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';

enum NkConnectionState { disconnected, connecting, connected, error }

/// 连接仪表盘（对标 NekoBox 首页）：大圆钮 + 当前节点 + 状态 + 实时上/下行。
///
/// **纯展示组件**：连接状态与速率由调用方传入，不碰任何 provider。
class ConnectionDashboard extends StatelessWidget {
  const ConnectionDashboard({
    required this.state,
    required this.name,
    required this.statusText,
    required this.up,
    required this.down,
    required this.onTap,
    this.disabled = false,
    super.key,
  });

  final NkConnectionState state;

  /// 当前节点名（未选时传占位文案）。
  final String name;

  /// 状态文案（如"已连接 / 点击连接"）。
  final String statusText;

  final String up;
  final String down;
  final VoidCallback? onTap;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isConnected = state == NkConnectionState.connected;

    final Color color = switch (state) {
      NkConnectionState.error => scheme.error,
      _ => scheme.primary,
    };
    final IconData icon = switch (state) {
      NkConnectionState.connected => Icons.stop_rounded,
      NkConnectionState.connecting => Icons.hourglass_top_rounded,
      NkConnectionState.error => Icons.error_outline_rounded,
      NkConnectionState.disconnected => Icons.power_settings_new_rounded,
    };

    return NkCard(
      child: Row(
        children: [
          SizedBox(
            width: 84,
            height: 84,
            child: Material(
              color: isConnected ? color : color.withOpacity(0.14),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: disabled ? null : onTap,
                child: Center(
                  child: Icon(icon, size: 32, color: isConnected ? Colors.white : color),
                ),
              ),
            ),
          ),
          const SizedBox(width: NkMetrics.pad),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(statusText, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: NkMetrics.gapSmall),
                Row(
                  children: [
                    _Speed(icon: Icons.arrow_upward_rounded, value: up, color: NkColors.latencyMid),
                    const SizedBox(width: NkMetrics.gap + 4),
                    _Speed(icon: Icons.arrow_downward_rounded, value: down, color: NkColors.latencyOk),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Speed extends StatelessWidget {
  const _Speed({required this.icon, required this.value, required this.color});

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
