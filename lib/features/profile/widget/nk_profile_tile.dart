import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/widget/profile_actions.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 配置卡片 —— **1:1 复刻** NekoBox `layout_profile.xml`（订阅 / 本地配置共用的紧凑三行卡）。
///
/// ```text
/// MaterialCard(margin 4 / elevation 2 / 圆角 4)
///  └ 横向：左缘 4dp 选中条（未选中 = 透明占位，保持行高一致）
///     └ 纵向：
///        行1 名称（粗体）              ✎ ⤴ 🗑（行内动作，对标卡片右缘图标）
///        行2 地址（次色）                     流量（已用 / 总量）
///        行3 状态（按余量着色）               最后更新
/// ```
///
/// 与 NekoBox 的刻意差异（都属"hiddify 功能降权、不删码"原则）：
/// - 订阅的流量进度条 / 到期天数由"大卡"降为行 2 / 行 3 的文字位（进度条仍保留在详情页）；
/// - 「更新」不再挂卡片（归一原则：更新入口归页 Toolbar 的"更新订阅"）；
/// - 本地配置无地址与订阅信息，自动收起 行2 / 行3 左半，卡片更矮。
class NkProfileTile extends HookConsumerWidget {
  const NkProfileTile(this.profile, {super.key, this.onTap});

  final ProfileEntity profile;

  /// 覆盖默认点击行为（默认进详情页）。
  final GestureTapCallback? onTap;

  static String _pad2(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final subInfo = switch (profile) {
      RemoteProfileEntity(:final subInfo) => subInfo,
      _ => null,
    };

    // 行2：地址 ······ 流量（与旧卡口径一致：已用 / 总量）。
    final host = switch (profile) {
      RemoteProfileEntity(:final url) => Uri.tryParse(url)?.host ?? url,
      LocalProfileEntity() => null,
    };
    final traffic = switch (subInfo) {
      final s? => s.consumption.sizeOf(s.total),
      _ => null,
    };
    // 行3 左：订阅状态（到期 / 余量），不足或过期用错误色。
    final (statusText, statusColor) = _status(t, theme, subInfo);
    // 行3 右：最后更新。
    final d = profile.lastUpdate;
    final updatedAt = '${d.year}-${_pad2(d.month)}-${_pad2(d.day)} ${_pad2(d.hour)}:${_pad2(d.minute)}';

    return Card(
      margin: const EdgeInsets.all(4),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      child: InkWell(
        onTap: onTap ?? () => context.goNamed('profileDetails', pathParameters: {'id': profile.id}),
        // IntrinsicHeight：行高由内容决定；否则 ListView 的无界高度会让 stretch 行塌成 0（卡片不可见）。
        child: IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 左缘 4dp 选中条（NekoBox 的 selected_view；未选中透明占位）。
                Container(width: 4, color: profile.active ? theme.colorScheme.primary : Colors.transparent),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 行 1：名称（粗体）+ 行内动作 编辑 / 分享 / 删除。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 2, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                profile.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontFamily: PlatformUtils.isWindows ? FontFamily.emoji : null,
                                ),
                              ),
                            ),
                            _CardAction(
                              icon: Icons.edit_rounded,
                              tooltip: t.common.edit,
                              onTap: () {
                                if (context.canPop()) context.pop();
                                context.goNamed('profileDetails', pathParameters: {'id': profile.id});
                              },
                            ),
                            AdaptiveMenu(
                              items: buildProfileShareItems(context, ref, profile),
                              builder: (context, toggleVisibility, child) => _CardAction(
                                icon: AdaptiveIcon(context).share,
                                tooltip: t.common.share,
                                onTap: toggleVisibility,
                              ),
                              child: null,
                            ),
                            _CardAction(
                              icon: Icons.delete_outline_rounded,
                              tooltip: t.common.delete,
                              onTap: () async => await confirmDeleteProfile(context, ref, profile),
                            ),
                          ],
                        ),
                      ),
                      // 行 2：地址 ······ 流量。
                      if (host != null || traffic != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
                          child: Row(
                            children: [
                              if (host != null)
                                Flexible(
                                  child: Text(
                                    host,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
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
                      // 行 3：状态（着色） ······ 最后更新。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 1, 8, 10),
                        child: Row(
                          children: [
                            if (statusText != null)
                              Text(
                                statusText,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            const Spacer(),
                            Text(
                              updatedAt,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
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
        ),
      ),
    );
  }

  /// 行3 状态：订阅给"剩余/到期"，本地配置不给（自动收起）。
  (String?, Color) _status(Translations t, ThemeData theme, SubscriptionInfo? subInfo) {
    final sub = t.components.subscriptionInfo;
    if (subInfo == null) return (null, theme.colorScheme.onSurfaceVariant);
    if (subInfo.isExpired) return (sub.expired, theme.colorScheme.error);
    if (subInfo.ratio >= 1) return (sub.noTraffic, theme.colorScheme.error);
    final remaining = subInfo.remaining.inDays > 365 ? "∞" : '${subInfo.remaining.inDays}';
    return (sub.remainingDuration(duration: remaining), theme.colorScheme.onSurfaceVariant);
  }
}

/// 卡片行内图标按钮（小尺寸、次色）—— 对标 NekoBox 卡片右缘的 ImageButton。
class _CardAction extends StatelessWidget {
  const _CardAction({required this.icon, required this.tooltip, required this.onTap});

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(NkMetrics.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
