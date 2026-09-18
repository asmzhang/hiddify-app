import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/bottom_sheets/root_bottom_sheet.dart';
import 'package:hiddify/features/proxy/data/protocol_form.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **编辑**已有节点 —— 节点行 ✎（NekoBox `ConfigurationFragment.kt:1594` → `settingIntent`）。
///
/// 与 NekoBox 的呈现差异（已记档）：NekoBox 是独立全屏 Activity，这里用**底部弹窗**。
/// 字段、顺序、分节、下拉取值全部取自规格文件（[protocolFormSpecFor]），没有自创项。
///
/// 保存链路（与 🗑 删除同一套"实体是权威"的写法）：
///   表单值 → [applyProtocolForm] 生成新出站 JSON → 实体表落库
///   → invalidate 列表 → `reconnect()` 让内核换上新出站表（**不动接管状态**）。
///
/// `profileId` / `groupId` 二选一指定归属组 —— 手动分组的节点也要能编辑（批次 3）。
Future<void> showProtocolFormSheet({
  required String type,
  required String tag,
  required String payloadJson,
  String? profileId,
  int? groupId,
}) => showRootBottomSheet<void>(
  child: ProtocolFormModal(
    type: type,
    tag: tag,
    payloadJson: payloadJson,
    profileId: profileId,
    groupId: groupId,
  ),
  isScrollControlled: true,
);

/// **手动新建**节点 —— NekoBox 节点页 ＋ → Manual Settings →
/// `ProfileSettingsActivity`（`editingId == 0` 分支 → `ProfileManager.createProfile`）。
///
/// 没有 `payloadJson`：出站定义从零构造，种子键由 [protocolSeedPayload] 给
/// （`tls.enabled` 这类"构建期写死、表单不管"的键，编辑时靠原样保留，新建时只能显式给）。
Future<void> showProtocolCreateSheet({required int groupId, required String type}) => showRootBottomSheet<void>(
  child: ProtocolFormModal(type: type, tag: '', targetGroupId: groupId),
  isScrollControlled: true,
);

class ProtocolFormModal extends HookConsumerWidget {
  const ProtocolFormModal({
    super.key,
    required this.type,
    required this.tag,
    this.payloadJson,
    this.profileId,
    this.groupId,
    this.targetGroupId,
  });

  final String type;

  /// 编辑时是节点身份（只展示，不改 —— 改名是独立功能）；
  /// 新建时为空，由用户在表单顶部的"配置名称"里填。
  final String tag;

  /// 编辑模式的出站 JSON；为 null ⇒ 新建模式。
  final String? payloadJson;

  /// 编辑模式：归属组（订阅 id 与分组主键二选一）。
  final String? profileId;
  final int? groupId;

  /// 新建模式：节点落到哪个分组。
  final int? targetGroupId;

  bool get isCreate => targetGroupId != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final spec = protocolFormSpecFor(type);

    if (spec == null) {
      // 只会在"该协议还没有表单"时发生 —— 给一句明确的话，
      // 不给一个空表单（宁可不编辑，也不要写坏配置）。
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.pages.proxies.form.unsupported, style: theme.textTheme.bodyMedium),
        ),
      );
    }

    // 解析一次就固定：表单期间不改 payload 原文。
    // 新建模式用"种子"当原文（`tag` 在保存时才拼进去，所以这里不带）。
    final source = useMemoized(() {
      if (payloadJson == null) return jsonEncode(<String, dynamic>{'type': spec.type, ...protocolSeedPayload(spec)});
      return payloadJson!;
    }, [payloadJson, spec]);

    final parsed = useMemoized(() {
      try {
        final decoded = jsonDecode(source);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }, [source]);

    if (parsed == null) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(t.pages.proxies.form.jsonInvalid, style: theme.textTheme.bodyMedium),
        ),
      );
    }

    final values = useState<Map<String, String>>(readProtocolFormValues(payload: parsed, spec: spec));
    final name = useState('');
    final errors = useState<Set<String>>(const {});
    final saving = useState(false);
    final layout = protocolFormLayout(spec);

    Future<void> save() async {
      final trimmedName = name.value.trim();
      final bad = <String>[
        ...validateProtocolForm(spec: spec, values: values.value),
        if (isCreate && trimmedName.isEmpty) 'name',
      ];
      errors.value = bad.toSet();
      if (bad.isNotEmpty) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }

      final updated = isCreate
          ? buildProtocolPayload(spec: spec, tag: trimmedName, values: values.value)
          : applyProtocolForm(payloadJson: payloadJson!, spec: spec, values: values.value);
      if (updated == null) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }

      saving.value = true;
      final notifier = ref.read(proxiesOverviewNotifierProvider.notifier);
      final bool ok;
      if (isCreate) {
        final created = await notifier.createNode(
          groupId: targetGroupId!,
          tag: trimmedName,
          type: spec.type,
          payload: updated,
        );
        ok = created != null;
      } else {
        ok = await notifier.updateNodePayload(
          profileId: profileId,
          groupId: groupId,
          tag: tag,
          payload: updated,
        );
      }
      saving.value = false;
      if (!context.mounted) return;
      if (!ok) {
        // 新建时最常见的失败原因是 tag 重名（内核配置按 tag 建索引，不能重）。
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      ref.read(inAppNotificationControllerProvider).showSuccessToast(
        isCreate ? t.pages.proxies.form.created : t.pages.proxies.form.saved,
      );
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: DraggableScrollableSheet(
        initialChildSize: .75,
        maxChildSize: .95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // 头部：标题 + （编辑时）节点名与协议；新建时节点名由下面的输入框给。
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isCreate ? t.pages.proxies.form.createTitle : t.pages.proxies.form.title,
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isCreate ? type : "$type · $tag",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  // 配置名称 —— NekoBox 每份表单的第一个字段（`profile_name`），
                  // 新建时它就是节点的 `tag`（身份），所以必填。
                  if (isCreate)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: TextFormField(
                        initialValue: '',
                        onChanged: (v) => name.value = v,
                        decoration: InputDecoration(
                          labelText: t.pages.proxies.form.profileName,
                          isDense: true,
                          errorText: errors.value.contains('name') ? '*' : null,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                  for (final section in layout) ...[
                    if (section.section.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                        child: Text(
                          _sectionLabel(t, section.section),
                          style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
                        ),
                      ),
                    for (final field in section.fields)
                      _FieldRow(
                        field: field,
                        value: values.value[field.id] ?? '',
                        invalid: errors.value.contains(field.id),
                        label: _fieldLabel(t, field.id),
                        notSetLabel: t.common.notSet,
                        onChanged: (value) => values.value = {...values.value, field.id: value},
                        // 被容器规则"摘掉"的字段（如传输方式选了 tcp 时的 host/path）没有意义，
                        // 置灰但仍然可编辑 —— 与 NekoBox 一样不做动态隐藏（它的 Preference 也是静态的）。
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving.value ? null : () => Navigator.of(context).pop(),
                    child: Text(t.common.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: saving.value ? null : save,
                    child: saving.value
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(t.common.save),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 一行字段：文本 / 数字 / 开关 / 下拉。四种形态照 NekoBox 的 `Preference` 类型。
class _FieldRow extends StatelessWidget {
  const _FieldRow({
    required this.field,
    required this.value,
    required this.invalid,
    required this.label,
    required this.notSetLabel,
    required this.onChanged,
  });

  final ProtocolField field;
  final String value;
  final bool invalid;
  final String label;
  final String notSetLabel;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (field.kind) {
      case ProtocolFieldKind.boolean:
        return SwitchListTile.adaptive(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: theme.textTheme.bodyMedium),
          value: value == 'true',
          // 关 = 清空（NekoBox：`if (bean.allowInsecure) insecure = true`，false 不写键）
          onChanged: (v) => onChanged(v ? 'true' : 'false'),
        );

      case ProtocolFieldKind.choice:
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(label, style: theme.textTheme.bodyMedium),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value.isEmpty ? notSetLabel : value,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
          onTap: () async {
            final picked = await _pickChoice(
              context,
              title: label,
              choices: field.choices,
              selected: value,
              notSetLabel: notSetLabel,
            );
            if (picked != null) onChanged(picked);
          },
        );

      case ProtocolFieldKind.integer:
      case ProtocolFieldKind.text:
      case ProtocolFieldKind.stringList:
      case ProtocolFieldKind.integerList:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextFormField(
            initialValue: value,
            onChanged: onChanged,
            keyboardType: field.kind == ProtocolFieldKind.integer ? TextInputType.number : null,
            inputFormatters: field.kind == ProtocolFieldKind.integer
                ? [FilteringTextInputFormatter.digitsOnly]
                : null,
            decoration: InputDecoration(
              labelText: label,
              isDense: true,
              errorText: invalid ? (field.required ? '*' : '!') : null,
              border: const OutlineInputBorder(),
            ),
          ),
        );
    }
  }
}

Future<String?> _pickChoice(
  BuildContext context, {
  required String title,
  required List<String> choices,
  required String selected,
  required String notSetLabel,
}) => showDialog<String>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    children: [
      for (final choice in choices)
        SimpleDialogOption(
          onPressed: () => Navigator.of(context).pop(choice),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: choice == selected ? Icon(Icons.check_rounded, size: 18, color: Theme.of(context).colorScheme.primary) : null,
              ),
              Text(choice.isEmpty ? notSetLabel : choice),
            ],
          ),
        ),
    ],
  ),
);

String _sectionLabel(TranslationsEn t, String section) {
  final s = t.pages.proxies.form.section;
  return switch (section) {
    'proxy' => s.proxy,
    'security' => s.security,
    'ws' => s.ws,
    'plugin' => s.plugin,
    _ => section,
  };
}

/// 字段 id → 文案。语言包是**静态类型**的（slang 生成），所以这里用 switch 映射，
/// 不做动态字符串索引 —— 少一个键在编译期就报错，比运行时空白好。
String _fieldLabel(TranslationsEn t, String id) {
  final f = t.pages.proxies.form;
  return switch (id) {
    'serverAddress' => f.serverAddress,
    'serverPort' => f.serverPort,
    'password' => f.password,
    'sni' => f.sni,
    'allowInsecure' => f.allowInsecure,
    'alpn' => f.alpn,
    'certificates' => f.certificates,
    'utlsFingerprint' => f.utlsFingerprint,
    'method' => f.method,
    'pluginName' => f.pluginName,
    'pluginConfig' => f.pluginConfig,
    'uuid' => f.uuid,
    'flow' => f.flow,
    'packetEncoding' => f.packetEncoding,
    'transport' => f.transport,
    'host' => f.host,
    // trojan 的 NekoBox 表单里 host/path 的标题随传输方式切换
    // （StandardV2RaySettingsActivity.updateView），这里保持统一标题。
    'path' => f.path,
    'wsMaxEarlyData' => f.wsMaxEarlyData,
    'earlyDataHeaderName' => f.earlyDataHeaderName,
    'security' => f.security,
    'realityPubKey' => f.realityPubKey,
    'realityShortId' => f.realityShortId,
    'serverPorts' => f.serverPorts,
    'serverPassword' => f.serverPassword,
    'serverSNI' => f.serverSNI,
    'serverAllowInsecure' => f.serverAllowInsecure,
    'serverALPN' => f.serverALPN,
    'serverCertificates' => f.serverCertificates,
    'serverObfs' => f.serverObfs,
    'serverUploadSpeed' => f.serverUploadSpeed,
    'serverDownloadSpeed' => f.serverDownloadSpeed,
    'serverStreamReceiveWindow' => f.serverStreamReceiveWindow,
    'serverConnectionReceiveWindow' => f.serverConnectionReceiveWindow,
    'hopInterval' => f.hopInterval,
    'serverProtocol' => f.serverProtocol,
    'serverUsername' => f.serverUsername,
    'serverAuthString' => f.serverAuthString,
    'serverAuthBase64' => f.serverAuthBase64,
    'serverPrivateKey' => f.serverPrivateKey,
    'serverPassword1' => f.serverPassword1,
    'version' => f.version,
    'serverInsecureConcurrency' => f.serverInsecureConcurrency,
    'serverMTU' => f.serverMTU,
    'localAddress' => f.localAddress,
    'privateKey' => f.privateKey,
    'peerPublicKey' => f.peerPublicKey,
    'peerPreSharedKey' => f.peerPreSharedKey,
    'reserved' => f.reserved,
    _ => id,
  };
}
