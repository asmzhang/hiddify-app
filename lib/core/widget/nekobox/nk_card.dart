import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';

/// 统一卡片容器（圆角/内边距一致），可选标题与点击。
///
/// 页面里的"一块内容"都用它，视觉才统一。
class NkCard extends StatelessWidget {
  const NkCard({
    required this.child,
    this.title,
    this.padding,
    this.onTap,
    this.margin,
    super.key,
  });

  final Widget child;
  final String? title;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.circular(NkMetrics.radius);

    final content = Padding(
      padding: padding ?? const EdgeInsets.all(NkMetrics.pad),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(title!, style: theme.textTheme.titleSmall),
            const SizedBox(height: NkMetrics.gapSmall),
          ],
          child,
        ],
      ),
    );

    return Card(
      margin: margin ?? EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: onTap == null ? content : InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }
}

/// 分节标题（设置 / 工具 / 关于等页面用）。
class NkSectionHeader extends StatelessWidget {
  const NkSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(NkMetrics.pad + 2, NkMetrics.gap + 4, NkMetrics.pad + 2, 4),
      child: Text(title, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
