import 'package:flutter/material.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/widget/preference_tile.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// 「高级端口」子页：只留 hiddify 独有的 PC 端口行（tproxy/redirect/direct，
/// 带 enable 开关）。NekoBox 已覆盖的项（服务模式/严格路由/mixed port 等）
/// 全部内联在设置主表，不再重复——归一原则。
/// DNS 子页已退役（全项重复）；此页从主表 NkNavRow「高级端口」进入
/// （goNamed('inboundOptions')，路由名沿用历史名避免动路由表）。
class InboundOptionsPage extends HookConsumerWidget with AppLogger {
  const InboundOptionsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    return Scaffold(
      appBar: AppBar(title: Text(t.pages.settings.inbound.title)),
      body: ListView(
        children: [
          if (PlatformUtils.isLinux)
            ValuePreferenceWidget(
              value: ref.watch(ConfigOptions.tproxyPort),
              preferences: ref.watch(ConfigOptions.tproxyPort.notifier),
              title: t.pages.settings.inbound.tproxyPort,
              icon: Icons.device_hub_rounded,
              inputToValue: int.tryParse,
              digitsOnly: true,
              validateInput: isPort,
              trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableTproxyPort),
            ),
          if (PlatformUtils.isLinux || PlatformUtils.isMacOS)
            ValuePreferenceWidget(
              value: ref.watch(ConfigOptions.redirectPort),
              preferences: ref.watch(ConfigOptions.redirectPort.notifier),
              title: t.pages.settings.inbound.redirectPort,
              icon: Icons.device_hub_rounded,
              inputToValue: int.tryParse,
              digitsOnly: true,
              validateInput: isPort,
              trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableRedirectPort),
            ),
          ValuePreferenceWidget(
            value: ref.watch(ConfigOptions.directPort),
            preferences: ref.watch(ConfigOptions.directPort.notifier),
            title: t.pages.settings.inbound.directPort,
            icon: Icons.device_hub_rounded,
            inputToValue: int.tryParse,
            digitsOnly: true,
            validateInput: isPort,
            trailing: SwitchPreferenceWidget(preference: ConfigOptions.enableDirectPort),
          ),
        ],
      ),
    );
  }
}
