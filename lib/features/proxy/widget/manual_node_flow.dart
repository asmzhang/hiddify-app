import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart' show kChainEntityType;
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/chain_settings_page.dart';
import 'package:hiddify/features/proxy/widget/protocol_form_modal.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **手动新建节点的完整流程** —— 对应 NekoBox 节点页 ＋ → Manual Settings
/// （`res/menu/add_profile_menu.xml:25-78`）→ 该协议的 `*SettingsActivity` →
/// 保存时 `ProfileSettingsActivity.saveAndExit` 的 `editingId == 0` 分支。
///
/// 三步（与 NekoBox 一一对应）：
/// 1. **选协议** —— NekoBox 是二级子菜单 17 项；我们有表单的见 [kManualCreatableProtocols]
///    （批次 2 后 10 项；trojan_go 不移植、wg 待 endpoint 通路，理由见该常量注释），
///    所以用一个对话框列出来代替子菜单（平台差异，已记档）。
/// 2. **定归属组** —— 照 `DataStore.selectedGroupForImport()`：
///    当前分组是手动组（`type = BASIC`）就用它，否则用第一个手动组；
///    **一个手动组都没有**时懒创建一个「未分组」（`DataStore.kt:56` 的 `ProxyGroup(ungrouped = true)`）。
/// 3. **填表单** —— 打开新建模式的协议表单；保存时落库并让内核换配置。
Future<void> startManualNodeFlow(BuildContext context, WidgetRef ref) async {
  final t = ref.read(translationsProvider).requireValue;

  final protocol = await _pickProtocol(context, t);
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
Future<int?> _resolveTargetGroupId(WidgetRef ref) async {
  final selectedKey = ref.read(selectedProxyGroupTagProvider);
  final selectedGroupId = manualGroupIdOf(selectedKey);
  if (selectedGroupId != null) return selectedGroupId;

  final tabs = ref.read(proxyGroupTabsProvider).valueOrNull ?? const <ProxyGroupTab>[];
  final firstManual = tabs.where((tab) => tab.groupId != null).firstOrNull;
  if (firstManual?.groupId != null) return firstManual!.groupId;

  // 一个手动组都没有 —— 注意"空的未分组组不进 Tab"（见 proxyGroupTabsProvider），
  // 所以这里必须走了库而不是 Tab 列表才能发现它，于是直接交给仓库去确保存在。
  final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);
  return notifier.ensureUngroupedGroup();
}
