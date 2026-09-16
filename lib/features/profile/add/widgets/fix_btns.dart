import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/constants.dart';
import 'package:hiddify/features/common/qr_code_scanner_screen.dart';
import 'package:hiddify/features/profile/add/widgets/widgets.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/features/proxy/widget/manual_node_flow.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class FixBtns extends ConsumerWidget {
  const FixBtns({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    final isDesktop = PlatformUtils.isDesktop;
    return Row(
      children: [
        const Gap(AddProfileModalConst.fixBtnsGap),
        FixBtn(
          key: const ValueKey('add_from_clipboard_button'),
          height: height,
          title: t.common.clipboard,
          icon: Icons.content_paste,
          onTap: () async {
            final cr = await Clipboard.getData(Clipboard.kTextPlain).then((value) => value?.text ?? '');
            ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
          },
        ),
        const Gap(AddProfileModalConst.fixBtnsGap),
        FixBtn(
          key: const ValueKey('add_from_file_button'),
          height: height,
          title: t.common.file,
          icon: Icons.insert_drive_file,
          onTap: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.custom,
              allowedExtensions: ['txt', 'json'],
            );
            if (result == null) return;
            final file = File(result.files.single.path!);
            if (!await file.exists()) return;
            final bytes = await file.readAsBytes();
            final content = utf8.decode(bytes);
            ref.read(addProfileNotifierProvider.notifier).addClipboard(content);
          },
        ),
        if (!isDesktop) ...[
          const Gap(AddProfileModalConst.fixBtnsGap),
          FixBtn(
            key: const ValueKey('add_by_qr_code_button'),
            height: height,
            title: t.common.scanQr,
            icon: Icons.qr_code_scanner,
            onTap: () async {
              final cr = await showQrCodeScanner();
              if (cr == null) return;
              ref.read(addProfileNotifierProvider.notifier).addClipboard(cr);
            },
          ),
        ],
        const Gap(AddProfileModalConst.fixBtnsGap),
        FixBtn(
          key: const ValueKey('add_manually_button'),
          height: height,
          title: t.common.manually,
          icon: Icons.add,
          onTap: () {
            ref.read(addProfilePageNotifierProvider.notifier).goManual();
          },
        ),
        // NekoBox 复刻 · ＋ → Manual Settings（`add_profile_menu.xml:25`）：
        // 手动输入**单个节点**（走协议表单），与上面那个"手动加订阅"不是一回事。
        const Gap(AddProfileModalConst.fixBtnsGap),
        FixBtn(
          key: const ValueKey('add_manual_node_button'),
          height: height,
          title: t.pages.proxies.form.manual,
          icon: Icons.playlist_add,
          onTap: () async {
            await startManualNodeFlow(context, ref);
          },
        ),
        const Gap(AddProfileModalConst.fixBtnsGap),
      ],
    );
  }
}
