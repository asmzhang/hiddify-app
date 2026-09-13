import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/failures.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/profile/overview/profiles_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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
              child: ElevatedButton.icon(
                onPressed: () => ref.read(bottomSheetsNotifierProvider.notifier).showAddProfile(),
                icon: const Icon(Icons.add_rounded),
                label: Text(t.pages.profiles.add),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            separatorBuilder: (_, _) => const Gap(12),
            itemCount: subs.length,
            itemBuilder: (_, index) => _SubscriptionTile(profile: subs[index]),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(t.presentShortError(error))),
      ),
    );
  }
}

class _SubscriptionTile extends HookConsumerWidget {
  const _SubscriptionTile({required this.profile});

  final RemoteProfileEntity profile;

  static String _2(int v) => v.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);
    final sub = profile.subInfo;
    final updating = ref.watch(updateProfileNotifierProvider(profile.id)).isLoading;

    final host = Uri.tryParse(profile.url)?.host ?? profile.url;
    final d = profile.lastUpdate;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    profile.name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (profile.active)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.check_circle_rounded, size: 18, color: theme.colorScheme.primary),
                  ),
                IconButton(
                  onPressed: updating
                      ? null
                      : () => ref.read(updateProfileNotifierProvider(profile.id).notifier).updateProfile(profile),
                  icon: updating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.update_rounded),
                  tooltip: t.common.update,
                ),
                ProfileActionsMenu(
                  profile,
                  (context, toggleVisibility, _) => IconButton(
                    onPressed: toggleVisibility,
                    icon: const Icon(Icons.more_vert_rounded),
                    tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                  ),
                ),
              ],
            ),
            Text(host, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            const Gap(6),
            Text(
              '${t.common.update}: ${d.year}-${_2(d.month)}-${_2(d.day)} ${_2(d.hour)}:${_2(d.minute)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (sub != null) ...[
              const Gap(8),
              RemainingTrafficIndicator(sub.ratio),
              const Gap(6),
              ProfileSubscriptionInfo(sub),
            ],
          ],
        ),
      ),
    );
  }
}
