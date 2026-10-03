import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/db/db.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/model/proxy_group.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';
import 'package:hiddify/features/proxy/overview/group_settings_sheet.dart';
import 'package:hiddify/features/proxy/overview/groups_page_spec.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **分组页** —— 对应 NekoBox `ui/GroupFragment.kt`（抽屉里的 `nav_group`）。
///
/// NekoBox 结构（本页照它来；规格投影 = `groups_page_spec.dart` 唯一数据源）：
/// - 工具栏 `add_group_menu.xml`：更新所有订阅（**带确认框**）/ 创建分组；**无 FAB**
/// - 列表项 `LayoutGroupItem`：组名 + 状态（空 / 从未更新 / N 个配置）+
///   「更新」按钮（仅订阅组）+ ✎ 编辑（ungrouped 隐藏）+ ⋮ 动作菜单
///   （`group_action_menu.xml`：分享订阅[订阅组]/导出/清空）
/// - 右滑删除 + 还原 snackbar（undo 窗口过后才落库）；卡片点击**无动作**
/// - 拖拽排序（userOrder，ungrouped 除外）
///
/// 与 NekoBox 的差异（已记档）：
/// - universal link 不做：`sn://subscription?` 是 Kryo 序列化专有格式
///   （`UniversalFmt.kt`）；订阅分享走订阅 URL（等价能力）
/// - 导出的是出站 JSON 而不是 std links（实体 payload 即完整出站 JSON，parity §8.6）
/// - 订阅组不参与本页拖拽排序（订阅次序跟订阅页——架构差异：订阅是一等实体）
/// - 卡片「更新中」进度指示不做（更新走前台通知通道，无进度回流本页）
/// - 前后置代理（frontProxy/landingProxy）未做 —— 等 chain 语义定案
///   （见 `nekobox-parity.md` §7 的术语纠正）
class GroupsPage extends HookConsumerWidget {
  const GroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final groups = ref.watch(proxyGroupListProvider);
    // 拖拽期间的本地顺序（ReorderableListView 要求 onReorder 真正改数据，
    // 而 provider 的列表不可变 ⇒ 用本地副本承载拖拽，落库后 invalidate 回流）。
    final localRows = useState<List<({ProxyGroupEntry group, int nodeCount})>?>(null);
    // provider 数据变化（首次加载 / 落库回流 / 组增删改名）⇒ 重置本地副本。
    useEffect(() {
      groups.whenData((rows) => localRows.value = rows);
      return null;
    }, [groups]);

    return Scaffold(
      appBar: AppBar(
        // 差异清单 D-1：NekoBox 分组页挂在 MainActivity 的 DrawerLayout 上，
        // 汉堡键由 Activity 提供；本项目手机端各顶级页统一自己挂（见 tools_page.dart:31）。
        // 分组页此前漏了 ⇒ 从抽屉进「分组」后无法再开抽屉，只能系统返回。
        leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
        title: Text(t.pages.groups.title),
        // NekoBox add_group_menu.xml：两枚常驻工具栏动作（顺序权威；无 FAB）。
        actions: [
          for (final action in nkGroupToolbarActions())
            IconButton(
              tooltip: action.label(t),
              onPressed: () => _runToolbarAction(context, ref, action.action),
              icon: Icon(action.icon),
            ),
        ],
      ),
      body: groups.when(
        data: (_) {
          final rows = localRows.value ?? const <({ProxyGroupEntry group, int nodeCount})>[];
          if (rows.isEmpty) return Center(child: Text(t.pages.groups.empty));
          return ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            onReorder: (oldIndex, newIndex) {
              // Flutter 标准 newIndex 语义：向下移时已含被拖项自身，需 -1。
              setStateLike(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final moved = rows.removeAt(oldIndex);
                rows.insert(newIndex, moved);
              });
              localRows.value = [...rows];
            },
            // 拖拽结束一次性落库（NekoBox `clearView → commitMove` 的对应点）。
            onReorderEnd: (_) => _commitReorder(context, ref, localRows.value ?? rows),
            proxyDecorator: (child, index, animation) => AnimatedBuilder(
              animation: animation,
              builder: (context, child) => Material(
                elevation: 4 * animation.value,
                color: Colors.transparent,
                child: child,
              ),
              child: child,
            ),
            itemBuilder: (context, index) {
              final row = rows[index];
              // NekoBox `getDragDirs`：ungrouped 不可拖；订阅组次序跟订阅页
              //（架构差异记档：订阅是一等实体），也不拖。
              final draggable = row.group.type != ProxyGroupType.subscription && !row.group.ungrouped;
              // NekoBox `getSwipeDirs`：右滑删除（ungrouped 除外）→ undo snackbar，
              // undo 窗口过后才落库（UndoSnackbarManager.commit 对应点）。
              return Dismissible(
                key: ValueKey('group-${row.group.id}'),
                direction: DismissDirection.endToStart,
                // 3.38 的 Dismissible 无 enabled 参数 —— confirmDismiss=false 等价禁用。
                confirmDismiss: (direction) async => nkGroupCardSwipable(ungrouped: row.group.ungrouped),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Icon(FluentIcons.delete_24_regular, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                onDismissed: (_) async {
                  final displayName = groupDisplayName(row.group, ungroupedLabel: t.pages.groups.defaultName);
                  // 本地移除（provider 未动）；还原 = 回插原位，不落库。
                  final restored = [...rows]..removeAt(index);
                  localRows.value = restored;
                  var undone = false;
                  final snackBar = ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(t.pages.groups.deleteUndoMsg(name: displayName)),
                      action: SnackBarAction(
                        label: t.pages.groups.undo,
                        onPressed: () {
                          undone = true;
                          final current = [...(localRows.value ?? restored)];
                          current.insert(index.clamp(0, current.length), row);
                          localRows.value = current;
                        },
                      ),
                    ),
                  );
                  await snackBar.closed; // controller.closed 即 Future<SnackBarClosedReason>
                  if (!undone && context.mounted) {
                    await ref.read(proxiesOverviewNotifierProvider.notifier).removeGroup(row.group.id);
                  }
                },
                child: NkGroupTile(
                  group: row.group,
                  nodeCount: row.nodeCount,
                  index: index,
                  dragHandle: draggable,
                  onEdit: () => _openGroupSettings(context, ref, row.group),
                  onUpdate: () => _updateSubscriptionGroup(context, ref, row.group),
                  actionItems: buildGroupActionItems(context, ref, row.group),
                ),
              );
            },
          );
        },
        error: (error, stackTrace) => Center(child: Text(t.presentShortError(error))),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  /// HookConsumerWidget 没有 setState —— 本地副本靠 useState。
  void setStateLike(void Function() fn) => fn();

  /// 工具栏动作接线（add_group_menu.xml）。
  void _runToolbarAction(BuildContext context, WidgetRef ref, NkGroupToolbarAction action) {
    switch (action) {
      case NkGroupToolbarAction.updateAllSubscriptions:
        unawaited(_updateAllSubscriptions(context, ref));
      case NkGroupToolbarAction.createGroup:
        unawaited(_createGroup(context, ref));
    }
  }

  /// 更新所有订阅（add_group_menu.xml `action_update_all`）：确认框（title=确认、
  /// message=更新所有订阅，GroupFragment.kt:116-128 同构）→ 更新全部订阅组。
  Future<void> _updateAllSubscriptions(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref.read(dialogNotifierProvider.notifier).showConfirmation(title: t.pages.groups.confirm, message: t.pages.groups.updateAll);
    if (!confirmed) return;
    await ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
  }

  /// 卡片「更新」按钮：仅订阅组（GroupFragment.kt:396-398 → startUpdate）。
  Future<void> _updateSubscriptionGroup(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final profile = await _remoteProfileOf(ref, group);
    if (profile == null) return;
    await ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 拖拽排序（NekoBox `GroupFragment.kt`：ItemTouchHelper move → `move()` 链式平移
  // → `clearView` 时 `commitMove()` 落库）。本项目的落点：
  //   · onReorder 期间只改本地副本（`useState`）；
  //   · onReorderEnd 时把整表 id 顺序一次写库（`moveGroups`）——
  //     比 NekoBox 的逐行接力落库简单，结果等价（userOrder = 界面下标）。
  //   · 不可拖行（订阅组 / ungrouped）不渲染把手 ⇒ 拖不动，但仍参与整表
  //     userOrder 重算（它们的下标不变，重算前后等价，无副作用）。
  // ───────────────────────────────────────────────────────────────────────────

  /// onReorderEnd：把拖拽后的界面顺序落库。
  Future<void> _commitReorder(BuildContext context, WidgetRef ref, List<({ProxyGroupEntry group, int nodeCount})> rows) async {
    final ids = [for (final row in rows) row.group.id];
    if (ids.length < 2) return;
    await ref.read(proxiesOverviewNotifierProvider.notifier).moveGroups(idsInDisplayOrder: ids);
  }

  Future<void> _createGroup(BuildContext context, WidgetRef ref) async {
    final t = ref.read(translationsProvider).requireValue;
    final name = await ref
        .read(dialogNotifierProvider.notifier)
        .showSettingText(lable: t.pages.groups.name, validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : t.pages.groups.name);
    if (name == null || name.trim().isEmpty) return;
    final id = await ref.read(proxiesOverviewNotifierProvider.notifier).createGroup(name: name.trim());
    if (!context.mounted) return;
    final notifier = ref.read(inAppNotificationControllerProvider);
    if (id == null) {
      notifier.showErrorToast(t.errors.unexpected);
    } else {
      notifier.showSuccessToast(t.pages.groups.created);
    }
  }

  /// ✎ 编辑 = 分组设置（NekoBox `GroupSettingsActivity` 对位；字段映射见
  /// `group_settings_sheet.dart` 头注释）。
  Future<void> _openGroupSettings(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final isSubscription = group.type == ProxyGroupType.subscription && profileIdOfSubscription(group.subscription) != null;
    await showDialog<void>(
      context: context,
      builder: (sheetContext) => NkGroupSettingsSheet(
        initialName: groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName),
        isSubscription: isSubscription,
        onSave: (name) => _applyRename(ref, group, name),
        onDelete: () => _confirmAndDeleteGroup(context, ref, group, sheetContext),
        // 可达性闭环：订阅字段的唯一管理入口 = 订阅页（GroupSettingsActivity
        // 对位，见 group_settings_sheet.dart 头注释）。
        onOpenSubscriptions: isSubscription
            ? () {
                Navigator.of(sheetContext).pop();
                context.goNamed('subscriptions');
              }
            : null,
      ),
    );
  }

  /// 应用重命名（toast 反馈照旧）。
  Future<void> _applyRename(WidgetRef ref, ProxyGroupEntry group, String name) async {
    final t = ref.read(translationsProvider).requireValue;
    final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).renameGroup(groupId: group.id, name: name);
    if (!ref.context.mounted) return;
    final notifier = ref.read(inAppNotificationControllerProvider);
    if (ok) {
      notifier.showSuccessToast(t.pages.groups.renamed);
    } else {
      notifier.showErrorToast(t.errors.unexpected);
    }
  }

  /// 删除：确认框（`delete_group_prompt` 对齐）→ removeGroup；
  /// 返回是否已删（sheet 据此关闭自己）。
  Future<bool> _confirmAndDeleteGroup(BuildContext context, WidgetRef ref, ProxyGroupEntry group, BuildContext sheetContext) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(title: t.pages.groups.deleteConfirm, message: groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName));
    if (!confirmed) return false;
    final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).removeGroup(group.id);
    if (ok && !sheetContext.mounted) {
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.pages.groups.deleted);
    }
    return ok;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 分组动作菜单（NekoBox `group_action_menu.xml` + `GroupFragment.kt:330-378`）。
  // 三组动作：分享订阅链接（订阅组限定）/ 导出节点（剪贴板·文件）/ 清空分组。
  // 与 NekoBox 的格式差异见类注释（universal link 是 Kryo 专有；导出走出站 JSON）。
  // 交互用 AdaptiveMenu 的 subItems —— 对应 NekoBox 菜单里 share/export 的子项结构。
  // ───────────────────────────────────────────────────────────────────────────

  /// 组卡片的 ⋮ 动作菜单 = `nkGroupActionMenu` 规格树 → AdaptiveMenuItem。
  /// 结构/词表由 groups_page_spec 钉死（L1 测试打它）；这里只接线叶子动作。
  /// NekoBox PopupMenu 是纯文本菜单（无 leading 图标）。
  List<AdaptiveMenuItem> buildGroupActionItems(BuildContext context, WidgetRef ref, ProxyGroupEntry group) {
    final isSubscription = group.type == ProxyGroupType.subscription && profileIdOfSubscription(group.subscription) != null;
    return nkGroupActionMenu(isSubscription: isSubscription).map((spec) => _menuFromSpec(context, ref, group, spec)).toList();
  }

  AdaptiveMenuItem _menuFromSpec(BuildContext context, WidgetRef ref, ProxyGroupEntry group, NkGroupMenuSpec spec) {
    final t = ref.read(translationsProvider).requireValue;
    final children = spec.children;
    if (children != null) {
      return AdaptiveMenuItem(title: spec.label(t), subItems: children.map((c) => _menuFromSpec(context, ref, group, c)).toList());
    }
    return AdaptiveMenuItem(title: spec.label(t), onTap: () => _runGroupAction(context, ref, group, spec.action!));
  }

  void _runGroupAction(BuildContext context, WidgetRef ref, ProxyGroupEntry group, NkGroupMenuAction action) {
    switch (action) {
      case NkGroupMenuAction.shareUrlToClipboard:
        unawaited(_copySubscriptionUrl(context, ref, group));
      case NkGroupMenuAction.shareQr:
        unawaited(_showSubscriptionQr(context, ref, group));
      case NkGroupMenuAction.exportToClipboard:
        unawaited(_exportNodesToClipboard(context, ref, group));
      case NkGroupMenuAction.exportToFile:
        unawaited(_exportNodesToFile(context, ref, group));
      case NkGroupMenuAction.clearNodes:
        unawaited(_clearGroup(context, ref, group));
    }
  }

  /// 订阅组对应的 `RemoteProfileEntity`（拿分享 URL 用）。找不到返回 null。
  Future<RemoteProfileEntity?> _remoteProfileOf(WidgetRef ref, ProxyGroupEntry group) async {
    final profileId = profileIdOfSubscription(group.subscription);
    if (profileId == null) return null;
    // 组本身不存 URL，`subscription` JSON 只记 profileId ⇒ 从订阅列表反查那条配置。
    final profiles = await ref.read(profilesNotifierProvider.future);
    return profiles.whereType<RemoteProfileEntity>().where((p) => p.id == profileId).firstOrNull;
  }

  Future<void> _copySubscriptionUrl(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final profile = await _remoteProfileOf(ref, group);
    final link = profile == null ? '' : LinkParser.generateSubShareLink(profile.url, profile.name);
    if (!context.mounted) return;
    if (link.isEmpty) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      return;
    }
    await Clipboard.setData(ClipboardData(text: link));
    if (context.mounted) {
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
    }
  }

  Future<void> _showSubscriptionQr(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final profile = await _remoteProfileOf(ref, group);
    final link = profile == null ? '' : LinkParser.generateSubShareLink(profile.url, profile.name);
    if (!context.mounted || link.isEmpty) return;
    await showQrCodeDialog(link, message: groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName));
  }

  /// 组内节点的出站 JSON 数组文本（导出的内容载体）。
  ///
  /// 本项目没有 `toStdLink(compact)` 的每协议分享链接生成器（parity §8.6 记档的差异），
  /// 实体 `payload` 本身就是完整出站 JSON —— 直接以 JSON 数组导出，
  /// 可被任何 sing-box 工具直接消费。
  Future<String?> _nodesExportText(WidgetRef ref, ProxyGroupEntry group) async {
    final nodes = (await ref.read(proxyEntityRepositoryProvider).groupWithNodes(group.id))?.nodes ?? const [];
    if (nodes.isEmpty) return null;
    final payloads = [
      for (final node in nodes)
        if (jsonDecode(node.payload) case final Map<String, dynamic> outbound) outbound,
    ];
    return const JsonEncoder.withIndent('  ').convert(payloads);
  }

  Future<void> _exportNodesToClipboard(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final text = await _nodesExportText(ref, group);
    if (!context.mounted) return;
    if (text == null) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.groups.empty);
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.clipboard.success);
    }
  }

  /// 文件导出（照 `config_option_notifier.exportJsonFile` 的桌面写盘先例）。
  Future<void> _exportNodesToFile(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final text = await _nodesExportText(ref, group);
    if (!context.mounted) return;
    if (text == null) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.pages.groups.empty);
      return;
    }

    final bytes = utf8.encode(text);
    final groupName = groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName);
    final outputFile = await FilePicker.platform.saveFile(
      fileName: '$groupName.json',
      type: FileType.custom,
      allowedExtensions: ['json'],
      bytes: bytes,
    );
    if (outputFile == null || !context.mounted) return;
    if (PlatformUtils.isDesktop) {
      final file = File(outputFile);
      if (!await file.exists()) await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes);
    }
    ref.read(inAppNotificationControllerProvider).showSuccessToast(t.common.msg.export.file.success);
  }

  /// 清空分组（NekoBox `clear`：确认框 → `GroupManager.clearGroup` —— 只清节点保留组）。
  Future<void> _clearGroup(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(title: t.pages.groups.clearConfirm, message: groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName));
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).clearGroup(group.id);
    if (!context.mounted) return;
    final notifier = ref.read(inAppNotificationControllerProvider);
    if (ok) {
      notifier.showSuccessToast(t.pages.groups.cleared);
    } else {
      notifier.showErrorToast(t.errors.unexpected);
    }
  }
}

/// 列表项 —— 照 NekoBox `LayoutGroupItem` + `GroupHolder.bind`：
/// 组名 + 状态 + 「更新」（仅订阅组，invisible 保占位）+ ✎（ungrouped 隐藏）+ ⋮。
/// ⋮ = 动作菜单（`group_action_menu.xml`，纯文本）。
/// 卡片点击无动作（spec `GroupFragment.kt:384 setOnClickListener { }`）；
/// 删除 = 右滑（页面层 Dismissible + undo），**无 🗑 按钮**。
class NkGroupTile extends ConsumerWidget {
  const NkGroupTile({
    super.key,
    required this.group,
    required this.nodeCount,
    required this.onEdit,
    required this.onUpdate,
    required this.actionItems,
    required this.index,
    this.dragHandle = false,
  });

  final ProxyGroupEntry group;
  final int nodeCount;
  final VoidCallback onEdit;
  final VoidCallback onUpdate;
  final List<AdaptiveMenuItem> actionItems;

  /// 在 ReorderableListView 中的下标（拖拽把手 [ReorderableDragStartListener] 必需）。
  final int index;

  /// 是否显示拖拽把手（NekoBox `getDragDirs`：ungrouped 不可拖；
  /// 本项目订阅组的次序跟订阅页，也不拖）。false = 不渲染把手 ⇒ 拖不动。
  final bool dragHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final isSubscription = group.type == ProxyGroupType.subscription;
    // 状态文案照 NekoBox `GroupFragment.kt:518-540`：
    // BASIC 组空 ⇒ 「空」，否则「N 个配置」；订阅组空 ⇒ 「从未更新」。
    final String status;
    if (nodeCount == 0) {
      status = isSubscription ? t.pages.groups.neverUpdated : t.pages.groups.empty;
    } else {
      status = t.pages.groups.nodeCount(n: nodeCount);
    }

    return NkCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        title: Text(groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName), style: theme.textTheme.bodyLarge),
        subtitle: Text(status, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        // NekoBox：卡片点击无动作（GroupFragment.kt:384）。
        // 拖拽把手（NekoBox 是整行长按拖动；Flutter 的 ReorderableListView 默认
        // 也是长按，但那与"点行打开分组"冲突 ⇒ 用显式把手，长按仅在把手上生效）。
        leading: dragHandle
            ? ReorderableDragStartListener(
                index: index,
                child: Icon(FluentIcons.re_order_dots_vertical_24_regular, color: theme.colorScheme.onSurfaceVariant),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 「更新」仅订阅组（GroupFragment.kt:387 invisible 保占位语义）。
            Visibility(
              visible: nkGroupCardShowsUpdate(isSubscription: isSubscription),
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: TextButton(onPressed: onUpdate, child: Text(t.pages.groups.cardUpdate)),
            ),
            // ✎ 编辑：ungrouped 组隐藏（GroupFragment.kt:386 isGone）。
            Visibility(
              visible: nkGroupCardShowsEdit(ungrouped: group.ungrouped),
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: NkCardAction(icon: FluentIcons.edit_24_regular, tooltip: t.pages.groups.edit, onTap: onEdit),
            ),
            AdaptiveMenu(
              items: actionItems,
              builder: (context, toggleVisibility, child) => NkCardAction(
                icon: AdaptiveIcon(context).more,
                tooltip: t.common.more,
                onTap: toggleVisibility,
              ),
              child: null,
            ),
          ],
        ),
      ),
    );
  }
}
