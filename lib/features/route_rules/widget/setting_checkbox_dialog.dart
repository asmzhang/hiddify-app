import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/dialog/root_dialog.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:protobuf/protobuf.dart';

class SettingCheckboxDialog extends ConsumerWidget {
  const SettingCheckboxDialog({
    super.key,
    required this.title,
    required this.values,
    required this.selectedValues,
    this.defaultValue,
    this.t,
  });

  final String title;
  final List<ProtobufEnum> values;
  final List<ProtobufEnum> selectedValues;
  final List<ProtobufEnum>? defaultValue;
  final Map<String, String>? t;

  String textWithTranslation(ProtobufEnum e) {
    if (t == null) return '$e';
    return t!['$e'] ?? '$e';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final checkboxNotififier = dialogCheckboxNotifierProvider(selectedValues);
    final current = ref.watch(checkboxNotififier);

    return AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 300),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: values
                .map(
                  (e) => CheckboxListTile(
                    title: Text(textWithTranslation(e)),
                    value: current.contains(e),
                    onChanged: (_) => ref.read(checkboxNotififier.notifier).update(e),
                  ),
                )
                .toList(),
          ),
        ),
      ),
      actions: [
        if (defaultValue != null) TextButton(child: Text(t.common.reset), onPressed: () => context.pop(defaultValue)),
        TextButton(child: Text(t.common.cancel), onPressed: () => context.pop()),
        TextButton(child: Text(t.common.done), onPressed: () => context.pop(current)),
      ],
    );
  }
}

/// 弹出多选设置对话框（业务入口留在 feature 侧）。
Future<List<ProtobufEnum>?> showSettingCheckboxDialog({
  required String title,
  required List<ProtobufEnum> values,
  required List<ProtobufEnum> selectedValues,
  List<ProtobufEnum>? defaultValue,
  Map<String, String>? t,
}) => showRootDialog<List<ProtobufEnum>?>(
  SettingCheckboxDialog(title: title, values: values, selectedValues: selectedValues, defaultValue: defaultValue, t: t),
);
