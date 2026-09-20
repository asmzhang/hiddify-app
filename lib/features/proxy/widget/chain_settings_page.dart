import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/bottom_sheets/root_bottom_sheet.dart';
import 'package:hiddify/features/proxy/data/config_assembly.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **chain 编辑页** —— 对齐 NekoBox `ChainSettingsActivity`（`ui/profile/`）：
/// 名字 + 有序成员列表 + 添加/替换/删除/拖排序，保存落 `proxy_entities`
/// （type='chain'，payload=`{"proxies":[…]}`，设计 `docs/design/chain-2026-09-20.md` D5）。
///
/// 与 NekoBox 的对应与差异（记档）：
/// - NekoBox 是全屏 Activity + RecyclerView + ItemTouchHelper；这里是**底部弹窗**
///   + ReorderableListView —— 呈现层平台差异（与协议表单同一处理，见 protocol_form_modal）；
/// - 拖排序 = 长按拖动（ItemTouchHelper 上下拖的 Flutter 对应物）；
/// - 左滑删除 = Dismissible（`ItemTouchHelper.START` 滑删）；
/// - 点已有成员行 = **替换模式**（NekoBox `replacing`：选新节点替换该行，不是进子编辑）；
/// - 「添加节点」行 = NekoBox AddHolder；
/// - 循环引用候选**置灰**（NekoBox `testProfileContains` → `circular_reference` 弹窗；
///   本项目改为禁点 + 行内提示，语义一致：链不能包含自身）。
///
/// **chain 不是协议表单**：名字（= tag）+ 成员列表就是它的全部字段；成员是**有序 tag
/// 引用**（UI 序 = 流量经过顺序：第一行入口、最后一行落地 —— NekoBox `ChainBean.proxies`
/// 同语义），保存只写这一段 JSON。
Future<void> showChainSettingsSheet({
  required String tag,
  String? groupId,
  int? chainGroupId,
  List<String> initialProxies = const [],
  bool isNew = false,
}) => showRootBottomSheet<void>(
  child: ChainSettingsModal(
    tag: tag,
    targetGroupId: chainGroupId,
    initialProxies: initialProxies,
    isNew: isNew,
  ),
  isScrollControlled: true,
);

class ChainSettingsModal extends HookConsumerWidget {
  const ChainSettingsModal({
    super.key,
    required this.tag,
    required this.targetGroupId,
    required this.initialProxies,
    required this.isNew,
  });

  /// chain 实体 tag（= 名字）。新建时为空串，由名字输入框产生。
  final String tag;
  final int? targetGroupId;
  final List<String> initialProxies;
  final bool isNew;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final nameController = useTextEditingController(text: isNew ? '' : tag);
    final proxies = useState<List<String>>(List.of(initialProxies));
    // 替换模式：非 -1 时点成员选择 = 替换这一行（NekoBox `replacing` 语义）
    final replacingIndex = useState(-1);
    final formKey = useState(GlobalKey<FormState>());

    // 全部可选成员 + 各自的展开（判环用）。一次性取，不监听 —— 弹窗生命周期内
    // 实体表变化不刷新成员清单（NekoBox 的 ProfileSelectActivity 同样是打开时快照）。
    final membersSnapshot = useFuture(
      ref.read(proxyEntityRepositoryProvider).selectableChainMembers(),
    );

    // 展开某个候选 tag 为它的"链摘要"（嵌套 chain 递归）；环返回 null。
    List<String>? flattenOf(String candidate, Map<String, List<String>> proxiesByTag) {
      final visiting = <String>{kChainTagPrefix + tag, candidate};
      List<String>? rec(String current) {
        final defs = proxiesByTag[current];
        if (defs == null) return null;
        if (visiting.contains(current)) return null;
        final expanded = <String>[];
        visiting.add(current);
        for (final member in defs) {
          if (proxiesByTag.containsKey(member)) {
            final part = rec(member);
            if (part == null) return null;
            expanded.addAll(part);
          } else {
            expanded.add(member);
          }
        }
        visiting.remove(current);
        return expanded;
      }

      return rec(candidate);
    }

    Future<void> pickMember(int atIndex) async {
      final all = membersSnapshot.data ?? const [];
      final proxiesByTag = <String, List<String>>{};
      for (final row in all) {
        if (row.type == kChainEntityType) {
          final defs = chainProxiesOf(row.payload);
          if (defs != null) proxiesByTag[row.tag] = defs;
        }
      }

      final selected = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(t.pages.proxies.chain.selectMember),
          children: [
            for (final row in all)
              Builder(
                builder: (context) {
                  // 循环引用判据（NekoBox ChainSettingsActivity.kt:181-204 同构）：
                  // 候选展开后包含正在编辑的 chain ⇒ 置灰。比较在"展开后的
                  // 跳点集合"上做 —— 嵌套引用也是环。
                  final flattened = flattenOf(row.tag, proxiesByTag);
                  final blocked = flattened == null || flattened.contains(kChainTagPrefix + tag);
                  // endpoint 型（wireguard）不能做跳点 —— 内核 stub 拒收（设计 D2）。
                  final endpointBlocked = row.type == 'wireguard';
                  final disabled = blocked || endpointBlocked;
                  return SimpleDialogOption(
                    onPressed: disabled ? null : () => Navigator.of(context).pop(row.tag),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(row.displayName.isEmpty ? row.tag : row.displayName),
                              if (row.type == kChainEntityType && flattened != null)
                                Text(
                                  flattened.join(' ➔ '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (endpointBlocked)
                                Text(
                                  t.pages.proxies.chain.endpointBlocked,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              if (blocked && !endpointBlocked)
                                Text(
                                  t.pages.proxies.chain.circular,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      );
      if (selected == null) return;
      if (atIndex >= 0) {
        proxies.value = [...proxies.value]..[atIndex] = selected;
        replacingIndex.value = -1;
      } else {
        proxies.value = [...proxies.value, selected];
      }
    }

    Future<void> save() async {
      final valid = formKey.value.currentState?.validate() ?? false;
      if (!valid) return;
      final name = nameController.text.trim();
      if (name.isEmpty) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.form.required);
        return;
      }
      if (proxies.value.isEmpty) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.proxies.chain.empty);
        return;
      }
      int? groupId = targetGroupId;
      if (groupId == null) {
        // 编辑模式没带 groupId：从库里按 tag 找回原归属
        final existing = await ref.read(proxyEntityRepositoryProvider).nodeByTagAnyGroup(tag);
        groupId = existing?.groupId;
      }
      if (groupId == null) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      final saved = await ref
          .read(proxyEntityRepositoryProvider)
          .saveChain(groupId: groupId, tag: name, proxies: proxies.value, displayName: name);
      if (saved == null) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
        return;
      }
      if (context.mounted) Navigator.of(context).pop();
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Form(
        key: formKey.value,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: t.pages.proxies.form.profileName),
                  validator: (value) => (value == null || value.trim().isEmpty) ? t.pages.proxies.form.required : null,
                  enabled: isNew, // tag 是身份：编辑时不可改名（与协议表单同一约定）
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    t.pages.proxies.chain.orderHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: proxies.value.length + 1,
                  onReorder: (oldIndex, newIndex) {
                    final list = [...proxies.value];
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = list.removeAt(oldIndex);
                    list.insert(newIndex, item);
                    proxies.value = list;
                  },
                  itemBuilder: (context, index) {
                    // 最后一行 = 添加节点（NekoBox AddHolder）
                    if (index == proxies.value.length) {
                      return ListTile(
                        key: const ValueKey('__add__'),
                        leading: const Icon(Icons.add_rounded),
                        title: Text(t.pages.proxies.chain.addMember),
                        onTap: () => pickMember(-1),
                      );
                    }
                    final memberTag = proxies.value[index];
                    return ReorderableDragStartListener(
                      key: ValueKey('chain-member-$index-$memberTag'),
                      index: index,
                      child: Dismissible(
                        key: ValueKey('chain-dismiss-$index-$memberTag'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.errorContainer,
                          alignment: AlignmentDirectional.centerEnd,
                          padding: const EdgeInsetsDirectional.only(end: 16),
                          child: Icon(Icons.delete_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                        ),
                        onDismissed: (_) {
                          final list = [...proxies.value]..removeAt(index);
                          proxies.value = list;
                        },
                        child: ListTile(
                          leading: Text('${index + 1}'),
                          title: Text(memberTag),
                          // 尾行是落地，其余行显示跳位（1 起）
                          subtitle: Text(
                            index == proxies.value.length - 1
                                ? t.pages.proxies.chain.landing
                                : t.pages.proxies.chain.entryHop(index: index + 1),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          trailing: const Icon(Icons.drag_handle_rounded),
                          onTap: () {
                            replacingIndex.value = index;
                            pickMember(index);
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: save,
                    child: Text(t.common.save),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
