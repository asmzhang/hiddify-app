import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/proxy/active/ip_widget.dart';
import 'package:hiddify/features/proxy/widget/protocol_chip.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
    // 未测速显示 — 而不是把这一格留空：留空等于"没有信息"，
    // 也让「按延迟排序」看起来像没生效
    final delay = proxy.urlTestDelay;
    final delayText = delay == 0 ? "—" : (delay > 65000 ? "×" : delay.toString());
    final delayTint = delay == 0 ? theme.disabledColor : delayColor(context, delay);

    return ListTile(
      // shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      title: Text(
        proxy.tagDisplay,
        overflow: TextOverflow.ellipsis,
        style: PlatformUtils.isWindows ? const TextStyle(fontFamily: FontFamily.emoji) : null,
      ),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 序号：方便口头指认"第几个"（窄屏上也占不了多少）
          if (index != null)
            SizedBox(
              width: 26,
              child: Text(
                "${index! + 1}",
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.disabledColor),
              ),
            ),
          IPCountryFlag(
            countryCode: proxy.ipinfo.countryCode,
            organization: proxy.ipinfo.org,
            size: 40,
            padding: const EdgeInsetsDirectional.only(start: 6, end: 8),
          ),
        ],
      ),
      subtitle: Row(
        children: [
          // NekoBox 风格的协议色标签（vmess 紫 / vless 青 / trojan 橙 / ss 蓝 …）
          ProtocolChip(proxy.type, compact: true),
          if (proxy.isGroup) ...[
            const Gap(6),
            Flexible(
              child: Text(
                proxy.groupSelectedTagDisplay.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(delayText, style: TextStyle(color: delayTint)),
          // 用量：延迟之外第二个"跑起来才知道"的量（nekoray 的表格也是同一行给）
          if (proxy.download + proxy.upload > 0)
            Text((proxy.download + proxy.upload).toInt().size(), style: Theme.of(context).textTheme.bodySmall),
        ],
      ),

      selected: selected,
      selectedTileColor: theme.colorScheme.primaryContainer,
      onTap: onTap,
      onLongPress: () async => await ref.read(dialogNotifierProvider.notifier).showProxyInfo(outboundInfo: proxy),
      horizontalTitleGap: 4,
    );
  }

  Color delayColor(BuildContext context, int delay) {
    if (Theme.of(context).brightness == Brightness.dark) {
      return switch (delay) {
        < 800 => Colors.lightGreen,
        < 1500 => Colors.orange,
        _ => Colors.redAccent,
      };
    }
    return switch (delay) {
      < 800 => Colors.green,
      < 1500 => Colors.deepOrangeAccent,
      _ => Colors.red,
    };
  }
}
