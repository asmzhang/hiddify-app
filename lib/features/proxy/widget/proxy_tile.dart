import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/core/widget/nekobox/nk_theme.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/offline_proxy_parser.dart';
import 'package:hiddify/features/proxy/data/outbound_to_link.dart';
import 'package:hiddify/features/proxy/widget/proxy_tile_spec.dart';
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
///        行3 协议（主题强调色纯文字）             状态（延迟绿/红纯文字）
/// ```
///
/// 行内动作照 `layout_profile.xml` 的**顺序与可见性**：`edit` → `share` → `remove`，
/// 三者默认显示，且只有"正在使用的那一个节点"禁用编辑/删除
/// （`ui/ConfigurationFragment.kt:1624-1625`：`isEnabled = !started`；
///  `:1612-1613` 的 `isGone = select` 只在"选择器模式"下隐藏 —— 那是 Chain 端点选择等场景）。
///
/// 与 NekoBox 的差异：
/// - 协议字段表单覆盖 15 类内核可用协议；Chain / Config 使用各自专用编辑页。
/// - 分享菜单保留标准链接二维码/剪贴板与配置 JSON 剪贴板/文件；SN Link 是 Kryo
///   专有格式，按项目定案不移植。标准链接当前覆盖 9 类（含 AnyTLS）。
/// - 改名（NekoBox `name_preferences.xml`）未纳入表单：`tag` 是节点身份，改名要跨
///   内核配置 / 选中偏好 / 删除基线三处迁移，属独立改动。
/// - 长按弹出节点详情（hiddify 补充能力）；国旗/序号不单独渲染（订阅名中的 emoji 保留）。
/// - 协议使用 `accentOrTextSecondary` 对应的主题强调色纯文字，而非原型稿中的 chip。
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
    // NekoBox `ConfigurationFragment.kt:1557-1559`：未开启 alwaysShowAddress
    // （默认 false）时地址置空 —— 行2 只在有流量时出现。
    final alwaysShowAddress = ref.watch(Preferences.alwaysShowAddress);
    var address = alwaysShowAddress ? displayAddress(proxy.host, proxy.port) : '';
    // NekoBox 内建协议统一用 accentOrTextSecondary；插件型才回落主文字色。
    final typeColor = theme.colorScheme.secondary;
    final configPayload = proxy.type == 'config' ? ref.watch(outboundJsonProvider(proxy.tag)).valueOrNull : null;
    final typeLabel = nkProxyTypeLabel(t, type: proxy.type, isSecure: proxy.isSecure, configPayload: configPayload);
    // NekoBox `traffic` = `%1$s↑ %2$s↓`，参数顺序为 tx / rx。
    final traffic = proxy.download > 0 || proxy.upload > 0
        ? '${proxy.upload.toInt().size()}↑ ${proxy.download.toInt().size()}↓'
        : null;
    if (traffic != null && address.length >= 30) {
      address = '${address.substring(0, 27)}...';
    }
    // 行3 右侧：状态 —— 纯函数规格投影（`proxy_tile_spec.dart`，NekoBox
    // `ConfigurationFragment.kt:1565-1592`）：未测速时流量**挪到状态位**显示
    // （行2 置空，两处只显示一处），无流量 = 空字符串（不是 "—" 占位）。
    final showTrafficInAddressRow = nkProxyShowTrafficInAddressRow(hasTraffic: traffic != null, tested: delay > 0);
    final (:text, :color) = nkProxyStatus(
      t,
      isGroup: proxy.isGroup,
      groupSelectedTagDisplay: proxy.groupSelectedTagDisplay.trim(),
      delay: delay,
      traffic: traffic,
      errorColor: NkColors.profileUnavailable,
      testedColor: delay >= NkColors.latencyTimeoutMs ? NkColors.profileUnavailable : NkColors.profileAvailable,
      neutralColor: theme.colorScheme.onSurfaceVariant,
    );
    final statusText = text;
    final statusColor = color;

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
                      // 顺序照 NekoBox `layout_profile.xml`：edit → share → remove。
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                proxy.tagDisplay,
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
                            // 分享菜单：标准链接动作 + 配置导出。
                            // SN Link 是 Kryo 专有格式，按项目定案不移植。
                            if (nkProxyShowsShare(proxy.type))
                              AdaptiveMenu(
                                items: _shareItems(context, ref, t),
                                builder: (context, toggleVisibility, child) => NkCardAction(
                                  icon: AdaptiveIcon(context).share,
                                  tooltip: t.common.share,
                                  onTap: toggleVisibility,
                                ),
                                child: null,
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
                      // 行 2：地址（alwaysShowAddress 门控） ······ 流量（未测速时挪状态位）。
                      if (address.isNotEmpty || showTrafficInAddressRow)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 8, 4),
                          child: Row(
                            children: [
                              if (address.isNotEmpty)
                                Flexible(
                                  child: Text(
                                    address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              const Spacer(),
                              if (showTrafficInAddressRow)
                                Text(
                                  traffic!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      // 行 3：协议（主题强调色纯文字） ······ 状态。
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 8, 12),
                        child: Row(
                          children: [
                            Text(typeLabel, style: theme.textTheme.bodyMedium?.copyWith(color: typeColor)),
                            const Spacer(),
                            Text(statusText, style: theme.textTheme.bodyMedium?.copyWith(color: statusColor)),
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

  List<AdaptiveMenuItem> _shareItems(BuildContext context, WidgetRef ref, Translations t) {
    final items = <AdaptiveMenuItem>[
      if (outboundTypeHasStandardLink(proxy.type)) ...[
        AdaptiveMenuItem(title: t.pages.groups.shareQr, onTap: () => _showStandardQr(context, ref, t)),
        AdaptiveMenuItem(title: t.pages.groups.exportToClipboard, onTap: () => _copyStandardLink(context, ref, t)),
      ],
      AdaptiveMenuItem(
        title: t.common.configuration,
        subItems: [
          AdaptiveMenuItem(title: t.pages.groups.exportToClipboard, onTap: () => _copyConfigJson(context, ref, t)),
          AdaptiveMenuItem(title: t.pages.groups.exportToFile, onTap: () => _exportConfigJson(context, ref, t)),
        ],
      ),
    ];
    return items;
  }

  Future<String?> _readOutboundJson(WidgetRef ref) async {
    try {
      return await ref.read(outboundJsonProvider(proxy.tag).future);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _readStandardLink(WidgetRef ref) async {
    final json = await _readOutboundJson(ref);
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, dynamic> ? outboundToLink(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  void _shareError(WidgetRef ref, Translations t) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
  }

  Future<void> _showStandardQr(BuildContext context, WidgetRef ref, Translations t) async {
    final link = await _readStandardLink(ref);
    if (!context.mounted) return;
    if (link == null) {
      _shareError(ref, t);
      return;
    }
    await showQrCodeDialog(link, message: proxy.tagDisplay);
  }

  Future<void> _copyStandardLink(BuildContext context, WidgetRef ref, Translations t) async {
    final link = await _readStandardLink(ref);
    if (!context.mounted) return;
    if (link == null) {
      _shareError(ref, t);
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
    }
  }

  Future<void> _copyConfigJson(BuildContext context, WidgetRef ref, Translations t) async {
    final json = await _readOutboundJson(ref);
    if (!context.mounted) return;
    if (json == null) {
      _shareError(ref, t);
      return;
    }
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) {
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
    }
  }

  Future<void> _exportConfigJson(BuildContext context, WidgetRef ref, Translations t) async {
    final json = await _readOutboundJson(ref);
    if (!context.mounted) return;
    if (json == null) {
      _shareError(ref, t);
      return;
    }
    final bytes = utf8.encode(json);
    try {
      final outputFile = await FilePicker.platform.saveFile(
        fileName: '${proxy.tagDisplay}.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (outputFile == null || !context.mounted) return;
      if (PlatformUtils.isDesktop) {
        final file = File(outputFile);
        if (!await file.exists()) await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      if (context.mounted) {
        ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.file.success);
      }
    } catch (_) {
      if (context.mounted) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.common.msg.export.file.failure);
      }
    }
  }
}
