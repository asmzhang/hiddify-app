import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/haptic/haptic_service.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/model/region.dart';
import 'package:hiddify/core/preferences/general_preferences.dart';
import 'package:hiddify/core/router/adaptive_layout/shell_drawer.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/core/router/go_router/helper/active_breakpoint_notifier.dart';
import 'package:hiddify/core/widget/nekobox/nk_card.dart';
import 'package:hiddify/features/auto_start/notifier/auto_start_notifier.dart';
import 'package:hiddify/features/common/general_pref_tiles.dart';
import 'package:hiddify/features/connection/notifier/connection_notifier.dart';
import 'package:hiddify/features/log/model/log_level.dart';
import 'package:hiddify/features/per_app_proxy/model/per_app_proxy_mode.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/settings/data/config_option_repository.dart';
import 'package:hiddify/features/settings/notifier/config_option/config_option_notifier.dart';
import 'package:hiddify/features/settings/notifier/reset_tunnel/reset_tunnel_notifier.dart';
import 'package:hiddify/features/settings/widget/lan_sharing_tile.dart';
import 'package:hiddify/features/settings/widget/nk_setting_rows.dart';
import 'package:hiddify/singbox/model/singbox_config_enum.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:humanizer/humanizer.dart';

enum ConfigOptionSection {
  warp,
  fragment;

  static final _warpKey = GlobalKey(debugLabel: "warp-section-key");
  static final _fragmentKey = GlobalKey(debugLabel: "fragment-section-key");

  GlobalKey get key => switch (this) {
    ConfigOptionSection.warp => _warpKey,
    ConfigOptionSection.fragment => _fragmentKey,
  };
}

/// NekoBox 设置页复刻（global_preferences.xml 五类内联结构）：
/// 基础 / 路由 / DNS / 入站 / 其他。高频项内联（开关/取值/选择行），
/// 低频大项（TLS 技巧、链式代理、路由规则、通用子页）保留导航行。
class SettingsPage extends HookConsumerWidget {
  SettingsPage({super.key, String? section})
    : section = section != null ? ConfigOptionSection.values.byName(section) : null;

  final ConfigOptionSection? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;

    return Scaffold(
      appBar: AppBar(
        // 手机端：汉堡键打开左侧导航抽屉；PC 端无（左侧是常驻 rail）
        leading: Breakpoint(context).isMobile() ? const ShellDrawerButton() : null,
        title: Text(t.pages.settings.title),
        actions: [
          MenuAnchor(
            menuChildren: <Widget>[
              SubmenuButton(
                menuChildren: <Widget>[
                  MenuItemButton(
                    onPressed: () async => await ref
                        .read(dialogNotifierProvider.notifier)
                        .showConfirmation(
                          title: t.common.msg.import.confirm,
                          message: t.dialogs.confirmation.settings.import.msg,
                        )
                        .then((shouldImport) async {
                          if (shouldImport) {
                            await ref.read(configOptionNotifierProvider.notifier).importFromClipboard();
                          }
                        }),
                    child: Text(t.pages.settings.options.import.clipboard),
                  ),
                  MenuItemButton(
                    onPressed: () async => await ref
                        .read(dialogNotifierProvider.notifier)
                        .showConfirmation(
                          title: t.common.msg.import.confirm,
                          message: t.dialogs.confirmation.settings.import.msg,
                        )
                        .then((shouldImport) async {
                          if (shouldImport) {
                            await ref.read(configOptionNotifierProvider.notifier).importFromJsonFile();
                          }
                        }),
                    child: Text(t.pages.settings.options.import.file),
                  ),
                ],
                child: Text(t.common.import),
              ),
              SubmenuButton(
                menuChildren: <Widget>[
                  MenuItemButton(
                    onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonClipboard(),
                    child: Text(t.pages.settings.options.export.anonymousToClipboard),
                  ),
                  MenuItemButton(
                    onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(),
                    child: Text(t.pages.settings.options.export.anonymousToFile),
                  ),
                  const PopupMenuDivider(),
                  MenuItemButton(
                    onPressed: () async => await ref
                        .read(configOptionNotifierProvider.notifier)
                        .exportJsonClipboard(excludePrivate: false),
                    child: Text(t.pages.settings.options.export.allToClipboard),
                  ),
                  MenuItemButton(
                    onPressed: () async =>
                        await ref.read(configOptionNotifierProvider.notifier).exportJsonFile(excludePrivate: false),
                    child: Text(t.pages.settings.options.export.allToFile),
                  ),
                ],
                child: Text(t.common.export),
              ),
              const PopupMenuDivider(),
              MenuItemButton(
                child: Text(t.pages.settings.options.reset),
                onPressed: () async => await ref.read(configOptionNotifierProvider.notifier).resetOption(),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              onPressed: () {
                if (controller.isOpen) {
                  controller.close();
                } else {
                  controller.open();
                }
              },
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ),
          const Gap(8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 16),
        children: [
          // ── 基础 ──
          NkSectionHeader(t.pages.settings.general.title),
          NkSettingCard(
            rows: [
              if (PlatformUtils.isDesktop)
                NkSwitchRow(
                  title: t.pages.settings.general.autoStart,
                  value: ref.watch(autoStartNotifierProvider).asData!.value,
                  onChanged: (value) async => value
                      ? await ref.read(autoStartNotifierProvider.notifier).enable()
                      : await ref.read(autoStartNotifierProvider.notifier).disable(),
                ),
              const NkPalettePrefTile(),
              const ThemeModePrefTile(),
              NkChoiceRow(
                title: t.pages.settings.inbound.serviceMode,
                selected: ref.watch(ConfigOptions.serviceMode),
                preferences: ref.watch(ConfigOptions.serviceMode.notifier),
                choices: ServiceMode.choices,
                presentChoice: (value) => value.present(t),
              ),
              // MTU：配置项一直存在（默认 9000），但此前没有任何 UI 入口（只能改 JSON）。
              // 标题沿用首字母缩写，不做翻译（同 "Clash API" 的处理）。
              NkValueRow<int>(
                title: 'MTU',
                value: ref.watch(ConfigOptions.mtu),
                preferences: ref.watch(ConfigOptions.mtu.notifier),
                digitsOnly: true,
                inputToValue: int.tryParse,
              ),
              NkChoiceRow(
                title: t.pages.settings.general.logLevel,
                selected: ref.watch(ConfigOptions.logLevel),
                preferences: ref.watch(ConfigOptions.logLevel.notifier),
                choices: LogLevel.values,
                presentChoice: (value) => value.name.toUpperCase(),
              ),
              const LocalePrefTile(),
              // NekoBox `tun_implementation` 在「基础」类（global_preferences.xml:31）。
              if (PlatformUtils.isAndroid || PlatformUtils.isDesktop)
                NkChoiceRow(
                  title: t.pages.settings.inbound.tunImplementation,
                  selected: ref.watch(ConfigOptions.tunImplementation),
                  preferences: ref.watch(ConfigOptions.tunImplementation.notifier),
                  choices: TunImplementation.values,
                  presentChoice: (value) => value.name,
                ),
              if (PlatformUtils.isDesktop) ...[
                const ClosingPrefTile(),
                NkSwitchRow(
                  title: t.pages.settings.general.silentStart,
                  value: ref.watch(Preferences.silentStart),
                  onChanged: ref.read(Preferences.silentStart.notifier).update,
                ),
              ],
              if (PlatformUtils.isAndroid) ...[
                NkSwitchRow(
                  title: t.pages.settings.general.dynamicNotification,
                  value: ref.watch(Preferences.dynamicNotification),
                  onChanged: ref.read(Preferences.dynamicNotification.notifier).update,
                ),
                NkSwitchRow(
                  title: t.pages.settings.general.hapticFeedback,
                  value: ref.watch(hapticServiceProvider),
                  onChanged: ref.read(hapticServiceProvider.notifier).updatePreference,
                ),
              ],
              // 「高级端口」子页：hiddify 独有的 tproxy/redirect/direct 端口
              // （带 enable 开关）。NekoBox 规格无此项（只有 mixed port）。
              NkNavRow(
                title: t.pages.settings.inbound.title,
                subtitle: '${t.pages.settings.inbound.tproxyPort} / ${t.pages.settings.inbound.redirectPort} / ${t.pages.settings.inbound.directPort}',
                onTap: () => context.goNamed('inboundOptions'),
              ),
              NkSwitchRow(
                title: t.pages.settings.general.memoryLimit,
                subtitle: t.pages.settings.general.memoryLimitMsg,
                value: !ref.watch(Preferences.disableMemoryLimit),
                onChanged: (value) async => await ref.read(Preferences.disableMemoryLimit.notifier).update(!value),
              ),
              NkNavRow(title: t.pages.settings.general.title, onTap: () => context.goNamed('general')),
            ],
          ),

          // ── 路由 ──
          NkSectionHeader(t.pages.settings.routing.title),
          NkSettingCard(
            rows: [
              NkChoiceRow(
                title: t.pages.settings.routing.generalOptions.region,
                selected: ref.watch(ConfigOptions.region),
                preferences: ref.watch(ConfigOptions.region.notifier),
                choices: Region.values,
                presentChoice: (value) => value.present(t),
                showFlag: true,
              ),
              NkNavRow(
                title: t.pages.settings.routing.routeRule.rule.title,
                onTap: () => context.goNamed('routingOptions'),
              ),
              if (PlatformUtils.isAndroid)
                NkSwitchRow(
                  title: t.pages.settings.routing.generalOptions.perAppProxy.title,
                  value: ref.watch(Preferences.perAppProxyMode).enabled,
                  onChanged: (value) async {
                    final newMode = value ? PerAppProxyMode.exclude : PerAppProxyMode.off;
                    await ref.read(Preferences.perAppProxyMode.notifier).update(newMode);
                    if (value && context.mounted) context.goNamed('perAppProxy');
                  },
                ),
              NkSwitchRow(
                title: t.pages.settings.routing.generalOptions.resolveDestination,
                value: ref.watch(ConfigOptions.resolveDestination),
                onChanged: ref.read(ConfigOptions.resolveDestination.notifier).update,
              ),
              // NekoBox `global_preferences.xml` 的 **Bypass LAN in Core**（内核侧绕过局域网）。
              // 与 NekoBox 那个 app 层的 Bypass LAN 是两个开关；hiddify 只有内核侧这一个，
              // 内核字段在册（RouteOptions.BypassLAN → json "bypass-lan"）。
              NkSwitchRow(
                title: t.pages.settings.routing.generalOptions.bypassLanInCore,
                value: ref.watch(ConfigOptions.bypassLan),
                onChanged: ref.read(ConfigOptions.bypassLan.notifier).update,
              ),
              NkChoiceRow(
                title: t.pages.settings.routing.generalOptions.ipv6Route,
                selected: ref.watch(ConfigOptions.ipv6Mode),
                preferences: ref.watch(ConfigOptions.ipv6Mode.notifier),
                choices: IPv6Mode.values,
                presentChoice: (value) => value.present(t),
              ),
              NkSwitchRow(
                title: t.pages.settings.inbound.strictRoute,
                value: ref.watch(ConfigOptions.strictRoute),
                onChanged: ref.read(ConfigOptions.strictRoute.notifier).update,
              ),
              NkChoiceRow(
                title: t.pages.settings.routing.generalOptions.balancerStrategy.title,
                selected: ref.watch(ConfigOptions.balancerStrategy),
                preferences: ref.watch(ConfigOptions.balancerStrategy.notifier),
                choices: BalancerStrategy.values,
                presentChoice: (value) => value.present(t),
              ),
            ],
          ),

          // ── DNS ──
          NkSectionHeader(t.pages.settings.dns.title),
          NkSettingCard(
            rows: [
              NkValueRow<String>(
                title: t.pages.settings.dns.remoteDns,
                value: ref.watch(ConfigOptions.remoteDnsAddress),
                preferences: ref.watch(ConfigOptions.remoteDnsAddress.notifier),
              ),
              NkChoiceRow(
                title: t.pages.settings.dns.remoteDnsDomainStrategy,
                selected: ref.watch(ConfigOptions.remoteDnsDomainStrategy),
                preferences: ref.watch(ConfigOptions.remoteDnsDomainStrategy.notifier),
                choices: DomainStrategy.values,
                presentChoice: (value) => value.present(t),
              ),
              NkValueRow<String>(
                title: t.pages.settings.dns.directDns,
                value: ref.watch(ConfigOptions.directDnsAddress),
                preferences: ref.watch(ConfigOptions.directDnsAddress.notifier),
              ),
              NkChoiceRow(
                title: t.pages.settings.dns.directDnsDomainStrategy,
                selected: ref.watch(ConfigOptions.directDnsDomainStrategy),
                preferences: ref.watch(ConfigOptions.directDnsDomainStrategy.notifier),
                choices: DomainStrategy.values,
                presentChoice: (value) => value.present(t),
              ),
              NkSwitchRow(
                title: t.pages.settings.dns.enableFakeDns,
                value: ref.watch(ConfigOptions.enableFakeDns),
                onChanged: ref.read(ConfigOptions.enableFakeDns.notifier).update,
              ),
            ],
          ),

          // ── 入站 ──
          NkSectionHeader(t.pages.settings.inbound.title),
          NkSettingCard(
            rows: [
              NkValueRow<int>(
                title: t.pages.settings.inbound.mixedPort,
                value: ref.watch(ConfigOptions.mixedPort),
                preferences: ref.watch(ConfigOptions.mixedPort.notifier),
                digitsOnly: true,
                inputToValue: int.tryParse,
                validateInput: isPort,
              ),
              NkSwitchRow(
                title: t.pages.settings.inbound.captureEnabled,
                subtitle: t.pages.settings.inbound.captureEnabledSubtitle,
                value: ref.watch(Preferences.captureEnabled),
                onChanged: (value) => ref.read(connectionNotifierProvider.notifier).setCapture(value),
              ),
              const LanSharingPreferenceWidget(),
              // 「严格路由」只在「路由」卡里出现一次（归一原则：一个能力一个入口）。
              NkChoiceRow(
                title: t.pages.settings.inbound.tunImplementation,
                selected: ref.watch(ConfigOptions.tunImplementation),
                preferences: ref.watch(ConfigOptions.tunImplementation.notifier),
                choices: TunImplementation.values,
                presentChoice: (value) => value.name,
              ),
            ],
          ),

          // ── 其他 ──
          NkSectionHeader(t.pages.settings.misc),
          NkSettingCard(
            rows: [
              NkValueRow<String>(
                title: t.pages.settings.general.connectionTestUrl,
                value: ref.watch(ConfigOptions.connectionTestUrl),
                preferences: ref.watch(ConfigOptions.connectionTestUrl.notifier),
              ),
              NkValueRow<Duration>(
                title: t.pages.settings.general.urlTestInterval,
                value: ref.watch(ConfigOptions.urlTestInterval),
                preferences: ref.watch(ConfigOptions.urlTestInterval.notifier),
                presentValue: (value) => value.toApproximateTime(isRelativeToNow: false),
              ),
              NkSwitchRow(
                title: 'Clash API',
                value: ref.watch(ConfigOptions.enableClashApi),
                onChanged: ref.read(ConfigOptions.enableClashApi.notifier).update,
              ),
              NkValueRow<int>(
                title: t.pages.settings.general.clashApiPort,
                value: ref.watch(ConfigOptions.clashApiPort),
                preferences: ref.watch(ConfigOptions.clashApiPort.notifier),
                digitsOnly: true,
                inputToValue: int.tryParse,
                validateInput: isPort,
                enabled: ref.watch(ConfigOptions.enableClashApi),
              ),
              NkNavRow(title: t.pages.settings.tlsTricks.title, onTap: () => context.goNamed('tlsTricks')),
              if (ref.watch(hasAnyProfileProvider).value ?? false)
                NkNavRow(
                  title: t.pages.settings.chain.title,
                  subtitle: t.pages.settings.chain.subtitle,
                  onTap: () => context.goNamed('chainOptions'),
                ),
              NkSwitchRow(
                title: t.pages.settings.general.useXrayCoreWhenPossible,
                subtitle: t.pages.settings.general.useXrayCoreWhenPossibleMsg,
                value: ref.watch(ConfigOptions.useXrayCoreWhenPossible),
                onChanged: ref.read(ConfigOptions.useXrayCoreWhenPossible.notifier).update,
              ),
              // NekoBox `allowInsecureOnRequest`（global_preferences.xml:236）：
              // 仅订阅更新跳过证书检查（RawUpdater.kt:66），纯 app 层开关，
              // 不影响内核与其它请求。按规格放「其他」类。
              NkSwitchRow(
                title: t.pages.settings.general.allowInsecureOnRequest,
                value: ref.watch(ConfigOptions.allowInsecureOnRequest),
                onChanged: ref.read(ConfigOptions.allowInsecureOnRequest.notifier).update,
              ),
              if (PlatformUtils.isIOS)
                NkNavRow(
                  title: t.pages.settings.resetTunnel,
                  onTap: () async {
                    await ref.read(resetTunnelNotifierProvider.notifier).run();
                  },
                ),
              if (Breakpoint(context).isMobile()) ...[
                NkNavRow(title: t.pages.logs.title, onTap: () => context.goNamed('logs')),
                NkNavRow(title: t.pages.about.title, onTap: () => context.goNamed('about')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
