import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 分组设置表单 —— NekoBox `GroupSettingsActivity` 的对话框等价物。
///
/// 规格映射（架构差异记档，见 `groups_page.dart` 类注释）：
/// - 分组名（`group_name` = 分组名）→ 本 sheet 可编辑。
/// - 订阅链接 / 去重 / 自动更新 → NekoBox 与分组同实体所以同屏；本项目订阅是
///   一等实体（RemoteProfileEntity），这些字段由**订阅页/配置编辑**管理
///   （归一原则：一个能力一个入口）——订阅组显示提示行代替。
///   去重在本项目是导入级恒开（`Deduplication.hash` 等价物），无开关。
/// - 删除 → spec 工具栏 `action_delete` + `delete_group_prompt` 确认框；
///   这里是 sheet 内 danger 动作 + 同款确认（确认框在页面侧）。
/// - 前后置代理 → 等 chain 语义定案（已记档，不进 sheet）。
class NkGroupSettingsSheet extends ConsumerStatefulWidget {
  const NkGroupSettingsSheet({
    super.key,
    required this.initialName,
    required this.isSubscription,
    required this.onSave,
    required this.onDelete,
    this.onOpenSubscriptions,
  });

  final String initialName;
  final bool isSubscription;

  /// 保存（页面侧执行重命名；返回后 sheet 自行关闭）。
  final Future<void> Function(String name) onSave;

  /// 删除（页面侧确认 + 删除；返回 true = 已删除，sheet 关闭）。
  final Future<bool> Function() onDelete;

  /// 订阅组提示行点击 → 打开订阅管理页（可达性闭环：归一原则下订阅字段的
  /// 唯一管理入口；null = 不可点）。
  final VoidCallback? onOpenSubscriptions;

  @override
  ConsumerState<NkGroupSettingsSheet> createState() => _NkGroupSettingsSheetState();
}

class _NkGroupSettingsSheetState extends ConsumerState<NkGroupSettingsSheet> {
  late final TextEditingController _name = TextEditingController(text: widget.initialName);
  bool _busy = false;

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || name == widget.initialName || _busy) return;
    setState(() => _busy = true);
    await widget.onSave(name);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() => _busy = true);
    final deleted = await widget.onDelete();
    if (deleted && mounted) Navigator.of(context).pop();
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    return AlertDialog(
      title: Text(t.pages.groups.settings),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _name,
            decoration: InputDecoration(labelText: t.pages.groups.name),
            enableSuggestions: false,
            autocorrect: false,
          ),
          if (widget.isSubscription)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              // 提示行可点 → 订阅管理页（功能②遗留可达性修复；chevron = 可点示性）。
              child: InkWell(
                onTap: widget.onOpenSubscriptions,
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        t.pages.groups.subscriptionHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                              decoration:
                                  widget.onOpenSubscriptions != null ? TextDecoration.underline : null,
                            ),
                      ),
                    ),
                    if (widget.onOpenSubscriptions != null)
                      Icon(Icons.chevron_right_rounded, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
        ],
      ),
      actions: [
        // spec：删除是 GroupSettingsActivity 工具栏 action_delete 的危险动作。
        TextButton(
          onPressed: _busy ? null : _delete,
          style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          child: Text(t.common.delete),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(t.common.save),
        ),
      ],
    );
  }
}
