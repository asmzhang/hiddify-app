import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 工具页（融合版）。
///
/// NekoBox 的「工具」是 网络(STUN/NAT) + 备份；hiddify 本来就把这些能力散落在
/// 设置页的菜单里，这里**收拢成独立页**，方便就近使用，不新造逻辑、不碰数据层。
class ToolsPage extends HookConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final config = ref.read(configOptionNotifierProvider.notifier);

    Future<void> importWithConfirm(Future<void> Function() action) async {
      final confirmed = await ref.read(dialogNotifierProvider.notifier).showConfirmation(
        title: t.common.msg.import.confirm,
        message: t.dialogs.confirmation.settings.import.msg,
      );
      if (confirmed) await action();
    }

    return Scaffold(
      appBar: AppBar(
        // 手机端：汉堡键打开左侧导航抽屉；PC 端无（左侧是常驻 rail）
        leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
        title: Text(t.pages.tools.title),
      ),
      body: ListView(
        children: [
          _SectionHeader(title: t.common.export),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(t.pages.settings.options.export.anonymousToFile),
            onTap: () async => await config.exportJsonFile(),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: Text(t.pages.settings.options.export.anonymousToClipboard),
            onTap: () async => await config.exportJsonClipboard(),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: Text(t.pages.settings.options.export.allToFile),
            onTap: () async => await config.exportJsonFile(excludePrivate: false),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: Text(t.pages.settings.options.export.allToClipboard),
            onTap: () async => await config.exportJsonClipboard(excludePrivate: false),
          ),
          const Divider(),
          _SectionHeader(title: t.common.import),
          ListTile(
            leading: const Icon(Icons.file_upload_outlined),
            title: Text(t.pages.settings.options.import.file),
            onTap: () async => await importWithConfirm(() => config.importFromJsonFile()),
          ),
          ListTile(
            leading: const Icon(Icons.content_paste_outlined),
            title: Text(t.pages.settings.options.import.clipboard),
            onTap: () async => await importWithConfirm(() => config.importFromClipboard()),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.update_rounded),
            title: Text(t.pages.profiles.updateSubscriptions),
            onTap: () => ref.read(foregroundProfilesUpdateNotifierProvider.notifier).trigger(),
          ),
          ListTile(
            leading: const Icon(Icons.restore_rounded),
            title: Text(t.pages.settings.options.reset),
            onTap: () async => await config.resetOption(),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}
