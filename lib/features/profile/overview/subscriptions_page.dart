import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/utils/preferences_utils.dart' show PreferencesNotifier;
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/nk_profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// NekoBox 复刻 · 分组排序持久化（对标 userOrder）。
/// 存 profile id 的显示顺序；未上榜的（新导入）排在末尾，按导入时间自然追加。
final groupOrderProvider = PreferencesNotifier.create<List<String>, List<String>>("profile_group_order", <String>[]);

/// 订阅 / 分组页（融合版）。
///
/// 对照 NekoBox 的「分组」页：这里是**订阅管理**视图——把所有远程 profile（订阅）单列出来，
/// 展示流量 / 到期 / 更新时间，并提供 更新 / 全部更新 / 编辑 / 分享 / 删除。
/// 数据、更新逻辑全部复用现有 provider，不新造。
class SubscriptionsPage extends HookConsumerWidget {
  const SubscriptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final asyncProfiles = ref.watch(profilesNotifierProvider);

    return Scaffold(
      appBar: AppBar(
        // 手机端：汉堡键打开左侧导航抽屉；PC 端无（左侧是常驻 rail）
        leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
        title: Text(t.pages.subscriptions.title),
        actions: [
          IconButton(
            onPressed: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
            icon: const Icon(Icons.update_rounded),
            tooltip: t.pages.profiles.updateSubscriptions,
          ),
          IconButton(
            onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
            icon: const Icon(Icons.add_rounded),
            tooltip: t.pages.profiles.add,
          ),
          const Gap(8),
        ],
      ),
      body: asyncProfiles.when(
        data: (all) {
          final subs = all.whereType<RemoteProfileEntity>().toList();
          if (subs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rss_feed_rounded, size: 48, color: Theme.of(context).disabledColor),
                  const Gap(12),
                  ElevatedButton.icon(
                    onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(t.pages.profiles.add),
                  ),
                ],
              ),
            );
          }
          // NekoBox 复刻 · 按持久化的 userOrder 排序（未上榜的按导入顺序排末尾）。
          final order = ref.watch(groupOrderProvider);
          final ordered = [...subs]
            ..sort((a, b) {
              final ia = order.indexOf(a.id);
              final ib = order.indexOf(b.id);
              return (ia < 0 ? order.length + subs.indexOf(a) : ia) - (ib < 0 ? order.length + subs.indexOf(b) : ib);
            });
          return ReorderableListView.builder(
            padding: const EdgeInsets.all(8).copyWith(bottom: 24),
            buildDefaultDragHandles: false,
            itemCount: ordered.length,
            onReorder: (oldIndex, newIndex) {
              // 标准 Reorderable 语义修正：newIndex 在向下移动时要 -1。
              final ids = ordered.map((e) => e.id).toList();
              if (oldIndex < newIndex) newIndex -= 1;
              final id = ids.removeAt(oldIndex);
              ids.insert(newIndex, id);
              ref.read(groupOrderProvider.notifier).update(ids);
            },
            itemBuilder: (context, index) {
              final profile = ordered[index];
              return Dismissible(
                key: ValueKey(profile.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.delete_rounded, color: Theme.of(context).colorScheme.onErrorContainer),
                ),
                onDismissed: (_) async {
                  await ref.read(profilesNotifierProvider.notifier).deleteProfile(profile);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(t.pages.profiles.msg.delete.success),
                          action: SnackBarAction(
                            label: t.common.undo,
                            onPressed: () =>
                                ref.read(profilesNotifierProvider.notifier).restoreSubscription(profile.url),
                          ),
                        ),
                      );
                  }
                },
                // NekoBox 复刻 · 长按拖拽排序（不再是桌面端默认的拖拽把手）。
                child: ReorderableDelayedDragStartListener(index: index, child: NkProfileTile(profile)),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.presentShortError(error))),
      ),
    );
  }
}
