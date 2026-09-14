import 'package:flutter/material.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 节点卡片 —— **1:1 复刻** NekoBox `layout_profile.xml`：
///
/// ```
/// MaterialCard(margin 4 / elevation 2 / 圆角 4)
///  └ 横向：左缘 4dp 选中条（未选中 = 透明占位，保持行高一致）
///     └ 纵向：
///        行1 名称（粗体）            [编辑/分享/删除图标 —— 二期随 hiddify 功能补充]
///        行2 地址（次色）                       流量 ↑/↓
///        行3 协议（按协议着色的纯文字）        状态（延迟绿/红纯文字）
/// ```
///
/// 与 NekoBox 的两处刻意差异（都属"hiddify 功能最后补充"原则）：
/// 长按弹出节点详情（补充能力）；国旗/序号暂不显示（二期按需补回）。
/// 删除图标与 NekoBox 一致默认不显示（订阅节点的增删走订阅更新）。
class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final delay = proxy.urlTestDelay;
    final address = '${proxy.host}:${proxy.port}';
    // 行3 左侧：协议类型 —— NekoBox 用 accentOrTextSecondary 的纯彩色文字（非徽标）。
    final typeColor = NkColors.protocolColor(proxy.type);
    // 行3 右侧：状态 —— 分组显示当前选中项；节点显示延迟（绿/红纯文字，复用 PingBadge 文案规则）。
    final String statusText;
    final Color statusColor;
    if (proxy.isGroup) {
      statusText = proxy.groupSelectedTagDisplay.trim();
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else if (delay <= 0) {
      statusText = '—';
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else {
      statusText = delay > NkColors.latencyTimeoutMs ? '×' : '$delay';
      statusColor = NkColors.latencyColor(context, delay) ?? theme.colorScheme.onSurfaceVariant;
    }
    // 行2 右侧：流量（上下行合计口径与原实现一致：分开显示，任一非零才显示）。
    final traffic = proxy.download > 0 || proxy.upload > 0
        ? '↑ ${proxy.upload.toInt().size()} ↓ ${proxy.download.toInt().size()}'
        : null;

    return Card(
      margin: const EdgeInsets.all(4),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: InkWell(
        onTap: onTap,
        onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左缘 4dp 选中条（NekoBox 的 selected_view；未选中透明占位）。
            Container(width: 4, color: selected ? theme.colorScheme.primary : Colors.transparent),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 行 1：名称（粗体，占满；右侧动作图标二期补充）。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            proxy.tagDisplay,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 行 2：地址 ······ 流量。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 8, 0),
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            address,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                        const Spacer(),
                        if (traffic != null)
                          Text(
                            traffic,
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                  // 行 3：协议（着色纯文字） ······ 状态。
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 3, 8, 12),
                    child: Row(
                      children: [
                        Text(
                          proxy.type,
                          style: theme.textTheme.bodySmall?.copyWith(color: typeColor, fontWeight: FontWeight.w600),
                        ),
                        const Spacer(),
                        Text(
                          statusText,
                          style: theme.textTheme.bodySmall?.copyWith(color: statusColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
