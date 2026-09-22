import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class SettingDivider extends ConsumerWidget {
  const SettingDivider({super.key, this.title});

  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    if (title == null) return const Divider(indent: 16, endIndent: 16, height: 1);
    return Row(
      children: [
        const Expanded(child: Divider(indent: 16, endIndent: 8, height: 1)),
        const Icon(size: 16, Icons.warning_rounded, color: Colors.amber),
        const Gap(2),
        // 必须弹性 + ellipsis：标题是本地化长句（en 的 onlyTunMode
        // "Only available in TUN mode"），手机宽度下会顶穿 Row
        // （实测 360dp 溢 25px、320dp 溢 65px）。两侧 Divider 已是
        // Expanded，文本不弹性时整行仍会溢出。
        Flexible(
          child: Text(
            title!,
            style: theme.textTheme.titleSmall!.copyWith(color: theme.colorScheme.onSurface),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
        const Expanded(child: Divider(indent: 8, endIndent: 16, height: 1)),
      ],
    );
  }
}
