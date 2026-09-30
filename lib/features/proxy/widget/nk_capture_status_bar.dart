import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/connection/notifier/connection_summary.dart';
import 'package:hiddify/utils/number_formatters.dart';

/// 底部状态条 —— NekoBox `widget/StatsBar.kt` + `layout_main.xml:46-99` 的 1:1 对应物。
///
/// NekoBox 权威规格（实测 `StatsBar.kt` / `MainActivity.kt`）：
/// - 仅 Connected 显示（`changeState` 非 Connected 一律 `performHide`；显隐条件
///   在页面侧：showStatsBar 门控 + 100ms 延迟，对齐 postWhenStarted+100ms）；
/// - 内容 = 状态文案（`vpn_connected`）+ ▲tx ▼rx（只显代理速率 `updateSpeed`）；
///   本项目补充节点名（connectionSummaryProvider 归一口径）；
/// - 点击 = `MainActivity.kt:94 if (connected) testConnection()` —— 未连接时整条
///   不挂载所以不可点（行为等价）；本项目落点 = [ConnectionTestDialog]（进度弹窗，
///   交互形态按 Throne 收口为刻意差异，不对照内联文案变化）。
///
/// 单行 Row vs NekoBox 三行竖排：宽屏观察点已定案维持单行
/// （docs/design/ui-real-device-observations-2026-09-22.md:8-11）。
///
/// 纯参数注入（[ConnectionFab] 同型）：provider 订阅留在页面薄壳
/// [_CaptureStatusBarShell]——stats 每秒 tick 的重建粒度只到状态条本身。
class NkCaptureStatusBar extends StatelessWidget {
  const NkCaptureStatusBar({
    super.key,
    required this.t,
    required this.summary,
    required this.uplink,
    required this.downlink,
    required this.onTap,
  });

  final Translations t;
  final ConnectionSummary summary;
  final int uplink;
  final int downlink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 白字（主色底上），与 NekoBox 的 StatsBar 一致（whiteOrTextPrimary）。
    final style = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimary);
    return Material(
      color: theme.colorScheme.primary,
      child: SafeArea(
        top: false,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Flexible(
                  child: Text(t.connection.statsConnected, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
                ),
                if (summary.nodeName != null) ...[
                  const Gap(8),
                  Flexible(
                    child: Text(summary.nodeName!, style: style, overflow: TextOverflow.ellipsis, maxLines: 1),
                  ),
                ],
                const Spacer(),
                Text("▲ ${uplink.speed()}", style: style),
                const Gap(10),
                Text("▼ ${downlink.speed()}", style: style),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
