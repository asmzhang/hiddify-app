import 'dart:convert';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/outbound_to_link.dart';
import 'package:hiddify/gen/fonts.gen.dart';
import 'package:hiddify/hiddifycore/generated/v2/hcore/hcore.pb.dart';
import 'package:hiddify/utils/custom_loggers.dart';
import 'package:hiddify/utils/number_formatters.dart';
import 'package:hiddify/utils/platform_utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 节点卡片 —— **1:1 复刻** NekoBox `layout_profile.xml`：
///
/// ```text
/// MaterialCard(margin 4 / elevation 2 / 圆角 4)
///  └ 横向：左缘 4dp 选中条（未选中 = 透明占位，保持行高一致）
///     └ 纵向：
///        行1 名称（粗体）                      行内动作：✎ 编辑 / ⤴ 分享 / 🗑 删除
///        行2 地址（次色）                       流量 ↑/↓
///        行3 协议（按协议着色的纯文字）        状态（延迟绿/红纯文字）
/// ```
///
/// 行内动作照 `layout_profile.xml` 的**顺序与可见性**：`edit` → `share` → `remove`，
/// 三者默认显示，且只有"正在使用的那一个节点"禁用编辑/删除
/// （`ui/ConfigurationFragment.kt:1624-1625`：`isEnabled = !started`；
///  `:1612-1613` 的 `isGone = select` 只在"选择器模式"下隐藏 —— 那是 Chain 端点选择等场景）。
///
/// 与 NekoBox 的差异：
/// - **✎ 只覆盖 4 种协议**（anytls / vless / hysteria2 / shadowsocks，真机 84 个节点的
///   100%）。其余协议（NekoBox 另有 8 份表单）没有表单，[onEdit] 传 null ⇒ 不显示按钮。
///   规格源仍是 NekoBox 的 `res/xml/*_preferences.xml`，见 `protocol_form.dart`。
/// - **⤴ 分享 = 标准链接优先**（NekoBox `*Fmt.toUri()` 的等价物，见
///   `outbound_to_link.dart`）：8 协议（ss/vless/vmess/trojan/hy2/tuic/socks/http）
///   生成可粘贴进其它客户端的链接；不支持的协议回落复制出站 JSON（原行为）。
/// - 改名（NekoBox `name_preferences.xml`）未纳入表单：`tag` 是节点身份，改名要跨
///   内核配置 / 选中偏好 / 删除基线三处迁移，属独立改动。
/// - 长按弹出节点详情（hiddify 补充能力）；国旗/序号暂不显示。
/// - 协议用**纯彩色文字**而非带色 chip：照 NekoBox 源码 `@id/profile_type`
///   （`textColor=?attr/accentOrTextSecondary` 的 TextView），mockup 里的 chip 是原型稿美化。
class ProxyTile extends HookConsumerWidget with PresLogger {
  const ProxyTile(
    this.proxy, {
    super.key,
    required this.selected,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.editEnabled = true,
    this.deleteEnabled = true,
  });

  final OutboundInfo proxy;
  final bool selected;
  final GestureTapCallback? onTap;

  /// ✎ 编辑节点（NekoBox `layout_profile.xml` 的 `@id/edit` → 该协议的 `*SettingsActivity`）。
  /// 为 null 时**不显示** —— 该协议还没有表单，或这一行不是实体（列表在走配置回落）。
  final VoidCallback? onEdit;

  /// 🗑 删除节点（NekoBox `removeButton`）。为 null 时**不显示**这个按钮
  /// （用于"这一行不是实体"的情形 —— 例如列表还在走配置回落）。
  final VoidCallback? onDelete;

  /// 是否可用 —— 照 NekoBox `ConfigurationFragment.kt:1624-1625` 的 `isEnabled = !started`：
  /// **正在使用的那个节点不允许编辑/删除**。
  final bool editEnabled;

  /// 是否可用 —— 同 [editEnabled]。
  final bool deleteEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    final delay = proxy.urlTestDelay;
    // 行2 左侧：地址 —— 取自**实体**（NekoBox `AbstractBean.displayAddress()`），
    // 不是运行期：内核的 `OutboundInfo` 不给 host/port。见 `displayAddress()`。
    final address = displayAddress(proxy.host, proxy.port);
    // 行3 左侧：协议类型 —— NekoBox 用 accentOrTextSecondary 的纯彩色文字（非徽标）。
    final typeColor = NkColors.protocolColor(proxy.type);
    // 行3 右侧：状态 —— 分组显示当前选中项；节点显示延迟（绿/红纯文字，复用 PingBadge 文案规则）。
    // 负数编码 = 实体测速结果里的"不可用"（TCP ping 落库的分类，见
    // `encodeOfflineTestResult`），显示为 NekoBox `connection_test_*` 文案而非 "×"。
    final String statusText;
    final Color statusColor;
    if (proxy.isGroup) {
      statusText = proxy.groupSelectedTagDisplay.trim();
      statusColor = theme.colorScheme.onSurfaceVariant;
    } else if (offlineTestErrorKey(delay) case final errorKey?) {
      statusText = switch (errorKey) {
        'testRefused' => t.pages.proxies.msg.testRefused,
        'testTimeout' => t.pages.proxies.msg.testTimeout,
        'testUnreachable' => t.pages.proxies.msg.testUnreachable,
        'testDomainNotFound' => t.pages.proxies.msg.testDomainNotFound,
        _ => t.pages.proxies.msg.testUnreachable,
      };
      statusColor = NkColors.latencyBad;
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
        // IntrinsicHeight：行高由内容决定；否则 ListView 的无界高度会让 stretch 行塌成 0（卡片不可见）。
        child: IntrinsicHeight(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
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
                      // 行 1：名称（粗体）+ 行内动作。
                      // 顺序照 NekoBox `layout_profile.xml`：edit → share → remove
                      // （`edit` 暂缺，见类注释）。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 4, 0),
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
                            NkCardAction(
                              icon: FluentIcons.edit_24_regular,
                              tooltip: t.common.edit,
                              onTap: editEnabled ? onEdit : null,
                            ),
                            // chain 无分享（NekoBox `ProxyEntity.haveLink() = false`
                            // → ConfigurationFragment.kt:1610-1644 隐藏 share/QR/剪贴板；
                            // chain 的 payload 是成员清单，分享出来别的客户端也解析不了）
                            if (proxy.type != 'chain')
                              NkCardAction(
                                icon: AdaptiveIcon(context).share,
                                tooltip: t.common.share,
                                onTap: () async {
                                  final json = await ref.read(outboundJsonProvider(proxy.tag).future);
                                  if (!context.mounted) return;
                                  if (json == null) {
                                    // 只在"两个来源都找不到这个 tag"时发生（理论上不该出现：
                                    // 列表本身就是从实体或同一份配置来的），所以用通用错误文案。
                                    ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
                                    return;
                                  }
                                  // 优先分享**标准链接**（可粘贴进 NekoBox/v2rayN 等客户端）；
                                  // 不支持的协议/字段残缺时回落到出站 JSON（原行为，不丢功能）。
                                  String text = json;
                                  try {
                                    final decoded = jsonDecode(json);
                                    if (decoded is Map<String, dynamic>) {
                                      final link = outboundToLink(decoded);
                                      if (link != null) text = link;
                                    }
                                  } catch (_) {
                                    // JSON 都解析不了时原样复制
                                  }
                                  await Clipboard.setData(ClipboardData(text: text));
                                  if (!context.mounted) return;
                                  ref
                                      .read(inAppNotificationControllerProvider)
                                      .showSuccessToast(t.common.msg.export.clipboard.success);
                                },
                              ),
                            if (onDelete != null)
                              NkCardAction(
                                icon: AdaptiveIcon(context).delete,
                                tooltip: t.common.delete,
                                // 正在使用的那个节点不允许删除（NekoBox `!started`）
                                onTap: deleteEnabled ? onDelete : null,
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w600,
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
}
