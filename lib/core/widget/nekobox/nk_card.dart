import 'package:flutter/material.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';

/// 统一卡片容器（圆角/内边距一致），可选标题与点击。
///
/// 页面里的"一块内容"都用它，视觉才统一。
class NkCard extends StatelessWidget {
  const NkCard({required this.child, this.title, this.padding, this.onTap, this.margin, super.key});

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

/// 卡片行内图标动作（小尺寸、次色）—— 对标 NekoBox 卡片右缘的 ImageButton。
///
/// 配置卡（NkProfileTile）与节点卡（ProxyTile）共用：NekoBox 的
/// `layout_profile.xml` 与配置卡一样有行内 ✎ / ⤴，两处图标尺寸与点击区必须一致，
/// 所以只保留这一个实现。
class NkCardAction extends StatelessWidget {
  const NkCardAction({required this.icon, required this.tooltip, required this.onTap, super.key});

  final IconData icon;
  final String tooltip;

  /// 为 null 表示**禁用**（照 NekoBox `editButton.isEnabled = !started`）：
  /// 置灰且不响应点击，而不是把按钮藏起来 —— 用户要知道"有这个东西、但现在不能用"。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = onTap == null
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: .38)
        : theme.colorScheme.onSurfaceVariant;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NkMetrics.radiusSmall),
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 18, color: color)),
      ),
    );
  }
}
