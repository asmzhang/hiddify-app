import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart' show kChainEntityType, kConfigEntityType;
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/widget/chain_settings_page.dart';
import 'package:hiddify/features/proxy/widget/config_settings_page.dart';
import 'package:hiddify/features/proxy/widget/protocol_form_modal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **手动新建节点的完整流程** —— 对应 NekoBox 节点页 ＋ → Manual Settings
/// （`res/menu/add_profile_menu.xml:25-78`）→ 该协议的 `*SettingsActivity` →
/// 保存时 `ProfileSettingsActivity.saveAndExit` 的 `editingId == 0` 分支。
///
/// 三步（与 NekoBox 一一对应）：
/// 1. **选协议** —— 配置页按 NekoBox 渲染二级协议菜单并通过 [initialProtocol]
///    直接进入对应表单；未指定时保留对话框作为复用入口。
/// 2. **定归属组** —— 照 `DataStore.selectedGroupForImport()`：
///    当前分组只有在数据库中确实是 BASIC 时才使用，否则取 userOrder 最前的 BASIC；
///    没有 BASIC 时懒创建「未分组」。
/// 3. **填表单** —— 打开新建模式的协议表单；保存时落库并让内核换配置。
Future<void> startManualNodeFlow(BuildContext context, WidgetRef ref, {String? initialProtocol}) async {
  final t = ref.read(translationsProvider).requireValue;

  final protocol = initialProtocol ?? await _pickProtocol(context, t);
  if (protocol == null || !context.mounted) return;

  final targetGroupId = await _resolveTargetGroupId(ref);
  if (targetGroupId == null) {
    ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
    return;
  }

  // chain 不是协议表单：直接开 ChainSettings 页（NekoBox `ConfigurationFragment.kt:444-446`
  // `action_new_chain` → `ChainSettingsActivity` 的对应物，新建模式 = 空成员列表）。
  if (protocol == kChainEntityType) {
    await showChainSettingsSheet(tag: '', chainGroupId: targetGroupId, isNew: true);
    return;
  }

  // config 同样不是协议表单（NekoBox `action_new_config` → `ConfigSettingsActivity`
  // 的对应物，新建模式 = 空 JSON）：payload 是用户手写的整份 JSON，没有字段可言。
  if (protocol == kConfigEntityType) {
    await showConfigSettingsSheet(tag: '', configGroupId: targetGroupId, isNew: true);
    return;
  }

  await showProtocolCreateSheet(groupId: targetGroupId, type: protocol);
}

/// 选协议。返回协议名（出站 JSON 的 `type` 取值）；取消返回 null。
Future<String?> _pickProtocol(BuildContext context, TranslationsEn t) => showDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(t.pages.proxies.form.selectProtocol),
    children: [
      for (final protocol in kManualCreatableProtocols)
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(protocol),
          child: Text(protocolDisplayName(protocol)),
        ),
    ],
  ),
);

/// 新节点落到哪个手动组。
///
/// 优先"当前正看着的手动组"（NekoBox `currentGroup()` 若为 BASIC 就返回它），
/// 否则第一个手动组；都没有就建「未分组」。
Future<int?> _resolveTargetGroupId(WidgetRef ref) {
  final selectedGroupId = manualGroupIdOf(ref.read(selectedProxyGroupTagProvider));
  return ref.read(proxyEntityRepositoryProvider).selectedGroupForImport(selectedGroupId);
}
