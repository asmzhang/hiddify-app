import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 配置卡片的**共享动作**（归一原则：一个能力一个实现）。
///
/// 这两个函数由 NekoBox 复刻卡片（[NkProfileTile] 的行内动作与「更多」菜单）共用，
/// 卡片的**视觉**不在这里 —— 见 `nk_profile_tile.dart`。
///
/// 历史：本文件原名 `profile_tile.dart`，曾是 hiddify 旧版"胖卡"（首页订阅摘要卡）
/// 的实现；旧首页 HomePage 退役后（`home` 路由已改为代理/配置页），胖卡整簇代码一并删除，
/// 只剩这两个仍被复刻卡片引用的动作函数，故改名。

/// 分享子项（URL 复制 / 二维码 / JSON 复制）。
List<AdaptiveMenuItem> buildProfileShareItems(BuildContext context, WidgetRef ref, ProfileEntity profile) {
  final t = ref.read(translationsProvider).requireValue;
  return [
    if (profile case RemoteProfileEntity(:final url, :final name)) ...[
      AdaptiveMenuItem(
        title: t.pages.profiles.share.urlToClipboard,
        onTap: () async {
          final link = LinkParser.generateSubShareLink(url, name);
          if (link.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: link));
            if (context.mounted) {
              ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
            }
          }
        },
      ),
      AdaptiveMenuItem(
        title: t.pages.profiles.share.showUrlQr,
        onTap: () async {
          final link = LinkParser.generateSubShareLink(url, name);
          if (link.isNotEmpty) {
            await showQrCodeDialog(link, message: name);
          }
        },
      ),
    ],
    AdaptiveMenuItem(
      title: t.pages.profiles.share.jsonToClipboard,
      onTap: () async => await ref.read(profilesNotifierProvider.notifier).exportConfigToClipboard(profile),
    ),
  ];
}

/// 删除确认。
Future<void> confirmDeleteProfile(BuildContext context, WidgetRef ref, ProfileEntity profile) async {
  final t = ref.read(translationsProvider).requireValue;
  await ref
      .read(dialogNotifierProvider.notifier)
      .showConfirmation(
        title: t.dialogs.confirmation.profile.delete.title,
        message: t.dialogs.confirmation.profile.delete.msg,
      )
      .then((deleteConfirmed) async {
        if (!deleteConfirmed) return;
        await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
      });
}
