import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/notification/in_app_notification_controller.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/proxy/data/offline_proxies.dart';
import 'package:hiddify/features/proxy/overview/proxies_overview_notifier.dart';
import 'package:hiddify/features/proxy/widget/connection_test_dialog.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 节点列表页的 ⋮ 菜单 —— 1:1 对照 NekoBox `res/menu/add_profile_menu.xml`
/// 的 `action_misc`（内层 8 项，顺序即规格）：
///
///   1. 更新当前组订阅（action_update_subscription）
///   2. 清空流量统计数据（action_clear_traffic_statistics）
///   3. 删除重复的服务器（action_remove_duplicate）
///   4. TCPing（action_connection_tcp_ping —— NekoBox translatable=false 全语言固定词）
///   5. URL Test（action_connection_url_test —— 同上）
///   6. 清理测试结果（action_connection_test_clear_results）
///   7. 清理不可用配置（action_connection_test_delete_unavailable）
///   8. 排序（action_order）—— 内嵌 radio 子菜单：原始 / 以名称 / 以延时
///      （`checkableBehavior="single"`；NekoBox `ProxyGroup.order` 随组存库，
///      本项目同一语义落在 `ProxiesSortNotifier` 的 `proxies_sort_by_group`）
///
/// 与 NekoBox 的两处有意差异：
///  · **没有「路由」项** —— NekoBox 的路由在抽屉（main_drawer_menu.xml 的
///    nav_route），不在 ⋮ 菜单；本项目抽屉已有路由入口（归一原则：一个入口）。
///  · 排序子菜单只有三项 —— `ProxiesSort.usage` 是 hiddify 遗留排序，菜单不出现
///    （枚举保留：历史落盘值读回不炸，只是没有菜单入口）。
///
/// radio 的视觉：Flutter 惯例用 ✓ 标记当前项（NekoBox 用 radio 圆点，意图相同：
/// 标出当前选中）。选中后菜单整体收起（Android radio 行为）。
///
/// 结构对等测试：test/features/proxy/proxies_menu_test.dart。
class ProxiesMenuButton extends ConsumerStatefulWidget {
  const ProxiesMenuButton({super.key, this.activeTab});

  /// 当前 Tab —— 删除/测速类动作要知道"动的是哪个组里的"（与节点行同口径）。
  final ProxyGroupTab? activeTab;

  @override
  ConsumerState<ProxiesMenuButton> createState() => _ProxiesMenuButtonState();
}

class _ProxiesMenuButtonState extends ConsumerState<ProxiesMenuButton> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider).requireValue;
    return MenuAnchor(
      controller: _controller,
      // 顺序 = NekoBox add_profile_menu.xml 的 action_misc 权威顺序（勿重排）。
      menuChildren: [
        _item(t.pages.proxies.updateSubscription, () => _updateSubscription()),
        _item(t.pages.proxies.clearTrafficStats, () => _clearTraffic(t)),
        _item(t.pages.proxies.removeDuplicate, () => _removeDuplicate(t)),
        _item(t.pages.proxies.tcpPing, () => _tcpPing(t)),
        _item(t.pages.proxies.urlTest, () => _urlTest(t)),
        _item(t.pages.proxies.clearTestResults, () => _clearResults(t)),
        _item(t.pages.proxies.deleteUnavailable, () => _deleteUnavailable(t)),
        _orderEntry(t),
      ],
      child: IconButton(
        onPressed: () => _controller.open(),
        // NekoBox 的 action_misc 图标即 Material 的 more_vert（ic_baseline_more_vert_24）。
        icon: const Icon(Icons.more_vert),
      ),
    );
  }

  Widget _item(String label, Future<void> Function() onTap) =>
      MenuItemButton(onPressed: onTap, child: Text(label));

  /// 「排序」= 带内嵌子菜单的入口（NekoBox action_order + checkableBehavior="single"）。
  Widget _orderEntry(Translations t) {
    final sortBy = ref.watch(proxiesSortNotifierProvider);
    return SubmenuButton(
      menuChildren: [
        for (final value in kOrderMenuValues)
          MenuItemButton(
            leadingIcon: sortBy == value ? const Icon(Icons.check, size: 18) : null,
            onPressed: () async {
              // 选中即整体收起（Android radio 子菜单行为），再落库。
              _controller.close();
              await ref.read(proxiesSortNotifierProvider.notifier).update(value);
            },
            child: Text(_orderLabel(t, value)),
          ),
      ],
      child: Text(t.pages.proxies.order),
    );
  }

  /// 子菜单三项（顺序 = NekoBox action_order_origin / by_name / by_delay）。
  static const kOrderMenuValues = <ProxiesSort>[ProxiesSort.unsorted, ProxiesSort.name, ProxiesSort.delay];

  String _orderLabel(Translations t, ProxiesSort value) => switch (value) {
    ProxiesSort.unsorted => t.pages.proxies.orderOptions.origin,
    ProxiesSort.name => t.pages.proxies.orderOptions.name,
    ProxiesSort.delay => t.pages.proxies.orderOptions.delay,
    // 菜单不含 usage（枚举穷举要求的兜底分支，不会出现在子菜单里）。
    ProxiesSort.usage => t.pages.proxies.sortOptions.usage,
  };

  Future<void> _updateSubscription() {
    ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger();
    return Future.value();
  }

  Future<void> _clearTraffic(Translations t) async {
    final tab0 = widget.activeTab;
    // NekoBox `ConfigurationFragment.kt:460-475`：无确认框静默执行，
    // 失败也不弹（本项目失败时提示一次，超出规格的防御性）。
    final ok = await ref
        .read(proxiesOverviewNotifierProvider.notifier)
        .clearTrafficStats(
          profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
          groupId: tab0?.groupId,
        );
    if (!ok) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
    }
  }

  Future<void> _removeDuplicate(Translations t) async {
    final tab0 = widget.activeTab;
    // NekoBox `ConfigurationFragment.kt:545-559`：先列重复者名单确认（上限 20 条），
    // 同意后才真删。空名单不弹框（NekoBox `toClear.isNotEmpty()` 判定）。
    final duplicates = await ref
        .read(proxiesOverviewNotifierProvider.notifier)
        .findDuplicateNodes(
          profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
          groupId: tab0?.groupId,
        );
    if (!mounted) return;
    if (duplicates.isEmpty) {
      ref.read(inAppNotificationControllerProvider).showInfoToast(t.pages.proxies.msg.noDuplicates);
      return;
    }
    final names = [
      for (final (index, node) in duplicates.indexed)
        if (index < 20) node.displayName else if (index == 20) '......' else null,
    ].whereType<String>();
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(
          title: t.dialogs.confirmation.deduplicate.title,
          message: '${t.dialogs.confirmation.deduplicate.msg}\n${names.join('\n')}',
        );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).deleteNodes(duplicates);
    if (!ok) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      return;
    }
    // 出站表少了节点 ⇒ 内核要换配置（与删组/清空分组同理）。
    if (tab0?.groupId != null) {
      await ref.read(proxiesOverviewNotifierProvider.notifier).reloadCoreForGroup(tab0!.groupId!);
    } else if (tab0?.profileId case final String pid) {
      await ref.read(proxiesOverviewNotifierProvider.notifier).reloadCoreForProfile(pid);
    }
  }

  Future<void> _tcpPing(Translations t) async {
    // NekoBox `pingTest(false)`（ConfigurationFragment.kt:694-832）：
    // 先弹进度框再开测，逐条回报（转圈 + 节点名 + n/N 计数），
    // 取消时已测结果照落库。无确认框，结果写实体列。
    final tab0 = widget.activeTab;
    try {
      final count = await runConnectionTest(
        context,
        ref,
        start: () => ref
            .read(proxiesOverviewNotifierProvider.notifier)
            .tcpPingNodes(
              profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
              groupId: tab0?.groupId,
            ),
      );
      if (count != null && count < 0 && mounted) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      }
    } catch (_) {
      if (mounted) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      }
    }
  }

  Future<void> _urlTest(Translations t) async {
    // NekoBox `urlTest()`（ConfigurationFragment.kt:834-901）：先弹进度框
    // 再开测。逐节点测试（进度 n/N + 当前节点 + 可取消）由
    // `ProxiesOverviewNotifier.urlTest` 内部的 runTcpPing 承担。
    try {
      await runConnectionTest(
        context,
        ref,
        start: () => ref.read(proxiesOverviewNotifierProvider.notifier).urlTest(),
      );
    } catch (_) {
      if (mounted) {
        ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      }
    }
  }

  Future<void> _clearResults(Translations t) async {
    final tab0 = widget.activeTab;
    final ok = await ref
        .read(proxiesOverviewNotifierProvider.notifier)
        .clearTestResults(
          profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
          groupId: tab0?.groupId,
        );
    if (!ok) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
    }
  }

  Future<void> _deleteUnavailable(Translations t) async {
    // NekoBox `ConfigurationFragment.kt:495-532`：先确认（一句
    // delete_confirm_prompt，不带名单），同意后真删。
    // 空名单不弹框（toClear.isNotEmpty() 判定），只 toast。
    final tab0 = widget.activeTab;
    final unavailable = await ref
        .read(proxiesOverviewNotifierProvider.notifier)
        .findUnavailableNodes(
          profileId: tab0 == null || tab0.profileId.isEmpty ? null : tab0.profileId,
          groupId: tab0?.groupId,
        );
    if (!mounted) return;
    if (unavailable.isEmpty) {
      ref.read(inAppNotificationControllerProvider).showInfoToast(t.pages.proxies.msg.noUnavailable);
      return;
    }
    final confirmed = await ref
        .read(dialogNotifierProvider.notifier)
        .showConfirmation(
          title: t.dialogs.confirmation.deleteUnavailable.title,
          message: t.dialogs.confirmation.deleteUnavailable.msg,
        );
    if (!confirmed || !mounted) return;
    final ok = await ref.read(proxiesOverviewNotifierProvider.notifier).deleteNodes(unavailable);
    if (!ok) {
      ref.read(inAppNotificationControllerProvider).showErrorToast(t.errors.unexpected);
      return;
    }
    // 出站表少了节点 ⇒ 内核要换配置（与去重同理）。
    if (tab0?.groupId != null) {
      await ref.read(proxiesOverviewNotifierProvider.notifier).reloadCoreForGroup(tab0!.groupId!);
    } else if (tab0?.profileId case final String pid) {
      await ref.read(proxiesOverviewNotifierProvider.notifier).reloadCoreForProfile(pid);
    }
  }
}
