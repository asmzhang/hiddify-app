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
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/widget/adaptive_icon.dart';
import 'package:hiddify/core/widget/adaptive_menu.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/features/common/qr_code_dialog.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/proxy/data/proxy_entity_import.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// **分组页** —— 对应 NekoBox `ui/GroupFragment.kt`（抽屉里的 `nav_group`）。
///
/// NekoBox 的结构（本页照它来）：
/// - 工具栏 `res/menu/add_group_menu.xml`：更新所有订阅 / **创建分组**
/// - 列表项 `LayoutGroupItem`：组名 + 状态（`group_status_empty` =「空」/
///   「N 个配置」）+ ✎ 编辑 + 动作菜单（`group_action_menu.xml`：分享/导出/清空）
/// - 点一项 = 打开那个分组（本项目的落点是"切到代理页的对应 Tab"）
///
/// 与 NekoBox 的差异（已记档）：
/// - 订阅在本项目是**独立导航项**（NekoBox 里订阅只是 `type = SUBSCRIPTION` 的分组），
///   所以"更新所有订阅"留在订阅页，本页只放"创建分组"。
/// - **universal link 不做**：NekoBox 的 `sn://subscription?` 是 Kryo 序列化的专有格式
///   （`UniversalFmt.kt`），本项目无对应实现；订阅分享走订阅 URL（等价能力）。
/// - **导出的是出站 JSON** 而不是 std links：本项目实体 `payload` 是完整出站 JSON
///   （parity §8.6 已记档的差异），没有 `toStdLink(compact)` 的每协议 toUri 生成器。
/// - 排序（拖拽 `userOrder`）✅ 已做（本页 ReorderableListView，见下方拖拽排序注释块）；
///   前后置代理（`frontProxy`/`landingProxy`）未做 —— 等 chain 语义定案
///   （见 `nekobox-parity.md` §7 的术语纠正）。
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
        title: Text(t.pages.groups.title),
        actions: [
          IconButton(
            tooltip: t.pages.groups.create,
            onPressed: () => _createGroup(context, ref),
            icon: const Icon(FluentIcons.add_24_regular),
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
              // NekoBox `getDragDirs`：ungrouped 与更新中的组不可拖 ——
              // 本项目订阅组由订阅排序（订阅页），这里只允许拖手动组。
              final draggable = row.group.type != ProxyGroupType.subscription && !row.group.ungrouped;
              return Container(
                // ReorderableListView 要求每个子项有 key（拖拽识别用）
                key: ValueKey('group-${row.group.id}'),
                child: _GroupTile(
                  group: row.group,
                  nodeCount: row.nodeCount,
                  index: index,
                  dragHandle: draggable,
                  onOpen: () => _openGroup(context, ref, row.group),
                  onRename: () => _renameGroup(context, ref, row.group),
                  onDelete: () => _deleteGroup(context, ref, row.group),
                  actionItems: buildGroupActionItems(context, ref, row.group),
                ),
              );
            },
          );
        },
        error: (error, stackTrace) => Center(child: Text(t.presentShortError(error))),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
      // 订阅在本项目是独立导航项，所以"更新所有订阅"不重复放在这里（见类注释）。
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _createGroup(context, ref),
        icon: const Icon(FluentIcons.add_24_regular),
        label: Text(t.pages.groups.create),
      ),
    );
  }

  /// HookConsumerWidget 没有 setState —— 本地副本靠 useState。
  void setStateLike(void Function() fn) => fn();

  /// 打开分组 = 切到代理页的对应 Tab（NekoBox 是打开这个分组的配置页）。
  ///
  /// 订阅分组也在这张表里（NekoBox 的 `groupDao.allGroups()` 不分类型），
  /// 所以除了按 `groupId` 匹配手动分组，还要按 `subscription` 里的 `profileId`
  /// 匹配订阅分组 —— 否则订阅组点了没反应。
  Future<void> _openGroup(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final tabs = ref.read(proxyGroupTabsProvider).valueOrNull ?? const <ProxyGroupTab>[];
    final ownerProfileId = profileIdOfSubscription(group.subscription);
    final match = tabs
        .where((tab) => group.type == ProxyGroupType.subscription
            ? (ownerProfileId != null && tab.profileId == ownerProfileId)
            : tab.groupId == group.id)
        .firstOrNull;
    if (match != null) {
      await ref.read(selectedProxyGroupTagProvider.notifier).update(match.key);
    }
    if (context.mounted) context.goNamed('home');
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

  Future<void> _renameGroup(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final name = await ref
        .read(dialogNotifierProvider.notifier)
        .showSettingText(
          lable: t.pages.groups.name,
          value: group.name ?? '',
          validator: (v) => (v?.trim().isNotEmpty ?? false) ? null : t.pages.groups.name,
        );
    if (name == null || name.trim().isEmpty) return;
    final ok = await ref
        .read(proxiesOverviewNotifierProvider.notifier)
        .renameGroup(groupId: group.id, name: name.trim());
    if (!context.mounted) return;
    final notifier = ref.read(inAppNotificationControllerProvider);
    if (ok) {
      notifier.showSuccessToast(t.pages.groups.renamed);
    } else {
      notifier.showErrorToast(t.errors.unexpected);
    }
  }

  Future<void> _deleteGroup(BuildContext context, WidgetRef ref, ProxyGroupEntry group) async {
    final t = ref.read(translationsProvider).requireValue;
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(title: t.pages.groups.deleteConfirm, message: groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName));
    if (!confirmed || !context.mounted) return;
    final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).removeGroup(group.id);
    if (!context.mounted) return;
    final notifier = ref.read(inAppNotificationControllerProvider);
    if (ok) {
      notifier.showSuccessToast(t.pages.groups.deleted);
    } else {
      notifier.showErrorToast(t.errors.unexpected);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // 分组动作菜单（NekoBox `group_action_menu.xml` + `GroupFragment.kt:330-378`）。
  // 三组动作：分享订阅链接（订阅组限定）/ 导出节点（剪贴板·文件）/ 清空分组。
  // 与 NekoBox 的格式差异见类注释（universal link 是 Kryo 专有；导出走出站 JSON）。
  // 交互用 AdaptiveMenu 的 subItems —— 对应 NekoBox 菜单里 share/export 的子项结构。
  // ───────────────────────────────────────────────────────────────────────────

  /// 组卡片的 ⋮ 动作菜单。订阅组多一个「分享订阅链接」子菜单
  /// （NekoBox 的 share 组只在 `type == SUBSCRIPTION` 时显示，同判定）。
  List<AdaptiveMenuItem> buildGroupActionItems(BuildContext context, WidgetRef ref, ProxyGroupEntry group) {
    final t = ref.read(translationsProvider).requireValue;
    final isSubscription = group.type == ProxyGroupType.subscription && profileIdOfSubscription(group.subscription) != null;
    return [
      if (isSubscription)
        AdaptiveMenuItem(
          title: t.common.share,
          leadingIcon: const Icon(FluentIcons.share_24_regular),
          subItems: [
            AdaptiveMenuItem(
              title: t.pages.profiles.share.urlToClipboard,
              onTap: () => _copySubscriptionUrl(context, ref, group),
            ),
            AdaptiveMenuItem(
              title: t.pages.profiles.share.showUrlQr,
              onTap: () => _showSubscriptionQr(context, ref, group),
            ),
          ],
        ),
      AdaptiveMenuItem(
        title: t.common.export,
        leadingIcon: const Icon(FluentIcons.arrow_export_24_regular),
        subItems: [
          AdaptiveMenuItem(
            title: t.pages.proxies.msg.exportToClipboard,
            onTap: () => _exportNodesToClipboard(context, ref, group),
          ),
          AdaptiveMenuItem(
            title: t.pages.proxies.msg.exportToFile,
            onTap: () => _exportNodesToFile(context, ref, group),
          ),
        ],
      ),
      AdaptiveMenuItem(
        title: t.pages.groups.clearNodes,
        leadingIcon: const Icon(FluentIcons.bin_recycle_24_regular),
        onTap: () => _clearGroup(context, ref, group),
      ),
    ];
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

/// 列表项 —— 照 NekoBox `LayoutGroupItem`：组名 + 状态 + ✎ + ⋮ + 🗑。
/// ⋮ 是动作菜单（`group_action_menu.xml`：分享/导出/清空），子项结构见
/// [GroupsPage.buildGroupActionItems]。
class _GroupTile extends ConsumerWidget {
  const _GroupTile({
    required this.group,
    required this.nodeCount,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.actionItems,
    required this.index,
    this.dragHandle = false,
  });

  final ProxyGroupEntry group;
  final int nodeCount;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final List<AdaptiveMenuItem> actionItems;

  /// 在 ReorderableListView 中的下标（拖拽把手 [ReorderableDragStartListener] 必需）。
  final int index;

  /// 是否显示拖拽把手（NekoBox `getDragDirs`：ungrouped / 更新中不可拖；
  /// 本项目订阅组的次序跟订阅页，也不拖）。false = 不渲染把手 ⇒ 拖不动。
  final bool dragHandle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    // 状态文案照 NekoBox `GroupFragment.kt:518-540`：
    // BASIC 组空 ⇒ 「空」，否则「N 个配置」；订阅组空 ⇒ 「从未更新」。
    final String status;
    if (nodeCount == 0) {
      status = group.type == ProxyGroupType.subscription ? t.pages.groups.neverUpdated : t.pages.groups.empty;
    } else {
      status = t.pages.groups.nodeCount(n: nodeCount);
    }

    return NkCard(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: EdgeInsets.zero,
      child: ListTile(
        title: Text(groupDisplayName(group, ungroupedLabel: t.pages.groups.defaultName), style: theme.textTheme.bodyLarge),
        subtitle: Text(status, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        onTap: onOpen,
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
            NkCardAction(icon: FluentIcons.edit_24_regular, tooltip: t.pages.groups.edit, onTap: onRename),
            AdaptiveMenu(
              items: actionItems,
              builder: (context, toggleVisibility, child) => NkCardAction(
                icon: AdaptiveIcon(context).more,
                tooltip: t.common.more,
                onTap: toggleVisibility,
              ),
              child: null,
            ),
            NkCardAction(icon: FluentIcons.delete_24_regular, tooltip: t.common.delete, onTap: onDelete),
          ],
        ),
      ),
    );
  }
}
