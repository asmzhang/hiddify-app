import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/bottom_sheets/root_bottom_sheet.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **config 编辑页** —— 对齐 NekoBox `ConfigSettingsActivity`（`ui/profile/`，
/// `config_preferences.xml` 三字段：profileName / isOutboundOnly / serverConfig）。
///
/// 与 NekoBox 的对应与差异（记档）：
/// - NekoBox 用 **isOutboundOnly 开关**声明形态（type=0/1）；这里改为**按 JSON 内容
///   自动识别**（顶层有 `type` 键 ⇒ outbound 形态，否则 full 形态 —— 与
///   [isConfigOutboundPayload] 组装判据、NekoBox `displayType()` 同源）。理由：
///   显式开关会造出「声明与内容不符」的状态（声明 outbound 但 JSON 是整份配置），
///   NekoBox 对此不设防；自动识别让 UI 提示与组装层行为**永远一致**，不存在第二条
///   形态判定路径。识别结果只用于提示，不写进 payload（净定义原则）。
/// - `serverConfig`（EditConfigPreference）→ JSON 多行编辑框；
/// - NekoBox 是全屏 Activity，这里是**底部弹窗**（与 chain/协议表单同一平台差异处理）。
///
/// 保存链路照 chain：名称（=tag）+ payload 落 `proxy_entities`（type='config'），
/// `reconnect()` 让内核换配置。outbound 形态的 tag 在组装期注入
/// （NekoBox `ConfigBuilder.kt:402` 同语义），payload 保持净定义。
Future<void> showConfigSettingsSheet({
  required String tag,
  String? groupId,
  int? configGroupId,
  String initialPayload = '',
  bool isNew = false,
}) => showRootBottomSheet<void>(
  child: ConfigSettingsModal(
    tag: tag,
    targetGroupId: configGroupId,
    initialPayload: initialPayload,
    isNew: isNew,
  ),
  isScrollControlled: true,
);

class ConfigSettingsModal extends HookConsumerWidget {
  const ConfigSettingsModal({
    super.key,
    required this.tag,
    required this.targetGroupId,
    required this.initialPayload,
    required this.isNew,
  });

  /// config 实体 tag（= 名字）。新建时为空串，由名字输入框产生。
  final String tag;
  final int? targetGroupId;
  final String initialPayload;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final nameController = useTextEditingController(text: isNew ? '' : tag);
    final jsonController = useTextEditingController(text: initialPayload);
    // 实时形态识别：只驱动提示文案，不参与校验/写入。
    final formType = useState<_ConfigFormType>(_classify(jsonController.text));
    jsonController.addListener(() => formType.value = _classify(jsonController.text));
    final saving = useState(false);

    Future<void> save() async {
      final name = nameController.text.trim();
      if (name.isEmpty) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.form.required);
        return;
      }
      // 与 _showJsonEditDialog（protocol_form_modal）同一判据：非空必须是 JSON 对象。
      // 空串不允许 —— 没有 payload 的 config 节点没有意义（NekoBox 保存空 config
      // 会在构建期炸出 bad config，这里在入口拦下）。
      final payload = jsonController.text.trim();
      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } catch (_) {}
      if (decoded is! Map<String, dynamic>) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.customConfig.jsonInvalid);
        return;
      }

      saving.value = true;
      int? groupId = targetGroupId;
      if (groupId == null) {
        // 编辑模式没带 groupId：从库里按 tag 找回原归属（chain 同款回查）
        final existing = await ref.read(proxyEntityRepositoryProvider).nodeByTagAnyGroup(tag);
        groupId = existing?.groupId;
      }
      if (groupId == null) {
        saving.value = false;
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);
      final bool ok;
      if (isNew) {
        final created = await notifier.createNode(
          groupId: groupId,
          tag: name,
          type: kConfigEntityType,
          payload: payload,
        );
        ok = created != null;
      } else {
        ok = await notifier.updateNodePayload(
          groupId: groupId,
          tag: tag,
          payload: payload,
        );
      }
      saving.value = false;
      if (!context.mounted) return;
      if (!ok) {
        // 新建时最常见的失败原因是 tag 重名（与协议表单同一提示）
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      ref.read(inAppNotificationControllerProvider).showSuccessToast(
            isNew ? t.pages.proxies.customConfig.created : t.pages.proxies.customConfig.saved,
          );
      Navigator.of(context).pop();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextFormField(
                controller: nameController,
                decoration: InputDecoration(labelText: t.pages.proxies.form.profileName),
                enabled: isNew, // tag 是身份：编辑时不可改名（与协议表单同一约定）
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  switch (formType.value) {
                    _ConfigFormType.outbound => t.pages.proxies.customConfig.outboundType,
                    _ConfigFormType.full => t.pages.proxies.customConfig.configType,
                    _ConfigFormType.invalid => t.pages.proxies.customConfig.jsonInvalid,
                  },
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: formType.value == _ConfigFormType.invalid
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: TextField(
                  controller: jsonController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  decoration: InputDecoration(
                    labelText: t.pages.proxies.customConfig.serverConfig,
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: saving.value ? null : save,
                  child: saving.value
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(t.common.save),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ConfigFormType { outbound, full, invalid }

/// UI 提示用形态识别 —— 与组装层 [isConfigOutboundPayload] 同判据
/// （JSON 对象 + 顶层 `type` 键），坏 JSON 单独一态给红字提示。
_ConfigFormType _classify(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return _ConfigFormType.invalid;
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is Map<String, dynamic>) {
      return decoded['type'] is String ? _ConfigFormType.outbound : _ConfigFormType.full;
    }
  } catch (_) {}
  return _ConfigFormType.invalid;
}
