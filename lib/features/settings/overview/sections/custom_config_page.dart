import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 全局自定义配置编辑页（NekoBox `globalCustomConfig` / `EditConfigPreference`）。
///
/// 规格 = 一段 sing-box 原生 JSON，在内核拼装完成后深合并进最终配置
/// （语义与挂载点见 `docs/design/custom-config-2026-09-18.md`）。
/// 无效 JSON 拦截在**写入时**（设计文档 §4：不拦在启动时——启动侧另有
/// raw 失败回落现状路径的兜底，两道防线互不替代）。
///
/// NekoBox 用对话框编辑；这里用全屏页——移动端对话框里塞大文本域体验差，
/// 且需要放合并语义提示与「清空」动作。
class CustomConfigPage extends ConsumerStatefulWidget {
  const CustomConfigPage({super.key});

  @override
  ConsumerState<CustomConfigPage> createState() => _CustomConfigPageState();
}

class _CustomConfigPageState extends ConsumerState<CustomConfigPage> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(ConfigOptions.customConfig));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 行内实时提示用：只报语法错误，不阻止编辑；真正的拦截在保存时。
  String? _syntaxError(String raw) {
    if (raw.trim().isEmpty) return null; // 空 = 停用，合法
    try {
      jsonDecode(raw);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  bool _isValid(String raw) {
    if (raw.trim().isEmpty) return true;
    return jsonDecode(raw) is Map<String, dynamic>;
  }

  Future<void> _save() async {
    final t = ref.read(translationsProvider).requireValue;
    final raw = _controller.text.trim();
    if (!_isValid(raw)) {
      final syntax = _syntaxError(raw) ?? t.pages.settings.customConfig.invalidJson;
      ref.read(inAppNotificationControllerProvider).showErrorToast(syntax);
      return;
    }
    await ref.read(ConfigOptions.customConfig.notifier).update(raw);
    if (mounted) Navigator.of(context).maybePop();
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.customConfig.saved);
  }

  Future<void> _clear() async {
    final t = ref.read(translationsProvider).requireValue;
    _controller.clear();
    setState(() => _errorText = null);
    await ref.read(ConfigOptions.customConfig.notifier).update("");
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.settings.customConfig.cleared);
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final hasContent = _controller.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.customConfig.title),
        actions: [
          TextButton(onPressed: () => _save(), child: Text(t.common.save)),
          IconButton(
            tooltip: t.common.reset,
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: hasContent ? () => _clear() : null,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              keyboardType: TextInputType.multiline,
              style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.4),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.all(16),
                hintText: '{ "route": { "rules+": [ ... ] } }',
                border: InputBorder.none,
                errorText: _errorText,
              ),
              onChanged: (value) {
                setState(() => _errorText = _syntaxError(value));
              },
            ),
          ),
          Material(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                t.pages.settings.customConfig.hint,
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
