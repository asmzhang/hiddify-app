import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/nekobox/ping_badge.dart';
import 'package:hiddify/core/widget/nekobox/protocol_chip.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 节点项（对标 NekoBox `layout_profile`）：
/// 卡片 + 选中左条 + 「名称 / 地址 / 协议色 type + ping 徽标」三行。
class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(this.proxy, {super.key, required this.selected, required this.onTap, this.index});

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  /// 列表里的序号（从 0 开始）。传了就显示，方便口头指认"第几个节点"。
  final int? index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final delay = proxy.urlTestDelay;
    final usage = proxy.download + proxy.upload;
    // 服务地址：host:port（NekoBox 的 profile_address）
    final address = '${proxy.host}:${proxy.port}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 选中高亮左条（NekoBox 的 selected_view）
              if (selected) Container(width: 4, color: theme.colorScheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 行 1：国旗 + 序号 + 名称 + 用量
                      Row(
                        children: [
                          IPCountryFlag(
                            countryCode: proxy.ipinfo.countryCode,
                            organization: proxy.ipinfo.org,
                            size: 20,
                            padding: const EdgeInsetsDirectional.only(end: 6),
                          ),
                          if (index != null) ...[
                            Text(
                              "${index! + 1}",
                              style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
                            ),
                            const Gap(6),
                          ],
                          Expanded(
                            child: Text(
                              proxy.tagDisplay,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                              ),
                            ),
                          ),
                          if (usage > 0) Text(usage.toInt().size(), style: theme.textTheme.bodySmall),
                        ],
                      ),
                      const Gap(2),
                      // 行 2：服务地址
                      Text(
                        address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      const Gap(6),
                      // 行 3：协议色标签（+ 分组） ····· ping 徽标
                      Row(
                        children: [
                          ProtocolChip(proxy.type, compact: true),
                          if (proxy.isGroup) ...[
                            const Gap(6),
                            Flexible(
                              child: Text(
                                proxy.groupSelectedTagDisplay.trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ],
                          const Spacer(),
                          PingBadge(delay),
                        ],
                      ),
                    ],
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
