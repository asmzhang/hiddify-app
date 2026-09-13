import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/features/profile/notifier/profiles_update_notifier.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/tools/data/stun_client.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 工具页（融合版）。
///
/// 对照 NekoBox 的「工具 = 网络 + 备份」两栏：
/// - 网络：新增 STUN / NAT 类型测试（本仓库原本没有，属补齐）；
/// - 备份：收拢 hiddify 已有的配置导出/导入/重置能力。
class ToolsPage extends HookConsumerWidget {
  const ToolsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          // 手机端：汉堡键打开左侧导航抽屉；PC 端无（左侧是常驻 rail）
          leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
          title: Text(t.pages.tools.title),
          bottom: TabBar(
            tabs: [
              Tab(text: t.pages.tools.network),
              Tab(text: t.pages.tools.backup),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_NetworkTab(), _BackupTab()],
        ),
      ),
    );
  }
}

class _NetworkTab extends HookConsumerWidget {
  const _NetworkTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final busy = useState(false);
    final result = useState<StunResult?>(null);
    final failed = useState(false);

    Future<void> run() async {
      busy.value = true;
      failed.value = false;
      try {
        result.value = await StunClient.test();
      } catch (_) {
        result.value = null;
        failed.value = true;
      } finally {
        busy.value = false;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(t.pages.tools.stunTest, style: theme.textTheme.titleMedium),
                    ),
                    FilledButton.icon(
                      onPressed: busy.value ? null : run,
                      icon: busy.value
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.play_arrow_rounded),
                      label: Text(t.pages.tools.stunTest),
                    ),
                  ],
                ),
                const Gap(12),
                if (failed.value)
                  Text(t.pages.tools.testFailed, style: TextStyle(color: theme.colorScheme.error))
                else if (result.value != null) ...[
                  _kv(context, t.pages.tools.publicAddress, '${result.value!.address}:${result.value!.port}'),
                  const Gap(8),
                  _kv(context, t.pages.tools.natType, _natLabel(result.value!.natType)),
                ] else
                  Text('—', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _natLabel(NatType n) => switch (n) {
    NatType.open => 'Open',
    NatType.cone => 'Cone',
    NatType.symmetric => 'Symmetric',
    NatType.unknown => '—',
  };
}

class _BackupTab extends HookConsumerWidget {
  const _BackupTab();

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

    return ListView(
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

Widget _kv(BuildContext context, String label, String value) {
  final theme = Theme.of(context);
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      const Gap(8),
      Flexible(
        child: Text(value, textAlign: TextAlign.right, style: theme.textTheme.bodyMedium),
      ),
    ],
  );
}
