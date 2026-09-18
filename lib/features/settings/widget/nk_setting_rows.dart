import 'package:flutter/material.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/utils/preferences_utils.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// NekoBox 设置页行组件（global_preferences.xml 风格）：
/// 紧凑行、无 leading 图标、当前值在右侧（.srow .v），开关行右侧 Switch（.toggle）。
/// 每行之间自动插入 0.5px 分隔线，行本身包在 NkCard（padding 0）里。

/// 分节卡片：children 为若干行，行间自动加分隔线。
class NkSettingCard extends StatelessWidget {
  const NkSettingCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final divider = Divider(
      height: 1,
      thickness: 0.5,
      indent: 16,
      endIndent: 16,
      color: Theme.of(context).dividerColor,
    );
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      children.add(rows[i]);
      if (i != rows.length - 1) children.add(divider);
    }
    return NkCard(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }
}

bool _defaultValidator(String _) => true;

/// 值行：右侧灰色当前值，点按弹输入对话框。
class NkValueRow<T> extends HookConsumerWidget {
  const NkValueRow({
    super.key,
    required this.title,
    required this.value,
    required this.preferences,
    this.subtitle,
    this.presentValue,
    this.formatInputValue,
    this.validateInput,
    this.inputToValue,
    this.digitsOnly = false,
    this.enabled = true,
    this.trailing,
  });

  final String title;
  final T value;
  final PreferencesNotifier<T, dynamic> preferences;
  final String? subtitle;
  final String Function(T value)? presentValue;
  final String Function(T value)? formatInputValue;
  final bool Function(String value)? validateInput;
  final T? Function(String input)? inputToValue;
  final bool digitsOnly;
  final bool enabled;

  /// 行尾附加控件（如端口启停开关）；与右侧当前值文本并存。
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final text = presentValue?.call(value) ?? value.toString();
    return ListTile(
      dense: true,
      enabled: enabled,
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: subtitle == null ? null : Text(subtitle!, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) trailing!,
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              text,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
      onTap: enabled
          ? () async {
              final inputValue = await ref
                  .read(dialogNotifierProvider.notifier)
                  .showSettingInput(
                    title: title,
                    initialValue: value,
                    validator: validateInput ?? _defaultValidator,
                    valueFormatter: formatInputValue,
                    onReset: preferences.reset,
                    digitsOnly: digitsOnly,
                    mapTo: inputToValue,
                    possibleValues: preferences.possibleValues,
                  );
              if (inputValue == null) return;
              await preferences.update(inputValue);
            }
          : null,
    );
  }
}

/// 选择行：右侧灰色当前项，点按弹选择器。
class NkChoiceRow<T> extends HookConsumerWidget {
  const NkChoiceRow({
    super.key,
    required this.title,
    required this.selected,
    required this.preferences,
    required this.choices,
    required this.presentChoice,
    this.showFlag = false,
    this.enabled = true,
  });

  final String title;
  final T selected;
  final PreferencesNotifier<T, dynamic> preferences;
  final List<T> choices;
  final String Function(T value) presentChoice;
  final bool showFlag;
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      enabled: enabled,
      title: Text(title, style: theme.textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            presentChoice(selected),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: enabled
          ? () async {
              final selection = await ref
                  .read(dialogNotifierProvider.notifier)
                  .showSettingPicker<T>(
                    title: title,
                    showFlag: showFlag,
                    selected: selected,
                    options: choices,
                    getTitle: (e) => presentChoice(e),
                    onReset: preferences.reset,
                  );
              if (selection == null) return;
              await preferences.update(selection);
            }
          : null,
    );
  }
}

/// 开关行：右侧 Switch（.toggle）。
class NkSwitchRow extends StatelessWidget {
  const NkSwitchRow({super.key, required this.title, required this.value, required this.onChanged, this.subtitle});

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: subtitle == null ? null : Text(subtitle!, style: theme.textTheme.bodySmall),
      trailing: Switch.adaptive(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

/// 导航行：右侧 ›，进入子页。
class NkNavRow extends StatelessWidget {
  const NkNavRow({super.key, required this.title, required this.onTap, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      title: Text(title, style: theme.textTheme.bodyMedium),
      subtitle: subtitle == null ? null : Text(subtitle!, style: theme.textTheme.bodySmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          Icon(Icons.chevron_right_rounded, size: 20, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
      onTap: onTap,
    );
  }
}
