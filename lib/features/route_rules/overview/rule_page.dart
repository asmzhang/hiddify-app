import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/features/proxy/data/proxy_data_providers.dart';
import 'package:hiddify/features/route_rules/notifier/rule_notifier.dart';
import 'package:hiddify/features/route_rules/overview/android_apps_page.dart';
import 'package:hiddify/features/route_rules/widget/setting_checkbox.dart';
import 'package:hiddify/features/route_rules/widget/setting_divider.dart';
import 'package:hiddify/features/route_rules/widget/setting_generic_list.dart';
import 'package:hiddify/features/route_rules/widget/setting_radio.dart';
import 'package:hiddify/features/route_rules/widget/setting_text.dart';
import 'package:hiddify/hiddifycore/generated/v2/config/route_rule.pb.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:protobuf/protobuf.dart';
import 'package:recase/recase.dart';

class RulePage extends HookConsumerWidget {
  const RulePage({super.key, this.ruleListOrder});

  final int? ruleListOrder;

  String getTitle(Map<String, String> t, RuleEnum key) => t[key.name.snakeCase] ?? key.name;

  /// Per-rule custom config must be a JSON object (possibly empty). The Go
  /// side mergeMaps only consumes objects; anything else fails there.
  static bool _isValidJsonConfig(String value) {
    if (value.trim().isEmpty) return true;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic>;
    } on FormatException {
      return false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final isRuleEdited = ref.watch(IsRuleEditedProvider(ruleListOrder));
    return Scaffold(
      appBar: AppBar(
        title: Text(t.pages.settings.routing.routeRule.rule.title),
        actions: [
          IconButton(
            onPressed: isRuleEdited
                ? () async {
                    await ref.read(ruleNotifierProvider(ruleListOrder).notifier).save();
                    if (context.mounted) context.pop();
                  }
                : null,
            icon: const Icon(Icons.check),
          ),
          const Gap(8),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            SettingText(
              title: RuleEnum.name.present(t),
              value: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.name)),
              setValue: (value) =>
                  ref.read(ruleNotifierProvider(ruleListOrder).notifier).update<String>(RuleEnum.name, value),
            ),
            SettingRadio<Outbound>(
              title: RuleEnum.outbound.present(t),
              values: Outbound.values,
              value: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.outbound)),
              setValue: (value) =>
                  ref.read(ruleNotifierProvider(ruleListOrder).notifier).update<Outbound>(RuleEnum.outbound, value),
              defaultValue: Outbound.direct,
              t: t.pages.settings.routing.routeRule.rule.outbound,
            ),
            const SettingDivider(),
            SettingGenericList<String>(
              title: RuleEnum.ruleSet.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.ruleSets)),
              useEllipsis: true,
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.ruleSet.name},
              ),
            ),
            SettingDivider(title: t.pages.settings.routing.routeRule.rule.onlyTunMode),
            SettingGenericList<String>(
              title: RuleEnum.packageName.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.packageNames)),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AndroidAppsPage(ruleListOrder: ruleListOrder),
                  fullscreenDialog: true,
                ),
              ),
              isPackageName: true,
              showPlatformWarning: !PlatformUtils.isAndroid,
            ),
            SettingGenericList<String>(
              title: RuleEnum.processName.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.processNames)),
              showPlatformWarning: !PlatformUtils.isDesktop,
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.processName.name},
              ),
            ),
            SettingGenericList<String>(
              title: RuleEnum.processPath.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.processPaths)),
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.processPath.name},
              ),
              showPlatformWarning: !PlatformUtils.isDesktop,
            ),
            const SettingDivider(),
            SettingRadio<Network>(
              title: RuleEnum.network.present(t),
              values: Network.values,
              value: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.network)),
              setValue: (value) =>
                  ref.read(ruleNotifierProvider(ruleListOrder).notifier).update<Network>(RuleEnum.network, value),
              defaultValue: Network.all,
              t: t.pages.settings.routing.routeRule.rule.network,
            ),
            // Batch 14 half 2: rule -> specific node/group (NekoBox
            // OutboundPreference "3" -> ProfileSelectActivity): a picker over
            // existing outbound tags, NOT free text — an unknown tag would
            // fail sing-box validation at start. Per-rule custom config
            // (NekoBox EditConfigPreference serverConfig) is a JSON edit.
            _OutboundTagTile(ruleListOrder: ruleListOrder),
            SettingText(
              title: RuleEnum.config.present(t),
              value: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.config)),
              setValue: (value) =>
                  ref.read(ruleNotifierProvider(ruleListOrder).notifier).update<String>(RuleEnum.config, value),
              validator: (value) =>
                  _isValidJsonConfig(value ?? '') ? null : t.pages.settings.routing.routeRule.rule.configInvalid,
            ),
            SettingGenericList<String>(
              title: RuleEnum.portRange.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.portRanges)),
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.portRange.name},
              ),
            ),
            SettingGenericList<String>(
              title: RuleEnum.sourcePortRange.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.sourcePortRanges)),
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {
                  'orderId': ruleListOrder?.toString() ?? 'new',
                  'ruleEnum': RuleEnum.sourcePortRange.name,
                },
              ),
            ),
            SettingCheckbox(
              title: RuleEnum.protocol.present(t),
              values: Protocol.values,
              selectedValues: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.protocols)),
              setValue: (value) => ref
                  .read(ruleNotifierProvider(ruleListOrder).notifier)
                  .update<List<ProtobufEnum>>(RuleEnum.protocol, value),
              t: t.pages.settings.routing.routeRule.rule.protocol,
            ),
            const SettingDivider(),
            SettingGenericList<String>(
              title: RuleEnum.ipCidr.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.ipCidrs)),
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.ipCidr.name},
              ),
            ),
            SettingGenericList<String>(
              title: RuleEnum.sourceIpCidr.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.sourceIpCidrs)),
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.sourceIpCidr.name},
              ),
            ),
            const SettingDivider(),
            // Batch 14: NekoBox routeDomain consolidation — ONE domain input
            // with prefix semantics (geosite:/full:/domain:/regexp:/keyword:/
            // bare value). The separate suffix/keyword/regex editing tiles are
            // retired; data already stored in those pb fields still flows to
            // the core and is merged (route_rules.go mergeUnique), it just has
            // no editing UI anymore.
            SettingGenericList<String>(
              title: RuleEnum.domain.present(t),
              values: ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.domains)),
              onTap: () => context.pushNamed(
                'genericList',
                pathParameters: {'orderId': ruleListOrder?.toString() ?? 'new', 'ruleEnum': RuleEnum.domain.name},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Route to node" tile: pick the outbound tag of an existing node/group
/// (NekoBox OutboundPreference "3" opens ProfileSelectActivity; here the
/// chain-member picker data source is reused). Empty tag = default routing.
class _OutboundTagTile extends ConsumerWidget {
  const _OutboundTagTile({this.ruleListOrder});

  final int? ruleListOrder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final currentTag = ref.watch(ruleNotifierProvider(ruleListOrder).select((value) => value.outboundTag));
    return ListTile(
      title: Text(RuleEnum.outboundTag.present(t)),
      subtitle: Text(currentTag.isEmpty ? t.pages.settings.routing.routeRule.rule.outboundTagNone : currentTag),
      onTap: () async {
        final members = await ref.read(proxyEntityRepositoryProvider).selectableChainMembers();
        if (!context.mounted) return;
        final selected = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(RuleEnum.outboundTag.present(t)),
            children: [
              // "None" first — clears the tag (default routing).
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(''),
                child: Text(
                  t.pages.settings.routing.routeRule.rule.outboundTagNone,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              for (final row in members)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(row.tag),
                  child: Text(row.displayName.isEmpty ? row.tag : '${row.displayName} (${row.tag})'),
                ),
            ],
          ),
        );
        if (selected == null) return; // dismissed
        ref.read(ruleNotifierProvider(ruleListOrder).notifier).update<String>(RuleEnum.outboundTag, selected);
      },
    );
  }
}
